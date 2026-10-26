extends SceneTree
## Builds data/steer_cal.json: for each car and speed, the road-wheel angle
## that gives each share (0, 5% .. 100%) of the car's peak steady cornering
## grip. Re-run after changing tyres, suspension or aero:
##   godot --headless --fixed-fps 120 --script res://tests/steer_calibrate.gd
const SPEEDS := [5.0, 10.0, 16.0, 24.0, 34.0, 46.0, 60.0, 76.0, 92.0]
const STEPS := 44
const SHARES := 20
func _initialize() -> void:
	_run()
func _steady(spec: Dictionary, v: float, angle: float) -> float:
	var car = load("res://scripts/car.gd").new()
	car.setup(spec)
	root.add_child(car)
	car.global_transform = Transform3D(Basis(), Vector3(0, car.spawn_height(), 0))
	for i in range(20):
		await physics_frame
	car.linear_velocity = Vector3(0, 0, v)
	car.fixed_steer = angle
	var acc := 0.0
	var n := 0
	for f in range(260):
		var err: float = v - car.linear_velocity.length()
		car.throttle = clampf(err * 0.6, 0.0, 1.0)
		car.brake_input = 0.0
		await physics_frame
		if f > 180:
			acc += absf(car.angular_velocity.y) * car.linear_velocity.length()
			n += 1
	car.queue_free()
	await physics_frame
	return acc / n
func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	root.add_child(ground)
	var specs = load("res://scripts/car_specs.gd")
	var out := {}
	for id in specs.CATALOG:
		var spec: Dictionary = specs.get_spec(id, 0)
		spec["no_steer_cal"] = true
		var max_angle: float = spec["steer_low"]
		var rows: Array = []
		for v in SPEEDS:
			var angles: Array = [0.0]
			var accs: Array = [0.0]
			for k in range(1, STEPS + 1):
				var ang: float = max_angle * pow(float(k) / STEPS, 1.8)
				# Past ~3x the tyre's peak slip plus geometry nothing more happens.
				angles.append(ang)
				accs.append(await _steady(spec, v, ang))
			# Monotonic part up to the peak.
			var peak := 0
			for k in range(accs.size()):
				if accs[k] > accs[peak] * 1.004:
					peak = k
			var a_peak: float = accs[peak]
			var row: Array = []
			for q in range(SHARES + 1):
				var want := a_peak * q / SHARES
				var k := 1
				while k < peak and accs[k] < want:
					k += 1
				var a0: float = accs[k - 1]
				var a1: float = accs[k]
				var t := clampf((want - a0) / maxf(a1 - a0, 0.0001), 0.0, 1.0)
				row.append(snappedf(lerpf(angles[k - 1], angles[k], t), 0.00001))
			rows.append(row)
			print("%-10s %5.1f m/s  peak %.2f g at %.3f rad" % [id, v, a_peak / 9.81, angles[peak]])
		out[id] = {"speeds": SPEEDS, "angles": rows}
	var f := FileAccess.open("res://data/steer_cal.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote data/steer_cal.json")
	quit()
