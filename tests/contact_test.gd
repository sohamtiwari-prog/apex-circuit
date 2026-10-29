extends SceneTree
## Racing contact with drivers at the wheel (AI drivers on both cars, as in a
## race): light touches must stay light. For each scenario (side-by-side
## squeeze, a tap on a rear corner, contact mid-corner, a late-braking
## rear-end) it measures what the contact does to each car over the next
## 3 seconds: yaw rate, how far it turns away from the direction of the
## track, whether it leaves the track, how much speed it loses.
##   godot --headless --fixed-fps 120 --script res://tests/contact_test.gd
var failures: Array[String] = []
var cars: Array = []
var drivers: Array = []
var touching := {}
var track: Track


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _straight_start(min_len: float) -> int:
	var n := track.size()
	var run := 0
	for i in range(n * 2):
		if absf(track.curv[i % n]) < 1.0 / 1500.0:
			run += 1
			if run * Track.SPACING >= min_len:
				return (i - run + 1) % n
		else:
			run = 0
	return 0


## A corner of radius 60..200 m with a straight run-in, by sample.
func _corner() -> int:
	var n := track.size()
	for i in range(n):
		var r := 1.0 / maxf(absf(track.curv[i]), 1e-6)
		if r > 70.0 and r < 220.0:
			var ok := true
			for k in range(1, 40):
				if absf(track.curv[(i - k + n) % n]) > 1.0 / 300.0 and k > 25:
					ok = false
			if ok:
				return i
	return 0


func _place(c: RaceCar, i: int, lat: float, v: float) -> void:
	c.global_transform = track.pose_at(i, c.spawn_height(), lat)
	c.angular_velocity = Vector3.ZERO
	c.reset_controls()
	c.controls_enabled = true
	c.linear_velocity = c.global_basis.z * v
	c.tyre_slip = 0.0 if c.get("tyre_slip") != null else 0.0


## Drives both cars for `secs`, with `push` steering the second car's lane
## (metres right of the line) over time. Returns per-car stats.
var hands_off := false        # car 0 holds its controls (a player who doesn't react)

func _drive(secs: float, lanes: Array, push: Callable, caps: Array = [999.0, 999.0]) -> Array:
	var n := track.size()
	var stats := [{}, {}]
	for k in 2:
		stats[k] = {"yaw": 0.0, "head": 0.0, "off": -INF, "v0": (cars[k] as RaceCar).forward_speed(), "vmin": INF, "contact": false}
	var frames := int(secs * 120.0)
	for f in frames:
		var t := f / 120.0
		for k in 2:
			var d: AIDriver = drivers[k]
			d.lane_offset = float(lanes[k]) + (float(push.call(t)) if k == 1 else 0.0)
			d.speed_cap = float(caps[k])
			d.update(cars[k], track)
			if k == 0 and hands_off:
				(cars[0] as RaceCar).steer_input = 0.0
				(cars[0] as RaceCar).throttle = 0.6
				(cars[0] as RaceCar).brake_input = 0.0
		await physics_frame
		var began := CarContacts.step(cars, 1.0 / 120.0, touching)
		for k in 2:
			var c: RaceCar = cars[k]
			var s: Dictionary = stats[k]
			if not touching.is_empty():
				s["contact"] = true
			if s["contact"]:
				var i := track.track_index(c.global_position, (drivers[k] as AIDriver).idx)
				var fwd := Vector3(c.global_basis.z.x, 0, c.global_basis.z.z).normalized()
				var head := rad_to_deg(acos(clampf(fwd.dot(track.htangents[i]), -1.0, 1.0)))
				s["head"] = maxf(s["head"], head)
				s["yaw"] = maxf(s["yaw"], absf(c.angular_velocity.y - c.forward_speed() * track.curv[i]))
				s["off"] = maxf(s["off"], absf(track.lateral(c.global_position, i)) - (track.road_half + Track.KERB_W))
				s["vmin"] = minf(s["vmin"], c.forward_speed())
	return stats


