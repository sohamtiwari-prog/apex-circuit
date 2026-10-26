extends SceneTree
## Measures how a car responds to steering: the numbers behind "feel".
##   godot --headless --fixed-fps 120 --script res://tests/handling_diag.gd -- gp26
var car
func _initialize() -> void:
	_run()
func _make(id: String) -> void:
	if car != null:
		car.queue_free()
		await physics_frame
	var specs = load("res://scripts/car_specs.gd")
	car = load("res://scripts/car.gd").new()
	car.setup(specs.get_spec(id, 0))
	root.add_child(car)
	car.global_position = Vector3(0, car.spawn_height(), 0)
	for i in range(60):
		await physics_frame
func _hold_speed(v: float) -> void:
	var err: float = v - car.forward_speed()
	car.throttle = clampf(err * 0.5, 0.0, 1.0) if err > 0 else 0.0
	car.brake_input = clampf(-err * 0.3, 0.0, 1.0) if err < -1.0 else 0.0
func _launch(v: float) -> void:
	car.global_transform = Transform3D(Basis(), Vector3(0, car.spawn_height(), 0))
	car.linear_velocity = Vector3(0, 0, v)
	car.angular_velocity = Vector3.ZERO
	car.steer_input = 0.0
	for i in range(120):
		_hold_speed(v)
		await physics_frame
func _step(v: float, s: float, lift: bool) -> void:
	await _launch(v)
	var peak := 0.0
	var t90 := -1.0
	var yaws: Array[float] = []
	var max_beta := 0.0
	var max_roll := 0.0
	var spun := false
	for f in range(360):
		car.steer_input = s
		if lift and f > 180:
			car.throttle = 0.0
			car.brake_input = 0.0
		else:
			_hold_speed(v)
		await physics_frame
		var yaw: float = absf(car.angular_velocity.y)
		yaws.append(yaw)
		peak = maxf(peak, yaw)
		var vel: Vector3 = car.linear_velocity
		var fwd: Vector3 = car.global_basis.z
		var beta := rad_to_deg(absf(Vector2(fwd.x, fwd.z).angle_to(Vector2(vel.x, vel.z)))) if vel.length() > 3 else 0.0
		max_beta = maxf(max_beta, beta)
		if beta > 25.0:
			spun = true
		max_roll = maxf(max_roll, rad_to_deg(absf(car.global_basis.get_euler().z)))
	var steady: float = yaws[170]
	for i in range(yaws.size()):
		if t90 < 0 and yaws[i] > 0.9 * steady:
			t90 = i / 120.0
	var vlat: float = steady * car.linear_velocity.length() / 9.81
	print("  %3.0f km/h steer %.2f%s: yaw %.2f rad/s (%.2f g), reach 90%% in %.2fs, overshoot %3.0f%%, slip max %4.1f deg, roll %.1f deg, end slip %4.1f, spun=%s" % [
		v * 3.6, s, " +lift" if lift else "", steady, vlat, t90, (peak / maxf(steady, 0.001) - 1.0) * 100.0,
		max_beta, max_roll, 0.0, spun])
func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	root.add_child(ground)
	var ids: Array = ["gp26", "vanta_gt", "marauder"]
	if OS.get_cmdline_user_args().size() > 0:
		ids = Array(OS.get_cmdline_user_args())
	for id in ids:
		await _make(id)
		print(id)
		for v in [22.0, 45.0, 70.0]:
			for s in [0.3, 0.7, 1.0]:
				await _step(v, s, false)
		await _step(45.0, 0.7, true)
		await _step(70.0, 0.7, true)
	quit()
