class_name TouchControls
extends Control
## Multi-touch pedals and steering buttons, drawn with _draw.
## Handles raw touch events itself so several fingers work at once.

var mode := "tilt"            # "tilt" or "buttons"
var auto_accelerate := false

var steer := 0.0
var gas := 0.0
var brake := 0.0

var _touches := {}            # finger index -> region name
var _regions := {}            # region name -> Rect2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()


func configure(control_mode: String, auto_acc: bool) -> void:
	mode = control_mode
	auto_accelerate = auto_acc
	release_all()
	_layout()


func release_all() -> void:
	_touches.clear()
	_update_state()


func _layout() -> void:
	var s := size
	if s.x <= 0.0:
		return
	var m := s.y * 0.04
	var b := clampf(s.y * 0.26, 110.0, 260.0)
	_regions.clear()
	if mode == "buttons":
		_regions["left"] = Rect2(m, s.y - m - b, b, b)
		_regions["right"] = Rect2(m * 2.0 + b, s.y - m - b, b, b)
		_regions["brake"] = Rect2(s.x - m * 2.0 - b * 1.8, s.y - m - b, b * 0.9, b)
		if not auto_accelerate:
			_regions["gas"] = Rect2(s.x - m - b * 0.9, s.y - m - b * 1.35, b * 0.9, b * 1.35)
		else:
			_regions["brake"] = Rect2(s.x - m - b * 1.2, s.y - m - b * 1.2, b * 1.2, b * 1.2)
	else:
		_regions["brake"] = Rect2(m, s.y - m - b * 1.25, b * 1.3, b * 1.25)
		if not auto_accelerate:
			_regions["gas"] = Rect2(s.x - m - b * 1.3, s.y - m - b * 1.25, b * 1.3, b * 1.25)
	queue_redraw()


func _region_at(p: Vector2) -> String:
	for key in _regions:
		var r: Rect2 = _regions[key]
		if r.grow(12.0).has_point(p):
			return key
	return ""


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var reg := _region_at(event.position)
			if reg != "":
				_touches[event.index] = reg
		else:
			_touches.erase(event.index)
		_update_state()
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			var reg := _region_at(event.position)
			if reg != "":
				_touches[event.index] = reg
			_update_state()


func _update_state() -> void:
	var held := {}
	for k in _touches:
		held[_touches[k]] = true
	steer = (1.0 if held.has("right") else 0.0) - (1.0 if held.has("left") else 0.0)
	brake = 1.0 if held.has("brake") else 0.0
	if auto_accelerate:
		gas = 0.0 if brake > 0.0 else 1.0
	else:
		gas = 1.0 if held.has("gas") else 0.0
	queue_redraw()


func _draw() -> void:
	var held := {}
	for k in _touches:
		held[_touches[k]] = true
	for key in _regions:
		var r: Rect2 = _regions[key]
		var on: bool = held.has(key)
		var accent := UIStyle.PAPER
		if key == "gas":
			accent = UIStyle.GREEN
		elif key == "brake":
			accent = UIStyle.RED
		var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.3 if not on else 0.7), true, Color(0, 0, 0, 0), 8)
		sb.border_color = Color(accent, 0.9 if on else 0.55)
		sb.border_width_bottom = 6
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		if on:
			sb.bg_color = Color(accent, 0.38)
		draw_style_box(sb, r)
		var c := r.get_center()
		var w := r.size.x * 0.2
		var ink := Color(UIStyle.PAPER, 0.92 if on else 0.75)
		match key:
			"left":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-w, 0), c + Vector2(w * 0.7, -w), c + Vector2(w * 0.7, w)]), ink)
			"right":
				draw_colored_polygon(PackedVector2Array([c + Vector2(w, 0), c + Vector2(-w * 0.7, -w), c + Vector2(-w * 0.7, w)]), ink)
			"gas":
				# Three forward chevrons.
				for k in range(3):
					var y := c.y + w * 0.9 - k * w * 0.75
					draw_polyline(PackedVector2Array([Vector2(c.x - w * 0.8, y), Vector2(c.x, y - w * 0.55), Vector2(c.x + w * 0.8, y)]), Color(ink, 0.45 + k * 0.25), 7.0, true)
				_caption("Gas", r, ink)
			"brake":
				# Two bars, like a pedal face.
				draw_rect(Rect2(c + Vector2(-w, -w * 0.75), Vector2(w * 2.0, w * 0.4)), ink)
				draw_rect(Rect2(c + Vector2(-w, -w * 0.05), Vector2(w * 2.0, w * 0.4)), ink)
				_caption("Brake", r, ink)


func _caption(text: String, r: Rect2, col: Color) -> void:
	var f := UIStyle.font("bold", true)
	var fs := int(clampf(r.size.x * 0.14, 18.0, 30.0))
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, Vector2(r.get_center().x - ts.x * 0.5, r.end.y - fs * 0.6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
