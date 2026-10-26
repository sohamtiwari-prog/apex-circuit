extends SceneTree
## Steady-state lateral acceleration for each steering input, at several
## speeds: how linear the steering feels.
##   godot --headless --fixed-fps 120 --script res://tests/steer_map.gd -- gp26
func _initialize() -> void:
	_run()
func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	root.add_child(ground)
	var ids: Array = Array(OS.get_cmdline_user_args()) if OS.get_cmdline_user_args().size() > 0 else ["gp26", "vanta_gt", "marauder"]
	var specs = load("res://scripts/car_specs.gd")
	for id in ids:
		print(id)
		for v in [12.0, 25.0, 45.0, 70.0]:
			var row := "  %3.0f km/h:" % (v * 3.6)
			var vals: Array = []
			for k in range(1, 11):
				var s := k / 10.0
				var car = load("res://scripts/car.gd").new()
				car.setup(specs.get_spec(id, 0))
				root.add_child(car)
				car.global_transform = Transform3D(Basis(), Vector3(0, car.spawn_height(), 0))
				for i in range(30):
					await physics_frame
				car.linear_velocity = Vector3(0, 0, v)
				var acc := 0.0
				var n := 0
				for f in range(300):
					car.steer_input = s
					var err: float = v - car.linear_velocity.length()
					car.throttle = clampf(err * 0.6, 0.0, 1.0)
					await physics_frame
					if f > 200:
						acc += absf(car.angular_velocity.y) * car.linear_velocity.length()
						n += 1
				vals.append(acc / n / 9.81)
				car.queue_free()
				await physics_frame
			var mx: float = vals.max()
			for x in vals:
				row += " %4.0f%%" % (x / mx * 100.0)
			row += "   (max %.2f g)" % mx
			print(row)
	quit()
