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
signal chat_requested(index: int)
signal replay_requested
signal box_requested
var replay_button: Button             # on the results screen
var replay_available := true:          # pause menu "Watch replay" (single player)
	set(v):
		replay_available = v
		if _menu_buttons.has("replay"):
			_menu_buttons["replay"].visible = v

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
var _sector_bars: Array[ColorRect] = []
var _mini_rects: Array[ColorRect] = []
var _mini_cols: Array[Color] = []
var _mini_cur := 0
var _mini_lbl: Label
var _mini_time := 0.0
var _ideal_val: Label
var _pulse := 0.0
var _timing_panel: PanelContainer
# Multiplayer quick chat
var _chat_btn: Button
var _chat_row: HBoxContainer
var _chat_toast: PanelContainer
var _chat_toast_lbl: Label
var _chat_time := 0.0
var _chat_open_time := 0.0
const MINI_IDLE := Color(0.945, 0.953, 0.965, 0.13)
var _drs: PanelContainer
var _drs_lbl: Label
var _drs_state := -1
var _delta_time := 0.0
# Start lights
var lights_box: PanelContainer
var lights: Array[Panel] = []

var _race_mode := false
var net_mode := false:                 # multiplayer: the game never pauses
	set(v):
		net_mode = v
		if _menu_buttons.has("restart"):
			(_menu_buttons["restart"] as Button).visible = not v
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
	_build_drs(root)
	_build_tow(root)
	_build_tyres(root)
	_build_action(root)
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
	_chat_btn = UIStyle.button("Chat", func(): _toggle_chat(), false, 22)
	_chat_btn.custom_minimum_size = Vector2(100, 60)
	_chat_btn.visible = false
	bar.add_child(_chat_btn)
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
	_timing_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	panel.add_child(v)
	_time_lbl = UIStyle.label("0:00.000", 40, UIStyle.PAPER, "extrabold", true)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_time_lbl)
	_last_val = _timing_row(v, "Last")
	_best_val = _timing_row(v, "Best")
	_ideal_val = _timing_row(v, "Ideal")
	_ideal_val.get_parent().visible = false
	# Per sector: a strip of 8 minisectors over the sector bar. Grey until
	# driven, then purple / green / yellow; the one being driven pulses.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	var sec := HBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	v.add_child(sec)
	for k in range(3):
		var col_box := VBoxContainer.new()
		col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_box.add_theme_constant_override("separation", 3)
		sec.add_child(col_box)
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 2)
		col_box.add_child(strip)
		for m in range(8):
			var r := ColorRect.new()
			r.color = MINI_IDLE
			r.custom_minimum_size = Vector2(0, 10)
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strip.add_child(r)
			_mini_rects.append(r)
			_mini_cols.append(MINI_IDLE)
		var b := ColorRect.new()
		b.color = Color(UIStyle.PAPER, 0.15)
		b.custom_minimum_size = Vector2(0, 5)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col_box.add_child(b)
		_sector_bars.append(b)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap2)
	_mini_lbl = UIStyle.label("Mini 1  0.000", 19, UIStyle.PAPER, "semibold", true)
	_mini_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mini_lbl.modulate.a = 0.0
	v.add_child(_mini_lbl)
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


func _build_drs(root: Control) -> void:
	_drs = PanelContainer.new()
	_drs.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_drs.offset_left = -262
	_drs.offset_right = -170
	_drs.offset_top = -74
	_drs.offset_bottom = -30
	_drs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drs.visible = false
	root.add_child(_drs)
	_drs_lbl = UIStyle.label("DRS", 26, UIStyle.FOG, "extrabold", true)
	_drs_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drs.add_child(_drs_lbl)


var _tow: PanelContainer
var _tow_bar: ColorRect

