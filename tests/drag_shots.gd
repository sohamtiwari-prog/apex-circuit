extends SceneTree
## Screenshots of drag steering: idle hint, then a thumb steering right.
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = "silvermoor"; st["car"] = "gp26"; st["control_mode"] = "drag"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	for i in range(120 * 6):
		await physics_frame
	await _shot(out + "/d1_idle.png")
	var t: Control = race.hud.touch
	var p0 := Vector2(t.size.x * 0.2, t.size.y * 0.78)
	var e := InputEventScreenTouch.new()
	e.index = 0; e.position = p0; e.pressed = true
	t._input(e)
	var d := InputEventScreenDrag.new()
	var lim: float = t.max_wheel_angle() * 0.6
	d.index = 0; d.position = p0 + Vector2(0, t.drag_range()) + Vector2(sin(lim), -cos(lim)) * t.drag_range()
	t._input(d)
	await _shot(out + "/d2_steer.png")
	race.hud.set_paused(true)
	await _shot(out + "/d3_pause.png")
	quit(0)
