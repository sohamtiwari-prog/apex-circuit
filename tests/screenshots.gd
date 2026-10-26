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
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in range(60):
		await process_frame
	await _shot(out + "/1_countdown.png")
	main.autopilot = AIDriver.new()
	for i in range(int(Engine.get_frames_per_second() * 0) + 240):
		await physics_frame
	for i in range(120 * 6):
		await physics_frame
	await _shot(out + "/2_chase.png")
	for i in range(120 * 7):
		await physics_frame
	main._cycle_camera()
	main._cycle_camera()
	for i in range(30):
		await physics_frame
	await _shot(out + "/3_hood.png")
	main._cycle_camera()
	main._cycle_camera()
	main.hud.set_paused(true)
	await _shot(out + "/4_pause.png")
	quit(0)