## Slipstream: a pill that fills as the tow gets stronger.
func _build_tow(root: Control) -> void:
	_tow = PanelContainer.new()
	_tow.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tow.offset_left = -440
	_tow.offset_right = -276
	_tow.offset_top = -74
	_tow.offset_bottom = -30
	_tow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tow.visible = false
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.75))
	sb.border_color = Color("5ec8ff")
	sb.set_border_width_all(3)
	_tow.add_theme_stylebox_override("panel", sb)
	root.add_child(_tow)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 32)
	_tow.add_child(stack)
	_tow_bar = ColorRect.new()
	_tow_bar.color = Color("5ec8ff", 0.45)
	_tow_bar.position = Vector2(-8, -2)
	_tow_bar.size = Vector2(0, 36)
	stack.add_child(_tow_bar)
	var l := UIStyle.label("SLIPSTREAM", 24, Color("5ec8ff"), "extrabold", true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(l)


# ------------------------------------------------------------ tyres and pits

var _tyre_btn: Button
var _tyre_badge: TyreBadge
var _tyre_lbl: Label
var _tyre_bar: ColorRect

## Tyre panel, right of the rev gauge: compound, wear, and BOX (tap).
func _build_tyres(root: Control) -> void:
	_tyre_btn = Button.new()
	_tyre_btn.focus_mode = Control.FOCUS_NONE
	_tyre_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tyre_btn.offset_left = 172
	_tyre_btn.offset_right = 352
	_tyre_btn.offset_top = -96
	_tyre_btn.offset_bottom = -26
	_tyre_btn.visible = false
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.75))
	for st in ["normal", "hover", "pressed", "focus"]:
		_tyre_btn.add_theme_stylebox_override(st, sb)
	_tyre_btn.pressed.connect(func(): box_requested.emit())
	root.add_child(_tyre_btn)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -10
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tyre_btn.add_child(h)
	_tyre_badge = TyreBadge.new()
	_tyre_badge.custom_minimum_size = Vector2(46, 46)
	_tyre_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_tyre_badge)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_tyre_lbl = UIStyle.label("", 20, UIStyle.PAPER, "extrabold", true)
	v.add_child(_tyre_lbl)
	var back := ColorRect.new()
	back.color = Color(UIStyle.PAPER, 0.15)
	back.custom_minimum_size = Vector2(0, 7)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(back)
	_tyre_bar = ColorRect.new()
	_tyre_bar.size = Vector2(0, 7)
	_tyre_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(_tyre_bar)


func set_tyres(compound: String, wear: float, box: bool, next: String, pitting: bool) -> void:
	if _tyre_btn == null:
		return
	_tyre_btn.visible = gauge.visible
	_tyre_badge.compound = compound
	var left := 1.0 - clampf(wear, 0.0, 1.0)
	if pitting:
		_tyre_lbl.text = "PIT LANE"
	elif box:
		_tyre_lbl.text = "BOX > " + String(Tyres.LETTER.get(next, "M"))
	else:
		_tyre_lbl.text = "%d%%  BOX?" % int(round(left * 100.0)) if wear > 0.7 else "%d%%" % int(round(left * 100.0))
	_tyre_lbl.add_theme_color_override("font_color", UIStyle.YELLOW if box or pitting else (UIStyle.RED if wear > 0.8 else UIStyle.PAPER))
	_tyre_bar.size.x = (_tyre_bar.get_parent() as Control).size.x * left
	_tyre_bar.color = UIStyle.GREEN if wear < 0.6 else (UIStyle.YELLOW if wear < 0.8 else UIStyle.RED)
	var sb := _tyre_btn.get_theme_stylebox("normal") as StyleBoxFlat
	sb.border_color = UIStyle.YELLOW
	sb.set_border_width_all(3 if box else 0)


## A tyre: dark rubber ring with the compound's coloured band and letter.
class TyreBadge extends Control:
	var compound := "medium":
		set(v):
			if v != compound:
				compound = v
				queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0.08, 0.08, 0.09))
		draw_arc(c, r * 0.72, 0, TAU, 40, Tyres.COLOR.get(compound, Color.WHITE), r * 0.16, true)
		var f := UIStyle.font("extrabold", false)
		var fs := int(r * 0.9)
		var t := String(Tyres.LETTER.get(compound, "M"))
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


