class_name Hud
extends CanvasLayer
## Race HUD (see UIStyle for the look):
##   top-left   timing tower: position, lap, the cars around you
##   top-right  camera / reset / pause, then the lap timing panel
##   right      live circuit map
##   bottom     rev gauge with shift lights, gear and speed; pedals
## plus start lights, banners, the pause menu and the classification.

signal restart_requested
signal reset_requested
signal camera_requested
signal settings_changed
signal menu_requested

var touch: TouchControls
var gauge: RevGauge
var minimap: MiniMap
var center_label: Label
var banner: PanelContainer
var banner_label: Label
var warn: PanelContainer
var warn_label: Label
var pause_panel: Control
var results_panel: Control
var cam_button: Button
var _menu_buttons := {}

# Timing tower
var _tower: VBoxContainer
var _pos_big: Label
var _pos_of: Label
var _lap_lbl: Label
var _rows_box: VBoxContainer
# Lap timing panel
var _time_lbl: Label
var _last_val: Label
var _best_val: Label
var _delta_lbl: Label
# Start lights
var lights_box: PanelContainer
var lights: Array[Panel] = []

var _race_mode := false
var _last_valid := true
var _total_laps := 0
var _best_seen := -1.0
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

	_build_tower(root)
	_build_timing(root)
	_build_gauge(root)
	_build_minimap(root)
	_build_messages(root)
	_build_lights(root)
	_build_pause_menu(root)
	_build_results(root)
	set_paused(false)


# ------------------------------------------------------------ layout

func _build_tower(root: Control) -> void:
	_tower = VBoxContainer.new()
	_tower.position = Vector2(18, 14)
	_tower.add_theme_constant_override("separation", 3)
	_tower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tower)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.86), true, UIStyle.APEX))
	head.custom_minimum_size = Vector2(236, 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tower.add_child(head)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	head.add_child(h)
	_pos_big = UIStyle.label("P1", 44, UIStyle.PAPER, "extrabold", true)
	h.add_child(_pos_big)
	_pos_of = UIStyle.label("/20", 22, UIStyle.FOG, "bold", true)
	_pos_of.size_flags_vertical = Control.SIZE_SHRINK_END
	_pos_of.custom_minimum_size = Vector2(0, 40)
	h.add_child(_pos_of)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_lap_lbl = UIStyle.label("Lap 1", 24, UIStyle.PAPER, "bold", true)
	_lap_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lap_lbl.size_flags_vertical = Control.SIZE_FILL
	h.add_child(_lap_lbl)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tower.add_child(_rows_box)


func _build_timing(root: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.offset_right = -16
	col.offset_top = 12
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	col.add_child(bar)
	cam_button = UIStyle.button("Chase", func(): camera_requested.emit(), false, 22)
	cam_button.custom_minimum_size = Vector2(118, 60)
	bar.add_child(cam_button)
	var rb := UIStyle.button("Reset", func(): reset_requested.emit(), false, 22)
	rb.custom_minimum_size = Vector2(104, 60)
	bar.add_child(rb)
	var pb := UIStyle.button("II", func(): set_paused(true), false, 24)
	pb.custom_minimum_size = Vector2(70, 60)
	bar.add_child(pb)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.8)))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.custom_minimum_size = Vector2(236, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	panel.add_child(v)
	_time_lbl = UIStyle.label("0:00.000", 40, UIStyle.PAPER, "extrabold", true)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_time_lbl)
	_last_val = _timing_row(v, "Last")
	_best_val = _timing_row(v, "Best")
	_delta_lbl = UIStyle.label("", 22, UIStyle.GREEN, "bold", true)
	_delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_delta_lbl.visible = false
	v.add_child(_delta_lbl)


func _timing_row(parent: Node, name: String) -> Label:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var n := UIStyle.label(name, 20, UIStyle.FOG, "semibold")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var val := UIStyle.label("-:--.---", 22, UIStyle.PAPER, "bold", true)
	h.add_child(val)
	return val


