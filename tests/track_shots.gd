extends SceneTree
## Screenshots for judging the look of tracks and cars in a race: chase,
## TV, helicopter and drone views a little way into a race.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/track_shots.gd -- <out_dir> [track] [prefix]
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	RenderingServer.render_loop_enabled = true
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	RenderingServer.render_loop_enabled = false
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var pre: String = args[2] if args.size() > 2 else "t"
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 2; st["opponents"] = 19
	st["track"] = args[1] if args.size() > 1 else "silvermoor"; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	RenderingServer.render_loop_enabled = false
	while race.state != 1:
		await physics_frame
	for i in 120 * 22:
		await physics_frame
	await _shot(out + "/%s1_chase.png" % pre)
	race.watch_replay(true)
	var rp = race.replay
	rp.ui._hidden_by_user = true
	rp.seek(float(rp.count) - 20.0 * 9.0)
	var i := 2
	for m in ["TV", "Helicopter", "Drone", "TV"]:
		rp.cam.mode = rp.cam.modes.find(m)
		rp.cam.cut()
		for f in 120 * 2:
			await physics_frame
		await _shot(out + "/%s%d_%s.png" % [pre, i, m.to_lower()])
		i += 1
	quit(0)
