extends SceneTree
## Driving your own pit stop (weekend.gd, "Pit stops: you drive"): the car is
## driven "by hand" (an AI standing in for your thumbs, not the autopilot).
##   - turn into the entry: you're in the pit lane (your box lit up);
##   - the limiter comes on at the speed line (too fast there: a penalty);
##   - stop at your box: the crew hold the car, change the tyres, let it go;
##   - the limiter goes off at the end of the lane, and you're racing again;
##   - drive past your box: no stop.
##   godot --headless --fixed-fps 120 --script res://tests/manual_pit_test.gd [-- track]

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _race(tid: String) -> Node:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 4; st["opponents"] = 5; st["track"] = tid
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = true
	st["pit_mode"] = "manual"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.control._fail.clear()
	var hand := AIDriver.new()
	hand.skill = 0.95
	hand.idx = race.player.idx
	race.input_driver = hand
	return race


## "You": into the pit lane, braking for the speed line (to `line_speed`),
## stopping at the box unless `stop` is false.
func _drive_in(race: Node, line_speed: float, stop: bool) -> void:
	var tr: Track = race.track
	var me = race.player
	var hand: AIDriver = race.input_driver
	hand.path_lat = func(i: int) -> float:
		var ps := tr.pit_ps(i)
		var going_in: bool = tr.pit_ps(me.idx) < tr.PIT_ENTRY_LEN or me.pit_phase >= 1
		if ps < -160.0 or ps > tr.pit_total() or not going_in:
			return tr.line_offset[i]
		var w := clampf((ps + 160.0) / 140.0, 0.0, 1.0)
		var lane := tr.pit_side * (tr.pit_box_lat() if absf(ps - me.pit_box) < 25.0 and stop and me.pit_box > 0.0 else tr.pit_lane_lat(maxf(ps, 0.0)))
		return lerpf(tr.line_offset[i], lane, w)
	race.set_meta("hand_line_speed", line_speed)
	race.set_meta("hand_stop", stop)


func _hand_caps(race: Node) -> void:
	var tr: Track = race.track
	var me = race.player
	var hand: AIDriver = race.input_driver
	# Stuck (a bot ran into you...): tap Reset, like you would.
	var still: float = race.get_meta("hand_still", 0.0)
	still = still + 1.0 / 120.0 if absf(me.car.forward_speed()) < 1.0 and me.pit_phase != 2 and race.state == 1 else 0.0
	race.set_meta("hand_still", still)
	if still > 3.0:
		race.set_meta("hand_still", 0.0)
		race._reset_to_track(me, true)
	if hand.path_lat.is_null():
		return
	var ps := tr.pit_ps(me.idx)
	var cap := 999.0
	var ls: float = race.get_meta("hand_line_speed", 22.0)
	if ps > -260.0 and ps < 0.0:
		cap = sqrt(30.0 * 30.0 + 2.0 * 6.0 * -ps)          # to the entry road at ~110 km/h
	elif ps >= 0.0 and ps < tr.PIT_ENTRY_LEN + tr.PIT_STRAIGHT_LEN and (ps < tr.PIT_ENTRY_LEN or me.pit_phase >= 1):
		cap = sqrt(ls * ls + 2.0 * 4.0 * maxf(tr.PIT_ENTRY_LEN - 15.0 - ps, 0.0))
	if bool(race.get_meta("hand_stop", true)) and me.pit_phase == 1 and me.pit_box > 0.0:
		var d: float = me.pit_box - ps
		cap = minf(cap, sqrt(2.0 * 3.0 * maxf(d - 0.5, 0.0)))
	hand.speed_cap = cap


func _run() -> void:
	await process_frame
	var tid: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "styria"
	print("track: ", tid)
	var race: Node = await _race(tid)
	var me = race.player
	var tr: Track = race.track
	var wk = race.weekend
	_check(wk.manual(me), "pit stops: you drive")
	wk.set_box("hard")
	await _drive_in(race, 17.0, true)
	var seen := {"limiter": false, "frozen": false, "box_lit": false, "guide": false}
	var stops0: int = me.stops
	var t := 0
	var done := false
	while t < 120 * 260 and not done:
		await physics_frame
		t += 1
		_hand_caps(race)
		if me.get_meta("limiter", false):
			seen["limiter"] = true
		if me.pit_phase == 1 and wk._marker != null and wk._marker.visible:
			seen["box_lit"] = true
		if me.pit_phase == 1 and race.hud._pit_guide != null and race.hud._pit_guide.visible:
			seen["guide"] = true
		if me.pit_phase == 2 and me.car.freeze:
			seen["frozen"] = true
		if me.stops > stops0 and me.pit_phase == 0:
			done = true
	print("    (after the stop: phase %d, ps %.0f, lat %.1f, %.1f m/s, frozen %s, controls %s, stops %d, %.0f s)" % [me.pit_phase, tr.pit_ps(me.idx), tr.lateral(me.car.global_position, me.idx), me.car.forward_speed(), me.car.freeze, me.car.controls_enabled, me.stops, t / 120.0])
	_check(seen["box_lit"] and seen["guide"], "into the pit lane: your box lit up, distance to it shown")
	_check(seen["limiter"], "limiter on at the speed line")
	var speeding := func() -> int: return race.control.messages.filter(func(m): return "speeding in the pit lane" in m).size()
	_check(speeding.call() == 0, "under 80 km/h at the line: no penalty")
	_check(seen["frozen"], "stopped at the box: the crew hold the car")
	_check(done and me.compound == "hard" and me.stops == stops0 + 1, "tyres changed (now %s), back out" % me.compound)
	_check(not me.get_meta("limiter", false), "limiter off after the lane")
	race.input_driver.path_lat = Callable()
	race.input_driver.speed_cap = 999.0
	# Back on track, racing: some distance on.
	var s0: float = tr.cum[me.idx]
	for k in 120 * 8:
		await physics_frame
	var gone := fposmod(tr.cum[me.idx] - s0, tr.total_length)
	_check(gone > 120.0 and me.pit_phase == 0, "racing again (%.0f m in 8 s)" % gone)
	# Too fast at the speed line: penalty. And past the box without stopping.
	wk.set_box("medium")
	await _drive_in(race, 32.0, false)
	t = 0
	var phase_seen := 0
	while t < 120 * 200:
		await physics_frame
		t += 1
		_hand_caps(race)
		phase_seen = maxi(phase_seen, me.pit_phase)
		if phase_seen >= 1 and me.pit_phase == 0:
			break
	_check(speeding.call() == 1, "over 80 km/h at the speed line: 5 s penalty")
	_check(me.stops == stops0 + 1 and me.compound == "hard", "drove past the box: no stop")
	for m in race.control.messages:
		print("    RC ", m)
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
