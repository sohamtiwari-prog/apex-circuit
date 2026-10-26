extends SceneTree
## Every track in the catalog must be drivable: the AI in a GP car completes
## a flying lap, stays on the road and never flips.
##   godot --headless --fixed-fps 120 --script res://tests/tracks_test.gd [track_id]

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _lap(track_id: String, car_id: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var track := Track.new()
	world.add_child(track)
	track.build(track_id)
	var car := RaceCar.new()
	car.setup(CarSpecs.get_spec(car_id))
	world.add_child(car)
	await physics_frame
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
	var worst_at := 0.0
	var flips := 0
	var stuck := 0
	for f in range(120 * 360):
		ai.update(car, track)
		await physics_frame
		var idx := track.nearest_index(car.global_position, prev)
		var lat := absf(track.lateral(car.global_position, idx))
		if lat > max_lat:
			max_lat = lat
			worst_at = track.cum[idx]
		if car.global_basis.y.y < 0.3:
			flips += 1
		stuck = stuck + 1 if car.speed_kmh() < 5.0 else 0
		if stuck > 600:
			break
		if prev > n * 0.9 and idx < n * 0.1:
			crossings += 1
			if crossings == 2:
				break
			frames = 0
			max_lat = 0.0
		frames += 1
		prev = idx
	var lap := frames / 120.0
	var limit := track.road_half + Track.KERB_W + 1.0
	print("%-34s %6.0f m  lap %d:%06.3f  max off-line %.1f m (at %.0f m)" % [track.track_name, track.total_length, int(lap) / 60, fmod(lap, 60.0), max_lat, worst_at])
	_check(crossings == 2, "%s: completes a lap" % track_id)
	_check(max_lat < limit, "%s: stays on the road (limit %.1f m)" % [track_id, limit])
	_check(flips == 0, "%s: never flips" % track_id)
	world.queue_free()
	await physics_frame


func _run() -> void:
	var only := OS.get_cmdline_user_args()
	for t in Track.CATALOG:
		if only.is_empty() or only.has(t["id"]):
			await _lap(t["id"], "gp26")
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
