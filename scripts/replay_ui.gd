class_name ReplayUI
extends CanvasLayer
## Replay controls, broadcast style: who you're watching and their place,
## the camera, the race clock, a timeline with the highlights marked on it,
## and transport buttons. Fades out after a few seconds of watching; a tap
## anywhere brings it back. "Hide" clears the screen for a clean shot.

const IDLE_HIDE := 4.5

var replay: Replay
var _root: Control
var _top: Control
var _bottom: Control
var _clock: Label
var _speed_lbl: Label
var _car_pos: Label
var _car_name: Label
var _car_stripe: ColorRect
var _cam_btn: Button
var _play: IconButton
var _speed_btn: Button
var _timeline: Timeline
var _caption: PanelContainer
var _caption_lbl: Label
var _rec_dot: ColorRect
var _idle := 0.0
var _shown := 1.0
var _hidden_by_user := false
var _blink := 0.0


func setup(r: Replay) -> void:
	replay = r
	layer = 6
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top()
	_build_bottom()
	_build_caption()
	refresh()


# ------------------------------------------------------------ layout

func _build_top() -> void:
	_top = Control.new()
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_bottom = 90
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_top)

	# Left: REPLAY tag and the race clock.
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.85)))
	tag.position = Vector2(28, 20)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(tag)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tag.add_child(row)
	var dot_box := CenterContainer.new()
	row.add_child(dot_box)
	_rec_dot = ColorRect.new()
	_rec_dot.color = UIStyle.RED
	_rec_dot.custom_minimum_size = Vector2(14, 14)
	dot_box.add_child(_rec_dot)
	row.add_child(UIStyle.label("REPLAY", 30, UIStyle.PAPER, "extrabold", true))
	_clock = UIStyle.label("", 28, UIStyle.FOG, "bold", true)
	row.add_child(_clock)
	_speed_lbl = UIStyle.label("", 28, UIStyle.YELLOW, "extrabold", true)
	row.add_child(_speed_lbl)

	# Centre: the car being watched, with arrows to change it.
	var mid := HBoxContainer.new()
	mid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mid.offset_left = -300
	mid.offset_right = 300
	mid.offset_top = 16
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 10)
	_top.add_child(mid)
	mid.add_child(_icon_button("prev", func(): replay.step_focus(-1), Vector2(64, 60)))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.85)))
	card.custom_minimum_size = Vector2(330, 60)
	mid.add_child(card)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 12)
	card.add_child(cr)
	_car_pos = UIStyle.label("P1", 32, UIStyle.PAPER, "extrabold", true)
	_car_pos.custom_minimum_size = Vector2(56, 0)
	cr.add_child(_car_pos)
	var sbox := CenterContainer.new()
	cr.add_child(sbox)
	_car_stripe = ColorRect.new()
	_car_stripe.custom_minimum_size = Vector2(6, 30)
	sbox.add_child(_car_stripe)
	_car_name = UIStyle.label("", 28, UIStyle.PAPER, "bold", true)
	_car_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_car_name.clip_text = true
	cr.add_child(_car_name)
	mid.add_child(_icon_button("next", func(): replay.step_focus(1), Vector2(64, 60)))

	# Right: the camera.
	_cam_btn = UIStyle.button("Auto", func():
		replay.cam.cycle_mode()
		refresh(), false, 26)
	_cam_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cam_btn.offset_left = -300
	_cam_btn.offset_right = -28
	_cam_btn.offset_top = 16
	_cam_btn.offset_bottom = 76
	_cam_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cam_btn.clip_text = true
	_top.add_child(_cam_btn)


