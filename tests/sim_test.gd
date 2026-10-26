extends SceneTree
## Headless physics checks. Run with:
##   godot --headless --fixed-fps 120 --script res://tests/sim_test.gd
## Exits with code 1 if any check fails.

var failures: Array[String] = []
var world: Node3D
var track: Track
var car: RaceCar


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _steps(n: int) -> void:
	for i in range(n):
		await physics_frame


func _setup(track_id: String, car_id: String) -> void:
	if world != null:
		world.queue_free()
		await physics_frame
	world = Node3D.new()
	root.add_child(world)
	track = Track.new()
	world.add_child(track)
	track.build(track_id)
	car = RaceCar.new()
	car.setup(CarSpecs.get_spec(car_id))
	world.add_child(car)
	await _steps(2)


func _place(xform: Transform3D) -> void:
	car.global_transform = xform
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	await _steps(120)


func _spawn(idx: int) -> void:
	await _place(track.pose_at(idx, car.spawn_height()))


func _fmt(s: float) -> String:
	return "%d:%06.3f" % [int(s) / 60, fmod(s, 60.0)]


## Straight-line acceleration and braking on open ground away from the track.
func _drag_test(label: String, min_top: float, t100_max: float, min_decel: float) -> void:
	var start := Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(-1900, car.spawn_height() + Track.GROUND_Y, 1800))
	await _place(start)
	car.throttle = 1.0
	var t := 0.0
	var t100 := -1.0
	var t200 := -1.0
	var top := 0.0
	while t < 40.0 and car.global_position.x < 1800.0:
		await physics_frame
		t += 1.0 / 120.0
		var kmh := car.speed_kmh()
		top = maxf(top, kmh)
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		if t200 < 0.0 and kmh >= 200.0:
			t200 = t
	print("%s: 0-100 %.2fs, 0-200 %.2fs, top %.0f km/h (gear %d, %.0f rpm)" % [label, t100, t200, top, car.gear, car.rpm])
	_check(t100 > 0.0 and t100 < t100_max, "%s 0-100 km/h under %.1f s" % [label, t100_max])
	_check(top > min_top, "%s top speed over %.0f km/h" % [label, min_top])
	_check(car.gear == car.gear_count(), "%s reaches top gear" % label)
	# Brake from top speed to 50 km/h.
	var v0 := car.forward_speed()
	car.throttle = 0.0
	car.brake_input = 1.0
	var p0 := car.global_position
	var frames := 0
	while car.forward_speed() > 50.0 / 3.6 and frames < 2400:
		await physics_frame
		frames += 1
	var v1 := car.forward_speed()
	var dist := p0.distance_to(car.global_position)
	var decel := (v0 * v0 - v1 * v1) / (2.0 * maxf(dist, 0.1))
	print("%s: braking %.0f->50 km/h in %.0f m (avg %.1f g)" % [label, v0 * 3.6, dist, decel / 9.81])
	_check(decel / 9.81 > min_decel, "%s average braking over %.1f g" % [label, min_decel])
	car.brake_input = 0.0


func _steer_test(label: String) -> void:
	await _spawn(0)
	car.throttle = 1.0
	await _steps(150)
	car.throttle = 0.3
	var h0 := car.global_basis.z
	car.steer_input = 1.0
	await _steps(60)
	var turn := h0.cross(car.global_basis.z).y      # negative = right turn
	_check(turn < -0.03, "%s: steer_input +1 turns right (%.3f)" % [label, turn])
	car.steer_input = 0.0


func _ai_lap(label: String, max_time: float) -> void:
	var n := track.size()
	await _spawn(n - 5)
	var ai := AIDriver.new()
	var prev := n - 5
	var crossings := 0
	var lap_frames := 0
	var max_lat := 0.0
	var flips := 0
	var top := 0.0
	for f in range(120 * 400):
		ai.update(car, track)
		await physics_frame
		var idx := track.nearest_index(car.global_position, prev)
		max_lat = maxf(max_lat, absf(track.lateral(car.global_position, idx)))
		top = maxf(top, car.speed_kmh())
		if car.global_basis.y.y < 0.3:
			flips += 1
		if prev > n * 0.9 and idx < n * 0.1:
			crossings += 1
			if crossings == 2:
				break
			lap_frames = 0
			max_lat = 0.0
		lap_frames += 1
		prev = idx
	var lap := lap_frames / 120.0
	print("%s: AI flying lap %s, top %.0f km/h, max off-line %.1f m" % [label, _fmt(lap), top, max_lat])
	_check(crossings == 2, "%s: AI completes a flying lap" % label)
	_check(crossings == 2 and lap < max_time, "%s: lap under %s" % [label, _fmt(max_time)])
	_check(max_lat < track.road_half + Track.KERB_W + 1.0, "%s: AI stays on the road" % label)
	_check(flips == 0, "%s: never flips" % label)


func _run() -> void:
	await _setup("silvermoor", "gp26")
	print("Track %s: %.0f m, %d samples" % [track.track_name, track.total_length, track.size()])
	await _drag_test("GP-26", 300.0, 3.2, 3.0)
	await _steer_test("GP-26")
	await _ai_lap("GP-26 @ Silvermoor", 125.0)

	await _setup("kestrel_park", "vanta_gt")
	await _drag_test("Vanta GT", 260.0, 4.5, 1.0)
	await _steer_test("Vanta GT")
	await _ai_lap("Vanta GT @ Kestrel Park", 80.0)

	await _setup("silvermoor", "vanta_gt")
	await _ai_lap("Vanta GT @ Silvermoor", 170.0)

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
