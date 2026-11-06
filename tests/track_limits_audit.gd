extends SceneTree
## Track limits, judged on a real race: the AI field (and you on the
## autopilot) racing two laps. Lists every strike, where and how far out;
## the AI drives the racing line, so strikes should be rare everywhere.
##   godot --headless --fixed-fps 120 --script res://tests/track_limits_audit.gd -- <track[,track]|all>
var failures: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var tracks: Array = []
	if a.is_empty() or a[0] == "all":
		for t in Track.CATALOG:
			tracks.append(String(t["id"]))
	else:
		tracks = Array(String(a[0]).split(","))
	for tid in tracks:
		var save: Node = root.get_node("Save")
		save.data = save.default_profile()
		var st: Dictionary = save.data["settings"]
		st["mode"] = "race"; st["laps"] = 2; st["opponents"] = 9; st["track"] = tid; st["car"] = "gp26"
		st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = true
		var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
		root.add_child(race)
		await physics_frame
		race.control._fail.clear()
		race.autopilot = load("res://scripts/ai_driver.gd").new()
		race.autopilot.skill = 0.95
		Engine.max_physics_steps_per_frame = 48
		var t := 0
		while race.state != 2 and t < 120 * 400:     # (2 = finished)
			await physics_frame
			t += 1
		var log: Array = race.control.tl_log
		var cars: int = race.entrants.size()
		print("  %-12s %d strikes in %d car-laps" % [tid, log.size(), cars * 2])
		for l in log:
			print("      ", l)
		var ok: bool = log.size() <= cars * 2 / 5
		if not ok:
			failures.append(tid)
		print(("  PASS  " if ok else "  FAIL  ") + "%s: strikes are rare for cars on the racing line" % tid)
		race.queue_free()
		await process_frame
		await process_frame
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
