extends SceneTree
## Every car: plausible acceleration and top speed, and the AI completes a
## clean lap of Silvermoor with it.
##   godot --headless --fixed-fps 120 --script res://tests/cars_test.gd [car_id]

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _test(car_id: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var track := Track.new()
	world.add_child(track)
	track.build("silvermoor")
	var car := RaceCar.new()
	car.setup(CarSpecs.get_spec(car_id))
	world.add_child(car)
	await physics_frame
	var spec := car.spec
	# Straight line on open ground.
	car.global_transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(-1900, car.spawn_height() + Track.GROUND_Y, 1800))
	car.reset_controls()
	for i in range(60):
		await physics_frame
	car.throttle = 1.0
	var t := 0.0
	var t100 := -1.0
	var top := 0.0
	while t < 45.0 and car.global_position.x < 1900.0:
		await physics_frame
		t += 1.0 / 120.0
		top = maxf(top, car.speed_kmh())
		if t100 < 0.0 and car.speed_kmh() >= 100.0:
			t100 = t
	var target_top: float = spec.get("top_kmh", 340.0)
	# Lap.
	var n := track.size()
	car.global_transform = track.pose_at(n - 5, car.spawn_height())
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	for i in range(60):
		await physics_frame
	var ai := AIDriver.new()
	var prev := n - 5
	var crossings := 0
	var frames := 0
	var max_lat := 0.0
	var flips := 0
	for f in range(120 * 300):
		ai.update(car, track)
		await physics_frame
		var idx := track.nearest_index(car.global_position, prev)
		max_lat = maxf(max_lat, absf(track.lateral(car.global_position, idx)))
		if car.global_basis.y.y < 0.3:
			flips += 1
		if prev > n * 0.9 and idx < n * 0.1:
			crossings += 1
			if crossings == 2:
				break
			frames = 0
			max_lat = 0.0
		frames += 1
		prev = idx
	var lap := frames / 120.0
	print("%-18s 0-100 %.2fs  top %3.0f km/h (spec %3.0f)  Silvermoor %d:%06.3f  off-line %.1f m" % [spec["name"], t100, top, target_top, int(lap) / 60, fmod(lap, 60.0), max_lat])
	_check(t100 > 1.5 and t100 < 6.0, "%s: 0-100 between 1.5 and 6 s" % car_id)
	_check(absf(top - target_top) < target_top * 0.08, "%s: top speed within 8%% of spec" % car_id)
	_check(crossings == 2, "%s: AI completes a lap" % car_id)
	_check(max_lat < track.road_half + Track.KERB_W + 1.0, "%s: AI stays on the road" % car_id)
	_check(flips == 0, "%s: never flips" % car_id)
	world.queue_free()
	await physics_frame


func _run() -> void:
	var only := OS.get_cmdline_user_args()
	for id in CarSpecs.CATALOG:
		if only.is_empty() or only.has(id):
			await _test(id)
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
