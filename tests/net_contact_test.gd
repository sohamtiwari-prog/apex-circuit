extends SceneTree
## Multiplayer contact, with the network in the loop: two cars, each
## "driven on its own phone" (both AI-driven here), each seeing the other
## only through the network code (NetRace: states 20 times a second, a
## one-way latency, the interpolation delay, the forward prediction) and
## pushed only by its own phone's contact (CarContacts.step_against).
## Scenarios: following closely in the slipstream (no contact should
## happen), squeezes and rear-corner taps (light ones mustn't unsettle
## anyone). Pass "old" to measure the previous model for comparison.
##   godot --headless --fixed-fps 120 --script res://tests/net_contact_test.gd [-- old]
var failures: Array[String] = []
var track: Track
var real: Array = []           # the two cars, each simulated on "its" phone
var proxy: Array = []          # proxy[k]: car k as drawn on the other phone
var drivers: Array = []
var phones: Array = []         # phones[k]: car k's phone (sees the other car)
var ents: Array = []           # fake entrants for the proxies
var sent: Array = [[], []]     # in-flight packets: [arrive_time, state_time, state]
var touching := [{}, {}]
var old := false
var latency := 0.06            # one way, seconds (good Wi-Fi ~0.01-0.03, online 0.05-0.15)
var t := 0.0


class FakeNet extends Node:
	func is_host() -> bool:
		return true


class FakeEntrant:
	var slot := 0
	var car: RaceCar
	var pit_phase := 0
	var pit_box := -1.0
	var team_idx := 0
	var compound := "medium"
	var next_compound := "medium"
	var wear := 0.0


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


func _place(c: RaceCar, i: int, lat: float, v: float, ahead := 0.0) -> void:
	c.global_transform = track.pose_at(i, c.spawn_height(), lat)
	c.global_position += c.global_basis.z * ahead
	c.angular_velocity = Vector3.ZERO
	c.reset_controls()
	c.controls_enabled = true
	c.linear_velocity = c.global_basis.z * v


func _reset_net() -> void:
	for k in 2:
		var ph: NetRace = phones[k]
		ph._buffers.clear()
		ph._yaw_rate.clear()
		ph.delay = 1.0 / NetRace.SEND_HZ + 0.05 + latency * 0.5
		sent[k].clear()
		touching[k].clear()


## The previous model: three circles per car, a spring on this phone's car
## at the circle (off-centre), against the car where it was drawn.
func _old_contact(c: RaceCar, o: RaceCar) -> void:
	var cp := c.global_position
	if cp.distance_squared_to(o.global_position) > 64.0:
		return
	for a in _circles(c):
		for b in _circles(o):
			var d: Vector3 = a - b
			d.y = 0.0
			var dist := d.length()
			var pen := 2.1 - dist
			if pen <= 0.0:
				continue
			var n := d / maxf(dist, 0.01)
			var rel := (c.linear_velocity - o.remote_vel).dot(n)
			c.apply_force(n * (c.mass * (55.0 * pen - 5.0 * minf(rel, 0.0))), a - cp)


static func _circles(c: RaceCar) -> Array:
	var b := c.global_basis
	var p := c.global_position
	var half := (float(c.spec["wheel_front_z"]) - float(c.spec["wheel_rear_z"])) * 0.5 + 0.55
	return [p + b.z * half * 0.72, p, p - b.z * half * 0.72]


func _drive(secs: float, lanes: Array, push: Callable) -> Array:
	var stats := [{}, {}]
	for k in 2:
		stats[k] = {"yaw": 0.0, "head": 0.0, "off": -INF, "v0": (real[k] as RaceCar).forward_speed(), "vmin": INF, "touch": 0, "overlap": 0.0}
	var send_t := 0.0
	var dt := 1.0 / 120.0
	for f in int(secs * 120.0):
		var tt := f / 120.0
		for k in 2:
			var d: AIDriver = drivers[k]
			d.lane_offset = float(lanes[k]) + (float(push.call(tt)) if k == 1 else 0.0)
			d.update(real[k], track)
		await physics_frame
		t += dt
		# Each phone sends its car 20 times a second; it arrives `latency` later.
		send_t -= dt
		if send_t <= 0.0:
			send_t = 1.0 / NetRace.SEND_HZ
			for k in 2:
				sent[k].append([t + latency, t, NetRace.car_state(real[k])])
		for k in 2:
			var other := 1 - k
			var ph: NetRace = phones[k]
			ph._sim = t
			while not sent[other].is_empty() and float(sent[other][0][0]) <= t:
				var pkt: Array = sent[other].pop_front()
				ph._push(other, pkt[2], pkt[1])
			if old:
				# The old drawing: interpolated, not carried forward.
				ph._drive_remote_lead(ents[other], t - ph.delay, 0.0)
			else:
				ph._drive_remote(ents[other], t - ph.delay)
		# Contact: each phone pushes only its own car.
		for k in 2:
			var c: RaceCar = real[k]
			var o: RaceCar = proxy[1 - k]
			if old:
				_old_contact(c, o)
			else:
				var kicks := {}
				var hits := CarContacts.step_against([c], [o], dt, touching[k], kicks)
				stats[k]["touch"] += hits.size()
				if kicks.has(o):
					(phones[k] as NetRace).add_kick(1 - k, kicks[o])
		var ca := CarContacts.capsule(real[0])
		var cb := CarContacts.capsule(real[1])
		var pts := CarContacts._closest(ca[0], ca[1], cb[0], cb[1])
		var ov: float = float(ca[2]) + float(cb[2]) - (pts[1] - pts[0]).length()
		stats[0]["overlap"] = maxf(stats[0]["overlap"], ov)
		for k in 2:
			var c: RaceCar = real[k]
			var s: Dictionary = stats[k]
			var i := track.track_index(c.global_position, (drivers[k] as AIDriver).idx)
			var fwd := Vector3(c.global_basis.z.x, 0, c.global_basis.z.z).normalized()
			s["head"] = maxf(s["head"], rad_to_deg(acos(clampf(fwd.dot(track.htangents[i]), -1.0, 1.0))))
			s["yaw"] = maxf(s["yaw"], absf(c.angular_velocity.y - c.forward_speed() * track.curv[i]))
			s["off"] = maxf(s["off"], absf(track.lateral(c.global_position, i)) - (track.road_half + Track.KERB_W))
			s["vmin"] = minf(s["vmin"], c.forward_speed())
	return stats


