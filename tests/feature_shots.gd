extends SceneTree
## Screens for review: a new circuit with the racing line and the ideal-lap
## ghost, and the Safety Car leading the field.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/feature_shots.gd -- <out_dir> <track> [sc]
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
	var tid: String = args[1]
	var sc := args.has("sc")
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 5; st["opponents"] = 7; st["graphics"] = "saver"; st["track"] = tid; st["car"] = "gp26"
	st["racing_line"] = not sc; st["ideal_ghost"] = not sc; st["qualifying"] = false
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.9
	race.line_guide.visible = not sc
	Engine.max_physics_steps_per_frame = 48
	while race.race_time < (22.0 if not sc else 30.0):
		await physics_frame
	if sc:
		race.control.deploy_sc("test")
		while not race.control.sc.out:
			await physics_frame
		for i in 120 * 25:
			await physics_frame
		pass
	await _shot("%s/%s_%s.png" % [out, tid, "sc" if sc else "line"])
	quit(0)
