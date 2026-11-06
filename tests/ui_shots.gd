extends SceneTree
## Screens for review: the running order board, the penalty strip, the
## onboard camera.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/ui_shots.gd -- <out_dir> [track]
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
	var tid: String = args[1] if args.size() > 1 else "silvermoor"
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 5; st["opponents"] = 19; st["graphics"] = "high"; st["track"] = tid; st["car"] = "gp26"
	st["qualifying"] = false
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.9
	Engine.max_physics_steps_per_frame = 48
	while race.race_time < 25.0:
		await physics_frame
	race.hud.show_penalty(5, "track limits")
	await _shot("%s/ui_penalty.png" % out)
	race.hud.cycle_tower()
	for i in 30:
		await physics_frame
	await _shot("%s/ui_board.png" % out)
	race.hud.cycle_tower()
	race.hud.cycle_tower()
	# Onboard.
	for m in 6:
		if race.cam.mode_name().to_lower().contains("cockpit"):
			break
		race.cam.cycle()
	for i in 240:
		await physics_frame
	await _shot("%s/ui_cockpit.png" % out)
	quit(0)
