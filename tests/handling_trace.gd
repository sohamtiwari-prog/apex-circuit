extends SceneTree
var car
func _initialize() -> void:
	_run()
func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	root.add_child(ground)
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "marauder"
	var v: float = float(args[1]) if args.size() > 1 else 45.0
	var s: float = float(args[2]) if args.size() > 2 else 0.7
	var specs = load("res://scripts/car_specs.gd")
	car = load("res://scripts/car.gd").new()
	car.setup(specs.get_spec(id, 0))
	root.add_child(car)
	car.global_position = Vector3(0, car.spawn_height(), 0)
	for i in range(60):
		await physics_frame
	car.linear_velocity = Vector3(0, 0, v)
	for f in range(400):
		car.steer_input = s if f > 120 else 0.0
		var err: float = v - car.forward_speed()
		car.throttle = clampf(err * 0.5, 0.0, 1.0)
		await physics_frame
		if f % 10 == 0 and f > 100:
			var w = car.wheels
			print("f%3d v%5.1f steer %+.3f yaw %+.2f | slip FL %+5.1f FR %+5.1f RL %+5.1f RR %+5.1f | load %5.0f %5.0f %5.0f %5.0f | y %.3f pitch %+.2f roll %+.2f" % [f, car.forward_speed(), car.steering, car.angular_velocity.y,
				rad_to_deg(w[0].slip_angle), rad_to_deg(w[1].slip_angle), rad_to_deg(w[2].slip_angle), rad_to_deg(w[3].slip_angle),
				w[0].load, w[1].load, w[2].load, w[3].load, car.global_position.y, rad_to_deg(car.rotation.x), rad_to_deg(car.rotation.z)])
	quit()
