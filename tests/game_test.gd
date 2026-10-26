extends SceneTree
## End-to-end check of the real game scene:
## countdown -> racing -> two timed laps -> best lap saved to disk.
##   godot --headless --fixed-fps 120 --script res://tests/game_test.gd

# Note: avoid referencing game class names here; this file is compiled before
# autoloads (Save) exist, and classes that use Save would fail to compile.
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

	# Main menu builds and shows a car.
	var menu: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for i in range(30):
		await process_frame
	_check(menu.preview != null and menu.preview.wheels.size() == 4, "menu shows the selected car")
	menu._select_track("silvermoor", true)
	menu._select_car("gp26", true)
	_check(save.get_setting("car") == "gp26" and save.get_setting("track") == "silvermoor", "menu selection is saved")
	menu.queue_free()
	await process_frame

	var scene: PackedScene = load("res://scenes/race.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await physics_frame
	_check(main.state == 0, "starts in countdown")
	for i in range(120 * 5):
		await physics_frame
	_check(main.state == 1, "countdown finishes and racing starts")

	main.autopilot = load("res://scripts/ai_driver.gd").new()
	var start_lap: int = main.lap
	var frames := 0
	var max_gear := 0
	while main.lap < start_lap + 2 and frames < 120 * 400:
		await physics_frame
		frames += 1
		max_gear = maxi(max_gear, main.car.gear)
	_check(max_gear >= 7, "gearbox shifts up through the gears (max %d)" % max_gear)
	_check(main.lap >= start_lap + 2, "two laps completed (lap counter %d)" % main.lap)
	print("  last lap: %.3f s" % main.last_lap)
	_check(main.track.track_id == "silvermoor" and main.car.spec["id"] == "gp26", "race uses the selected car and track")

	# Old (v1) saves keep their best lap, re-keyed to the car it was set with.
	var old := {"best_laps": {"kestrel_park": 61000}}
	var migrated: Dictionary = save.default_profile()
	save._merge(migrated, old)
	save._migrate(migrated)
	_check(int(migrated["best_laps"].get("kestrel_park|vanta_gt", -1)) == 61000, "v1 save migrates to per-car best laps")

	var key: String = save.lap_key("silvermoor", "gp26")
	var best: int = save.get_best_lap(key)
	_check(best > 0, "best lap recorded in profile (%d ms)" % best)

	# Reload the profile from disk exactly as a fresh app launch would.
	var reloaded: Dictionary = save._load()
	_check(int(reloaded["best_laps"].get(key, -1)) == best, "best lap survives reload from disk")
	_check(int(reloaded["stats"]["laps"]) >= 2, "lap count saved (%d)" % int(reloaded["stats"]["laps"]))

	# Corrupt the main save: the backup must take over.
	var f := FileAccess.open(save.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var recovered: Dictionary = save._load()
	_check(int(recovered["best_laps"].get(key, -1)) > 0, "corrupt save recovers from backup")
	save.save()

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
