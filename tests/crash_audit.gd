extends SceneTree
## Wheel-to-wheel with the bots, the way a person races them: a full race
## from mid-grid (P12 of 20), driven with on/off thumbs (full throttle or
## none, full brake or none, the default assists on top), racing hard: it
## follows close, pulls out to pass, and doesn't always leave room. Every
## contact your car has is recorded with what it did to you over the next
## 3 seconds: how far the car turned from the track's direction, the
## sideways spin, whether you left the road, how much speed it cost.
## A contact "ruins your race" if it spins you (> 50 deg off the track's
## direction), throws you off the road, or stops you.
##   godot --headless --fixed-fps 120 --script res://tests/crash_audit.gd [-- track[,track] [laps] [style]]
## style: racer (default), timid (brakes early, slower: the bots come at you),
## bully (squeezes across into cars alongside).

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var tracks: Array = Array(String(args[0]).split(",")) if args.size() > 0 else ["silvermoor", "brianza", "marina"]
	var laps := int(args[1]) if args.size() > 1 else 2
	var style: String = args[2] if args.size() > 2 else "racer"
	var all_contacts := 0
	var all_ruined := 0
	var all_hard := 0
	for tid in tracks:
		var r: Array = await _race(String(tid), laps, style)
		all_contacts += int(r[0])
		all_ruined += int(r[1])
		all_hard += int(r[2])
	print("")
	print("  %d contacts in all, %d of them hard (closing > 6 m/s), %d ruined the race" % [all_contacts, all_hard, all_ruined])
	_check(all_contacts > 0, "there was wheel-to-wheel contact to judge (%d)" % all_contacts)
	_check(all_ruined == 0, "no contact spins you, throws you off or stops you (%d of %d did)" % [all_ruined, all_contacts])
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _race(tid: String, laps: int, style: String) -> Array:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = laps; st["opponents"] = 19; st["track"] = tid
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = true
	st["difficulty"] = "medium"; st["pit_mode"] = "auto"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	Engine.max_physics_steps_per_frame = 48
	var tr: Track = race.track
	var me = race.player
	var car: RaceCar = race.car
	var hand := AIDriver.new()
	hand.skill = 0.9 if style == "timid" else 0.975
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tid + style)
	var pass_side := [0.0, 0.0]             # [lane offset, seconds left]
	var L := tr.total_length
	race.thumbs = func() -> Array:
		hand.idx = me.idx
		# A person racing: follow close, pull out to pass when stuck behind.
		var my_s: float = tr.cum[me.idx]
		var my_lat := tr.lateral(car.global_position, me.idx)
		var cap := 999.0
		var lead_lat := 0.0
		var lead_gap := 999.0
		var beside_lat := 999.0
		for o in race.entrants:
			if o == me or not o.car.visible or o.pit_phase > 0:
				continue
			var gap := fposmod(tr.cum[o.idx] - my_s + L * 0.5, L) - L * 0.5
			var dl := tr.lateral(o.car.global_position, o.idx) - my_lat
			if gap > 0.5 and gap < 40.0 and absf(dl) < 2.2 and gap < lead_gap:
				lead_gap = gap
				lead_lat = dl
				# Aggressive: right up to their gearbox, a little faster.
				cap = o.car.forward_speed() + 2.0 + maxf(gap - 7.0, 0.0) * 0.6
			if absf(gap) < 5.0 and absf(dl) < 4.5:
				beside_lat = dl
		pass_side[1] -= 1.0 / 120.0
		if lead_gap < 25.0 and pass_side[1] <= 0.0:
			var side := -signf(lead_lat) if absf(lead_lat) > 0.4 else (1.0 if rng.randf() < 0.5 else -1.0)
			pass_side[0] = clampf(my_lat - tr.line_offset[me.idx] + side * 3.2, -tr.road_half + 1.2 - tr.line_offset[me.idx], tr.road_half - 1.2 - tr.line_offset[me.idx])
			pass_side[1] = 3.0
		var lane: float = pass_side[0] if pass_side[1] > 0.0 else 0.0
		if style == "bully" and beside_lat < 900.0:
			lane = (my_lat - tr.line_offset[me.idx]) + signf(beside_lat) * 1.5   # squeeze them
		hand.lane_offset = move_toward(hand.lane_offset, lane, 0.05)
		hand.speed_cap = cap
		hand.update(car, tr)
		var brk := 1.0 if car.brake_input > 0.15 else 0.0
		var gas := 0.0 if brk > 0.0 else (1.0 if car.throttle > 0.3 else 0.0)
		return [clampf(car.steer_input, -1.0, 1.0), gas, brk]
	race.autopilot = null
	# Every contact your car has: [time, other, closing, before: speed]
	var open: Array = []
	var results: Array = []
	race.car_contact.connect(func(a, b, closing):
		if a == car or b == car:
			var other: RaceCar = b if a == car else a
			# Who hit whom: the car behind along the track, if it was faster.
			var ds := other.global_position - car.global_position
			var ahead := ds.dot(car.global_basis.z)
			var who := "side by side"
			if absf(ahead) > 2.5:
				who = "you hit them" if ahead > 0.0 else "hit from behind"
			open.append({"t": race.race_time, "closing": closing, "v0": car.forward_speed(), "head": 0.0, "yaw": 0.0, "off": -INF, "vmin": INF, "who": who, "lap": me.lap, "resets": race.recoveries, "trace": [], "other": other}))
	var t := 0
	var solo := [0]
	var solo_last := [-99.0]
	var limit := 120 * (60 + laps * 150)
	while t < limit and not me.finished:
		await physics_frame
		t += 1
		var i: int = me.idx
		var fwd := Vector3(car.global_basis.z.x, 0, car.global_basis.z.z).normalized()
		var head := rad_to_deg(acos(clampf(fwd.dot(tr.htangents[i]), -1.0, 1.0)))
		var yaw := absf(car.angular_velocity.y - car.forward_speed() * tr.curv[i])
		var off := absf(tr.lateral(car.global_position, i)) - (tr.road_half + Track.KERB_W)
		if open.is_empty():
			# Spins with nobody near: the driving, not contact (for comparison).
			if head > 50.0 and car.forward_speed() > 3.0 and race.race_time - solo_last[0] > 5.0:
				solo[0] += 1
				solo_last[0] = race.race_time
		for c in open:
			if t % 6 == 0 and (c["trace"] as Array).size() < 40:
				var sa_f := (car.wheels[0].slip_angle + car.wheels[1].slip_angle) * 0.5
				var sa_r := (car.wheels[2].slip_angle + car.wheels[3].slip_angle) * 0.5
				var o: RaceCar = c["other"]
				var rel := o.global_position - car.global_position
				(c["trace"] as Array).append("      %.2f v %3.0f head %5.1f yaw %5.2f (want %5.2f) slipF %5.2f slipR %5.2f steer %5.2f thr %.1f brk %.1f lat %5.1f | other fwd %4.1f side %4.1f" % [
					race.race_time - float(c["t"]), car.forward_speed() * 3.6, head, car.angular_velocity.y, car.forward_speed() * tr.curv[i], sa_f, sa_r, car.steering, car.throttle, car.brake_input,
					tr.lateral(car.global_position, i), rel.dot(car.global_basis.z), rel.dot(car.global_basis.x)])
			c["head"] = maxf(c["head"], head)
			c["yaw"] = maxf(c["yaw"], yaw)
			c["off"] = maxf(c["off"], off)
			c["vmin"] = minf(c["vmin"], car.forward_speed())
		var k := 0
		while k < open.size():
			if race.race_time - float(open[k]["t"]) > 3.0:
				var c: Dictionary = open[k]
				c["reset"] = race.recoveries > int(c["resets"])
				results.append(c)
				open.remove_at(k)
			else:
				k += 1
	results.append_array(open)
	var ruined := 0
	var hard := 0
	print("  %s (%s): finished %s P%d, %d contacts, %d spins with no contact" % [tid, style, "yes" if me.finished else "NO", me.position, results.size(), solo[0]])
	var traced := 0
	for c in results:
		var lost: float = 1.0 - maxf(float(c["vmin"]), 0.0) / maxf(float(c["v0"]), 1.0)
		var bad: bool = float(c["head"]) > 50.0 or float(c["off"]) > 2.0 or (float(c["vmin"]) < 5.0 and float(c["v0"]) > 15.0) or bool(c.get("reset", false))
		if float(c["closing"]) > 6.0:
			hard += 1
		if bad:
			ruined += 1
		print("    %s lap %d t=%5.1f  %-16s closing %4.1f m/s at %3.0f km/h -> turned %4.0f deg, yaw %.2f, %s, speed lost %3.0f%%%s" % [
			"RUINED" if bad else "  ok  ", int(c["lap"]), float(c["t"]), c["who"], float(c["closing"]), float(c["v0"]) * 3.6,
			float(c["head"]), float(c["yaw"]), ("%.1f m off" % float(c["off"])) if float(c["off"]) > 0.0 else "on track", lost * 100.0,
			" RESET" if c.get("reset", false) else ""])
		if bad and OS.has_environment("TRACE") and traced < 3 and float(c["closing"]) > 1.0:
			traced += 1
			for line in c["trace"]:
				print(line)
	race.queue_free()
	await process_frame
	await process_frame
	return [results.size(), ruined, hard]