# ------------------------------------------------------------ action button

var _action: Button

func _build_action(root: Control) -> void:
	_action = UIStyle.button("", Callable(), false, 24)
	_action.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_action.offset_left = -150
	_action.offset_right = 150
	_action.offset_top = 150
	_action.offset_bottom = 212
	_action.visible = false
	root.add_child(_action)


## A single button under the banner (e.g. "Skip qualifying").
func show_action(text: String, cb: Callable) -> void:
	for c in _action.pressed.get_connections():
		_action.pressed.disconnect(c["callable"])
	_action.text = text
	_action.pressed.connect(cb)
	_action.visible = true


func hide_action() -> void:
	_action.visible = false


## Qualifying classification, your tyre choice for the race, and Start.
func show_quali(rows: Array, compound: String, weather: String, on_start: Callable) -> void:
	for c in results_panel.get_children():
		c.queue_free()
	touch.release_all()
	touch.visible = false
	_set_live_visible(false)
	var chosen := [compound]
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28 if side != "left" else 44)
	results_panel.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	margin.add_child(cols)
	var me := {}
	for r in rows:
		if r["player"]:
			me = r
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	left.add_child(UIStyle.label("Qualifying", 30, UIStyle.FOG, "bold", true))
	left.add_child(UIStyle.label("P%d" % int(me.get("pos", 0)), 120, UIStyle.APEX if int(me.get("pos", 99)) <= 3 else UIStyle.PAPER, "extrabold", true))
	left.add_child(UIStyle.label(String(me.get("time", "")) + ("   pole!" if int(me.get("pos", 0)) == 1 else ""), 30, UIStyle.PURPLE if int(me.get("pos", 0)) == 1 else UIStyle.PAPER, "bold", true))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	var wl := {"dry": "Dry race", "wet": "Wet race: wets are fitted", "changing": "Rain expected during the race"}
	left.add_child(UIStyle.label("Race tyres  ·  " + String(wl.get(weather, "")), 20, UIStyle.FOG, "bold", true))
	var tyres := HBoxContainer.new()
	tyres.add_theme_constant_override("separation", 8)
	left.add_child(tyres)
	var btns := {}
	var paint := func():
		for k in btns:
			var b: Button = btns[k]
			var sb := UIStyle.panel(Color(UIStyle.TARMAC_2, 0.95) if k != chosen[0] else Color(Tyres.COLOR[k], 0.9))
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, sb)
			b.add_theme_color_override("font_color", UIStyle.INK if k == chosen[0] else UIStyle.PAPER)
			b.add_theme_color_override("font_hover_color", UIStyle.INK if k == chosen[0] else UIStyle.PAPER)
	for k in Tyres.COMPOUNDS:
		var b := UIStyle.button(String(Tyres.NAMES[k]), func():
			chosen[0] = k
			paint.call(), false, 22)
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tyres.add_child(b)
		btns[k] = b
	paint.call()
	var go := UIStyle.button("Start the race", func():
		results_panel.visible = false
		touch.visible = true
		_set_live_visible(true)
		on_start.call(chosen[0]), true, 34)
	go.custom_minimum_size = Vector2(0, 80)
	left.add_child(go)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(UIStyle.label("Starting grid", 36, UIStyle.PAPER, "extrabold", true))
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
		var rr: Dictionary = r.duplicate()
		rr["best"] = r["time"]
		rr["fastest"] = int(r["pos"]) == 1
		list.add_child(_result_row(rr))
	results_panel.visible = true


func set_tow(t: float) -> void:
	if _tow == null:
		return
	var on := t > 0.12 and gauge.visible
	_tow.visible = on
	if on:
		_tow_bar.size.x = (_tow.size.x - 12.0) * clampf(t, 0.0, 1.0)


