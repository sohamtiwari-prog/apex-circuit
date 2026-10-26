class_name RaceCar
extends RigidBody3D
## A drivable car built from a spec (see car_specs.gd). Forward is +Z, left is +X.
##
## Inputs (set every physics frame by a controller):
##   throttle     0..1
##   brake_input  0..1   (also reverses when nearly stopped)
##   steer_input  -1..1  (+ = right)
##
## Physics model (everything here, no built-in vehicle):
##   - raycast suspension per wheel: spring + damper + bump stop, anti-roll bars,
##     so load moves between the tyres under braking, power and cornering;
##   - tyres: lateral force from slip angle on a Pacejka-style curve that rises
##     progressively, peaks, then holds ~80% in a slide (forgiving, catchable);
##     longitudinal force from engine/brakes, combined on a friction circle;
##   - steering lock shrinks with speed so full lock is always just past the
##     grip peak: steering is proportional at every speed;
##   - traction control / ABS give cornering grip priority (no power slides,
##     no locked fronts); switched off, the driver can spin the rears or lock up.

var spec: Dictionary = {}
var wheels: Array[CarWheel] = []
var front_wheels: Array[CarWheel] = []
var rear_wheels: Array[CarWheel] = []

var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var controls_enabled := true
var traction_control := true
var abs_enabled := true
var steering := 0.0               # current road-wheel angle, rad, + = left

# Drivetrain state, read by HUD and audio.
var gear := 1                     # -1 = reverse, 1..n forward
var rpm := 1000.0
var engine_load := 0.0            # 0..1, how hard the engine is working
var tyre_slip := 0.0              # 0..1, worst wheel, for tyre squeal and smoke
var wheels_on_grass := 0

const STEER_SPEED := 3.4          # steering input travel per second (full lock in ~0.3 s)
const GRASS_GRIP := 0.62
const GRAVEL_GRIP := 0.5
const STABILITY := 10.0           # 1/s, yaw damping from stability control
const SLIP_SHAPE := 1.65          # Pacejka C: progressive before the peak, ~80% grip in a slide

var _steer := 0.0                 # smoothed steering input, -1..1
var _shift_timer := 0.0
var _rays: Array[RayCast3D] = []

# Spec values cached as plain floats: read every tick by every car.
var _steer_low := 0.5
var _max_force := 9000.0
var _drag := 0.6
var _downforce := 1.0
var _down_z := 0.0
var _brake_base := 12.0
var _brake_aero := 0.0
var _brake_max := 13.0
var _radius_rear := 0.35
var _idle := 900.0
var _peak := 7000.0
var _redline := 8000.0
var _upshift := 7800.0
var _downshift := 6500.0
var _shift_time := 0.1
var _power := 400000.0
var _gears := PackedFloat32Array()
var _mu_f := 1.6
var _mu_r := 1.7
var _b_f := 10.0                  # Pacejka B per axle
var _b_r := 10.0
var _alpha_peak_f := 0.1
var _k_spring := 50000.0
var _c_damp := 3000.0
var _k_arb_f := 10000.0
var _k_arb_r := 8000.0
var _rest := 0.2
var _travel := 0.15
var _wheelbase := 2.7
var _corner_mass := 300.0
var _brake_bias := 0.6


func setup(car_spec: Dictionary) -> void:
	spec = car_spec


