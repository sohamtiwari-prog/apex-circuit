extends SceneTree
## Headless physics checks. Run with:
##   godot --headless --fixed-fps 120 --script res://tests/sim_test.gd
## Prints acceleration, braking, steering-direction and an AI lap time,
## and exits with code 1 if any check fails.

var track: Track
var car: RaceCar
var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _steps(n: int) -> void:
	for i in range(n):
		await physics_frame


func _spawn(idx: int) -> void:
	car.global_transform = track.pose_at(idx, 0.55)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	await _steps(120)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	track = Track.new()
	world.add_child(track)
	track.build()
	print("Track %s: %.0f m, %d samples" % [Track.TRACK_NAME, track.total_length, track.size()])
	car = RaceCar.new()
	world.add_child(car)
	await _steps(2)

	# 1. Acceleration on the main straight.
	await _spawn(0)
	var start := car.global_position
	print("Acceleration (full throttle):")
	car.throttle = 1.0
	for s in range(1, 9):
		await _steps(120)
		print("  t=%ds  %.1f km/h" % [s, car.speed_kmh()])
	var moved := car.global_position - start
	var along := moved.dot(track.tangents[0])
	_check(along > 50.0, "car drives forward along +Z (moved %.1f m along track)" % along)
	_check(car.speed_kmh() > 150.0, "reaches >150 km/h in 8 s (%.0f)" % car.speed_kmh())

	# 2. Braking from current speed.
	var v0 := car.speed_kmh()
	car.throttle = 0.0
	car.brake_input = 1.0
	var p0 := car.global_position
	var frames := 0
	while car.forward_speed() > 1.0 and frames < 1200:
		await physics_frame
		frames += 1
	var bdist := p0.distance_to(car.global_position)
	print("Braking from %.0f km/h: %.1f m in %.2f s" % [v0, bdist, frames / 120.0])
	var vms := v0 / 3.6
	var decel := vms * vms / (2.0 * maxf(bdist, 0.1))
	_check(decel > 7.0 and decel < 16.0, "braking decel plausible (%.1f m/s^2)" % decel)

	# 3. Steering direction: steer_input +1 must turn right.
	await _spawn(0)
	car.throttle = 1.0
	await _steps(180)
	car.throttle = 0.3
	var h0 := car.global_basis.z
	car.steer_input = 1.0
	await _steps(90)
	var h1 := car.global_basis.z
	var turn := h0.cross(h1).y      # negative = clockwise = right turn
	print("Steer +1 heading change cross.y = %.3f" % turn)
	_check(turn < -0.05, "steer_input +1 turns right")
	car.steer_input = 0.0

	# 4. AI lap: proves the track is drivable and gives a reference time.
	await _spawn(track.size() - 3)
	var ai := AIDriver.new()
	var lap_started := false
	var lap_frames := 0
	var prev_idx := track.size() - 3
	var max_lat := 0.0
	var flips := 0
	var done := false
	var hits := 0
	for f in range(120 * 240):
		ai.update(car, track)
		await physics_frame
		var idx := track.nearest_index(car.global_position, prev_idx)
		var lat := absf(track.lateral(car.global_position, idx))
		max_lat = maxf(max_lat, lat)
		if car.global_basis.y.y < 0.3:
			flips += 1
		if prev_idx > track.size() * 0.9 and idx < track.size() * 0.1:
			hits += 1
			if hits == 1:
				lap_started = true
				lap_frames = 0
			elif hits == 2:
				done = true
				break
		if lap_started:
			lap_frames += 1
		prev_idx = idx
	var lap_s := lap_frames / 120.0
	print("AI flying lap: %d:%06.3f  (max lateral %.1f m, flip frames %d)" % [int(lap_s) / 60, fmod(lap_s, 60.0), max_lat, flips])
	_check(done, "AI completes a full lap")
	_check(max_lat < Track.ROAD_HALF + Track.KERB_W + 1.0, "AI stays on the road (max %.1f m)" % max_lat)
	_check(flips == 0, "car never flips")

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
