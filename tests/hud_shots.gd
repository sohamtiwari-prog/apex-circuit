extends SceneTree
## HUD review: start lights, mid-race, pause menu, classification.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/hud_shots.gd -- <out_dir> [track]
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
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 19
	st["track"] = args[1] if args.size() > 1 else "silvermoor"; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	for i in range(120 * 3 + 20):
		await physics_frame
	await _shot(out + "/h1_lights.png")
	while race.state == 0:
		await physics_frame
	for i in range(120 * 9):
		await physics_frame
	await _shot(out + "/h2_race.png")
	race.hud.set_paused(true)
	await _shot(out + "/h3_pause.png")
	race.hud.set_paused(false)
	for e in race.entrants:
		e.best_lap = 90.0 + randf() * 3.0
	race._show_results()
	await _shot(out + "/h4_results.png")
	quit(0)
