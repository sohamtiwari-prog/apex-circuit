extends SceneTree
## Measures each car's maximum steady cornering acceleration at several
## speeds on open ground, and fits a(v) = a0 + a1 * v^2 (tyre grip plus
## downforce). The results calibrate the AI's speed profiles
## (ai_grip / ai_grip_aero in car_specs.gd).
##   godot --headless --fixed-fps 120 --script res://tests/grip_test.gd

func _initialize() -> void:
	_run()


func _measure(car_id: String, speeds: Array) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	world.add_child(ground)
	var car := RaceCar.new()
	car.setup(CarSpecs.get_spec(car_id))
	world.add_child(car)
	await physics_frame
	var pts: Array = []
	for v in speeds:
		var best := 0.0
		var steer := 0.05
		while steer <= 1.0:
			car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, car.spawn_height(), 0))
			car.linear_velocity = car.global_basis.z * v
			car.angular_velocity = Vector3.ZERO
			car.reset_controls()
			car.traction_control = true
			var lat_sum := 0.0
			var samples := 0
			var spun := false
			for f in range(360):
				car.steer_input = steer
				var err: float = v - car.forward_speed()
				car.throttle = clampf(err * 0.6 + 0.25, 0.0, 1.0)
				car.brake_input = clampf(-err * 0.5, 0.0, 1.0) if err < -1.0 else 0.0
				await physics_frame
				var vel := car.linear_velocity
				var slip := absf(car.global_basis.z.signed_angle_to(vel.normalized(), Vector3.UP)) if vel.length() > 1.0 else 0.0
				if slip > 0.2:
					spun = true
				if f > 180:
					lat_sum += absf(car.angular_velocity.y) * vel.length()
					samples += 1
			if spun:
				break
			var held := absf(car.forward_speed() - v) < 1.5
			if held and samples > 0:
				best = maxf(best, lat_sum / samples)
			steer += 0.05
		pts.append([v, best])
		print("  %-9s %5.0f km/h  max lateral %.1f m/s^2 (%.2f g)" % [car_id, v * 3.6, best, best / 9.81])
	# Least-squares fit of a = a0 + a1 v^2.
	var n := float(pts.size())
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for p in pts:
		var x: float = p[0] * p[0]
		sx += x
		sy += p[1]
		sxx += x * x
		sxy += x * p[1]
	var a1 := (n * sxy - sx * sy) / maxf(n * sxx - sx * sx, 0.0001)
	var a0 := (sy - a1 * sx) / n
	print("  %s fit: a0 = %.2f m/s^2, a1 = %.5f per (m/s)^2" % [car_id, a0, a1])
	world.queue_free()
	await physics_frame


func _run() -> void:
	await _measure("gp26", [12.0, 18.0, 25.0, 35.0, 50.0, 65.0])
	await _measure("vanta_gt", [10.0, 15.0, 22.0, 30.0, 40.0])
	quit(0)
