class_name RaceCar
extends VehicleBody3D
## A drivable car built from a spec (see car_specs.gd). Forward is +Z.
##
## Inputs (set every physics frame by a controller):
##   throttle     0..1
##   brake_input  0..1   (also reverses when nearly stopped)
##   steer_input  -1..1  (+ = right)

# Signs verified by tests/sim_test.gd against Godot's VehicleBody3D.
const STEER_SIGN := -1.0
const ENGINE_SIGN := 1.0

var spec: Dictionary = {}

var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var controls_enabled := true
var surface_drag := 0.0           # extra drag when off the road (set by race logic)
var traction_control := true
var abs_enabled := true

# Drivetrain state, read by HUD and audio.
var gear := 1                     # -1 = reverse, 1..n forward
var rpm := 1000.0
var engine_load := 0.0            # 0..1, how hard the engine is working
var tyre_slip := 0.0              # 0..1, worst wheel, for tyre squeal

var wheels: Array[VehicleWheel3D] = []
var front_wheels: Array[VehicleWheel3D] = []
var rear_wheels: Array[VehicleWheel3D] = []
var _steer := 0.0
var _shift_timer := 0.0
var _tc_factor := 1.0
var _abs_factor := 1.0

# Spec values cached as plain floats: read every tick by every car.
var _steer_low := 0.5
var _steer_high := 0.08
var _steer_full := 60.0
var _steer_rate := 2.5
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


func setup(car_spec: Dictionary) -> void:
	spec = car_spec


func _ready() -> void:
	if spec.is_empty():
		spec = CarSpecs.get_spec("gp26")
	_steer_low = spec["steer_low"]
	_steer_high = spec["steer_high"]
	_steer_full = spec["steer_full_speed"]
	_steer_rate = spec["steer_rate"]
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
	mass = spec["mass"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = spec["com"]
	can_sleep = false
	# Layer 1: the track and barriers. Layer 2: cars.
	collision_layer = 2
	collision_mask = 1 | 2
	# Godot's default damping acts like a huge invisible parachute; we model
	# aero drag ourselves, so remove it.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.4
	for c in spec["collision"]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = c[0]
		cs.shape = box
		cs.position = c[1]
		add_child(cs)
	var fz: float = spec["wheel_front_z"]
	var rz: float = spec["wheel_rear_z"]
	var wy: float = spec["wheel_y"]
	_add_wheel(Vector3(-spec["track_front"], wy, fz), true)
	_add_wheel(Vector3(spec["track_front"], wy, fz), true)
	_add_wheel(Vector3(-spec["track_rear"], wy, rz), false)
	_add_wheel(Vector3(spec["track_rear"], wy, rz), false)
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
	gear = 1
	_shift_timer = 0.0


## Seat height above the road for spawning.
func spawn_height() -> float:
	return float(spec["rest_length"]) + float(spec["radius_rear"]) - float(spec["wheel_y"]) + 0.05


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

	# Speed-sensitive, rate-limited steering.
	var max_steer := lerpf(_steer_low, _steer_high, clampf(absf(v) / _steer_full, 0.0, 1.0))
	_steer = move_toward(_steer, clampf(str_in, -1.0, 1.0) * max_steer, _steer_rate * delta)
	steering = _steer * STEER_SIGN

	# Tyre state: skidinfo is 1.0 with full grip, lower when sliding.
	var rear_grip := 1.0
	var front_grip := 1.0
	for w in rear_wheels:
		rear_grip = minf(rear_grip, w.get_skidinfo())
	for w in front_wheels:
		front_grip = minf(front_grip, w.get_skidinfo())
	tyre_slip = clampf((0.95 - minf(rear_grip, front_grip)) / 0.6, 0.0, 1.0)

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

	# Traction control: trim throttle while the rear tyres are spinning.
	if traction_control and drive > 0.0:
		_tc_factor = move_toward(_tc_factor, 0.35 if rear_grip < 0.8 else 1.0, 4.0 * delta)
		drive *= _tc_factor
	else:
		_tc_factor = 1.0
	# ABS: release brake pressure while the fronts are locking.
	if abs_enabled and braking > 0.0 and controls_enabled:
		_abs_factor = move_toward(_abs_factor, 0.6 if front_grip < 0.75 else 1.0, 6.0 * delta)
		braking *= _abs_factor
	else:
		_abs_factor = 1.0

	if _shift_timer > 0.0 and drive > 0.0:
		drive *= 0.15               # torque cut during the shift

	engine_load = clampf(drive, 0.0, 1.0)
	if drive != 0.0:
		var force := minf(_max_force, _engine_power(rpm) / maxf(absf(v), 1.0))
		engine_force = drive * force * 0.5 * ENGINE_SIGN   # per rear wheel
		brake = 0.0
	else:
		engine_force = 0.0
		var decel := minf(_brake_base + _brake_aero * v * v, _brake_max)
		var per_wheel_force := mass * decel * 0.25 * braking + 60.0
		# VehicleBody3D's brake is an impulse per wheel per physics tick.
		brake = per_wheel_force / float(Engine.physics_ticks_per_second)

	var vel := linear_velocity
	var spd := vel.length()
	apply_central_force(-vel * spd * _drag)
	var down := -global_basis.y * _downforce * v * v
	apply_force(down, global_basis * Vector3(0, 0, _down_z))
	if surface_drag > 0.0:
		var flat := Vector3(vel.x, 0.0, vel.z)
		apply_central_force(-flat * mass * surface_drag)


# ------------------------------------------------------------ construction

func _add_wheel(pos: Vector3, front: bool) -> void:
	var w := VehicleWheel3D.new()
	w.position = pos
	w.use_as_steering = front
	w.use_as_traction = not front
	w.wheel_radius = spec["radius_front"] if front else spec["radius_rear"]
	w.wheel_rest_length = spec["rest_length"]
	w.suspension_travel = spec["travel"]
	w.suspension_stiffness = spec["stiffness"]
	w.suspension_max_force = spec["max_susp_force"]
	w.damping_compression = spec["damp_comp"]
	w.damping_relaxation = spec["damp_relax"]
	w.wheel_friction_slip = spec["grip_front"] if front else spec["grip_rear"]
	w.wheel_roll_influence = spec["roll_influence"]
	add_child(w)
	wheels.append(w)
	if front:
		front_wheels.append(w)
	else:
		rear_wheels.append(w)
