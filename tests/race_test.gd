extends SceneTree
## A full race: 20 cars, standing start, positions, finish and results.
## Also measures the simulation cost of a full grid.
##   godot --headless --fixed-fps 120 --script res://tests/race_test.gd [track] [laps]
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var track_id: String = args[0] if args.size() > 0 else "styria"
	var laps: int = int(args[1]) if args.size() > 1 else 2
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"
	st["laps"] = laps
	st["opponents"] = 19
	st["track"] = track_id
	st["car"] = "gp26"
	st["difficulty"] = "medium"
	save.save()

	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	await physics_frame
	_check(race.entrants.size() == 20, "20 cars on the grid (%d)" % race.entrants.size())
	_check(race.player.position >= 5, "player starts mid-grid (P%d)" % race.player.position)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97

	var t0 := Time.get_ticks_usec()
	var frames := 0
	var resets := 0
	var min_moved := INF
	var overtakes := 0
	var last_pos: int = race.player.position
	while not race._results_shown and frames < 120 * 200 * (laps + 1):
		await physics_frame
		frames += 1
		if race.player.position != last_pos:
			overtakes += 1
			last_pos = race.player.position
	var sim_ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxi(frames, 1)
	print("  %d frames, %.2f ms per physics tick with 20 cars (headless, this machine)" % [frames, sim_ms])
	print("  player finished P%d after %d position changes" % [race.player.position, overtakes])
	_check(race._results_shown, "race finishes and the results screen appears")
	_check(race.player.finished, "player crossed the line after %d laps" % laps)
	var finished := 0
	var seen := {}
	var furthest_last := INF
	for e in race.entrants:
		if e.finished:
			finished += 1
		seen[e.position] = true
		furthest_last = minf(furthest_last, e.progress)
	_check(seen.size() == race.entrants.size(), "positions are unique 1..%d" % race.entrants.size())
	print("  %d cars had finished when the results appeared" % finished)
	_check(furthest_last > race.track.total_length * (laps - 1), "no car stranded (last car covered %.0f m)" % furthest_last)
	var stats: Dictionary = save.data["stats"]
	_check(int(stats["races"]) == 1, "race recorded in profile")

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
