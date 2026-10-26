extends SceneTree
## Measures simulation cost per physics tick for different grid sizes.
func _initialize() -> void:
	_run()
func _run() -> void:
	var save: Node = root.get_node("Save")
	for n in [0, 5, 11, 19]:
		save.data = save.default_profile()
		var st: Dictionary = save.data["settings"]
		st["mode"] = "race"; st["laps"] = 5; st["opponents"] = n; st["track"] = "styria"; st["car"] = "gp26"
		var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
		root.add_child(race)
		race.autopilot = load("res://scripts/ai_driver.gd").new()
		for i in range(120 * 8):
			await physics_frame
		var t0 := Time.get_ticks_usec()
		for i in range(120 * 10):
			await physics_frame
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 1200.0
		print("opponents=%2d  %.2f ms per tick" % [n, ms])
		race.queue_free()
		await physics_frame
	quit(0)