## 0 hidden, 1 not available, 2 available (opens on the next straight), 3 open.
func set_drs(st: int) -> void:
	if st == _drs_state:
		return
	_drs_state = st
	_drs.visible = st > 0
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.75))
	sb.set_border_width_all(0)
	match st:
		2:
			sb.border_color = UIStyle.GREEN
			sb.set_border_width_all(3)
			_drs_lbl.add_theme_color_override("font_color", UIStyle.GREEN)
		3:
			sb.bg_color = UIStyle.GREEN
			_drs_lbl.add_theme_color_override("font_color", UIStyle.INK)
		_:
			_drs_lbl.add_theme_color_override("font_color", Color(UIStyle.FOG, 0.7))
	_drs.add_theme_stylebox_override("panel", sb)


func _build_minimap(root: Control) -> void:
	minimap = MiniMap.new()
	# Beside the timing panel (placed each frame in _place_minimap), so the
	# panel can grow without covering it.
	minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	minimap.size = Vector2(180, 180)
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
	banner.offset_top = 176
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
	warn.offset_top = 240
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
	_menu_buttons["replay"] = _menu_button(left, "Watch replay", func(): replay_requested.emit())
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
		var order := ["tilt", "drag", "buttons"]
		var i := order.find(String(save.get_setting("control_mode")))
		save.set_setting("control_mode", order[(i + 1) % order.size()]))
	_setting(v, "sens", "Steering sensitivity", func():
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
	_setting(v, "steer_assist", "Steering assist", func(): _cycle_level("steer_assist"))
	_setting(v, "brake_assist", "Brake assist", func(): _cycle_level("brake_assist"))
	_setting(v, "tc", "Traction control", func(): _toggle("traction_control"))
	_setting(v, "abs", "ABS", func(): _toggle("abs"))
	_setting(v, "line", "Racing line", func(): _toggle("racing_line"))
	_setting(v, "ghost", "Ghost car (time trial)", func(): _toggle("ghost"))
	_setting(v, "graphics", "Graphics", func():
		save.set_setting("graphics", "saver" if save.get_setting("graphics") != "saver" else "high"))
	_refresh_menu()


func _menu_button(parent: Node, text: String, cb: Callable, primary := false) -> Button:
	var b := UIStyle.button(text, cb, primary, 28)
	b.custom_minimum_size = Vector2(0, 68)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(b)
	return b


## Off -> Moderate -> Full -> Off.
func _cycle_level(key: String) -> void:
	var order := ["off", "moderate", "full"]
	var cur: float = save.assist_level(key)
	var i := 0 if cur <= 0.0 else (1 if cur < 1.0 else 2)
	save.set_setting(key, order[(i + 1) % 3])


func _level_name(key: String) -> String:
	var cur: float = save.assist_level(key)
	return "Off" if cur <= 0.0 else ("Moderate" if cur < 1.0 else "Full")


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
	var control := String(save.get_setting("control_mode"))
	(_menu_buttons["controls"] as Label).text = {"tilt": "Tilt phone", "drag": "Wheel (left thumb)", "buttons": "Buttons"}.get(control, "Tilt phone")
	(_menu_buttons["sens"] as Label).text = "%.1fx" % float(save.get_setting("tilt_sensitivity"))
	(_menu_buttons["invert"] as Label).text = on_off.call("invert_tilt")
	(_menu_buttons["auto"] as Label).text = on_off.call("auto_accelerate")
	(_menu_buttons["steer_assist"] as Label).text = _level_name("steer_assist")
	(_menu_buttons["brake_assist"] as Label).text = _level_name("brake_assist")
	(_menu_buttons["tc"] as Label).text = on_off.call("traction_control")
	(_menu_buttons["abs"] as Label).text = on_off.call("abs")
	(_menu_buttons["line"] as Label).text = on_off.call("racing_line")
	(_menu_buttons["ghost"] as Label).text = on_off.call("ghost")
	(_menu_buttons["graphics"] as Label).text = "Battery saver" if save.get_setting("graphics") == "saver" else "High"
	touch.configure(control, bool(save.get_setting("auto_accelerate")), float(save.get_setting("tilt_sensitivity")))
	settings_changed.emit()


func set_paused(p: bool) -> void:
	get_tree().paused = p and not net_mode
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


func show_sector(k: int, t: float, delta: float, colour: Color) -> void:
	if k == 0:
		for b in _sector_bars:
			b.color = Color(UIStyle.PAPER, 0.15)
	_sector_bars[k].color = colour
	_delta_lbl.visible = true
	var d := ("  %+.3f" % delta) if absf(delta) > 0.0005 else ""
	_delta_lbl.text = "Sector %d  %.3f%s" % [k + 1, t, d]
	_delta_lbl.add_theme_color_override("font_color", colour if colour != UIStyle.FOG else UIStyle.PAPER)
	_delta_time = 4.0


func reset_sectors() -> void:
	for b in _sector_bars:
		b.color = Color(UIStyle.PAPER, 0.15)
	for m in _mini_rects.size():
		_mini_cols[m] = MINI_IDLE
		_mini_rects[m].color = MINI_IDLE
	_mini_cur = 0
	_mini_lbl.modulate.a = 0.0
	minimap.clear_minis()


## Minisector m done in t seconds (t < 0: skipped). delta is vs your best.
func show_mini(m: int, t: float, delta: float, colour: Color) -> void:
	var count := _mini_rects.size()
	if m == 0:
		# A new lap: clear the old one except this first minisector.
		for i in count:
			_mini_cols[i] = MINI_IDLE
			_mini_rects[i].color = MINI_IDLE
		minimap.clear_minis()
	_mini_cols[m] = colour
	_mini_rects[m].color = colour
	minimap.set_mini(m, count, colour)
	_mini_cur = (m + 1) % count
	if t < 0.0:
		return
	var d := ("  %+.3f" % delta) if absf(delta) > 0.0005 else ""
	_mini_lbl.text = "Mini %d  %.3f%s" % [m + 1, t, d]
	_mini_lbl.add_theme_color_override("font_color", colour if colour != UIStyle.FOG else UIStyle.PAPER)
	_mini_lbl.modulate.a = 1.0
	_mini_time = 3.0


## Ideal lap (sum of your best minisectors), time trial only; t < 0 hides it.
func set_ideal(t: float) -> void:
	_ideal_val.get_parent().visible = t > 0.0
	_ideal_val.text = fmt_time(t)


## Results: rank points earned (with the breakdown) and progress to the next
## rank, animated from where you were; a banner when you move up.
func _rank_column(cols: Control, rank: Dictionary) -> void:
	var award: Dictionary = rank["award"]
	var before: int = rank["before"]
	var after: int = rank["after"]
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 2)
	cols.add_child(col)
	col.add_child(UIStyle.label("Rank points", 30, UIStyle.FOG, "bold", true))
	var gain := UIStyle.label("+0", 76, UIStyle.APEX, "extrabold", true)
	col.add_child(gain)
	for line in award["lines"]:
		var h := HBoxContainer.new()
		col.add_child(h)
		var n := UIStyle.label(String(line[0]), 20, UIStyle.FOG, "semibold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(UIStyle.label(String(line[1]), 20, UIStyle.PAPER, "bold", true))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	var promoted := Ranks.tier_index(after) > Ranks.tier_index(before) or Ranks.stars_of(after) > Ranks.stars_of(before)
	if promoted:
		var up := UIStyle.label("Promoted!", 30, Ranks.tier_color(after), "extrabold", true)
		col.add_child(up)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var badge := RankBadge.new()
	badge.custom_minimum_size = Vector2(72, 80)
	badge.rp = before
	row.add_child(badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	row.add_child(names)
	var tier := UIStyle.label(Ranks.tier_name(before), 30, Ranks.tier_color(before), "extrabold", true)
	names.add_child(tier)
	var total := UIStyle.label("%d RP" % before, 20, UIStyle.FOG, "bold", true)
	names.add_child(total)
	var bar := _rank_bar(col)
	var next := UIStyle.label("", 19, UIStyle.FOG, "semibold")
	col.add_child(next)
	var set_rp := func(v: float):
		var rp := int(round(v))
		var pr := Ranks.progress(rp)
		bar.size.x = bar.get_parent().size.x * clampf(float(pr.x) / maxf(pr.y, 1), 0.0, 1.0)
		bar.color = Ranks.tier_color(rp)
		gain.text = "+%d" % (rp - before)
		total.text = "%d RP" % rp
		tier.text = Ranks.tier_name(rp)
		tier.add_theme_color_override("font_color", Ranks.tier_color(rp))
		badge.rp = rp
		next.text = "%d RP to %s" % [pr.y - pr.x, Ranks.next_name(rp)]
	set_rp.call(float(before))
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.5)
	tw.tween_method(set_rp, float(before), float(after), 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Championship round: points scored, where that leaves you.
func _champ_column(cols: Control, reward: Dictionary, rank: Dictionary) -> void:
	var ev: Dictionary = reward["event"]
	var out: Dictionary = reward["champ"]
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 4)
	cols.add_child(col)
	col.add_child(UIStyle.label(String(ev.get("series_name", "Championship")), 22, UIStyle.FOG, "bold", true))
	col.add_child(UIStyle.label("Round %d of %d" % [int(ev["round"]) + 1, int(ev["rounds"])], 34, UIStyle.PAPER, "extrabold", true))
	col.add_child(UIStyle.label("+%d points" % int(out["gained"]), 64, UIStyle.APEX, "extrabold", true))
	var b := int(out["before"])
	var a := int(out["after"])
	var move := "" if a == b else ("  (up from P%d)" % b if a < b else "  (down from P%d)" % b)
	col.add_child(UIStyle.label("Championship: P%d%s" % [a, move], 24, UIStyle.GREEN if a < b else UIStyle.PAPER, "bold", true))
	if out.has("final"):
		var f: Dictionary = out["final"]
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 10)
		col.add_child(sp)
		col.add_child(UIStyle.label("CHAMPION!" if int(f["position"]) == 1 else "Season over: P%d" % int(f["position"]), 40, UIStyle.YELLOW, "extrabold", true))
		if int(f["prize"]) > 0:
			col.add_child(UIStyle.label("Prize: +" + UIStyle.money(int(f["prize"])), 24, UIStyle.GREEN, "bold", true))
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp2)
	if not rank.is_empty():
		col.add_child(UIStyle.label("+%d RP   %s" % [int(rank["after"]) - int(rank["before"]), Ranks.tier_name(int(rank["after"]))], 22, Ranks.tier_color(int(rank["after"])), "bold", true))


