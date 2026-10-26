extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	root.add_child(ground)
	var id: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "gp26"
	var car = load("res://scripts/car.gd").new()
	car.setup(load("res://scripts/car_specs.gd").get_spec(id, 0))
	root.add_child(car)
	car.global_position = Vector3(0, car.spawn_height(), 0)
	for i in range(60):
		await physics_frame
	car.throttle = 1.0
	var prev: float = 0.0
	for f in range(120 * 20):
		await physics_frame
		var v: float = car.forward_speed()
		if f % 60 == 0:
			var w = car.wheels
			print("t=%4.1f v=%5.1f acc=%5.2f gear %d rpm %5.0f load F %5.0f R %5.0f util R %.2f TC %s comp R %.3f" % [f / 120.0, v, (v - prev) * 2.0, car.gear, car.rpm, w[0].load, w[2].load, w[2].utilisation, car.traction_control, w[2].compression])
			prev = v
	quit()
