class_name Hud
extends CanvasLayer
## Race HUD, top-bar buttons and the pause/settings menu.

signal restart_requested
signal reset_requested
signal camera_requested
signal settings_changed
signal menu_requested

var touch: TouchControls
var lap_label: Label
var time_label: Label
var last_label: Label
var best_label: Label
var speed_label: Label
var unit_label: Label
var gear_label: Label
var shift_lights: Array[ColorRect] = []
var center_label: Label
var banner_label: Label
var warn_label: Label
var pause_panel: PanelContainer
var cam_button: Button
var _menu_buttons := {}
var pos_label: Label
var board: VBoxContainer
var lights_box: HBoxContainer
var lights: Array[Panel] = []
var results_panel: PanelContainer
var _race_mode := false
var _last_valid := true
var _last_lit := -1
var _total_laps := 0
# Looked up at runtime (not by global name) so this script also compiles in tests.
var save: Node
var _banner_time := 0.0
var _warn_time := 0.0


func _ready() -> void:
	save = get_node("/root/Save")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	touch = TouchControls.new()
	touch.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(touch)

	# Timing block, top-left.
	var timing := VBoxContainer.new()
	timing.position = Vector2(24, 18)
	timing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(timing)
	lap_label = _label(30, timing)
	time_label = _label(46, timing)
	last_label = _label(24, timing)
	best_label = _label(24, timing)

	# Speedometer, bottom-centre.
	var speed_box := VBoxContainer.new()
	speed_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	speed_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	speed_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	speed_box.offset_bottom = -16
	speed_box.alignment = BoxContainer.ALIGNMENT_END
	speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(speed_box)
	var shift_box := HBoxContainer.new()
	shift_box.alignment = BoxContainer.ALIGNMENT_CENTER
	shift_box.add_theme_constant_override("separation", 6)
	shift_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_box.add_child(shift_box)
	for i in range(10):
		var light := ColorRect.new()
		light.custom_minimum_size = Vector2(22, 12)
		light.color = Color(1, 1, 1, 0.12)
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shift_box.add_child(light)
		shift_lights.append(light)
	gear_label = _label(44, speed_box)
	gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	speed_label = _label(64, speed_box)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_label = _label(20, speed_box)
	unit_label.text = "KM/H"
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Countdown / big messages.
	center_label = _label(120, root)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	banner_label = _label(38, root)
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_label.offset_top = 110
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	warn_label = _label(26, root)
	warn_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	warn_label.offset_top = 170
	warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_label.add_theme_color_override("font_color", Color(1, 0.75, 0.2))

	# Top-right buttons.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -18
	bar.offset_top = 16
	bar.add_theme_constant_override("separation", 14)
	root.add_child(bar)
	cam_button = _button("CAM", bar, func(): camera_requested.emit())
	cam_button.custom_minimum_size = Vector2(110, 72)
	var rb := _button("RESET", bar, func(): reset_requested.emit())
	rb.custom_minimum_size = Vector2(120, 72)
	var pb := _button("II", bar, func(): set_paused(true))
	pb.custom_minimum_size = Vector2(90, 72)

	# Race position (big) and a mini leaderboard under the timing block.
	pos_label = _label(50, timing)
	pos_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	board = VBoxContainer.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_theme_constant_override("separation", 2)
	timing.add_child(board)

	# Start lights: five pairs of red lamps across the top.
	lights_box = HBoxContainer.new()
	lights_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	lights_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lights_box.offset_top = 40
	lights_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lights_box.add_theme_constant_override("separation", 14)
	lights_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lights_box)
	for i in range(5):
		var lamp := Panel.new()
		lamp.custom_minimum_size = Vector2(64, 64)
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lights_box.add_child(lamp)
		lights.append(lamp)
	lights_box.visible = false

	_build_pause_menu(root)
	_build_results(root)
	set_paused(false)


