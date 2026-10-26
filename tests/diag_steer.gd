extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var ground := StaticBody3D.new(); var cs := CollisionShape3D.new(); cs.shape = WorldBoundaryShape3D.new(); ground.add_child(cs); world.add_child(ground)
	var car := RaceCar.new(); car.setup(CarSpecs.get_spec("gp26")); world.add_child(car)
	await physics_frame
	for v in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]:
		for st in [0.3, 1.0]:
			car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, car.spawn_height(), 0))
			car.linear_velocity = Vector3(0, 0, v)
			car.angular_velocity = Vector3.ZERO
			car.reset_controls()
			var h0 := car.global_basis.z
			var p0 := car.global_position
			for f in range(120):
				car.steer_input = st
				var err: float = v - car.forward_speed()
				car.throttle = clampf(err * 0.6 + 0.25, 0.0, 1.0)
				await physics_frame
			var h1 := car.global_basis.z
			var turn := rad_to_deg(h0.signed_angle_to(h1, Vector3.UP))
			var disp := car.global_position - p0
			var vel := car.linear_velocity
			var slip := rad_to_deg(h1.signed_angle_to(vel.normalized(), Vector3.UP))
			print("v=%2.0f steer=%.1f wheel=%.3frad heading %+6.1f deg  moved x=%+6.1f (right is -x)  yaw=%+.2f  slip=%+.1f  speed=%.1f" % [v, st, car.steering, turn, disp.x, car.angular_velocity.y, slip, car.forward_speed()])
	quit(0)
