extends SceneTree
## Quick visual review of a track: chase-cam shots at a few points of a lap,
## plus an elevated view.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/look_shots.gd -- <out_dir> <track> [car] [times...]
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
	var track_id: String = args[1] if args.size() > 1 else "silvermoor"
	var car_id: String = args[2] if args.size() > 2 else "gp26"
	var times: Array = [3, 14, 30]
	if args.size() > 3:
		times = []
		for k in range(3, args.size()):
			times.append(float(args[k]))
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = track_id; st["car"] = car_id
	st["racing_line"] = true
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	await _shot("%s/%s_grid.png" % [out, track_id])
	while race.state == 0:
		await physics_frame
	var t := 0.0
	for k in range(times.size()):
		while t < float(times[k]):
			await physics_frame
			t += 1.0 / 120.0
		await _shot("%s/%s_t%02d.png" % [out, track_id, int(times[k])])
	# Elevated view over the car.
	var cam := Camera3D.new()
	race.add_child(cam)
	var p: Vector3 = race.car.global_position
	cam.global_position = p + Vector3(25, 22, 25)
	cam.look_at(p, Vector3.UP)
	cam.fov = 55
	cam.current = true
	await _shot("%s/%s_aerial.png" % [out, track_id])
	quit(0)
