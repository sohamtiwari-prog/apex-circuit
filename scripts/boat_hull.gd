class_name BoatHull
extends RefCounted
## How a racing powerboat (a tunnel-hull catamaran) moves on the water
## (scripts/water.gd). The car code (scripts/car.gd) hands a boat's physics
## to this each step; the inputs, steering and everything the race reads
## (speed, rpm, engine load) stay the car's.
##
## Points along the bottoms of the two sponsons (spec "hull_points") each
## find the water under them every step:
##   - buoyancy: the water they're down in holds them up (Archimedes), with
##     damping, so the boat bobs, pitches and rolls over the swell;
##   - planing lift: water striking the hull at speed lifts it, so the boat
##     rises until only the back of the sponsons skims (and the drag falls);
##   - drag: the wetted hull's skin friction, plus the "hump" of pushing a
##     bow wave at low speed, before it's up on the plane;
## the tunnel's air cushion lifts it more at speed; the outboard pushes at
## the stern, below the water, and loses its bite when the boat leaves the
## water (the engine screams, the boat coasts). Other boats' wakes are
## bumps in the water (scripts/water.gd): cross one and the hull hops. It turns by the outboard
## swinging the stern round and the sponsons' edges gripping the water: a
## turn asks for a yaw rate, the hull's grip (it carries ~2 g, more than a
## car on road tyres) bends the path to follow, and past it the boat slides
## wide. It leans into the turn the way tunnel hulls do.

const RHO := 1000.0                # water, kg/m^3
const G := 9.81
const DEPTH_CAP := 0.5             # the sponsons are this deep: no more lift from deeper
const WET_DEPTH := 0.18            # a point this far under counts as fully wetted
const HEAVE_DAMP := 1700.0         # N per (m/s) per m^2 of hull
const PLANE_LIFT := 0.0032         # lift coefficient of the planing bottom
const SKIN := 0.7                  # N per (m/s)^2 per m^2 wetted
const HUMP := 2600.0               # N at the hump speed, fully wetted
const HUMP_SPEED := 9.0            # m/s
const SIDE_GRIP := 9.0             # 1/s: how quickly sideways drift is stopped (within grip)
const YAW_GAIN := 16.0             # 1/s: how quickly the yaw rate follows the steering
const PROP_EFF := 0.66

var points: Array[Vector3] = []
var area := 0.4
var prop := Vector3(0, -0.3, -3.1)
var mu := 2.2
var aero_lift := 0.0
var thrust_max := 6000.0
var top_speed := 60.0
var wet_frac := 0.0                 # share of the hull in the water (spray, sound)
var airborne := false
var prop_bite := 1.0
var contact := 1.0                  # smoothed share of the boat's weight the water carries
var dbg_r_want := 0.0
var slam := 0.0                     # how hard the bow last hit the water (m/s): spray
var over_wake := false              # crossing another boat's wake
var _tick := 0
var _surf := PackedFloat32Array()   # water height under each point (refreshed in turn)
var _rise := PackedFloat32Array()
var _near: Array = []               # other boats' wake points nearby
var _near_owner := 0
var slide := 0.0                    # sideways slide, 0..1 (spray)


func setup(spec: Dictionary) -> void:
	for p in spec["hull_points"]:
		points.append(p)
	area = float(spec["hull_area"]) / points.size()
	prop = spec["prop"]
	mu = float(spec["mu_front"]) * 1.08
	aero_lift = float(spec.get("aero_lift", 0.0))
	thrust_max = float(spec["max_drive_force"])
	top_speed = float(spec["top_kmh"]) / 3.6


