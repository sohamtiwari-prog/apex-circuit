extends SceneTree
## One GP car from the angles F1 cars are photographed from, for reviewing
## its shape: side profile, low front three-quarter, rear three-quarter,
## top, head on and from behind; then three liveries side by side.
##   godot --resolution 1600x720 --script res://tests/gp_shots.gd -- <out_dir> [car_id] [team]

func _initialize() -> void:
	_run()


func _shot(cam: Camera3D, pos: Vector3, look: Vector3, path: String, fov := 30.0) -> void:
	cam.position = pos
	cam.fov = fov
	cam.look_at(look, Vector3.UP if absf((look - pos).normalized().y) < 0.98 else Vector3.FORWARD)
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _car(world: Node3D, id: String, team: int, at: Vector3) -> RaceCar:
	var car := RaceCar.new()
	car.setup(CarSpecs.get_spec(id, team))
	car.freeze = true
	world.add_child(car)
	var off: float = float(car.spec["wheel_y"]) - float(car.spec["rest_length"]) - float(car.spec["radius_rear"]) + 0.02
	car.position = at + Vector3(0, -0.43 - off, 0)
	return car


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var id: String = args[1] if args.size() > 1 else "gp26"
	var team: int = int(args[2]) if args.size() > 2 else 0
	var world := Node3D.new()
	root.add_child(world)
	Look.build(world, "park", "day", "styria")
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.22, 0.23)
	fm.roughness = 0.9
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = fm
	floor_mi.position.y = -0.43
	world.add_child(floor_mi)
	_car(world, id, team, Vector3.ZERO)
	_car(world, id, team + 3, Vector3(-30, 0, 0))
	_car(world, id, team + 6, Vector3(-27, 0, 0))
	_car(world, id, team + 1, Vector3(-24, 0, 0))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	for i in 6:
		await process_frame
	var y := -0.05
	await _shot(cam, Vector3(9.5, 0.1, 0.0), Vector3(0, y, -0.1), out + "/s1_side.png", 30.0)
	await _shot(cam, Vector3(3.6, 0.0, 5.2), Vector3(0, y, 0.4), out + "/s2_front34.png", 32.0)
	await _shot(cam, Vector3(-3.8, 0.55, -5.0), Vector3(0, y + 0.1, -0.4), out + "/s3_rear34.png", 32.0)
	await _shot(cam, Vector3(0.01, 9.0, 0.0), Vector3(0, -0.4, 0.0), out + "/s4_top.png", 38.0)
	await _shot(cam, Vector3(0.0, 0.12, 7.0), Vector3(0, y + 0.05, 0.0), out + "/s5_front.png", 26.0)
	await _shot(cam, Vector3(0.0, 0.5, -7.0), Vector3(0, y + 0.1, 0.0), out + "/s6_rear.png", 26.0)
	await _shot(cam, Vector3(1.6, 0.9, 2.1), Vector3(0, 0.2, -0.2), out + "/s7_cockpit_close.png", 40.0)
	await _shot(cam, Vector3(-27.0, 2.2, 7.5), Vector3(-27.0, -0.2, 0.0), out + "/s8_liveries.png", 42.0)
	quit(0)
