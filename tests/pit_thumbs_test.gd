extends SceneTree
## Your own pit stop the way a person drives it on the phone: the touch
## controls' inputs (full throttle or none, full brake or none, the default
## assists on top), not the AI's smooth pedals. A number of ways of doing it
## (late turn-in, too fast, short of the box, throttle held all through the
## stop, steering left to the assist...). The car must never fly, spin, get
## reset or stuck, and must get back out racing.
##   godot --headless --fixed-fps 120 --script res://tests/pit_thumbs_test.gd [-- track[,track] [style[,style]]]

const STYLES := ["line", "late", "hot", "short", "long", "wide", "gas_held", "hands_off", "tap_brake", "no_assists"]
const TRACKS := ["styria", "silvermoor", "lakeside", "red_sea", "caspian", "desert", "marina", "duinen", "lone_star", "gulf"]

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
	var tracks: Array = TRACKS if args.size() < 1 or args[0] == "all" else Array(String(args[0]).split(","))
	var styles: Array = STYLES if args.size() < 2 or args[1] == "all" else Array(String(args[1]).split(","))
	for tid in tracks:
		for sty in styles:
			await _one(String(tid), String(sty))
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)


func _one(tid: String, sty: String) -> void:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 4; st["opponents"] = 7; st["track"] = tid
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = true
	st["pit_mode"] = "manual"; st["team"] = 3
	if sty == "no_assists" or sty == "hot":
		st["steer_assist"] = "off"; st["brake_assist"] = "off"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	var tr: Track = race.track
	if not tr.has_pit_lane:
		race.queue_free()
		await process_frame
		return
	race.control._fail.clear()
	var me = race.player
	var car: RaceCar = race.car
	var wk = race.weekend
	var hand := AIDriver.new()
	hand.skill = 0.93
	hand.idx = me.idx
	var stop := sty != "long"
	var box_shift := {"short": 3.2, "long": -14.0}.get(sty, 0.0) as float
	var lat_shift := 2.2 if sty == "wide" else 0.0
	var ramp := 45.0 if sty == "late" else 140.0
	var armed := [false]          # heading for the pits (after the first lap)
	hand.path_lat = func(i: int) -> float:
		var ps := tr.pit_ps(i)
		var going_in: bool = armed[0] and (tr.pit_ps(me.idx) < tr.PIT_ENTRY_LEN or me.pit_phase >= 1)
		if ps < -ramp - 20.0 or ps > tr.pit_total() or not going_in:
			return tr.line_offset[i]
		var w := clampf((ps + ramp + 20.0) / ramp, 0.0, 1.0)
		var near_box: bool = absf(ps - me.pit_box) < 25.0 and stop and me.pit_box > 0.0 and me.pit_phase <= 1
		var lane: float = tr.pit_side * ((tr.pit_box_lat() - lat_shift) if near_box else tr.pit_lane_lat(maxf(ps, 0.0)))
		return lerpf(tr.line_offset[i], lane, w)
	# The person's thumbs: what the AI would do, on/off pedals.
	var hold_brake := [0.0]
	race.thumbs = func() -> Array:
		var ps: float = tr.pit_ps(me.idx)
		var cap := 999.0
		if armed[0]:
			var ls := 34.0 if sty == "hot" else 19.0
			if ps > -300.0 and ps < 0.0:
				cap = sqrt(ls * ls + 2.0 * 7.0 * -ps) if sty != "hot" else 999.0
			elif ps >= 0.0 and ps < tr.PIT_ENTRY_LEN and me.pit_phase <= 1:
				cap = sqrt(ls * ls + 2.0 * 5.0 * maxf(tr.PIT_ENTRY_LEN - 10.0 - ps, 0.0))
			if stop and me.pit_phase == 1 and me.pit_box > 0.0:
				var d: float = me.pit_box - box_shift - ps
				if d > -2.0:                   # (overshot it: drive on, like a person would)
					cap = minf(cap, sqrt(2.0 * 5.0 * maxf(d - 1.0, 0.0)))
		hand.speed_cap = cap
		hand.update(car, tr)
		var steer: float = car.steer_input
		var v := car.forward_speed()
		var brk := 1.0 if car.brake_input > 0.15 or v > cap + 1.0 else 0.0
		if sty == "tap_brake" and brk > 0.0 and int(race.race_time * 4.0) % 2 == 0:
			brk = 0.0
		# At the box: on the brake until the crew have it (then off it).
		if stop and me.pit_phase == 1 and me.pit_box > 0.0 and absf(me.pit_box - box_shift - ps) < 3.0:
			brk = 1.0
		if me.pit_phase == 2:
			hold_brake[0] += 1.0 / 120.0
			brk = 1.0 if sty != "gas_held" and hold_brake[0] < 1.0 else 0.0
		if sty == "hot" and ps > tr.PIT_ENTRY_LEN - 70.0 and ps < tr.PIT_ENTRY_LEN + 2.0:
			brk = 0.0                  # (forgot to brake for the line)
		var gas := 0.0 if brk > 0.0 else 1.0
		# In the lane: leave the steering to the assist.
		if sty == "hands_off" and me.pit_phase >= 1:
			steer = 0.0
		return [clampf(steer, -1.0, 1.0), gas, brk]
	race.autopilot = null
	# Off the grid, then put 600 m before the pit entry at speed (quicker
	# than a whole lap; tests/pit_stuck_test.gd does the same), and box.
	while race.race_time < 3.0:
		await physics_frame
	var n: int = tr.size()
	var i0 := 0
	for i in n:
		if absf(tr.pit_ps(i) + 600.0) < 2.0:
			i0 = i
			break
	var xf: Transform3D = tr.pose_at(i0, car.spawn_height(), tr.line_offset[i0])
	race._place(me, xf)
	car.linear_velocity = xf.basis.z * 60.0
	car.controls_enabled = true
	me.lap = 1
	hand.idx = i0
	wk.set_box("hard")
	armed[0] = true
	var stops0: int = me.stops
	var t := 0
	var max_vy := 0.0
	var max_yaw := 0.0
	var max_tilt := 0.0
	var air := 0.0
	var max_air := 0.0
	var phase_seen := 0
	var back_at := -1
	var still := 0.0
	var worst_still := 0.0
	var resets0: int = race.reset_log.size()
	var lim_pen0: int = race.control.messages.filter(func(m): return "speeding in the pit lane" in m).size()
	while t < 120 * 150:
		await physics_frame
		t += 1
		phase_seen = maxi(phase_seen, me.pit_phase)
		var ps: float = tr.pit_ps(me.idx)
		var near_pits: bool = phase_seen > 0 or (ps > -150.0 and ps < tr.PIT_ENTRY_LEN)
		if OS.has_environment("PIT_DEBUG") and near_pits and (t % 30 == 0 or absf(car.linear_velocity.y) > 4.0):
			print("      dbg t=%.2f ph %d ps %.1f box %.1f lat %.2f y %.2f vy %.1f v %.1f frz %s ctl %s ghost %s thr %.1f brk %.1f up %.2f" % [t / 120.0, me.pit_phase, ps, me.pit_box, tr.lateral(car.global_position, me.idx), car.global_position.y, car.linear_velocity.y, car.forward_speed(), car.freeze, car.controls_enabled, car.is_ghost, car.throttle, car.brake_input, car.global_basis.y.y])
		if near_pits and not car.freeze:
			# (Up and down relative to the road: Lone Star's hill isn't flying.)
			var tg: Vector3 = tr.tangents[me.idx]
			max_vy = maxf(max_vy, absf(car.linear_velocity.y - car.linear_velocity.dot(tg) * tg.y))
			# Spinning: the car pointing well away from where it's going.
			var hv := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
			var hf := Vector3(car.global_basis.z.x, 0.0, car.global_basis.z.z)
			var yaw_rel: float = absf(hf.signed_angle_to(hv, Vector3.UP)) if hv.length() > 5.0 else 0.0
			if yaw_rel > max_yaw and OS.has_environment("PIT_DEBUG"):
				print("      yaw %.2f at ph %d ps %.1f lat %.1f v %.1f steer %.2f" % [yaw_rel, me.pit_phase, ps, tr.lateral(car.global_position, me.idx), car.forward_speed(), car.steer_input])
			max_yaw = maxf(max_yaw, yaw_rel)
			max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0))))
			var contact := 0
			for w in car.wheels:
				if w.in_contact:
					contact += 1
			air = air + 1.0 / 120.0 if contact == 0 else 0.0
			max_air = maxf(max_air, air)
		var waiting: bool = me.pit_phase == 2 or (me.pit_phase == 1 and me.pit_box > 0.0 and absf(me.pit_box - ps) < 6.0)
		if absf(car.forward_speed()) < 1.0 and not waiting:
			still += 1.0 / 120.0
			worst_still = maxf(worst_still, still)
		else:
			still = 0.0
		if phase_seen > 0 and me.pit_phase == 0 and back_at < 0:
			back_at = t
		if back_at > 0 and t > back_at + 120 * 6:
			break
	var lat: float = absf(tr.lateral(car.global_position, me.idx))
	var resets: Array = race.reset_log.slice(resets0).filter(func(r): return "(you)" in r)
	var lim_pen: int = race.control.messages.filter(func(m): return "speeding in the pit lane" in m).size() - lim_pen0
	var tag := "%s %s" % [tid, sty]
	print("    %-11s %-10s phase %d->%d, stops %d, vy %.1f, slip %.2f, tilt %.0f deg, air %.2f s, still %.1f s, back %s, %.0f km/h lat %.1f, resets %d, pit pens %d" % [
		tid, sty, phase_seen, me.pit_phase, me.stops - stops0, max_vy, max_yaw, max_tilt, max_air, worst_still,
		("%.0f s" % (back_at / 120.0)) if back_at > 0 else "never", car.speed_kmh(), lat, resets.size(), lim_pen])
	for r in resets:
		print("      reset: ", r)
	_check(max_vy < 6.0 and max_air < 0.4 and max_tilt < 25.0, "%s: stays on the ground (vy %.1f m/s, %.2f s in the air, tilt %.0f)" % [tag, max_vy, max_air, max_tilt])
	_check(max_yaw < 0.6, "%s: no spin (slip %.0f deg)" % [tag, rad_to_deg(max_yaw)])
	_check(resets.is_empty(), "%s: never reset" % tag)
	_check(back_at > 0 and me.pit_phase == 0 and car.forward_speed() > 11.0 and lat < tr.road_half + 3.0 and worst_still < 4.0, "%s: back out racing" % tag)
	if sty == "long":
		_check(me.stops == stops0, "%s: drove past the box, no stop" % tag)
	elif sty == "hot":
		pass                           # (too fast, no assists: may well miss the box)
	else:
		_check(me.stops == stops0 + 1 and me.compound == "hard", "%s: the stop happens" % tag)
	_check(lim_pen == (1 if sty == "hot" else 0), "%s: pit-lane speeding penalty only when too fast (%d)" % [tag, lim_pen])
	race.queue_free()
	await process_frame
	await process_frame
