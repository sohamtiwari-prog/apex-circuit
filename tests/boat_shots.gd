extends SceneTree
## Pictures of a powerboat race: the grid at the start gantry, the chase
## camera, a low side shot running alongside, the cockpit, from above.
##   godot --rendering-method mobile --resolution 1600x720 --script res://tests/boat_shots.gd -- <out_dir> [course] [team]
func _initialize() -> void:
	_run()


func _snap(path: String) -> void:
	for i in 3:
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
	st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 7
	st["track"] = args[1] if args.size() > 1 else "lago_brisa"; st["car"] = "h1"; st["time_of_day"] = "day"; st["weather"] = "dry"
	st["team"] = int(args[2]) if args.size() > 2 else 0
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	for i in 20:
		await process_frame
	var a := AIDriver.new()
	a.skill = 0.97
	race.autopilot = a
	for c in race.get_children():
		if c is CanvasLayer:
			c.visible = false
	await _snap(out + "/b1_grid.png")
	# (Run with --fixed-fps 30: 14 seconds into the race.)
	for i in 420:
		await process_frame
	await _snap(out + "/b2_chase.png")
	var cam := Camera3D.new()
	race.add_child(cam)
	cam.far = 3000.0
	var car: RaceCar = race.car
	cam.current = true
	var b := car.global_basis
	cam.global_position = car.global_position + b.x * 7.0 + b.z * 2.5 + Vector3(0, 0.9, 0)
	cam.look_at(car.global_position + Vector3(0, 0.5, 0))
	cam.fov = 45.0
	await _snap(out + "/b3_side.png")
	cam.global_position = car.global_position - b.z * 9.0 + b.x * 3.0 + Vector3(0, 2.2, 0)
	cam.look_at(car.global_position + b.z * 4.0)
	cam.fov = 50.0
	await _snap(out + "/b4_rear34.png")
	var tr: Track = race.track
	var c0: Vector3 = tr.points[0]
	cam.global_position = c0 + tr.rights[0] * 40.0 + Vector3(0, 60.0, 0) - tr.htangents[0] * 60.0
	cam.look_at(c0 + tr.htangents[0] * 80.0)
	await _snap(out + "/b5_aerial.png")
	cam.global_position = c0 + Vector3(0, 700.0, 0) + tr.htangents[0] * 200.0 - tr.rights[0] * 300.0
	cam.look_at(c0 + tr.htangents[0] * 200.0)
	cam.fov = 60.0
	await _snap(out + "/b6_overview.png")
	cam.current = false
	race.cam.current = true
	race._cycle_camera()
	await _snap(out + "/b7_cockpit.png")
	quit(0)
