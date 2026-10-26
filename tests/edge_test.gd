extends SceneTree
## Drive diagonally off the track and back on at speed. Nothing should stop
## the car at the track edge: it must slow only gently on the grass.
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _cross(race: Node, car_id: String, assists: bool, outward: bool) -> void:
	var track = race.track
	var car = race.car
	race.save.data["settings"]["steer_assist"] = assists
	race.save.data["settings"]["brake_assist"] = false
	# A long straight: start 300 m after the line.
	var idx := 150
	var lat0: float = 0.0 if outward else track.road_half + 9.0
	var heading: float = 0.35 if outward else -0.35        # radians off the track direction
	var b: Basis = Basis.looking_at(-track.tangents[idx], Vector3.UP).rotated(Vector3.UP, -heading)
	car.global_transform = Transform3D(b, track.points[idx] + track.rights[idx] * lat0 + Vector3.UP * car.spawn_height())
	car.linear_velocity = car.global_basis.z * 30.0
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	race.player.idx = idx
	var hud = race.hud
	var min_v := 999.0
	var worst_drop := 0.0
	var prev_v := 30.0
	var crossed := false
	var aim: Vector3 = car.global_basis.z
	for f in range(240):
		# The driver holds their chosen line (straight off, or straight back on).
		var fwd: Vector3 = car.global_basis.z
		fwd.y = 0.0
		hud.touch.steer = clampf(-fwd.normalized().signed_angle_to(aim, Vector3.UP) * 3.0, -1.0, 1.0)
		hud.touch.gas = 0.6
		hud.touch.brake = 0.0
		await physics_frame
		var v: float = car.forward_speed()
		worst_drop = maxf(worst_drop, (prev_v - v) * 120.0)       # m/s^2 of deceleration
		prev_v = v
		min_v = minf(min_v, v)
		var lat: float = absf(track.lateral(car.global_position, track.nearest_index(car.global_position, idx)))
		if outward and lat > track.road_half + Track.KERB_W + 3.0:
			crossed = true
		if not outward and lat < track.road_half - 1.0:
			crossed = true
	var label := "%s %s assists %s" % [car_id, "leaving" if outward else "rejoining", "on" if assists else "off"]
	print("  %-34s crossed=%s  slowest %.1f m/s  hardest decel %.1f m/s^2" % [label, crossed, min_v, worst_drop])
	_check(crossed, "%s: crosses the track edge" % label)
	_check(worst_drop < 9.0, "%s: no wall-like impact at the edge" % label)
	_check(min_v > 22.0, "%s: grass slows the car, but gently" % label)
func _run() -> void:
	await process_frame
	for car_id in ["gp26", "vanta_gt"]:
		var save: Node = root.get_node("Save")
		save.data = save.default_profile()
		var st: Dictionary = save.data["settings"]
		st["mode"] = "time_trial"; st["track"] = "silvermoor"; st["car"] = car_id; st["control_mode"] = "buttons"
		var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
		root.add_child(race)
		for i in range(120 * 7):
			await physics_frame
		for assists in [true, false]:
			await _cross(race, car_id, assists, true)
			await _cross(race, car_id, assists, false)
		race.queue_free()
		await physics_frame
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