func _label(fs: int, parent: Node) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, fs / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(text: String, parent: Node, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.72)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Color(1.0, 0.42, 0.1, 0.9)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_pause_menu(root: Control) -> void:
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.97)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(26)
	pause_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(pause_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 560)
	scroll.scroll_deadzone = 24       # a slightly moving tap still presses a button
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pause_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	scroll.add_child(v)

	var title := _label(40, v)
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_menu_buttons["resume"] = _button("Resume", v, func(): set_paused(false))
	_menu_buttons["restart"] = _button("Restart race", v, func():
		set_paused(false)
		restart_requested.emit())
	_menu_buttons["reset"] = _button("Reset car to track", v, func():
		set_paused(false)
		reset_requested.emit())
	_menu_buttons["controls"] = _button("", v, func():
		save.set_setting("control_mode", "buttons" if save.get_setting("control_mode") == "tilt" else "tilt")
		_refresh_menu())
	_menu_buttons["auto"] = _button("", v, func():
		save.set_setting("auto_accelerate", not bool(save.get_setting("auto_accelerate")))
		_refresh_menu())
	_menu_buttons["invert"] = _button("", v, func():
		save.set_setting("invert_tilt", not bool(save.get_setting("invert_tilt")))
		_refresh_menu())
	_menu_buttons["sens"] = _button("", v, func():
		var steps := [0.6, 0.8, 1.0, 1.3, 1.6, 2.0]
		var cur := float(save.get_setting("tilt_sensitivity"))
		var nxt: float = steps[0]
		for s in steps:
			if s > cur + 0.01:
				nxt = s
				break
		save.set_setting("tilt_sensitivity", nxt)
		_refresh_menu())
	_menu_buttons["tc"] = _button("", v, func():
		save.set_setting("traction_control", not bool(save.get_setting("traction_control")))
		_refresh_menu())
	_menu_buttons["abs"] = _button("", v, func():
		save.set_setting("abs", not bool(save.get_setting("abs")))
		_refresh_menu())
	_menu_buttons["brake_assist"] = _button("", v, func():
		save.set_setting("brake_assist", not bool(save.get_setting("brake_assist")))
		_refresh_menu())
	_menu_buttons["steer_assist"] = _button("", v, func():
		save.set_setting("steer_assist", not bool(save.get_setting("steer_assist")))
		_refresh_menu())
	_menu_buttons["quit"] = _button("Quit to main menu", v, func(): menu_requested.emit())
	for key in _menu_buttons:
		(_menu_buttons[key] as Button).custom_minimum_size = Vector2(0, 66)
	_refresh_menu()


func _refresh_menu() -> void:
	var tilt: bool = save.get_setting("control_mode") == "tilt"
	(_menu_buttons["controls"] as Button).text = "Steering: " + ("Tilt phone" if tilt else "On-screen buttons")
	(_menu_buttons["auto"] as Button).text = "Auto-accelerate: " + ("On" if save.get_setting("auto_accelerate") else "Off")
	(_menu_buttons["invert"] as Button).text = "Invert tilt: " + ("On" if save.get_setting("invert_tilt") else "Off")
	(_menu_buttons["sens"] as Button).text = "Tilt sensitivity: %.1fx" % float(save.get_setting("tilt_sensitivity"))
	(_menu_buttons["tc"] as Button).text = "Traction control: " + ("On" if save.get_setting("traction_control") else "Off")
	(_menu_buttons["abs"] as Button).text = "ABS: " + ("On" if save.get_setting("abs") else "Off")
	(_menu_buttons["brake_assist"] as Button).text = "Brake assist: " + ("On" if save.get_setting("brake_assist") else "Off")
	(_menu_buttons["steer_assist"] as Button).text = "Steering assist: " + ("On" if save.get_setting("steer_assist") else "Off")
	touch.configure(String(save.get_setting("control_mode")), bool(save.get_setting("auto_accelerate")))
	settings_changed.emit()


func set_paused(p: bool) -> void:
	get_tree().paused = p
	pause_panel.visible = p
	touch.release_all()
	if not p:
		save.save()


func is_paused() -> bool:
	return get_tree().paused


# ------------------------------------------------------------ display

static func fmt_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.---"
	var ms := int(round(seconds * 1000.0))
	return "%d:%02d.%03d" % [ms / 60000, (ms / 1000) % 60, ms % 1000]


func set_camera_name(n: String) -> void:
	cam_button.text = n


func update_timing(lap: int, lap_time: float, last: float, best: float, valid: bool) -> void:
	lap_label.text = ("LAP %d / %d" % [maxi(lap, 1), _total_laps]) if _race_mode else ("LAP %d" % maxi(lap, 1))
	time_label.text = fmt_time(lap_time)
	if valid != _last_valid:
		_last_valid = valid
		time_label.add_theme_color_override("font_color", Color.WHITE if valid else Color(1, 0.45, 0.35))
	last_label.text = "LAST  " + fmt_time(last)
	best_label.text = "BEST  " + fmt_time(best)


