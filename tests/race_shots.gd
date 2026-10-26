extends SceneTree
## Screenshots of a race: grid with start lights, the start, mid-race, results.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/race_shots.gd -- <out_dir> [track]
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 1; st["opponents"] = 19
	st["track"] = args[1] if args.size() > 1 else "silvermoor"; st["car"] = "gp26"; st["team"] = 0
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	for i in range(120 * 3 + 30):
		await physics_frame
	await _shot(out + "/r1_lights.png")
	while race.state == 0:
		await physics_frame
	for i in range(120 * 2):
		await physics_frame
	await _shot(out + "/r2_start.png")
	race.cam.set_mode(1)
	for i in range(120 * 12):
		await physics_frame
	await _shot(out + "/r3_midrace.png")
	race.cam.set_mode(3)
	for i in range(60):
		await physics_frame
	await _shot(out + "/r4_tcam.png")
	race.cam.set_mode(0)
	while not race._results_shown:
		await physics_frame
	for i in range(30):
		await process_frame
	await _shot(out + "/r5_results.png")
	quit(0)