func _report(name: String, st: Array) -> Array:
	var worst_head := 0.0
	var worst_off := -INF
	var worst_yaw := 0.0
	for k in 2:
		var s: Dictionary = st[k]
		print("    %-34s car %d: yaw %.2f rad/s, turned %.1f deg off the track's line, %s, speed %.0f -> min %.0f km/h%s" % [
			name, k, s["yaw"], s["head"], ("%.1f m OFF TRACK" % s["off"]) if s["off"] > 0.0 else "stayed on", s["v0"] * 3.6, minf(s["vmin"], s["v0"]) * 3.6, "" if s["contact"] else " (no contact)"])
		worst_head = maxf(worst_head, s["head"])
		worst_off = maxf(worst_off, s["off"])
		worst_yaw = maxf(worst_yaw, s["yaw"])
	return [worst_head, worst_off, worst_yaw, st[0]["contact"] or st[1]["contact"]]


func _run() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	track = Track.new()
	world.add_child(track)
	track.build(OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "silvermoor")
	for k in 2:
		var c := RaceCar.new()
		c.setup(CarSpecs.get_spec("gp26", k))
		world.add_child(c)
		cars.append(c)
		var d := AIDriver.new()
		d.skill = 0.97
		drivers.append(d)
	await physics_frame
	hands_off = OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "hands_off"
	var s0 := _straight_start(500.0)
	var corner := _corner()
	var n := track.size()
	var light_ok := true
	var light_on := true
	var firm_ok := true

	# 1. Side by side on a straight, the second car drifts across into the first.
	for drift in [0.8, 1.5, 3.0]:
		var i := (s0 + 20) % n
		_place(cars[0], i, -1.4, 60.0)
		_place(cars[1], i, 1.4, 60.0)
		for d in drivers:
			(d as AIDriver).idx = i
		var lane0: float = -1.4 - track.line_offset[i]
		var lane1: float = 1.4 - track.line_offset[i]
		var r := _report("squeeze at %.1f m/s" % drift, await _drive(3.0, [lane0, lane1], func(t: float) -> float: return -minf(t * drift, 3.2)))
		if drift <= 1.5:
			light_ok = light_ok and r[0] < 8.0 and r[2] < 0.5
			light_on = light_on and r[1] < 0.0
		else:
			firm_ok = firm_ok and r[0] < 25.0 and r[1] < 1.5

	# 2. A tap on a rear corner (the car behind half a car to one side).
	for cs in [[2.0, 0.9], [4.0, 1.1], [8.0, 1.2]]:
		var closing: float = cs[0]
		var off: float = cs[1]
		var i := (s0 + 60) % n
		_place(cars[0], i + 4, 0.0, 50.0)
		_place(cars[1], i, off, 50.0 + closing)
		(cars[1] as RaceCar).global_position += (cars[1] as RaceCar).global_basis.z * 1.0
		for d in drivers:
			(d as AIDriver).idx = i
		var lane: float = -track.line_offset[i]
		var r := _report("rear-corner tap %.0f m/s, %.1f m across" % [closing, off], await _drive(3.0, [lane, lane + off], func(_t: float) -> float: return 0.0))
		if closing <= 4.0:
			light_ok = light_ok and r[0] < 10.0 and r[2] < 0.6
			light_on = light_on and r[1] < 0.0
		else:
			firm_ok = firm_ok and r[0] < 30.0 and r[1] < 1.5

	# 3. Mid-corner: side by side through a bend, the outside car runs wide-in.
	if corner > 0:
		var i := (corner - 30 + n) % n
		var prof := track.speed_profile((cars[0] as RaceCar).spec)
		var v := minf(prof[i], prof[corner]) * 0.9
		_place(cars[0], i, -1.4, v)
		_place(cars[1], i, 1.4, v)
		for d in drivers:
			(d as AIDriver).idx = i
		var inner := -1.4 - track.line_offset[i]
		var outer := 1.4 - track.line_offset[i]
		var sgn := 1.0
		var r := _report("mid-corner touch", await _drive(3.0, [inner, outer], func(t: float) -> float: return -minf(t * 1.2, 2.6) * sgn, [v, v]))
		light_ok = light_ok and r[0] < 12.0
		light_on = light_on and r[1] < 0.5

	# 4. Rear-end under braking: the car behind brakes late.
	var ib := (s0 + 100) % n
	_place(cars[0], ib + 5, 0.0, 55.0)
	_place(cars[1], ib, 0.0, 61.0)
	for d in drivers:
		(d as AIDriver).idx = ib
	var lane_b: float = -track.line_offset[ib]
	var rb := _report("late-braking rear-end", await _drive(3.0, [lane_b, lane_b], func(_t: float) -> float: return 0.0, [30.0, 55.0]))
	firm_ok = firm_ok and rb[0] < 30.0 and rb[1] < 1.5

	# 5. Brushing the barrier: flat out down a straight, angled into the wall.
	var wall_ok := true
	for ang in [2.0, 5.0, 9.0]:
		var iw := (s0 + 140) % n
		var wl: float = track.wall_at(iw, 1.0)
		var c: RaceCar = cars[0]
		c.global_transform = track.pose_at(iw, c.spawn_height(), wl - 2.2)
		c.global_basis = Basis(Vector3.UP, -deg_to_rad(ang)) * c.global_basis
		c.angular_velocity = Vector3.ZERO
		c.reset_controls()
		c.controls_enabled = true
		c.linear_velocity = c.global_basis.z * 60.0
		(cars[1] as RaceCar).global_position = track.points[(iw + n / 2) % n] + Vector3(0, 3, 0)
		(cars[1] as RaceCar).linear_velocity = Vector3.ZERO
		var yaw := 0.0
		var head := 0.0
		var vmin := 60.0
		var d0: AIDriver = drivers[0]
		d0.idx = iw
		for f in 360:
			# Hands off (what the barrier itself does to the car).
			if f < 360:
				c.steer_input = 0.0
				c.throttle = 0.8
				c.brake_input = 0.0
			else:
				d0.lane_offset = 0.0
				d0.update(c, track)
			await physics_frame
			var i := track.track_index(c.global_position, d0.idx)
			var fwd := Vector3(c.global_basis.z.x, 0, c.global_basis.z.z).normalized()
			head = maxf(head, rad_to_deg(acos(clampf(fwd.dot(track.htangents[i]), -1.0, 1.0))))
			yaw = maxf(yaw, absf(c.angular_velocity.y - c.forward_speed() * track.curv[i]))
			vmin = minf(vmin, c.forward_speed())
		var after := rad_to_deg(Vector3(c.global_basis.z.x, 0, c.global_basis.z.z).normalized().signed_angle_to(track.htangents[track.track_index(c.global_position, d0.idx)], Vector3.UP))
		print("    barrier brush at %.0f deg, 216 km/h, hands off: yaw %.2f rad/s, turned up to %.1f deg (now %.1f deg), slowest %.0f km/h, %.1f m from the wall" % [ang, yaw, head, after, vmin * 3.6, track.wall_at(track.track_index(c.global_position, d0.idx), 1.0) - track.lateral(c.global_position, track.track_index(c.global_position, d0.idx))])
		wall_ok = wall_ok and head < ang + 5.0 and absf(after) < 4.0 and vmin > 50.0
	_check(wall_ok, "brushing the barrier at speed glances off it: no spin, hardly any speed lost")

	_check(light_ok, "light touches don't unsettle either car (under ~10 deg, no big yaw)")
	_check(light_on, "and neither car is pushed off the track by them")
	_check(firm_ok, "firmer hits don't spin anyone or fire them off the circuit")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