func _ready() -> void:
	if spec.is_empty():
		spec = CarSpecs.get_spec("gp26")
	_steer_low = spec["steer_low"]
	_max_force = spec["max_drive_force"]
	_drag = spec["drag"]
	_downforce = spec["downforce"]
	_down_z = spec["downforce_balance"]
	_brake_base = spec["brake_base"]
	_brake_aero = spec["brake_aero"]
	_brake_max = spec["brake_max"]
	_radius_rear = spec["radius_rear"]
	_idle = spec["idle_rpm"]
	_peak = spec["peak_rpm"]
	_redline = spec["redline"]
	_upshift = spec["upshift_rpm"]
	_downshift = spec["downshift_rpm"]
	_shift_time = spec["shift_time"]
	_power = spec["power"]
	_gears = PackedFloat32Array(spec["gears"])
	_mu_f = spec["mu_front"]
	_mu_r = spec["mu_rear"]
	var c := SLIP_SHAPE
	_alpha_peak_f = deg_to_rad(float(spec["slip_peak_front"]))
	_b_f = tan(PI / (2.0 * c)) / _alpha_peak_f
	_b_r = tan(PI / (2.0 * c)) / deg_to_rad(float(spec["slip_peak_rear"]))
	_rest = spec["rest_length"]
	_travel = spec["travel"]
	_brake_bias = spec["brake_bias"]

	mass = spec["mass"]
	var fz: float = spec["wheel_front_z"]
	var rz: float = spec["wheel_rear_z"]
	_wheelbase = fz - rz
	_corner_mass = mass * 0.25
	var omega := TAU * float(spec["susp_hz"])
	_k_spring = _corner_mass * omega * omega
	_c_damp = 2.0 * float(spec["susp_damping"]) * sqrt(_k_spring * _corner_mass)
	_k_arb_f = _k_spring * float(spec["arb_front"])
	_k_arb_r = _k_spring * float(spec["arb_rear"])

	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = spec["com"]
	var com: Vector3 = spec["com"]
	var a := fz - com.z
	var b := com.z - rz
	var half_track := float(spec["track_front"])
	# Inertia of a car-shaped mass: yaw ~0.85 m a b (the "dynamic index").
	var yaw_i := mass * a * b * float(spec.get("yaw_inertia", 0.85))
	inertia = Vector3(mass * a * b * 0.8, yaw_i, mass * (half_track * half_track) * 0.55)
	can_sleep = false
	# Layer 1: the track and barriers. Layer 2: cars.
	collision_layer = 2
	collision_mask = 1 | 2
	# Slippery bodywork: touching cars glance off each other instead of locking.
	var pm := PhysicsMaterial.new()
	pm.friction = 0.12
	pm.bounce = 0.05
	physics_material_override = pm
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.15
	for col in spec["collision"]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = col[0]
		cs.shape = box
		cs.position = col[1]
		add_child(cs)
	var wy: float = spec["wheel_y"]
	_add_wheel(Vector3(spec["track_front"], wy, fz), true)     # front left
	_add_wheel(Vector3(-spec["track_front"], wy, fz), true)    # front right
	_add_wheel(Vector3(spec["track_rear"], wy, rz), false)     # rear left
	_add_wheel(Vector3(-spec["track_rear"], wy, rz), false)    # rear right
	var body := CarBody.new()
	add_child(body)
	body.build(spec, self)


## A ghost car can't be hit by (or hit) other cars; the track still holds it.
func set_ghost(on: bool) -> void:
	collision_layer = 0 if on else 2
	collision_mask = 1 if on else (1 | 2)


func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


func speed_kmh() -> float:
	return absf(forward_speed()) * 3.6


func gear_count() -> int:
	return spec["gears"].size()


func reset_controls() -> void:
	throttle = 0.0
	brake_input = 0.0
	steer_input = 0.0
	_steer = 0.0
	steering = 0.0
	for w in wheels:
		w.prev_compression = w.compression
	gear = 1
	_shift_timer = 0.0


## Seat height above the road for spawning.
func spawn_height() -> float:
	return float(spec["rest_length"]) + float(spec["radius_rear"]) - float(spec["wheel_y"]) + 0.05



## Road-wheel angle (rad, + = right) for a steering input at this speed.
## Input maps through the inverse of the tyre curve, so cornering force grows
## in proportion to the input; full input sits just past the front tyres'
## grip peak at any speed, the rest of the range is never wasted.
func steer_angle(input: float, v: float) -> float:
	var x := clampf(absf(input), 0.0, 1.0)
	var v2 := maxf(v * v, 1.0)
	var a_lat := _mu_f * (9.81 + _downforce * v2 / mass)
	var geometric := _wheelbase * a_lat / v2
	var slip := _alpha_peak_f * 1.08 * tan(asin(x * 0.999) / SLIP_SHAPE) / tan(PI / (2.0 * SLIP_SHAPE))
	return signf(input) * minf(geometric * x + slip, _steer_low)


func max_steer_angle(v: float) -> float:
	return steer_angle(1.0, v)


## Steering input that gives a road-wheel angle (rad, + = right) at speed v.
func input_for_angle(angle: float, v: float) -> float:
	var target := absf(angle)
	if target >= max_steer_angle(v):
		return signf(angle)
	var lo := 0.0
	var hi := 1.0
	for _i in range(12):
		var mid := (lo + hi) * 0.5
		if steer_angle(mid, v) < target:
			lo = mid
		else:
			hi = mid
	return signf(angle) * (lo + hi) * 0.5


# ------------------------------------------------------------ simulation

func _wheel_rpm_from_speed(v: float, ratio: float) -> float:
	return absf(v) / (TAU * _radius_rear) * 60.0 * ratio


func _engine_power(at_rpm: float) -> float:
	var x := (at_rpm - _peak) / maxf(_peak - _idle, 1.0)
	return _power * clampf(1.0 - x * x * 0.55, 0.35, 1.0)