## Career event result: stars (new ones flash in), what they were for, the
## credits, and rank points.
func _reward_column(cols: Control, reward: Dictionary, rank: Dictionary) -> void:
	var ev: Dictionary = reward["event"]
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 4)
	cols.add_child(col)
	col.add_child(UIStyle.label(String(ev.get("series_name", "Career")), 22, UIStyle.FOG, "bold", true))
	col.add_child(UIStyle.label(Career.TYPE_NAMES.get(String(ev["type"]), "Race"), 34, UIStyle.PAPER, "extrabold", true))
	var stars := StarRow.new()
	stars.custom_minimum_size = Vector2(300, 84)
	stars.stars = int(reward["prev"])
	col.add_child(stars)
	var got := int(reward["stars"])
	var msg := ""
	if int(reward["new"]) > 0:
		msg = "%d new star%s!" % [int(reward["new"]), "" if int(reward["new"]) == 1 else "s"]
	elif got == 0:
		msg = "No stars this time"
	else:
		msg = "Matched your best"
	col.add_child(UIStyle.label(msg, 26, UIStyle.YELLOW if int(reward["new"]) > 0 else UIStyle.FOG, "bold", true))
	if String(ev["type"]) == "time_trial":
		var names := ["Gold", "Silver", "Bronze"]
		var tg: Array = reward["targets"]
		for k in mini(tg.size(), 3):
			var h := HBoxContainer.new()
			col.add_child(h)
			var n := UIStyle.label("%s  %d star%s" % [names[k], 3 - k, "" if k == 2 else "s"], 20, UIStyle.FOG, "semibold")
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(n)
			var beat: bool = float(reward["best"]) > 0.0 and float(reward["best"]) <= float(tg[k])
			h.add_child(UIStyle.label(UIStyle.fmt_time(float(tg[k])), 20, UIStyle.GREEN if beat else UIStyle.PAPER, "bold", true))
	else:
		col.add_child(UIStyle.label(String(Career.TYPE_RULES.get(String(ev["type"]), "")), 18, UIStyle.FOG, "medium"))
		(col.get_child(col.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	if not rank.is_empty():
		col.add_child(UIStyle.label("+%d RP   %s" % [int(rank["after"]) - int(rank["before"]), Ranks.tier_name(int(rank["after"]))], 22, Ranks.tier_color(int(rank["after"])), "bold", true))
	# New stars light up one by one.
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for s in range(int(reward["prev"]) + 1, got + 1):
		tw.tween_interval(0.45)
		tw.tween_callback(func(): stars.stars = s)


func _rank_bar(parent: Control) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(UIStyle.PAPER, 0.12)
	back.custom_minimum_size = Vector2(0, 12)
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.size = Vector2(0, 12)
	back.add_child(fill)
	return fill


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


## Multiplayer: show the Chat button; phrases go out through chat_requested.
func enable_chat(phrases: Array) -> void:
	_chat_btn.visible = true
	_chat_row = HBoxContainer.new()
	_chat_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_chat_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chat_row.offset_top = 84
	_chat_row.add_theme_constant_override("separation", 8)
	_chat_row.visible = false
	add_child(_chat_row)
	for i in phrases.size():
		var k: int = i
		var b := UIStyle.button(String(phrases[i]), func():
			chat_requested.emit(k)
			_chat_row.visible = false, false, 22)
		b.custom_minimum_size = Vector2(0, 58)
		_chat_row.add_child(b)
	_chat_toast = PanelContainer.new()
	_chat_toast.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.88)))
	_chat_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_chat_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chat_toast.offset_top = 14
	_chat_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_toast.visible = false
	add_child(_chat_toast)
	_chat_toast_lbl = UIStyle.label("", 24, UIStyle.PAPER, "bold", true)
	_chat_toast.add_child(_chat_toast_lbl)


