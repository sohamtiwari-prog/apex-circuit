extends SceneTree
## Car-to-car contact (scripts/car_contacts.gd): rear-end hits at several
## closing speeds, straight and offset, and side-by-side rubbing. A tap is a
## tap: the car hit gains under half the closing speed, the hitter loses a
## bit more; no launches, no spins from nudges, cars never pass through each
## other, and rubbing wheels barely changes anyone's speed.
var failures: Array[String] = []
var cars: Array = []
var touching := {}
var hits := []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _step() -> void:
	await physics_frame
	for h in CarContacts.step(cars, 1.0 / 120.0, touching):
		hits.append(h[2])
func _overlap() -> float:
	var ca := CarContacts.capsule(cars[0])
	var cb := CarContacts.capsule(cars[1])
	var pts := CarContacts._closest(ca[0], ca[1], cb[0], cb[1])
	return float(ca[2]) + float(cb[2]) - (pts[1] - pts[0]).length()
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var track := Track.new()
	world.add_child(track)
	track.build("silvermoor")
	for k in 2:
		var c := RaceCar.new()
		c.setup(CarSpecs.get_spec("gp26"))
		world.add_child(c)
		cars.append(c)
	await physics_frame
	var n := track.size()
	var best := 0
	var run := 0
	var start := 0
	for i in range(n * 2):
		if absf(track.curv[i % n]) < 1.0 / 2000.0:
			run += 1
			if run > best:
				best = run
				start = (i - run + 1) % n
		else:
			run = 0
	var ok_split := true
	var ok_spin := true
	var ok_overlap := true
	for cs in [[3.0, 0.0], [6.0, 0.0], [12.0, 0.0], [20.0, 0.0], [6.0, 1.0], [12.0, 1.2]]:
		var closing: float = cs[0]
		var offset: float = cs[1]
		var i0 := (start + 40) % n
		var front: RaceCar = cars[0]
		var back: RaceCar = cars[1]
		var v0 := 50.0
		front.global_transform = track.pose_at(i0 + 4, front.spawn_height())
		back.global_transform = track.pose_at(i0, back.spawn_height(), offset)
		for c in cars:
			c.angular_velocity = Vector3.ZERO
			c.reset_controls()
			c.controls_enabled = true
		front.linear_velocity = front.global_basis.z * v0
		back.linear_velocity = back.global_basis.z * (v0 + closing)
		# Start about a metre apart (centres 7 m) so even slow closes touch.
		back.global_position -= back.global_basis.z * -1.0
		var vf := []
		var vb := []
		var yaw := 0.0
		var lift := 0.0
		var worst := 0.0
		hits.clear()
		for f in 320:
			front.throttle = 0.55
			back.throttle = 0.55
			await _step()
			vf.append(front.forward_speed())
			vb.append(back.forward_speed())
			yaw = maxf(yaw, maxf(absf(front.angular_velocity.y), absf(back.angular_velocity.y)))
			if f > 60:
				lift = maxf(lift, absf(front.linear_velocity.y) + absf(back.linear_velocity.y))
			worst = maxf(worst, _overlap())
		var hit := -1
		for f in range(1, vf.size()):
			if hit < 0 and vf[f] - vf[f - 1] > 0.2:
				hit = f
		if hit < 0:
			print("    closing %4.1f: no contact" % closing)
			ok_split = false
			continue
		# The cars' own acceleration over the same time, from the frames before.
		var drift_f: float = (vf[hit - 1] - vf[maxi(hit - 11, 0)]) / 10.0
		var drift_b: float = (vb[hit - 1] - vb[maxi(hit - 11, 0)]) / 10.0
		var after := mini(hit + 15, vf.size() - 1)
		var dvf: float = vf[after] - vf[hit - 1] - drift_f * (after - hit + 1)
		var dvb: float = vb[after] - vb[hit - 1] - drift_b * (after - hit + 1)
		print("    closing %4.1f m/s, offset %.1f m: car ahead %+5.1f, car behind %+5.1f m/s; overlap %.2f m; yaw %.2f rad/s; vertical %.2f m/s" % [closing, offset, dvf, dvb, worst, yaw, lift])
		if dvf > closing * 0.45 + 0.4 or -dvb > closing * 0.72 + 0.4 or dvf < closing * 0.2 - 0.4:
			ok_split = false
		if (offset > 0.0 and closing <= 6.0 and yaw > 0.6) or yaw > 1.5:
			ok_spin = false
		if worst > 0.5:
			ok_overlap = false
	_check(ok_split, "the car hit gains under half the closing speed; the hitter takes a bit more")
	_check(ok_spin, "nudges don't spin anyone")
	_check(ok_overlap, "cars never drive through each other (overlap under 0.5 m even at 20 m/s)")
	_check(hits.size() > 0, "contacts are reported (for incident counting)")

	# Side by side, drifting together at 2 m/s: rubbing, not braking.
	var i1 := (start + 120) % n
	var l: RaceCar = cars[0]
	var r: RaceCar = cars[1]
	l.global_transform = track.pose_at(i1, l.spawn_height(), -1.3)
	r.global_transform = track.pose_at(i1, r.spawn_height(), 1.3)
	for c in cars:
		c.angular_velocity = Vector3.ZERO
		c.reset_controls()
		c.controls_enabled = true
		c.linear_velocity = c.global_basis.z * 50.0
	l.linear_velocity += l.global_basis.x * -1.0
	r.linear_velocity += r.global_basis.x * 1.0
	var v_before := (l.forward_speed() + r.forward_speed()) * 0.5
	var max_yaw := 0.0
	for f in 120:
		l.throttle = 0.55
		r.throttle = 0.55
		await _step()
		max_yaw = maxf(max_yaw, maxf(absf(l.angular_velocity.y), absf(r.angular_velocity.y)))
	var v_after := (l.forward_speed() + r.forward_speed()) * 0.5
	print("    side by side: speed %.1f -> %.1f m/s (both on part throttle); yaw %.2f rad/s; gap now %.2f m" % [v_before, v_after, max_yaw, -_overlap()])
	_check(v_after > v_before - 1.5 and max_yaw < 0.8, "rubbing wheels barely changes speed or direction")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
