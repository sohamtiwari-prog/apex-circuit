extends SceneTree
## Renders every car (and several GP liveries) for visual review.
##   godot --rendering-driver opengl3 --script res://tests/car_showcase.gd -- <out_dir>

func _initialize() -> void:
	_run()


func _shot(cam: Camera3D, pos: Vector3, look: Vector3, path: String, fov := 35.0) -> void:
	cam.position = pos
	cam.fov = fov
	cam.look_at(look, Vector3.UP)
	for i in range(3):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.32, 0.34)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = fm
	floor_mi.position.y = -0.43
	world.add_child(floor_mi)

	var ids: Array = CarSpecs.CATALOG
	var x := 0.0
	for id in ids:
		var car := RaceCar.new()
		car.setup(CarSpecs.get_spec(id, 0))
		car.freeze = true
		world.add_child(car)
		var ground_off: float = float(car.spec["wheel_y"]) - float(car.spec["rest_length"]) - float(car.spec["radius_rear"]) + 0.02
		car.position = Vector3(x, -0.43 - ground_off, 0)
		x += 3.2
	# A row of GP liveries behind.
	for t in range(1, 6):
		var car := RaceCar.new()
		car.setup(CarSpecs.get_spec("gp26", t))
		car.freeze = true
		world.add_child(car)
		var ground_off: float = float(car.spec["wheel_y"]) - float(car.spec["rest_length"]) - float(car.spec["radius_rear"]) + 0.02
		car.position = Vector3((t - 1) * 3.2, -0.43 - ground_off, -7.0)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	for i in range(5):
		await process_frame
	await _shot(cam, Vector3(4.5, 1.6, 4.5), Vector3(0.3, 0.0, 0), out + "/gp_front34.png", 32.0)
	await _shot(cam, Vector3(-4.0, 1.4, -4.0), Vector3(0.0, 0.1, 0), out + "/gp_rear34.png", 32.0)
	await _shot(cam, Vector3(0.0, 0.5, 6.5), Vector3(0.0, 0.1, 0), out + "/front.png", 38.0)
	await _shot(cam, Vector3(-6.0, 0.6, -7.0), Vector3(0.0, 0.1, -7.0), out + "/gp_side.png", 38.0)
	await _shot(cam, Vector3(3.2 + 4.5, 1.6, 4.8), Vector3(3.2, -0.05, 0), out + "/vanta.png", 32.0)
	await _shot(cam, Vector3(6.4 + 4.5, 1.6, 4.8), Vector3(6.4, -0.05, 0), out + "/stuttgart.png", 32.0)
	await _shot(cam, Vector3(9.6 + 4.5, 1.6, 4.8), Vector3(9.6, -0.05, 0), out + "/marauder.png", 32.0)
	await _shot(cam, Vector3(12.8 + 4.5, 1.6, 4.8), Vector3(12.8, -0.05, 0), out + "/toro.png", 32.0)
	await _shot(cam, Vector3(16.0 + 4.5, 1.6, 4.8), Vector3(16.0, -0.05, 0), out + "/veloce.png", 32.0)
	await _shot(cam, Vector3(8.0, 9.0, 14.0), Vector3(8.0, -0.4, -3.0), out + "/lineup.png", 45.0)
	quit(0)