func update_engine(gear: int, rpm: float, shift_rpm: float, redline: float) -> void:
	gear_label.text = "R" if gear < 0 else str(gear)
	# F1-style shift lights: green, then red, then all blue at the shift point.
	var start := shift_rpm - (redline - shift_rpm) * 6.0
	var frac := clampf((rpm - start) / (shift_rpm - start), 0.0, 1.0)
	var lit := int(round(frac * shift_lights.size()))
	if rpm >= shift_rpm:
		lit = 99
	if lit == _last_lit:
		return
	_last_lit = lit
	for i in range(shift_lights.size()):
		var col := Color(1, 1, 1, 0.12)
		if rpm >= shift_rpm:
			col = Color(0.25, 0.45, 1.0)
		elif i < lit:
			col = Color(0.2, 0.9, 0.3) if i < 4 else (Color(1.0, 0.2, 0.15) if i < 7 else Color(0.6, 0.3, 1.0))
		shift_lights[i].color = col


func set_race_mode(race: bool, laps: int) -> void:
	_race_mode = race
	_total_laps = laps
	pos_label.visible = race
	board.visible = race


func show_lights(lit: int, out: bool) -> void:
	lights_box.visible = not out
	for i in range(lights.size()):
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(32)
		sb.bg_color = Color(1.0, 0.08, 0.05) if i < lit else Color(0.12, 0.02, 0.02, 0.85)
		sb.border_color = Color(0.05, 0.05, 0.05)
		sb.set_border_width_all(6)
		lights[i].add_theme_stylebox_override("panel", sb)


func update_position(pos: int, total: int, rows: Array) -> void:
	pos_label.text = "P%d / %d" % [pos, total]
	for c in board.get_children():
		c.queue_free()
	var last := 0
	for r in rows:
		if int(r["pos"]) > last + 1:
			var dots := _label(14, board)
			dots.text = "   ..."
		last = int(r["pos"])
		var l := _label(17, board)
		l.text = "%2d  %-14s %s" % [r["pos"], r["name"], r["gap"]]
		if r["player"]:
			l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))


func _build_results(root: Control) -> void:
	results_panel = PanelContainer.new()
	results_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.94)
	sb.set_content_margin_all(28)
	results_panel.add_theme_stylebox_override("panel", sb)
	results_panel.visible = false
	results_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(results_panel)


func hide_results() -> void:
	results_panel.visible = false


func show_results(rows: Array, on_restart: Callable, on_menu: Callable) -> void:
	for c in results_panel.get_children():
		c.queue_free()
	touch.release_all()
	touch.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	results_panel.add_child(v)
	var title := _label(44, v)
	var me := 0
	for r in rows:
		if r["player"]:
			me = int(r["pos"])
	title.text = "RACE RESULT  ·  YOU FINISHED P%d" % me
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2) if me <= 3 else Color.WHITE)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for h in ["POS", "DRIVER", "TEAM", "TIME / GAP", "BEST LAP"]:
		var l := _label(20, grid)
		l.text = h
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	for r in rows:
		var col := Color(1.0, 0.75, 0.2) if r["player"] else Color.WHITE
		for val in [str(r["pos"]), r["name"], r["team"], r["gap"], r["best"]]:
			var l := _label(24, grid)
			l.text = val
			l.add_theme_color_override("font_color", col)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	bar.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bar)
	var again := _button("Race again", bar, func():
		touch.visible = true
		on_restart.call())
	again.custom_minimum_size = Vector2(280, 76)
	var menu := _button("Main menu", bar, func(): on_menu.call())
	menu.custom_minimum_size = Vector2(280, 76)
	results_panel.visible = true


func update_speed(kmh: float) -> void:
	speed_label.text = str(int(round(kmh)))


func show_center(text: String) -> void:
	center_label.text = text


func show_banner(text: String, color: Color, secs := 3.5) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	_banner_time = secs


func show_warning(text: String, secs := 1.5) -> void:
	warn_label.text = text
	_warn_time = secs


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		if _banner_time <= 0.0:
			banner_label.text = ""
	if _warn_time > 0.0:
		_warn_time -= delta
		if _warn_time <= 0.0:
			warn_label.text = ""
