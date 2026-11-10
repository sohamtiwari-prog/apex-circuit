extends SceneTree
## The race session's flow, the way a player goes through it: finishing,
## pausing around the finish, "Race again", restarting mid-qualifying, the
## pause menu over the running-order board, a time trial's tyres.
##   godot --headless --fixed-fps 120 --script res://tests/flow_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _race(tid: String, laps: int, extra: Dictionary = {}) -> Node:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = laps; st["opponents"] = 5; st["track"] = tid; st["car"] = "gp26"
	st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = true
	for k in extra:
		st[k] = extra[k]
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	return race


## The player's own inputs (the way thumbs drive), so the game's own
## cool-down autopilot is the only one there is.
func _drive_by_hand(race: Node) -> void:
	var hand := AIDriver.new()
	hand.skill = 0.97
	race.thumbs = func() -> Array:
		hand.idx = race.player.idx
		hand.update(race.car, race.track)
		return [race.car.steer_input, race.car.throttle, race.car.brake_input]


func _secs(s: float) -> void:
	for i in int(s * 120.0):
		await physics_frame


func _run() -> void:
	await process_frame
	Engine.max_physics_steps_per_frame = 48
	# 1. Finish, pause during the 2.5 s before the results: they wait.
	var race := _race("styria", 1)
	await physics_frame
	_drive_by_hand(race)
	var t := 0
	while not race.player.finished and t < 120 * 150:
		await physics_frame
		t += 1
	_check(race.player.finished, "the race finishes (by hand)")
	_check(race.autopilot != null, "the AI takes the car for the cool-down lap")
	race.hud.set_paused(true)
	for i in 400:
		await process_frame
	_check(not race._results_shown, "results wait while the game is paused")
	race.hud.set_paused(false)
	# They come up 2.5 s after the flag, or once a time penalty has been
	# added on (pen_pending + 0.5 s), whichever is later.
	var due := maxf(2.5, float(race.player.pen_pending) + 0.5) + 1.0
	t = 0
	while not race._results_shown and t < int(due * 120.0):
		await physics_frame
		t += 1
	_check(race._results_shown, "and come up once it's resumed (due within %.1f s)" % due)
	# 2. Race again: the car is yours, not the AI's.
	race._restart()
	await physics_frame
	_check(race.autopilot == null, "\"Race again\": the AI hands your car back")
	_check(race.engineer._said_pos == 0, "the engineer forgets the last race's place")
	# 3. Restart within 2.5 s of finishing: no results in the new race.
	_drive_by_hand(race)
	t = 0
	while not race.player.finished and t < 120 * 170:
		await physics_frame
		t += 1
	race._restart()
	await _secs(4.0)
	_check(not race._results_shown, "restarting right after the flag: no results pop up over the new grid")
	# 4. The pause menu sits over the running-order board.
	race.hud.cycle_tower()
	race.hud.cycle_tower()
	race.hud.set_paused(true)
	var board: Control = race.hud._board
	var pp: Control = race.hud.pause_panel
	_check(board == null or (pp.get_index() > board.get_index() and pp.get_parent() == board.get_parent()), "the pause menu is drawn over the running-order board")
	race.hud.set_paused(false)
	race.queue_free()
	await process_frame
	# 5. Restart in qualifying: qualifying again, not a race that thinks it's qualifying.
	race = _race("styria", 2, {"qualifying": true})
	await _secs(1.0)
	_check(race.weekend.in_quali and race.state == 3, "qualifying starts")
	race._restart()
	await _secs(0.5)
	_check(race.weekend.in_quali and race.state == 3, "restarted in qualifying: still qualifying (state %d)" % race.state)
	race.weekend.finish_qualifying(90.0)
	race.queue_free()
	await process_frame
	# 6. The bots start a restarted race on fresh starting tyres.
	race = _race("styria", 3)
	await _secs(1.0)
	var start_tyres: Array = []
	for e in race.entrants:
		start_tyres.append(e.compound)
	for e in race.entrants:
		if not e.is_player:
			e.compound = "wet"
	race._restart()
	await physics_frame
	var same := true
	for k in race.entrants.size():
		same = same and race.entrants[k].compound == start_tyres[k]
	_check(same, "after a restart everyone's on their starting tyres (not the last race's wets)")
	race.queue_free()
	await process_frame
	# 7. A time trial's tyres don't wear.
	race = _race("styria", 3, {"mode": "time_trial"})
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	await _secs(60.0)
	_check(race.player.wear == 0.0, "time trial: no tyre wear (%.3f)" % race.player.wear)
	race.queue_free()
	await process_frame
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