func _build_bottom() -> void:
	_bottom = PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.INK, 0.78), false)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_bottom.add_theme_stylebox_override("panel", sb)
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_left = 24
	_bottom.offset_right = -24
	_bottom.offset_top = -104
	_bottom.offset_bottom = -18
	_root.add_child(_bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bottom.add_child(row)
	row.add_child(_icon_button("back", func(): replay.skip(-10.0)))
	_play = _icon_button("pause", func():
		replay.toggle_pause()
		refresh())
	row.add_child(_play)
	row.add_child(_icon_button("fwd", func(): replay.skip(10.0)))
	_speed_btn = UIStyle.button("1x", func():
		replay.cycle_speed()
		refresh(), false, 26)
	_speed_btn.custom_minimum_size = Vector2(92, 68)
	row.add_child(_speed_btn)
	_timeline = Timeline.new()
	_timeline.replay = replay
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size = Vector2(200, 68)
	_timeline.seek_requested.connect(func(frac: float):
		replay.seek(frac * float(replay.count - 1))
		_idle = 0.0)
	row.add_child(_timeline)
	var hl := UIStyle.button("Highlights", func(): replay.next_highlight(), true, 26)
	hl.custom_minimum_size = Vector2(0, 68)
	hl.visible = not replay.events.is_empty()
	row.add_child(hl)
	row.add_child(_icon_button("eye", func():
		_hidden_by_user = true
		_shown = 0.0
		_apply_shown()))
	row.add_child(_icon_button("close", func(): replay.stop()))


func _build_caption() -> void:
	_caption = PanelContainer.new()
	_caption.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.9), true, UIStyle.APEX))
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.offset_top = -176
	_caption.offset_bottom = -124
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	_root.add_child(_caption)
	_caption_lbl = UIStyle.label("", 28, UIStyle.PAPER, "bold", true)
	_caption.add_child(_caption_lbl)


func _icon_button(kind: String, cb: Callable, size := Vector2(76, 68)) -> IconButton:
	var b := IconButton.new()
	var normal := UIStyle.panel(Color(UIStyle.TARMAC, 0.88))
	normal.border_color = Color(UIStyle.PAPER, 0.18)
	normal.set_border_width_all(2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(UIStyle.APEX, 0.85)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	b.kind = kind
	b.pressed.connect(func():
		_idle = 0.0
		cb.call())
	return b


# ------------------------------------------------------------ state

func refresh() -> void:
	if replay == null or replay.cam == null:
		return
	var i := replay.focus
	var p := replay.position_of(i)
	_car_pos.text = "P%d" % p if p > 0 else "-"
	_car_pos.add_theme_color_override("font_color", UIStyle.APEX if replay.is_player[i] else UIStyle.PAPER)
	_car_name.text = replay.names[i]
	_car_stripe.color = replay.colors[i]
	_cam_btn.text = replay.cam.shot_name()
	_play.kind = "play" if replay.paused else "pause"
	_play.queue_redraw()
	_speed_btn.text = Replay.SPEED_NAMES[replay.speed_i]
	_speed_lbl.text = "" if replay.speed_i == 0 else ("SLOW-MO" if Replay.SPEEDS[replay.speed_i] < 1.0 else "FAST")
	var lap := replay.lap_of(i)
	var clock := UIStyle.fmt_time(replay.time_at())
	if replay.total_laps > 0:
		_clock.text = "Lap %d/%d  %s" % [mini(lap + 1, replay.total_laps), replay.total_laps, clock]
	else:
		_clock.text = "Lap %d  %s" % [lap + 1, clock]
	_timeline.queue_redraw()
	var ev := replay.caption()
	_caption.visible = not ev.is_empty()
	if not ev.is_empty():
		_caption_lbl.text = String(ev["text"])
		var col: Color = Timeline.color_of(String(ev["kind"]))
		var cs := _caption.get_theme_stylebox("panel") as StyleBoxFlat
		cs.border_color = col


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_idle = 0.0
			if _shown < 0.99:
				_hidden_by_user = false
				_shown = 1.0
				_apply_shown()
				get_viewport().set_input_as_handled()   # this tap only wakes the controls


func _apply_shown() -> void:
	for c in [_top, _bottom]:
		c.modulate.a = _shown
		c.visible = _shown > 0.02


func _process(delta: float) -> void:
	if replay == null:
		return
	_blink += delta
	_rec_dot.visible = replay.paused or fmod(_blink, 1.0) < 0.6
	if not replay.paused and not _timeline.dragging:
		_idle += delta
	else:
		_idle = 0.0
	var want := 0.0 if _hidden_by_user or _idle > IDLE_HIDE else 1.0
	if absf(_shown - want) > 0.001:
		_shown = move_toward(_shown, want, delta * (4.0 if want > _shown else 1.6))
		_apply_shown()
	refresh()
	# The caption stays, even with the controls hidden; not in a clean shot.
	if _hidden_by_user:
		_caption.visible = false


## Transport buttons with drawn icons (no font glyphs needed).
class IconButton extends Button:
	var kind := "play":
		set(v):
			kind = v
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var col := UIStyle.PAPER
		var s := minf(size.x, size.y) * 0.22
		match kind:
			"play":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s), c + Vector2(s, 0), c + Vector2(-s * 0.7, s)]), col)
			"pause":
				draw_rect(Rect2(c + Vector2(-s * 0.75, -s), Vector2(s * 0.5, s * 2.0)), col)
				draw_rect(Rect2(c + Vector2(s * 0.25, -s), Vector2(s * 0.5, s * 2.0)), col)
			"back", "fwd":
				var d := -1.0 if kind == "back" else 1.0
				for k in 2:
					var o := c + Vector2(d * (k * s * 0.9 - s * 0.45), 0)
					draw_colored_polygon(PackedVector2Array([o + Vector2(-d * s * 0.5, -s * 0.8), o + Vector2(d * s * 0.6, 0), o + Vector2(-d * s * 0.5, s * 0.8)]), col)
			"prev", "next":
				var d := -1.0 if kind == "prev" else 1.0
				draw_polyline(PackedVector2Array([c + Vector2(-d * s * 0.4, -s * 0.9), c + Vector2(d * s * 0.5, 0), c + Vector2(-d * s * 0.4, s * 0.9)]), col, 5.0, true)
			"close":
				draw_line(c + Vector2(-s * 0.8, -s * 0.8), c + Vector2(s * 0.8, s * 0.8), col, 5.0, true)
				draw_line(c + Vector2(s * 0.8, -s * 0.8), c + Vector2(-s * 0.8, s * 0.8), col, 5.0, true)
			"eye":
				var pts := PackedVector2Array()
				for k in 25:
					var a := PI * k / 24.0
					pts.append(c + Vector2(-cos(a) * s * 1.2, -sin(a) * s * 0.75))
				for k in 25:
					var a := PI * k / 24.0
					pts.append(c + Vector2(cos(a) * s * 1.2, sin(a) * s * 0.75))
				draw_polyline(pts, col, 3.5, true)
				draw_circle(c, s * 0.38, col)
				draw_line(c + Vector2(-s * 1.1, s * 0.95), c + Vector2(s * 1.1, -s * 0.95), col, 3.5, true)


