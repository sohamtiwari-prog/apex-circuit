extends SceneTree
## Screenshot: the race engineer's radio card and a flag, at the Marina night race.
func _initialize() -> void:
	_run()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 19; st["track"] = "marina"; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	RenderingServer.render_loop_enabled = false
	while race.player.lap < 1:
		await physics_frame
	for i in 30:
		await physics_frame
	race.hud.set_flag("yellow")
	RenderingServer.render_loop_enabled = true
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/radio.png")
	print("saved")
	quit(0)