func _toggle_chat() -> void:
	if _chat_row == null:
		return
	_chat_row.visible = not _chat_row.visible
	_chat_open_time = 5.0


func show_chat(who: String, text: String) -> void:
	if _chat_toast == null:
		return
	_chat_toast_lbl.text = "%s:  %s" % [who, text]
	_chat_toast.visible = true
	_chat_toast.reset_size()
	_chat_time = 3.5


func _place_minimap() -> void:
	if _timing_panel == null:
		return
	var r := _timing_panel.get_global_rect()
	minimap.position = Vector2(r.position.x - minimap.size.x - 18.0, r.position.y)


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
	_pulse += delta
	_place_minimap()
	if _chat_time > 0.0:
		_chat_time -= delta
		if _chat_time <= 0.0:
			_chat_toast.visible = false
	if _chat_row != null and _chat_row.visible:
		_chat_open_time -= delta
		if _chat_open_time <= 0.0:
			_chat_row.visible = false
	if _mini_cur < _mini_rects.size() and _mini_cols[_mini_cur] == MINI_IDLE:
		_mini_rects[_mini_cur].color = Color(UIStyle.PAPER, 0.3 + 0.25 * sin(_pulse * 6.0))
	if _mini_time > 0.0:
		_mini_time -= delta
		if _mini_time <= 0.0:
			_mini_lbl.modulate.a = 0.0
	if _delta_time > 0.0:
		_delta_time -= delta
		if _delta_time <= 0.0:
			_delta_lbl.visible = false
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
	_drs.visible = on and _drs_state > 0
	gauge.visible = on
	minimap.visible = on
	_time_lbl.get_parent().get_parent().get_parent().visible = on