func _build_gauge(root: Control) -> void:
	gauge = RevGauge.new()
	gauge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	gauge.custom_minimum_size = Vector2(300, 176)
	gauge.size = Vector2(300, 176)
	gauge.offset_left = -150
	gauge.offset_right = 150
	gauge.offset_top = -194
	gauge.offset_bottom = -18
	root.add_child(gauge)


func _build_minimap(root: Control) -> void:
	minimap = MiniMap.new()
	minimap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	minimap.offset_right = -16
	minimap.offset_left = -196
	minimap.offset_top = -110
	minimap.offset_bottom = 70
	root.add_child(minimap)


func _build_messages(root: Control) -> void:
	center_label = UIStyle.outlined(UIStyle.label("", 132, UIStyle.PAPER, "extrabold", true), 10)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(center_label)

	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.9), true, UIStyle.APEX))
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.offset_top = 124
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	root.add_child(banner)
	banner_label = UIStyle.label("", 34, UIStyle.PAPER, "bold", true)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)

	warn = PanelContainer.new()
	warn.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.9), true, UIStyle.YELLOW))
	warn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	warn.offset_top = 190
	warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warn.visible = false
	root.add_child(warn)
	warn_label = UIStyle.label("", 24, UIStyle.YELLOW, "bold", true)
	warn.add_child(warn_label)


func _build_lights(root: Control) -> void:
	lights_box = PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.INK, 0.9), false, Color(0, 0, 0, 0), 12)
	sb.set_content_margin_all(14)
	lights_box.add_theme_stylebox_override("panel", sb)
	lights_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lights_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lights_box.offset_top = 30
	lights_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lights_box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	lights_box.add_child(h)
	for i in range(5):
		var pod := VBoxContainer.new()
		pod.add_theme_constant_override("separation", 8)
		h.add_child(pod)
		for k in range(2):
			var lamp := Panel.new()
			lamp.custom_minimum_size = Vector2(46, 46)
			lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pod.add_child(lamp)
			lights.append(lamp)
	lights_box.visible = false


# ------------------------------------------------------------ pause menu

func _build_pause_menu(root: Control) -> void:
	pause_panel = ColorRect.new()
	(pause_panel as ColorRect).color = Color(UIStyle.INK, 0.6)
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause_panel)
	var frame := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.97), false, UIStyle.APEX, 6)
	sb.set_content_margin_all(26)
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60
	frame.offset_right = -60
	frame.offset_top = 40
	frame.offset_bottom = -40
	pause_panel.add_child(frame)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	frame.add_child(cols)

	# Left: what to do next.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	left.add_child(UIStyle.label("Paused", 54, UIStyle.PAPER, "extrabold", true))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	left.add_child(gap)
	_menu_buttons["resume"] = _menu_button(left, "Resume", func(): set_paused(false), true)
	_menu_buttons["restart"] = _menu_button(left, "Restart", func():
		set_paused(false)
		restart_requested.emit())
	_menu_buttons["reset"] = _menu_button(left, "Put car back on track", func():
		set_paused(false)
		reset_requested.emit())
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	_menu_buttons["quit"] = _menu_button(left, "Quit to menu", func(): menu_requested.emit())

	# Right: driving settings, as rows of setting + value.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UIStyle.label("Driving", 30, UIStyle.FOG, "bold", true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 24       # a slightly moving tap still presses a button
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	_setting(v, "controls", "Steering", func():
		save.set_setting("control_mode", "buttons" if save.get_setting("control_mode") == "tilt" else "tilt"))
	_setting(v, "sens", "Tilt sensitivity", func():
		var steps := [0.6, 0.8, 1.0, 1.3, 1.6, 2.0]
		var cur := float(save.get_setting("tilt_sensitivity"))
		var nxt: float = steps[0]
		for s in steps:
			if s > cur + 0.01:
				nxt = s
				break
		save.set_setting("tilt_sensitivity", nxt))
	_setting(v, "invert", "Invert tilt", func(): _toggle("invert_tilt"))
	_setting(v, "auto", "Auto-accelerate", func(): _toggle("auto_accelerate"))
	_setting(v, "steer_assist", "Steering assist", func(): _toggle("steer_assist"))
	_setting(v, "brake_assist", "Brake assist", func(): _toggle("brake_assist"))
	_setting(v, "tc", "Traction control", func(): _toggle("traction_control"))
	_setting(v, "abs", "ABS", func(): _toggle("abs"))
	_setting(v, "line", "Racing line", func(): _toggle("racing_line"))
	_setting(v, "graphics", "Graphics", func():
		save.set_setting("graphics", "saver" if save.get_setting("graphics") != "saver" else "high"))
	_refresh_menu()