## The replay's length, what's been watched, highlight marks; drag to scrub.
class Timeline extends Control:
	signal seek_requested(frac: float)
	var replay: Replay
	var dragging := false

	static func color_of(kind: String) -> Color:
		match kind:
			"contact":
				return UIStyle.RED
			"gain":
				return UIStyle.GREEN
			"loss":
				return UIStyle.YELLOW
			"lead":
				return UIStyle.APEX
			"fastest":
				return UIStyle.PURPLE
		return UIStyle.PAPER

	func _draw() -> void:
		if replay == null or replay.count < 2:
			return
		var y := size.y * 0.5
		var x0 := 14.0
		var w := size.x - 28.0
		var n := float(replay.count - 1)
		draw_rect(Rect2(x0, y - 4, w, 8), Color(UIStyle.PAPER, 0.2))
		var fx := x0 + w * clampf(replay.t / n, 0.0, 1.0)
		draw_rect(Rect2(x0, y - 4, fx - x0, 8), UIStyle.APEX)
		for ev in replay.events:
			var ex := x0 + w * float(int(ev["f"])) / n
			draw_rect(Rect2(ex - 2.5, y - 16, 5, 32), color_of(String(ev["kind"])))
		draw_circle(Vector2(fx, y), 13.0, UIStyle.PAPER)
		draw_circle(Vector2(fx, y), 7.0, UIStyle.APEX)

	func _gui_input(event: InputEvent) -> void:
		var x := -1.0
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				x = event.position.x
		elif event is InputEventMouseMotion and dragging:
			x = event.position.x
		if x >= 0.0:
			seek_requested.emit(clampf((x - 14.0) / maxf(size.x - 28.0, 1.0), 0.0, 1.0))
			accept_event()