func _update_gearbox(v: float, delta: float, want_reverse: bool) -> void:
	var gears := _gears
	if want_reverse:
		gear = -1
	elif gear == -1:
		gear = 1
	if _shift_timer > 0.0:
		_shift_timer -= delta
	if gear > 0:
		var cur := _wheel_rpm_from_speed(v, gears[gear - 1])
		if cur > _upshift and gear < gears.size() and _shift_timer <= 0.0:
			gear += 1
			_shift_timer = _shift_time
		elif gear > 1:
			var lower := _wheel_rpm_from_speed(v, gears[gear - 2])
			if lower < _downshift and _shift_timer <= 0.0:
				gear -= 1
				_shift_timer = _shift_time * 0.5
	var ratio: float = gears[0] if gear < 0 else gears[gear - 1]
	var target := maxf(_wheel_rpm_from_speed(v, ratio), _idle)
	# Free-revving when the clutch slips at launch.
	if gear == 1 and throttle > 0.1 and absf(v) < 6.0:
		target = maxf(target, lerpf(_idle, _peak * 0.75, throttle))
	rpm = minf(lerpf(rpm, target, 1.0 - exp(-18.0 * delta)), _redline)



func _physics_process(delta: float) -> void:
	var v := forward_speed()
	var thr := throttle if controls_enabled else 0.0
	var brk := brake_input if controls_enabled else 0.0
	var str_in := steer_input if controls_enabled else 0.0

	# Smoothed, speed-scaled steering.
	var rate := lerpf(STEER_SPEED, STEER_SPEED * 0.55, clampf(absf(v) / 70.0, 0.0, 1.0))
	_steer = move_toward(_steer, clampf(str_in, -1.0, 1.0), rate * delta)
	steering = -steer_angle(_steer, v)

	var want_reverse := controls_enabled and brk > 0.05 and v < 1.5 and thr < 0.05
	_update_gearbox(v, delta, want_reverse)

	var drive := 0.0
	var braking := 0.0
	if not controls_enabled:
		braking = 1.0               # held on the brakes (grid, countdown)
	elif want_reverse:
		drive = -brk * 0.35
	elif brk > 0.05:
		braking = brk
	elif thr > 0.01:
		drive = thr
	if _shift_timer > 0.0 and drive > 0.0:
		drive *= 0.15               # torque cut during the shift
	engine_load = clampf(absf(drive), 0.0, 1.0)

	var drive_force := 0.0
	if drive != 0.0:
		drive_force = drive * minf(_max_force, _engine_power(rpm) / maxf(absf(v), 1.0))
	var brake_force := 0.0
	if braking > 0.0:
		brake_force = mass * minf(_brake_base + _brake_aero * v * v, _brake_max) * braking

	_simulate_wheels(delta, drive_force, brake_force)

	var vel := linear_velocity
	apply_central_force(-vel * vel.length() * _drag)
	apply_force(-global_basis.y * _downforce * v * v, global_basis * Vector3(0, 0, _down_z))


