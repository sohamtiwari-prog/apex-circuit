extends SceneTree
## Drag steering and assist levels.
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _touch(t: Control, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	t._input(e)
func _drag(t: Control, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	t._input(e)
func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = "silvermoor"; st["car"] = "gp26"
	st["control_mode"] = "drag"; st["steer_assist"] = "off"; st["brake_assist"] = "off"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	for i in range(10):
		await process_frame
	var t: Control = race.hud.touch
	_check(t.mode == "drag", "drag steering mode is active")
	var sz: Vector2 = t.size
	var r: float = t.drag_range()
	var lim: float = t.max_wheel_angle()
	var p0 := Vector2(sz.x * 0.2, sz.y * 0.75)
	_touch(t, 0, p0, true)
	_check(absf(t.steer) < 0.001, "touching down doesn't steer (%.2f)" % t.steer)
	# Thumb around the rim by half the lock.
	var hub := p0 + Vector2(0, r)
	var half := hub + Vector2(sin(lim * 0.5), -cos(lim * 0.5)) * r
	_drag(t, 0, half)
	_check(absf(t.steer - 0.485) < 0.03, "half the wheel rotation = half lock right (%.2f)" % t.steer)
	# Sliding straight sideways also turns the wheel.
	_drag(t, 0, p0 + Vector2(-r * tan(lim * 0.25), 0))
	_check(t.steer < -0.2 and t.steer > -0.3, "sliding sideways turns it too: quarter lock left (%.2f)" % t.steer)
	_drag(t, 0, p0 + Vector2(r * 2.5, r * 0.3))
	_check(t.steer > 0.99, "full lock at the end of the rim (%.2f)" % t.steer)
	# The wheel follows past full lock; turning back by the full range centres.
	var h2: Vector2 = t._drag_origin
	var thumb: Vector2 = t._drag_pos
	var rad := (thumb - h2).length()
	_drag(t, 0, h2 + Vector2(0, -rad))
	_check(absf(t.steer) < 0.02, "wheel follows the thumb: turning back by the full range centres (%.2f)" % t.steer)
	# A second finger on the gas while steering.
	var gas_rect: Rect2 = t._regions["gas"]
	_touch(t, 1, gas_rect.get_center(), true)
	var h3: Vector2 = t._drag_origin
	_drag(t, 0, h3 + Vector2(sin(lim * 0.6), -cos(lim * 0.6)) * r)
	_check(t.gas > 0.9 and t.steer > 0.4, "steer and gas at the same time (gas %.1f, steer %.2f)" % [t.gas, t.steer])
	# The car gets the input.
	for i in range(3):
		await physics_frame
	_check(absf(race.car.steer_input - t.steer) < 0.001, "car receives the drag steering")
	_touch(t, 0, p0, false)
	_check(absf(t.steer) < 0.001, "letting go centres the steering")
	_touch(t, 1, gas_rect.get_center(), false)
	_check(t.gas < 0.01, "letting go of gas")
	# A touch outside the steering area doesn't steer.
	_touch(t, 2, Vector2(sz.x * 0.6, sz.y * 0.5), true)
	_drag(t, 2, Vector2(sz.x * 0.6 + r, sz.y * 0.5))
	_check(absf(t.steer) < 0.001, "touches in the middle of the screen don't steer")
	_touch(t, 2, Vector2(sz.x * 0.6 + r, sz.y * 0.5), false)

	# Losing focus (an edge swipe showing the system bars) doesn't pause the
	# race; leaving the app does.
	race.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	race.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not race.hud.is_paused() and not race.hud.pause_panel.visible, "a focus loss (system bars) doesn't open the pause menu")
	race.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(race.hud.is_paused() and race.hud.pause_panel.visible, "leaving the app pauses the race")
	race.hud.set_paused(false)

	# Assist levels and migration of old on/off saves.
	_check(is_equal_approx(save.assist_level("steer_assist"), 0.0), "assist off = 0")
	st["brake_assist"] = "moderate"
	_check(is_equal_approx(save.assist_level("brake_assist"), 0.5), "moderate = 0.5")
	var old: Dictionary = save.default_profile()
	old["settings"]["brake_assist"] = true
	old["settings"]["steer_assist"] = false
	save._migrate(old)
	_check(old["settings"]["brake_assist"] == "full" and old["settings"]["steer_assist"] == "off", "old on/off saves become full/off")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
