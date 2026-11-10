extends SceneTree
## The kinds of quick race (menu.gd quick_event): a checkpoint run (the
## clock runs down, every gate tops it up a little less, the run ends when
## it runs out, the distance is kept as your best) and an eliminator on a
## big grid (several out a lap, down to the last few at the flag); a duel
## (one rival) and from the back (you start last).
##   godot --headless --fixed-fps 120 --script res://tests/race_types_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _start(tid: String, rt: String, laps: int, opp: int, car := "gp26") -> Node:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["race_type"] = rt; st["track"] = tid; st["car"] = car
	st["laps"] = laps; st["opponents"] = opp; st["difficulty"] = "medium"
	save.pending_event = load("res://scripts/menu.gd").quick_event(save)
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	return race


func _run() -> void:
	await process_frame
	Engine.max_physics_steps_per_frame = 48
	# 1. Checkpoint run.
	var race := _start("styria", "checkpoint", 3, 19)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.96
	_check(race.entrants.size() == 1, "checkpoint run: on your own (%d cars)" % race.entrants.size())
	_check(race.cp_left > 3.0, "the clock starts with time on it (%.1f s)" % race.cp_left)
	var gates_seen := 0
	var topped := false
	var last_left: float = race.cp_left
	var t := 0
	while not race.player.finished and t < 120 * 600:
		await physics_frame
		t += 1
		if race.cp_gates > gates_seen:
			gates_seen = race.cp_gates
			topped = topped or race.cp_left > last_left
		last_left = race.cp_left
	var laps: float = race.checkpoint_distance() / race.track.total_length
	print("    run over after %.0f s: %d gates, %.2f laps" % [t / 120.0, race.cp_gates, laps])
	_check(race.player.finished, "the run ends when the clock runs out")
	_check(gates_seen >= 6 and topped, "gates top the clock up (%d gates)" % gates_seen)
	_check(laps > 1.0 and laps < 8.0, "a good driver lasts more than a lap, not for ever (%.2f laps)" % laps)
	for i in 400:
		await physics_frame
	_check(race._results_shown and race.last_reward.has("checkpoint"), "the results show the run")
	var save: Node = root.get_node("Save")
	_check(save.checkpoint_best(race.lap_key) > 1000.0, "the distance is kept as your best (%.0f m)" % save.checkpoint_best(race.lap_key))
	race.queue_free()
	await process_frame
	# 2. Eliminator, 12 cars, 3 laps: five out after each of the first two.
	race = _start("kestrel_park", "eliminator", 3, 11)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.99
	_check(int(race.event["elim_per_lap"]) == 5, "eliminator: 5 out a lap with 12 cars over 3 laps (%d)" % int(race.event["elim_per_lap"]))
	t = 0
	while not race.player.finished and t < 120 * 400:
		await physics_frame
		t += 1
	var out := 0
	for e in race.entrants:
		if e.eliminated:
			out += 1
	_check(race.player.finished, "the eliminator ends for you")
	_check(out >= 5, "cars were knocked out (%d)" % out)
	race.queue_free()
	await process_frame
	# 3. Duel and from the back.
	race = _start("styria", "duel", 2, 19)
	await physics_frame
	_check(race.entrants.size() == 2, "duel: you and one rival (%d cars)" % race.entrants.size())
	race.queue_free()
	await process_frame
	race = _start("styria", "overtake", 2, 11)
	await physics_frame
	await physics_frame
	_check(race.player.grid == race.entrants.size(), "from the back: you start last (P%d of %d)" % [race.player.grid, race.entrants.size()])
	race.queue_free()
	await process_frame
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
