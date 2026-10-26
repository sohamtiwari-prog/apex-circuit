extends SceneTree
## Drive off the track, press "Reset car to track" in the pause menu, and
## check the car ends up on the road, facing the right way, and drivable.
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _run() -> void:
	# Let the Save autoload finish loading from disk before we override it.
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["opponents"] = 5; st["track"] = "silvermoor"; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	for i in range(120 * 7):
		await physics_frame
	print("  state after lights: %d" % race.state)
	# Put the car 40 m off the track, sideways.
	var car = race.car
	var idx: int = race.player.idx
	car.global_transform = Transform3D(Basis(Vector3.UP, 1.3), race.track.points[idx] + race.track.rights[idx] * 40.0 + Vector3.UP * 0.5)
	for i in range(120):
		await physics_frame
	var lat0: float = race.track.lateral(car.global_position, race.track.nearest_index(car.global_position, -1))
	print("  before reset: %.1f m from the centreline" % lat0)
	# Press the actual buttons: pause, then "Reset car to track".
	race.hud.set_paused(true)
	await process_frame
	var btn: Button = race.hud._menu_buttons["reset"]
	btn.pressed.emit()
	for i in range(30):
		await physics_frame
	var i2: int = race.track.nearest_index(car.global_position, -1)
	var lat1: float = race.track.lateral(car.global_position, i2)
	var heading: float = car.global_basis.z.dot(race.track.tangents[i2])
	print("  after reset: %.1f m from centreline, heading dot %.2f, paused=%s, controls=%s" % [lat1, heading, paused, car.controls_enabled])
	_check(absf(lat1) < race.track.road_half, "car is back on the road")
	_check(heading > 0.9, "car faces the direction of travel")
	_check(not paused, "game is unpaused")
	car.throttle = 1.0
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	for i in range(120 * 3):
		await physics_frame
	_check(car.speed_kmh() > 40.0, "car drives away after the reset (%.0f km/h)" % car.speed_kmh())
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