func _menu_button(parent: Node, text: String, cb: Callable, primary := false) -> Button:
	var b := UIStyle.button(text, cb, primary, 28)
	b.custom_minimum_size = Vector2(0, 68)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(b)
	return b


func _toggle(key: String) -> void:
	save.set_setting(key, not bool(save.get_setting(key)))


## A settings row: name on the left, current value on the right; tap to change.
func _setting(parent: Node, key: String, text: String, change: Callable) -> void:
	var b := UIStyle.button("", func():
		change.call()
		_refresh_menu(), false, 24)
	b.custom_minimum_size = Vector2(0, 62)
	parent.add_child(b)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 26
	h.offset_right = -26
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var name := UIStyle.label(text, 24, UIStyle.PAPER, "semibold")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.size_flags_vertical = Control.SIZE_FILL
	h.add_child(name)
	var val := UIStyle.label("", 24, UIStyle.APEX, "bold", true)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.size_flags_vertical = Control.SIZE_FILL
	h.add_child(val)
	_menu_buttons[key] = val


func _refresh_menu() -> void:
	var on_off := func(k: String) -> String: return "On" if bool(save.get_setting(k)) else "Off"
	var tilt: bool = save.get_setting("control_mode") == "tilt"
	(_menu_buttons["controls"] as Label).text = "Tilt phone" if tilt else "Buttons"
	(_menu_buttons["sens"] as Label).text = "%.1fx" % float(save.get_setting("tilt_sensitivity"))
	(_menu_buttons["invert"] as Label).text = on_off.call("invert_tilt")
	(_menu_buttons["auto"] as Label).text = on_off.call("auto_accelerate")
	(_menu_buttons["steer_assist"] as Label).text = on_off.call("steer_assist")
	(_menu_buttons["brake_assist"] as Label).text = on_off.call("brake_assist")
	(_menu_buttons["tc"] as Label).text = on_off.call("traction_control")
	(_menu_buttons["abs"] as Label).text = on_off.call("abs")
	(_menu_buttons["line"] as Label).text = on_off.call("racing_line")
	(_menu_buttons["graphics"] as Label).text = "Battery saver" if save.get_setting("graphics") == "saver" else "High"
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


# ------------------------------------------------------------ live display

static func fmt_time(seconds: float) -> String:
	return UIStyle.fmt_time(seconds)


func set_camera_name(n: String) -> void:
	cam_button.text = n


func update_timing(lap: int, lap_time: float, last: float, best: float, valid: bool) -> void:
	_lap_lbl.text = ("Lap %d/%d" % [maxi(lap, 1), _total_laps]) if _race_mode else ("Lap %d" % maxi(lap, 1))
	_time_lbl.text = fmt_time(lap_time)
	if valid != _last_valid:
		_last_valid = valid
		_time_lbl.add_theme_color_override("font_color", UIStyle.PAPER if valid else UIStyle.RED)
	_last_val.text = fmt_time(last)
	_best_val.text = fmt_time(best)
	if best > 0.0 and absf(best - _best_seen) > 0.0005:
		_best_seen = best
		_best_val.add_theme_color_override("font_color", UIStyle.PURPLE)
	if last > 0.0 and best > 0.0:
		var d := last - best
		_delta_lbl.visible = true
		_delta_lbl.text = ("%+.3f" % d) if d > 0.0005 else "Best lap"
		_delta_lbl.add_theme_color_override("font_color", UIStyle.YELLOW if d > 0.0005 else UIStyle.PURPLE)


