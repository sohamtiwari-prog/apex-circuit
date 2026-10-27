extends SceneTree
## The barriers must hold: hit them flat out at an angle all round every
## track and the car stays inside. Reset must bring the car back from
## anywhere, even from outside the barriers.
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _put(race: Node, idx: int, lat: float, heading: float, speed: float) -> void:
	var track = race.track
	var car = race.car
	var b: Basis = Basis.looking_at(-track.tangents[idx], Vector3.UP).rotated(Vector3.UP, heading)
	car.global_transform = Transform3D(b, track.points[idx] + track.rights[idx] * lat + Vector3.UP * car.spawn_height())
	car.linear_velocity = car.global_basis.z * speed
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	race.player.idx = idx
	race.player.prev_idx = idx
func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	var only := OS.get_cmdline_user_args()
	var tracks := ["silvermoor", "styria", "brianza", "ardennes", "riviera", "entrelagos", "desert", "kestrel_park"]
	if not only.is_empty():
		tracks = only
	for tid in tracks:
		save.data = save.default_profile()
		var st: Dictionary = save.data["settings"]
		st["mode"] = "time_trial"; st["track"] = tid; st["car"] = "gp26"; st["control_mode"] = "buttons"
		st["steer_assist"] = "off"; st["brake_assist"] = "off"
		var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
		root.add_child(race)
		while race.state == 0:
			await physics_frame
		var track = race.track
		var car = race.car
		var hud = race.hud
		var n: int = track.size()
		var escapes: Array = []
		var hits := 0
		for k in 32:
			for side in [-1.0, 1.0]:
				var idx: int = (n * k) / 32
				# 30 degrees towards the barrier at ~300 km/h.
				_put(race, idx, side * clampf(track.wall_at(idx, side) - 9.0, -track.road_half, track.road_half), -side * 0.52, 83.0)
				var worst := 0.0
				var hint := idx
				for f in 150:
					hud.touch.steer = 0.0
					hud.touch.gas = 1.0
					hud.touch.brake = 0.0
					await physics_frame
					hint = track.track_index(car.global_position, hint)
					var lat: float = absf(track.lateral(car.global_position, hint))
					worst = maxf(worst, lat)
					if car.global_position.y < track.points[hint].y - 4.0:
						worst = 999.0
				var w: float = track.wall_at(idx, side)
				if worst > w - 3.0:
					hits += 1
				if worst > w + 2.0:
					escapes.append("%d%s(%.0fm)" % [idx, "R" if side > 0 else "L", worst])
		print("  %-11s wall %.0f m: %d hits, escapes %s" % [tid, track.wall_offset, hits, str(escapes)])
		_check(escapes.is_empty(), "%s: flat-out barrier hits never get through (%d/64 escaped)" % [tid, escapes.size()])
		# Reset from outside the barriers, upside down, and from far away.
		var bad: Array = []
		for k in 6:
			var idx: int = (n * k) / 6 + 7
			_put(race, idx, track.wall_at(idx, 1.0) + 12.0 + k * 6.0, 0.0, 0.0)
			if k == 3:
				car.global_transform.basis = car.global_transform.basis.rotated(car.global_basis.z, PI)
			if k == 5:
				car.global_position.y -= 30.0          # below the ground
			for f in 60:
				await physics_frame
			hud.reset_requested.emit()
			for f in 120:
				hud.touch.gas = 0.0
				await physics_frame
			var i2: int = track.nearest_index(car.global_position, -1)
			var lat: float = absf(track.lateral(car.global_position, i2))
			var upright: bool = car.global_basis.y.y > 0.9
			var on_ground: bool = absf(car.global_position.y - track.points[i2].y) < 2.0
			if lat > track.road_half or not upright or not on_ground:
				bad.append("%d: lat %.1f up %s ground %s" % [k, lat, upright, on_ground])
		_check(bad.is_empty(), "%s: Reset brings the car back onto the road from anywhere %s" % [tid, str(bad)])
		race.queue_free()
		await process_frame
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
