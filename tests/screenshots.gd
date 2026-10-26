extends SceneTree
## Renders screenshots of the running game (needs a display/GPU).
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/screenshots.gd -- <out_dir>

func _initialize() -> void:
	_run()


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var save: Node = root.get_node("Save")
	var menu: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for i in range(90):
		await process_frame
	await _shot(out + "/0_menu.png")
	menu.queue_free()
	save.set_setting("car", args[1] if args.size() > 1 else "gp26")
	save.set_setting("track", args[2] if args.size() > 2 else "silvermoor")
	save.set_setting("camera", 0)
	var main: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in range(60):
		await process_frame
	await _shot(out + "/1_countdown.png")
	main.autopilot = load("res://scripts/ai_driver.gd").new()
	for i in range(int(Engine.get_frames_per_second() * 0) + 240):
		await physics_frame
	for i in range(120 * 6):
		await physics_frame
	await _shot(out + "/2_chase.png")
	for i in range(120 * 7):
		await physics_frame
	main.cam.set_mode(2)
	for i in range(30):
		await physics_frame
	await _shot(out + "/3_onboard.png")
	main.cam.set_mode(3)
	for i in range(240):
		await physics_frame
	await _shot(out + "/3b_onboard2.png")
	main.cam.set_mode(0)
	main.hud.set_paused(true)
	await _shot(out + "/4_pause.png")
	quit(0)