func update_engine(gear: int, rpm: float, shift_rpm: float, redline: float, idle := 1000.0, kmh := -1.0) -> void:
	gauge.set_engine(gear, rpm, shift_rpm, redline, idle, kmh if kmh >= 0.0 else float(gauge.speed))


func update_speed(kmh: float) -> void:
	gauge.speed = int(round(kmh))
	gauge.queue_redraw()


func set_race_mode(race: bool, laps: int) -> void:
	_race_mode = race
	_total_laps = laps
	_rows_box.visible = race
	_pos_big.visible = race
	_pos_of.visible = race
	if not race:
		_lap_lbl.add_theme_font_size_override("font_size", 30)


func set_track(points: PackedVector3Array) -> void:
	minimap.set_points(points)


func update_map(cars: Array) -> void:
	minimap.set_cars(cars)


func show_lights(lit: int, out: bool) -> void:
	lights_box.visible = not out
	for i in range(lights.size()):
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(23)
		var on := (i / 2) < lit
		sb.bg_color = UIStyle.RED if on else Color(0.16, 0.04, 0.04)
		if on:
			sb.shadow_color = Color(UIStyle.RED, 0.6)
			sb.shadow_size = 10
		lights[i].add_theme_stylebox_override("panel", sb)


## rows: [{pos, name, gap, player, color}] for the cars to show.
func update_position(pos: int, total: int, rows: Array) -> void:
	_pos_big.text = "P%d" % pos
	_pos_of.text = "/%d" % total
	for c in _rows_box.get_children():
		c.queue_free()
	var last := 0
	for r in rows:
		if int(r["pos"]) > last + 1:
			var dots := UIStyle.outlined(UIStyle.label("·  ·  ·", 14, UIStyle.FOG, "bold"), 3)
			dots.custom_minimum_size = Vector2(236, 12)
			dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_rows_box.add_child(dots)
		last = int(r["pos"])
		_rows_box.add_child(_tower_row(r))


