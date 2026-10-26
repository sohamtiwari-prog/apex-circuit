extends SceneTree
## Yaw overshoot vs. tyre/suspension parameters (road car at speed).
func _initialize() -> void:
	_run()
func _one(id: String, over: Dictionary, v: float, s: float) -> String:
	var specs = load("res://scripts/car_specs.gd")
	var sp: Dictionary = specs.get_spec(id, 0)
	for k in over:
		sp[k] = over[k]
	var car = load("res://scripts/car.gd").new()
	car.setup(sp)
	root.add_child(car)
	car.global_position = Vector3(0, car.spawn_height(), 0)
	for i in range(60):
		await physics_frame
	car.linear_velocity = Vector3(0, 0, v)
	var peak := 0.0
	var ys: Array[float] = []
	for f in range(480):
		car.steer_input = s if f > 120 else 0.0
		car.throttle = clampf((v - car.forward_speed()) * 0.5, 0.0, 1.0)
		await physics_frame
		if f > 120:
			ys.append(absf(car.angular_velocity.y))
			peak = maxf(peak, ys[-1])
	var steady: float = ys[-1]
	var mn := 99.0
	for i in range(ys.find(peak), ys.size()):
		mn = minf(mn, ys[i])
	car.queue_free()
	await physics_frame
	return "steady %.2f (%.2f g) peak %.2f  dip %.2f  overshoot %3.0f%%" % [steady, steady * v / 9.81, peak, mn, (peak / steady - 1) * 100]
func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	root.add_child(ground)
	var trials := [
		{},
		{"yaw_inertia": 0.5},
		{"yaw_inertia": 1.5},
		{"downforce": 0.0},
		{"drag": 0.0},
		{"power": 900000.0},
	]
	for t in trials:
		print("%-60s %s" % [str(t), await _one("marauder", t, 68.0, 0.3)])
	quit()
