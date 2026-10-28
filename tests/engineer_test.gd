extends SceneTree
## Race engineer: lap reports with gaps, a stopped car ahead brings out the
## yellow flag (then green), a car a lap up behind shows blue, contact
## buzzes the phone, and the result is called at the flag.
##   godot --headless --fixed-fps 120 --script res://tests/engineer_test.gd
var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 11; st["track"] = "kestrel_park"; st["car"] = "gp26"
	st["qualifying"] = false; st["weather"] = "dry"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var eng = race.engineer
	while race.player.lap < 1:
		await physics_frame
	await physics_frame
	var lap_msg := ""
	for m in eng.radio_log:
		if m.begins_with("Lap 1") or m.begins_with("Fastest"):
			lap_msg = m
	print("    radio: ", eng.radio_log)
	_check(lap_msg.contains(":") and (lap_msg.contains("ahead") or lap_msg.contains("behind")), "lap report with the gaps: \"%s\"" % lap_msg)
	# A car stops on the track 150 m ahead.
	var victim = null
	for e in race.entrants:
		if not e.is_player:
			victim = e
			break
	var L: float = race.track.total_length
	var n: int = race.track.size()
	var cum: PackedFloat32Array = race.track.cum
	var pi: int = race.player.idx
	var idx := (pi + 75) % n
	race._place(victim, race.track.pose_at(idx, victim.car.spawn_height(), race.track.road_half - 1.0))
	victim.lap = race.player.lap + (1 if idx < pi else 0)
	var yellow := false
	for f in 480:
		await physics_frame
		victim.ai.speed_cap = 0.0
		if eng._flag == "yellow":
			yellow = true
			break
	_check(yellow and race.hud._flag.visible, "a stopped car ahead brings out the yellow flag")
	victim.ai.speed_cap = 999.0
	var bi := posmod(race.player.idx - 20, n)
	race._place(victim, race.track.pose_at(bi, victim.car.spawn_height(), -race.track.road_half + 1.0))
	victim.ai.speed_cap = 0.0
	var green := false
	for f in 360:
		await physics_frame
		victim.lap = race.player.lap + (2 if bi > race.player.idx else 1)
		if eng._flag == "green":
			green = true
		if eng._flag == "blue":
			break
	_check(green or eng._flag == "blue", "the yellow clears once the car is out of the way")
	_check(eng._flag == "blue", "blue flag when a car a lap up is close behind (%s)" % eng._flag)
	var lead = victim
	lead.ai.speed_cap = 999.0
	lead.lap = race.player.lap
	# Contact buzz.
	var b0: int = eng.buzzes
	race.car_contact.emit(race.car, lead.car, 6.0)
	_check(eng.buzzes > b0, "contact buzzes the phone")
	while not race._results_shown and race.race_time < 400.0:
		await physics_frame
	var last: String = eng.radio_log[eng.radio_log.size() - 1] if not eng.radio_log.is_empty() else ""
	_check(last.begins_with("P%d" % race.player.position), "the result is called at the flag: \"%s\"" % last)
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
