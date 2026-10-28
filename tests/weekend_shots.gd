extends SceneTree
## Screenshots: qualifying classification with tyre choice, racing in the
## rain (spray, wet track, tyre panel), the pit lane.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/weekend_shots.gd -- <out_dir> [track]
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	RenderingServer.render_loop_enabled = false
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 19; st["qualifying"] = true; st["weather"] = "wet"
	st["track"] = args[1] if args.size() > 1 else "silvermoor"; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.95
	RenderingServer.render_loop_enabled = false
	await physics_frame
	race.weekend.finish_qualifying(-1.0)
	await _shot(out + "/w1_quali.png")
	race.weekend._end_qualifying()
	race.hud.results_panel.visible = false
	race.hud.touch.visible = true
	race.hud._set_live_visible(true)
	while race.state == 0:
		await physics_frame
	for i in 120 * 14:
		await physics_frame
	await _shot(out + "/w2_rain_chase.png")
	race.cam.set_mode(1)
	for i in 60:
		await physics_frame
	await _shot(out + "/w3_rain_far.png")
	race.weekend.toggle_box()
	while race.player.pit_phase != 2:
		await physics_frame
	for i in 30:
		await physics_frame
	await _shot(out + "/w4_pit.png")
	quit(0)
