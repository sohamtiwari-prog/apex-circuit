extends SceneTree
## Race weekend: qualifying sets the grid; tyres wear and cost grip; the AI
## and you can pit (about 15-25 s lost, tyres renewed); rain arrives in a
## "changing" race, the track gets wet, cars on slicks pit for wets.
##   godot --headless --fixed-fps 120 --script res://tests/weekend_test.gd
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"
	st["laps"] = 4
	st["opponents"] = 11
	st["track"] = "kestrel_park"
	st["car"] = "gp26"
	st["qualifying"] = true
	st["weather"] = "changing"
	st["tyres"] = "soft"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var wk = race.weekend
	await physics_frame
	var hidden := 0
	for e in race.entrants:
		if not e.is_player and not e.car.visible:
			hidden += 1
	_check(int(race.state) == 3 and hidden == race.entrants.size() - 1, "qualifying: just you on track (%d others away)" % hidden)
	var t := 0
	while wk.in_quali and t < 120 * 150:
		await physics_frame
		t += 1
	_check(not wk.in_quali and wk.quali_done, "the flying lap ends qualifying (%.1f s)" % (t / 120.0))
	var my_q := 0.0
	for r in wk.quali_results:
		if r["e"].is_player:
			my_q = float(r["time"])
	var times: Array = wk.quali_results.map(func(r): return float(r["time"]))
	print("    qualifying: you %.3f; pole %.3f, last %.3f" % [my_q, times[0], times[times.size() - 1]])
	var sorted := true
	for k in range(1, times.size()):
		sorted = sorted and times[k] >= times[k - 1]
	_check(sorted and times[times.size() - 1] - times[0] < 8.0, "qualifying order is by time, field within 8 s")
	_check(race.hud.results_panel.visible, "qualifying classification and tyre choice are shown")
	wk.player_compound = "soft"
	wk._end_qualifying()
	race.hud.results_panel.visible = false
	await physics_frame
	var my_slot: int = wk.grid_order.find(race.player)
	var lined_up := true
	for e in race.entrants:
		var k: int = wk.grid_order.find(e)
		var want: Transform3D = race._grid_pose(k)
		lined_up = lined_up and e.car.global_position.distance_to(want.origin) < 1.5
	_check(int(race.state) == 0 and lined_up, "the grid is in qualifying order (you start P%d)" % (my_slot + 1))
	_check(race.player.compound == "soft", "you start on the tyres you chose")

	# Race: wear, an AI stop, your stop, the rain.
	while int(race.state) == 0:
		await physics_frame
	await _frames(120 * 20)
	var w20: float = race.player.wear
	print("    after 20 s racing: your soft tyres %.0f%% worn, grip x%.3f" % [w20 * 100.0, race.car.grip_scale])
	_check(w20 > 0.02 and race.car.grip_scale < 1.035, "tyres wear and lose grip as they do")
	# Force one AI car's tyres to be finished: it should pit.
	var ai_e = null
	for e in race.entrants:
		if not e.is_player and e.position > 3:
			ai_e = e
			break
	ai_e.wear = 0.9
	var pitted := false
	var lost := 0.0
	var gap0: float = ai_e.progress
	var t0: float = race.race_time
	for f in 120 * 90:
		await physics_frame
		if ai_e.stops > 0 and ai_e.pit_phase == 0:
			pitted = true
			break
	_check(pitted and ai_e.wear < 0.2, "an AI with worn tyres pits and comes out on fresh ones (%s)" % ai_e.compound)
	# You: box, through the lane, back to racing.
	wk.toggle_box()
	var in_lane := false
	var ok_stop := false
	var t_box: float = race.race_time
	for f in 120 * 120:
		await physics_frame
		if race.player.pit_phase > 0:
			in_lane = true
		if in_lane and race.player.pit_phase == 0:
			ok_stop = true
			break
	_check(in_lane and ok_stop and race.player.stops == 1 and race.player.wear < 0.1, "you box, stop, and rejoin on new tyres (%s)" % race.player.compound)
	var moved: bool = race.car.forward_speed() > 15.0
	_check(moved, "and drive on after the pit lane")
	print("    rain from %.0f%% of the race; wetness now %.2f" % [wk._rain_from * 100.0, wk.wetness])
	while not race._results_shown and race.race_time < 600.0:
		await physics_frame
	var wets := 0
	for e in race.entrants:
		if e.compound == "wet":
			wets += 1
	print("    finished: wetness %.2f, %d cars on wets, road wetness param %.2f" % [wk.wetness, wets, float(race.track.road_mat.get_shader_parameter("wetness"))])
	_check(wk.wetness > 0.5 and float(race.track.road_mat.get_shader_parameter("wetness")) > 0.4, "the rain came and the track got wet")
	_check(wets >= 4, "cars changed to wets in the rain (%d)" % wets)
	_check(race._results_shown, "the race still finishes")
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