func _simulate_wheels(delta: float, drive_force: float, brake_force: float) -> void:
	var xf := global_transform
	var up := xf.basis.y
	var com_g := xf * center_of_mass
	var lin := linear_velocity
	var ang := angular_velocity

	# --- suspension
	for i in range(4):
		var w := wheels[i]
		var ray := _rays[i]
		ray.force_raycast_update()
		w.prev_compression = w.compression
		w.in_contact = false
		w.load = 0.0
		if ray.is_colliding():
			var hit := ray.get_collision_point()
			var dist := (ray.global_position - hit).dot(up)
			var comp := _rest + w.wheel_radius - dist
			if comp > 0.0:
				w.in_contact = true
				w.contact_point = hit
				w.contact_normal = ray.get_collision_normal()
				w.compression = minf(comp, _travel + 0.05)
				var f := _k_spring * w.compression + _c_damp * (w.compression - w.prev_compression) / delta
				if comp > _travel:
					f += _k_spring * 8.0 * (comp - _travel)     # bump stop
				w.load = maxf(f, 0.0)
		if not w.in_contact:
			w.compression = maxf(w.compression - delta * 1.5, 0.0)
	# Anti-roll bars move load across each axle.
	_anti_roll(wheels[0], wheels[1], _k_arb_f)
	_anti_roll(wheels[2], wheels[3], _k_arb_r)

	# --- tyres
	var worst := 0.0
	var side_force := 0.0
	wheels_on_grass = 0
	var static_hold := absf(lin.dot(xf.basis.z)) < 0.6
	for i in range(4):
		var w := wheels[i]
		var front := i < 2
		w.steer_angle = steering if front else 0.0
		if not w.in_contact or w.load <= 0.0:
			w.utilisation = 0.0
			w.slip_angle = 0.0
			continue
		var n := w.contact_normal
		apply_force(up * w.load, w.contact_point - xf.origin)
		var fwd := xf.basis.z
		if front:
			fwd = fwd.rotated(up, steering)
		fwd = (fwd - n * fwd.dot(n)).normalized()
		var side := n.cross(fwd)                 # left
		var arm := w.contact_point - com_g
		var cv := lin + ang.cross(arm)
		var vx := cv.dot(fwd)
		var vy := cv.dot(side)
		var mu := _mu_f if front else _mu_r
		if w.surface != 0:
			mu *= GRASS_GRIP if w.surface == 1 else GRAVEL_GRIP
			wheels_on_grass += 1
		var cap := mu * w.load

		# Lateral: Pacejka-style curve on slip angle.
		var alpha := atan2(vy, maxf(absf(vx), 3.5))
		w.slip_angle = alpha
		var b := _b_f if front else _b_r
		var fy := -cap * sin(SLIP_SHAPE * atan(b * alpha))
		# Never push harder than it takes to stop the sideways motion this tick.
		var fy_stop := absf(vy) * _corner_mass / delta
		fy = clampf(fy, -fy_stop, fy_stop)

		# Longitudinal: engine (rear) and brakes.
		var fx := 0.0
		var demand := 0.0
		if not front:
			fx += drive_force * 0.5
		if brake_force > 0.0:
			var share := _brake_bias if front else 1.0 - _brake_bias
			var fb := brake_force * share * 0.5
			if static_hold:
				fx += clampf(-vx * _corner_mass / delta, -fb, fb)
			else:
				fx -= signf(vx) * fb
		demand = absf(fx) / maxf(cap, 1.0)
		var assisted := (traction_control and not front and brake_force <= 0.0) or (abs_enabled and brake_force > 0.0)
		if assisted:
			# Cornering keeps priority: drive gets what's left; brakes always get 35%.
			var floor_share := 0.35 if brake_force > 0.0 else 0.08
			var avail := maxf(sqrt(maxf(cap * cap - fy * fy, 0.0)), cap * floor_share)
			fx = clampf(fx, -avail, avail)
			w.locked = false
		else:
			w.locked = demand > 1.02
			fx = clampf(fx, -cap, cap)
			if w.locked:
				fx *= 0.85                      # sliding rubber
				fy *= 0.35                      # spinning/locked tyres barely steer
		var total := sqrt(fx * fx + fy * fy)
		if total > cap:
			fx *= cap / total
			fy *= cap / total
		# Rolling resistance, much more on grass.
		var roll := 0.012
		if w.surface == 1:
			roll = 0.07 + 0.0018 * absf(vx)
		elif w.surface == 2:
			roll = 0.2 + 0.004 * absf(vx)          # gravel traps bog you down
		fx -= clampf(vx * 4.0, -1.0, 1.0) * w.load * roll

		w.utilisation = maxf(absf(alpha) * b / tan(PI / (2.0 * SLIP_SHAPE)), demand if not assisted else 0.0)
		worst = maxf(worst, w.skid())
		var lift := up * (com_g - w.contact_point).dot(up) * 0.45
		var tyre_f := fwd * fx + side * fy
		side_force += tyre_f.dot(xf.basis.x)
		apply_force(tyre_f, w.contact_point + lift - xf.origin)
		w.spin_rate = vx / w.wheel_radius
		if w.locked:
			w.spin_rate = 0.0 if fx * vx < 0.0 else w.spin_rate * 1.6
	tyre_slip = worst
	_stability(side_force, delta)


## Stability control (always on, like a modern road or race car's ESC):
## damps any difference between the yaw rate and the yaw rate the tyres'
## sideways force supports. Takes the snap out of sudden inputs and catches
## a slide before it becomes a spin; steady cornering is untouched.
func _stability(side_force: float, _delta: float) -> void:
	var v := linear_velocity.length()
	if v < 8.0:
		return
	var r := angular_velocity.dot(global_basis.y)
	var r_supported := (side_force / mass) / v      # +x force (left) -> +yaw (left)
	var k := STABILITY if traction_control else STABILITY * 0.45
	apply_torque(-global_basis.y * (r - r_supported) * k * inertia.y)


static func _anti_roll(l: CarWheel, r: CarWheel, k: float) -> void:
	if l.in_contact and r.in_contact:
		var f := (l.compression - r.compression) * k
		l.load = maxf(l.load + f, 0.0)
		r.load = maxf(r.load - f, 0.0)


func _process(delta: float) -> void:
	for w in wheels:
		w.update_visual(delta)


# ------------------------------------------------------------ construction

func _add_wheel(pos: Vector3, front: bool) -> void:
	var w := CarWheel.new()
	w.position = pos
	w.mount = pos
	w.use_as_steering = front
	w.wheel_radius = spec["radius_front"] if front else spec["radius_rear"]
	w.rest_length = _rest
	add_child(w)
	wheels.append(w)
	if front:
		front_wheels.append(w)
	else:
		rear_wheels.append(w)
	var ray := RayCast3D.new()
	ray.position = pos
	ray.target_position = Vector3(0, -(_rest + w.wheel_radius + 0.25), 0)
	ray.collision_mask = 1
	ray.enabled = false
	add_child(ray)
	_rays.append(ray)