## rows: [{pos, name, team, gap, best, player, color, fastest}]
func show_results(rows: Array, on_restart: Callable, on_menu: Callable, again_text := "Race again", rank: Dictionary = {}, on_replay: Callable = Callable(), reward: Dictionary = {}) -> void:
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
	var tt: bool = reward.has("event") and reward["event"]["type"] == "time_trial"
	if tt:
		left.add_child(UIStyle.label("Best lap", 30, UIStyle.FOG, "bold", true))
		var bt := UIStyle.label(String(me.get("best", "-")), 72, UIStyle.PAPER, "extrabold", true)
		bt.custom_minimum_size = Vector2(0, 150)
		bt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		left.add_child(bt)
	else:
		left.add_child(UIStyle.label("You finished", 30, UIStyle.FOG, "bold", true))
		var big := UIStyle.label("P%d" % int(me.get("pos", 0)), 150, UIStyle.APEX if int(me.get("pos", 99)) <= 3 else UIStyle.PAPER, "extrabold", true)
		left.add_child(big)
		left.add_child(UIStyle.label("of %d" % rows.size(), 30, UIStyle.FOG, "bold", true))
	if int(reward.get("credits", 0)) > 0:
		left.add_child(UIStyle.label("+" + UIStyle.money(int(reward["credits"])), 30, UIStyle.GREEN, "extrabold", true))
	if me.get("best", "-") != "-" and not tt:
		var bl := UIStyle.label("Best lap %s" % me["best"], 26, UIStyle.PURPLE if me.get("fastest", false) else UIStyle.PAPER, "bold", true)
		bl.custom_minimum_size = Vector2(0, 54)
		bl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		left.add_child(bl)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	if on_restart.is_valid():
		var again := UIStyle.button(again_text, func():
			touch.visible = true
			_set_live_visible(true)
			on_restart.call(), true, 30)
		again.custom_minimum_size = Vector2(0, 74)
		left.add_child(again)
	else:
		var wait := UIStyle.label("The host starts the next race", 22, UIStyle.FOG, "semibold")
		wait.custom_minimum_size = Vector2(0, 74)
		wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		left.add_child(wait)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	left.add_child(gap)
	var lower := HBoxContainer.new()
	lower.add_theme_constant_override("separation", 12)
	left.add_child(lower)
	replay_button = null
	if on_replay.is_valid():
		var rp := UIStyle.button("Replay", func(): on_replay.call(), false, 26)
		rp.custom_minimum_size = Vector2(0, 64)
		rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rp.add_theme_color_override("font_disabled_color", Color(UIStyle.FOG, 0.5))
		rp.add_theme_stylebox_override("disabled", UIStyle.panel(Color(UIStyle.TARMAC, 0.5)))
		lower.add_child(rp)
		replay_button = rp
	var menu := UIStyle.button("Menu", func(): on_menu.call(), false, 26)
	menu.custom_minimum_size = Vector2(0, 64)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(menu)

	if reward.has("champ"):
		_champ_column(cols, reward, rank)
	elif reward.has("event"):
		_reward_column(cols, reward, rank)
	elif not rank.is_empty():
		_rank_column(cols, rank)

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
