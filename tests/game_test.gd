extends SceneTree
## End-to-end check of the real game scene:
## countdown -> racing -> two timed laps -> best lap saved to disk.
##   godot --headless --fixed-fps 120 --script res://tests/game_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()     # start from a clean profile
	save.save()

	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await physics_frame
	_check(main.state == 0, "starts in countdown")
	for i in range(120 * 5):
		await physics_frame
	_check(main.state == 1, "countdown finishes and racing starts")

	main.autopilot = AIDriver.new()
	var start_lap: int = main.lap
	var frames := 0
	while main.lap < start_lap + 2 and frames < 120 * 200:
		await physics_frame
		frames += 1
	_check(main.lap >= start_lap + 2, "two laps completed (lap counter %d)" % main.lap)
	print("  last lap: %s" % Hud.fmt_time(main.last_lap))

	var best: int = save.get_best_lap(Track.TRACK_ID)
	_check(best > 0, "best lap recorded in profile (%d ms)" % best)

	# Reload the profile from disk exactly as a fresh app launch would.
	var reloaded: Dictionary = save._load()
	_check(int(reloaded["best_laps"].get(Track.TRACK_ID, -1)) == best, "best lap survives reload from disk")
	_check(int(reloaded["stats"]["laps"]) >= 2, "lap count saved (%d)" % int(reloaded["stats"]["laps"]))

	# Corrupt the main save: the backup must take over.
	var f := FileAccess.open(save.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var recovered: Dictionary = save._load()
	_check(int(recovered["best_laps"].get(Track.TRACK_ID, -1)) > 0, "corrupt save recovers from backup")
	save.save()

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