func _tower_row(r: Dictionary) -> Control:
	var me: bool = r["player"]
	var row := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.APEX, 0.95) if me else Color(UIStyle.TARMAC, 0.8))
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	sb.content_margin_left = 8
	row.add_theme_stylebox_override("panel", sb)
	row.custom_minimum_size = Vector2(236, 32)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	var ink := UIStyle.INK if me else UIStyle.PAPER
	var p := UIStyle.label(str(r["pos"]), 21, ink, "extrabold", true)
	p.custom_minimum_size = Vector2(26, 0)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(p)
	var bar := ColorRect.new()
	bar.color = r.get("color", UIStyle.FOG)
	bar.custom_minimum_size = Vector2(5, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var name := UIStyle.label("YOU" if me else UIStyle.code(String(r["name"])), 21, ink, "bold")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	var gap := UIStyle.label(String(r["gap"]) if r["gap"] != "" else "Leader", 19, Color(ink, 0.8) if me else UIStyle.FOG, "semibold", true)
	h.add_child(gap)
	return row


# ------------------------------------------------------------ messages

func show_center(text: String) -> void:
	center_label.text = text


func show_banner(text: String, color: Color, secs := 3.5) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	(banner.get_theme_stylebox("panel") as StyleBoxFlat).border_color = color
	banner.visible = text != ""
	banner.reset_size()
	banner.offset_left = -banner.size.x * 0.5
	banner.offset_right = banner.size.x * 0.5
	_banner_time = secs


func show_warning(text: String, secs := 1.5) -> void:
	warn_label.text = text
	warn.visible = text != ""
	warn.reset_size()
	warn.offset_left = -warn.size.x * 0.5
	warn.offset_right = warn.size.x * 0.5
	_warn_time = secs


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		if _banner_time <= 0.0:
			banner.visible = false
	if _warn_time > 0.0:
		_warn_time -= delta
		if _warn_time <= 0.0:
			warn.visible = false


# ------------------------------------------------------------ classification

func _build_results(root: Control) -> void:
	results_panel = ColorRect.new()
	(results_panel as ColorRect).color = Color(UIStyle.INK, 0.97)
	results_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_panel.visible = false
	results_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(results_panel)


func hide_results() -> void:
	results_panel.visible = false
	_set_live_visible(true)


func _set_live_visible(on: bool) -> void:
	_tower.visible = on
	gauge.visible = on
	minimap.visible = on
	_time_lbl.get_parent().get_parent().get_parent().visible = on


## rows: [{pos, name, team, gap, best, player, color, fastest}]
func show_results(rows: Array, on_restart: Callable, on_menu: Callable) -> void:
	for c in results_panel.get_children():
		c.queue_free()
	touch.release_all()
	touch.visible = false
	_set_live_visible(false)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28 if side != "left" else 44)
	results_panel.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	margin.add_child(cols)

	# Left: your result, and what next.
	var me := {}
	for r in rows:
		if r["player"]:
			me = r
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 0)
	cols.add_child(left)
	left.add_child(UIStyle.label("You finished", 30, UIStyle.FOG, "bold", true))
	var big := UIStyle.label("P%d" % int(me.get("pos", 0)), 150, UIStyle.APEX if int(me.get("pos", 99)) <= 3 else UIStyle.PAPER, "extrabold", true)
	left.add_child(big)
	left.add_child(UIStyle.label("of %d" % rows.size(), 30, UIStyle.FOG, "bold", true))
	if me.get("best", "-") != "-":
		var bl := UIStyle.label("Best lap %s" % me["best"], 26, UIStyle.PURPLE if me.get("fastest", false) else UIStyle.PAPER, "bold", true)
		bl.custom_minimum_size = Vector2(0, 54)
		bl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		left.add_child(bl)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	var again := UIStyle.button("Race again", func():
		touch.visible = true
		_set_live_visible(true)
		on_restart.call(), true, 30)
	again.custom_minimum_size = Vector2(0, 74)
	left.add_child(again)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	left.add_child(gap)
	var menu := UIStyle.button("Main menu", func(): on_menu.call(), false, 26)
	menu.custom_minimum_size = Vector2(0, 64)
	left.add_child(menu)

	# Right: the classification.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(UIStyle.label("Classification", 36, UIStyle.PAPER, "extrabold", true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for r in rows:
		list.add_child(_result_row(r))
	results_panel.visible = true


func _result_row(r: Dictionary) -> Control:
	var mine: bool = r["player"]
	var row := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.APEX, 0.95) if mine else Color(UIStyle.TARMAC_2, 0.95))
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", sb)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var ink := UIStyle.INK if mine else UIStyle.PAPER
	var p := UIStyle.label(str(r["pos"]), 26, ink, "extrabold", true)
	p.custom_minimum_size = Vector2(34, 0)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(p)
	var bar := ColorRect.new()
	bar.color = r.get("color", UIStyle.FOG)
	bar.custom_minimum_size = Vector2(6, 26)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var name := UIStyle.label("You" if mine else String(r["name"]), 24, ink, "bold")
	name.custom_minimum_size = Vector2(170, 0)
	h.add_child(name)
	var team := UIStyle.label(String(r["team"]), 20, Color(ink, 0.75) if mine else UIStyle.FOG, "semibold")
	team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team.clip_text = true
	h.add_child(team)
	var gap := UIStyle.label(String(r["gap"]), 22, ink, "bold", true)
	gap.custom_minimum_size = Vector2(118, 0)
	gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(gap)
	var best_col := UIStyle.PURPLE if r.get("fastest", false) else (Color(ink, 0.75) if mine else UIStyle.FOG)
	var best := UIStyle.label(String(r["best"]), 20, best_col, "semibold", true)
	best.custom_minimum_size = Vector2(96, 0)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(best)
	return row
