extends SceneTree
## A "beginner" holds full throttle, never brakes, and steers for the middle
## of the track (not the racing line).
## With brake + steering assist on, they must still get round the lap on
## the road; this is what keeps the game friendly on a phone.
var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _lap(track_id: String, car_id: String, level: String) -> Array:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = track_id; st["car"] = car_id
	st["control_mode"] = "buttons"
	st["brake_assist"] = level; st["steer_assist"] = level
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	for i in range(120 * 7):
		await physics_frame
	var track = race.track
	var car = race.car
	var braked := 0
	print("    [%s %s] race sees brake_assist=%s steer_assist=%s control=%s" % [track_id, car_id, race.save.get_setting("brake_assist"), race.save.get_setting("steer_assist"), race.save.get_setting("control_mode")])
	var n: int = track.size()
	var off_frames := 0
	var off_where := {}
	var frames := 0
	var start_lap: int = race.player.lap
	while race.player.lap < start_lap + 1 and frames < 120 * 240:
		# Beginner: aim at the centreline 20 m ahead, flat out, never brake.
		var idx: int = race.player.idx
		var ti: int = (idx + 10) % n
		var to: Vector3 = track.points[ti] - car.global_position
		to.y = 0.0
		var fwd: Vector3 = car.global_basis.z
		fwd.y = 0.0
		var ang: float = fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
		# Turn the wheel by about the right amount for that point (pure
		# pursuit on the centreline), but never brake: braking is the assist's job.
		var wb: float = float(car.spec["wheel_front_z"]) - float(car.spec["wheel_rear_z"])
		var delta := atan2(2.0 * wb * sin(ang), maxf(to.length(), 1.0))
		race.hud.touch.steer = car.input_for_angle(-delta, car.forward_speed())
		race.hud.touch.gas = 1.0
		race.hud.touch.brake = 0.0
		await physics_frame
		frames += 1
		if absf(track.lateral(car.global_position, race.player.idx)) > track.road_half + Track.KERB_W:
			off_frames += 1
			var bucket := int(track.cum[race.player.idx] / 100.0) * 100
			off_where[bucket] = off_where.get(bucket, 0) + 1
		if car.brake_input > 0.05:
			braked += 1
	print("    braked on %d frames; ended at %.0f m, %.1f km/h, lat %.1f" % [braked, track.cum[race.player.idx], car.speed_kmh(), track.lateral(car.global_position, race.player.idx)])
	if level != "off" and not off_where.is_empty():
		print("    off road at (m: frames): ", off_where)
	var done: bool = race.player.lap >= start_lap + 1
	var off_pct := 100.0 * off_frames / maxi(frames, 1)
	race.queue_free()
	await physics_frame
	return [done, off_pct, frames / 120.0]


func _run() -> void:
	# Let the Save autoload finish loading from disk before we override it.
	await process_frame
	var specs: Array = [["silvermoor", "gp26"], ["riviera", "gp26"], ["brianza", "marauder"]]
	if OS.get_cmdline_user_args().size() > 0:
		specs = []
		for a in OS.get_cmdline_user_args():
			specs.append(Array(a.split(",")))
	for spec in specs:
		var with_assist: Array = await _lap(spec[0], spec[1], "full")
		var moderate: Array = await _lap(spec[0], spec[1], "moderate")
		var without: Array = await _lap(spec[0], spec[1], "off")
		print("%-11s %-9s FULL: lap %s, %.0f%% off road | MODERATE: lap %s, %.0f%% off | OFF: lap %s, %.0f%% off" % [spec[0], spec[1],
			"done in %.0fs" % with_assist[2] if with_assist[0] else "NOT finished", with_assist[1],
			"done in %.0fs" % moderate[2] if moderate[0] else "NOT finished", moderate[1],
			"done" if without[0] else "NOT finished", without[1]])
		# (A run that stopped against a barrier has a meaningless off-road %:
		# finishing beats it.)
		var below_off: bool = moderate[1] <= without[1] + 0.5 or (moderate[0] and not without[0])
		_check(moderate[1] < with_assist[1] + 60.0 and below_off, "%s/%s: moderate sits between full and off" % [spec[0], spec[1]])
		_check(with_assist[0], "%s/%s: beginner completes the lap with assists" % [spec[0], spec[1]])
		_check(with_assist[1] < 8.0, "%s/%s: beginner stays on the road with assists" % [spec[0], spec[1]])
	print("")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