func step(car: RaceCar, delta: float, steer_angle: float) -> void:
	var b := car.global_basis
	var origin := car.global_position
	var com := origin + b * car.center_of_mass
	var vel := car.linear_velocity
	var w := car.angular_velocity
	var m := car.mass
	var fwd_h := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var right_h := Vector3(b.x.x, 0.0, b.x.z).normalized()       # (the car's +x: its left)
	var v := vel.dot(fwd_h)

	# --- the hull in the water (and over other boats' wakes)
	# The water under each point is looked up every other step, half the
	# points at a time (a phone does eight boats' sums at 120 a second; the
	# water under a point barely changes in one step).
	_tick += 1
	if _tick % 4 == 1 or _near_owner != car.get_instance_id():
		_near = Water.wakes_near(origin, car.get_instance_id())
		_near_owner = car.get_instance_id()
	var load := 0.0
	var wetted := 0.0
	var hit := 0.0
	if _surf.size() != points.size():
		_surf.resize(points.size())
		_rise.resize(points.size())
		_surf.fill(INF)
	for pi in points.size():
		var p: Vector3 = points[pi]
		var wp := origin + b * p
		if (pi + _tick) % 2 == 0 or _surf[pi] == INF:
			var surf := Water.height(wp.x, wp.z)
			if not _near.is_empty():
				surf += Water.wake_height(wp.x, wp.z, _near)
			_surf[pi] = surf
			_rise[pi] = Water.rise_rate(wp.x, wp.z)
		var depth := _surf[pi] - wp.y
		if depth <= 0.0:
			continue
		var rise := _rise[pi]
		var pv := vel + w.cross(wp - com)
		var wet := clampf(depth / WET_DEPTH, 0.0, 1.0)
		# (How hard the bow comes down into the water: spray.)
		if p.z > 1.0:
			hit = maxf(hit, -(pv.y - rise))
		var up := RHO * G * area * minf(depth, DEPTH_CAP)
		up -= HEAVE_DAMP * area * (pv.y - rise) * clampf(depth / 0.03, 0.0, 1.0)
		# (The planing surfaces are the flat aft two thirds of the sponsons;
		# the fine bow just parts the water.)
		var along := maxf(pv.dot(fwd_h), 0.0)
		var planing := clampf((1.8 - p.z) / 1.2, 0.15, 1.0)
		up += PLANE_LIFT * 0.5 * RHO * along * along * area * wet * planing
		up = maxf(up, 0.0)
		load += up
		wetted += area * wet
		# Skin friction and the bow wave, against the way this bit of hull moves.
		var hv := Vector3(pv.x, 0.0, pv.z)
		var sp := hv.length()
		var drag := 0.0
		if sp > 0.01:
			var hump := HUMP * exp(-pow((sp - HUMP_SPEED) / 4.5, 2.0)) * area / (area * points.size())
			drag = (SKIN * sp * sp * area + hump) * wet
			car.apply_force(-hv / sp * drag + Vector3.UP * up, wp - origin)
		else:
			car.apply_force(Vector3.UP * up, wp - origin)
	wet_frac = clampf(wetted / maxf(area * points.size(), 0.001), 0.0, 1.0)
	slam = maxf(slam - delta * 6.0, hit)
	over_wake = not _near.is_empty()
	airborne = load <= 0.0
	# How firmly the hull is on the water, smoothed over the skips from crest
	# to crest (a planing hull is in the air half the time at speed).
	# (Measured against the weight the air cushion leaves on the water.)
	var on_water := maxf(m * G - aero_lift * v * absf(v), m * G * 0.3)
	contact = lerpf(contact, clampf(load / (on_water * 0.28), 0.0, 1.0), clampf(delta * 4.0, 0.0, 1.0))
	var in_water := clampf(contact * 1.4, 0.0, 1.0)

	# --- the tunnel's air cushion and the air
	car.apply_central_force(Vector3.UP * aero_lift * v * absf(v))
	car.apply_central_force(-vel * vel.length() * float(car.spec["drag"]))

	# --- the outboard
	var pp := origin + b * prop
	var prop_depth := Water.height(pp.x, pp.z) - pp.y
	prop_bite = clampf((prop_depth + 0.06) / 0.2, 0.0, 1.0)
	var thr := car.throttle if car.controls_enabled else 0.0
	var brk := car.brake_input if car.controls_enabled else 0.0
	var thrust := 0.0
	if thr > 0.01:
		thrust = thr * minf(thrust_max, float(car.spec["power"]) * PROP_EFF / maxf(absf(v), 3.0))
	elif brk > 0.05 and v < 1.5 and not car.no_reverse:
		thrust = -brk * thrust_max * 0.3                         # reverse gear
	thrust *= prop_bite
	if thrust != 0.0:
		car.apply_force(fwd_h * thrust, pp - origin)
	# "Braking": off the throttle, the engine trimmed in, the bow digs in.
	if brk > 0.05 and v > 1.5:
		var dec := minf(float(car.spec["brake_base"]), v * 1.5) * brk * in_water
		car.apply_central_force(-fwd_h * dec * m)
	if not car.controls_enabled and v > 0.0:
		car.apply_central_force(-fwd_h * minf(4.0, v * 2.0) * m * in_water)

	# --- turning: the steering asks for a yaw rate; the hull's grip decides
	# how much of it the path follows.
	var grip := mu * G * in_water
	var wb := maxf(float(car.spec["wheel_front_z"]) - float(car.spec["wheel_rear_z"]), 1.0)
	var r_want := v * tan(steer_angle) / wb
	var r_cap := grip * 1.05 / maxf(absf(v), 4.0) + 0.05
	r_want = clampf(r_want, -r_cap, r_cap)
	dbg_r_want = r_want
	# (At a crawl the outboard swings the stern round on its own.)
	r_want += steer_angle * thr * clampf(1.0 - absf(v) / 8.0, 0.0, 1.0) * 1.2 * prop_bite
	var r := w.dot(Vector3.UP)
	var authority := maxf(in_water, 0.15)
	car.apply_torque(Vector3.UP * (r_want - r) * YAW_GAIN * car.inertia.y * authority)
	# Sideways drift: the sponsons' edges stop it, up to their grip.
	var v_lat := vel.dot(right_h)
	var f_lat := clampf(-v_lat * SIDE_GRIP * m, -grip * m, grip * m)
	car.apply_force(right_h * f_lat, b * (car.center_of_mass + Vector3(0, 0.0, -0.25)))
	# Turning scrubs speed: the sponsons' edges dig in.
	car.apply_central_force(-fwd_h * absf(f_lat) * 0.12 * signf(v))
	# Lean into the turn (tunnel hulls bank inwards, like a motorbike).
	var a_lat := f_lat / m
	var roll := asin(clampf(b.x.y, -1.0, 1.0))               # + : left side up
	var lean := clampf(a_lat / G * 0.09, -0.3, 0.3)          # the inside side down
	car.apply_torque(fwd_h * (lean + roll) * -40.0 * car.inertia.z * in_water)
	# Pitch and roll steadiness from the water (and a little from the air).
	var pr := w - Vector3.UP * r
	car.apply_torque(-pr * (0.8 + 3.0 * in_water) * car.inertia.x * 0.5)

	# --- the engine: the propeller's slip at low speed, free revs out of the water
	var idle := float(car.spec["idle_rpm"])
	var red := float(car.spec["redline"])
	var on_load := clampf(absf(v) / top_speed, 0.0, 1.0)
	var slip := thr * clampf(1.0 - absf(v) / 18.0, 0.0, 1.0) * 0.5
	var want := idle + (red - idle) * clampf(on_load * 0.92 + slip + thr * 0.08, 0.0, 1.0)
	if thr > 0.3 and prop_bite < 0.3:
		want = red * 1.02                                     # out of the water: over-revs
	car.rpm = move_toward(car.rpm, want, (red - idle) * 3.0 * delta)
	car.gear = -1 if thrust < 0.0 else 1
	car.engine_load = thr
	car.tyre_slip = 0.0
	slide = clampf(absf(v_lat) / 8.0, 0.0, 1.0) * in_water