func _report(name: String, st: Array) -> Array:
	var head := 0.0
	var off := -INF
	var vloss := 0.0
	var yaw := 0.0
	for k in 2:
		var s: Dictionary = st[k]
		print("    %-30s car %d: yaw %.2f rad/s, turned %4.1f deg, %s, speed %3.0f -> min %3.0f km/h%s" % [
			name, k, s["yaw"], s["head"], ("%.1f m OFF" % s["off"]) if s["off"] > 0.0 else "on track", s["v0"] * 3.6, minf(s["vmin"], s["v0"]) * 3.6,
			("   (cars overlapped %.2f m at most, %d touches)" % [st[0]["overlap"], st[0]["touch"] + st[1]["touch"]]) if k == 1 else ""])
		head = maxf(head, s["head"])
		off = maxf(off, s["off"])
		vloss = maxf(vloss, (s["v0"] - minf(s["vmin"], s["v0"])) * 3.6)
		yaw = maxf(yaw, s["yaw"])
	return [head, off, vloss, yaw, st[0]["overlap"]]


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	old = args.has("old")
	for a in args:
		if a.begins_with("latency="):
			latency = float(a.substr(8))
	var world := Node3D.new()
	root.add_child(world)
	track = Track.new()
	world.add_child(track)
	track.build("silvermoor")
	for k in 2:
		var c := RaceCar.new()
		c.setup(CarSpecs.get_spec("gp26", k))
		world.add_child(c)
		real.append(c)
		var p := RaceCar.new()
		p.setup(CarSpecs.get_spec("gp26", k))
		world.add_child(p)
		NetRace.make_remote(p)
		proxy.append(p)
		var d := AIDriver.new()
		d.skill = 0.97
		drivers.append(d)
		var ph := NetRace.new()
		ph.Net = FakeNet.new()
		world.add_child(ph)
		ph.set_process(false)
		phones.append(ph)
		var fe := FakeEntrant.new()
		fe.slot = k
		fe.car = p
		ents.append(fe)
	await physics_frame
	print("model: %s, one-way latency %.0f ms" % ["old" if old else "new", latency * 1000.0])
	var s0 := _straight_start(600.0)
	var n := track.size()

	# 1. Following in the slipstream, 9 m between centres (a car length clear).
	var i1 := (s0 + 20) % n
	_reset_net()
	_place(real[0], i1, 0.0, 70.0, 9.0)
	_place(real[1], i1, 0.0, 70.0)
	for d in drivers:
		(d as AIDriver).idx = i1
		(d as AIDriver).speed_cap = 70.0
	var lane: float = -track.line_offset[i1]
	var r1 := _report("following 9 m behind at 250 km/h", await _drive(3.0, [lane, lane], func(_x: float) -> float: return 0.0))
	for d in drivers:
		(d as AIDriver).speed_cap = 999.0

	# 2. Squeezes: side by side, the second car drifts across into the first.
	var squeeze_ok := true
	for drift in [1.0, 2.5]:
		var i := (s0 + 60) % n
		_reset_net()
		_place(real[0], i, -1.4, 60.0)
		_place(real[1], i, 1.4, 60.0)
		for d in drivers:
			(d as AIDriver).idx = i
		var r := _report("squeeze at %.1f m/s" % drift, await _drive(3.0, [-1.4 - track.line_offset[i], 1.4 - track.line_offset[i]], func(x: float) -> float: return -minf(x * drift, 3.2)))
		squeeze_ok = squeeze_ok and r[0] < 12.0 and r[1] < 0.5 and r[4] < 0.6

	# 3. Rear-corner taps.
	var tap_ok := true
	for cs in [[2.0, 0.9], [5.0, 1.1]]:
		var i := (s0 + 110) % n
		_reset_net()
		_place(real[0], i, 0.0, 50.0, 7.0)
		_place(real[1], i, float(cs[1]), 50.0 + float(cs[0]))
		for d in drivers:
			(d as AIDriver).idx = i
		var ln: float = -track.line_offset[i]
		var r := _report("rear-corner tap %.0f m/s" % cs[0], await _drive(3.0, [ln, ln + float(cs[1])], func(_x: float) -> float: return 0.0))
		tap_ok = tap_ok and r[0] < 12.0 and r[1] < 0.5 and r[4] < 0.8

	_check(r1[3] < 0.3 and r1[0] < 3.0, "following closely: no phantom contact from the network delay (yaw %.2f rad/s)" % r1[3])
	_check(squeeze_ok, "side-by-side squeezes stay light with the network in between")
	_check(tap_ok, "rear-corner taps don't spin anyone with the network in between")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
