extends SceneTree
## After your finish: watching the rest of the race live from another car
## (and back to the results), and the replay's highlights reel (one moment
## after another, then it stops at the end).
##   godot --headless --fixed-fps 120 --script res://tests/spectate_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	Engine.max_physics_steps_per_frame = 48
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["track"] = "kestrel_park"; st["car"] = "gp26"; st["laps"] = 2; st["opponents"] = 11; st["difficulty"] = "easy"
	save.pending_event = {}
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 1.0
	var t := 0
	while not race._results_shown and t < 120 * 300:
		await physics_frame
		t += 1
	_check(race._results_shown, "the race finishes")
	var running := 0
	for e in race.entrants:
		if not e.finished:
			running += 1
	print("    %d cars still running at your results" % running)
	race.spectate(true)
	await physics_frame
	_check(race.spectating and race.cam.target != race.car and not race.hud.results_panel.visible, "Watch: the camera follows another car, the results make way")
	var first = race.cam.target
	race.spectate_step(1)
	await physics_frame
	_check(race.cam.target != first, "the arrows change car")
	for i in 240:
		await physics_frame
	race.spectate(false)
	await physics_frame
	_check(not race.spectating and race.cam.target == race.car and race.hud.results_panel.visible, "Results: back to your car and the results")
	race.watch_highlights()
	await physics_frame
	_check(race.replay.playing and race.replay.reel, "Highlights: the replay plays as a reel")
	var focus_seen := {}
	t = 0
	while race.replay.reel and t < 120 * 400:
		await physics_frame
		focus_seen[race.replay.focus] = true
		t += 1
	_check(not race.replay.reel and race.replay.paused, "the reel stops after the last moment (%.0f s, %d events)" % [t / 120.0, race.replay.events.size()])
	race.replay.stop()
	# (Leave a clean profile behind: the next test in the same run reads it.)
	var sv: Node = root.get_node("Save")
	sv.data = sv.default_profile()
	sv.save()
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
