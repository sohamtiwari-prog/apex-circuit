class_name TouchControls
extends Control
## Multi-touch pedals and steering buttons, drawn with _draw.
## Handles raw touch events itself so several fingers work at once.

var mode := "tilt"            # "tilt", "drag" or "buttons"
var sensitivity := 1.0        # drag: higher = less thumb travel for full lock
var auto_accelerate := false

var steer := 0.0
var gas := 0.0
var brake := 0.0

var _touches := {}            # finger index -> region name
var _regions := {}            # region name -> Rect2
# Drag steering: a floating slider wherever the left thumb lands.
var _drag_finger := -1
var _drag_origin := Vector2.ZERO
var _drag_pos := Vector2.ZERO
var _steer_zone := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()


func configure(control_mode: String, auto_acc: bool, sens := 1.0) -> void:
	mode = control_mode
	auto_accelerate = auto_acc
	sensitivity = sens
	release_all()
	_layout()


func release_all() -> void:
	_touches.clear()
	_drag_finger = -1
	_update_state()


## Thumb travel (pixels) from the touch point to full lock.
func drag_range() -> float:
	return clampf(size.y * 0.2, 90.0, 220.0) / maxf(sensitivity, 0.3)


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
	elif mode == "drag":
		# Left thumb steers anywhere in the lower-left; both pedals on the right.
		_steer_zone = Rect2(0, s.y * 0.3, s.x * 0.42, s.y * 0.7)
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
			elif mode == "drag" and _drag_finger < 0 and _steer_zone.has_point(event.position):
				_drag_finger = event.index
				_drag_origin = event.position
				_drag_pos = event.position
		else:
			_touches.erase(event.index)
			if event.index == _drag_finger:
				_drag_finger = -1
		_update_state()
	elif event is InputEventScreenDrag:
		if event.index == _drag_finger:
			_drag_pos = event.position
			# The slider follows the thumb past full lock, so coming back
			# always starts steering the other way straight away.
			var r := drag_range()
			var dx := _drag_pos.x - _drag_origin.x
			if absf(dx) > r:
				_drag_origin.x = _drag_pos.x - signf(dx) * r
			_update_state()
		elif _touches.has(event.index):
			var reg := _region_at(event.position)
			if reg != "":
				_touches[event.index] = reg
			_update_state()


func _update_state() -> void:
	var held := {}
	for k in _touches:
		held[_touches[k]] = true
	steer = (1.0 if held.has("right") else 0.0) - (1.0 if held.has("left") else 0.0)
	if mode == "drag":
		steer = 0.0
		if _drag_finger >= 0:
			var dx := _drag_pos.x - _drag_origin.x
			var r := drag_range()
			var x := clampf(dx / r, -1.0, 1.0)
			# Small dead zone, then linear: precise near the centre.
			steer = signf(x) * clampf((absf(x) - 0.03) / 0.97, 0.0, 1.0)
	brake = 1.0 if held.has("brake") else 0.0
	if auto_accelerate:
		gas = 0.0 if brake > 0.0 else 1.0
	else:
		gas = 1.0 if held.has("gas") else 0.0
	queue_redraw()


func _draw() -> void:
	if mode == "drag":
		_draw_drag_steer()
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


func _draw_drag_steer() -> void:
	var r := drag_range()
	var active := _drag_finger >= 0
	var c := _drag_origin if active else Vector2(_steer_zone.position.x + _steer_zone.size.x * 0.42, _steer_zone.end.y - size.y * 0.16)
	var a := 0.85 if active else 0.4
	# Track with a centre notch and end stops.
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.45 if active else 0.3), true, Color(0, 0, 0, 0), 6)
	draw_style_box(sb, Rect2(c.x - r - 18, c.y - 16, r * 2 + 36, 32))
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(UIStyle.PAPER, a * 0.5), 4.0, true)
	draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color(UIStyle.PAPER, a * 0.6), 2.0, true)
	if active:
		var x := clampf(_drag_pos.x - c.x, -r, r)
		var fill := UIStyle.APEX
		draw_line(c, c + Vector2(x, 0), fill, 6.0, true)
		draw_circle(c + Vector2(x, 0), 26.0, Color(UIStyle.PAPER, 0.9))
		draw_circle(c + Vector2(x, 0), 20.0, fill)
	else:
		draw_circle(c, 22.0, Color(UIStyle.PAPER, 0.35))
		var f := UIStyle.font("bold", true)
		var text := "Drag to steer"
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string_outline(f, c + Vector2(-ts.x * 0.5, -32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0, 0.45))
		draw_string(f, c + Vector2(-ts.x * 0.5, -32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UIStyle.PAPER, 0.8))
		for side in [-1.0, 1.0]:
			var tip := c + Vector2(side * (r + 4), 0)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-side * 14, -10), tip + Vector2(-side * 14, 10)]), Color(UIStyle.PAPER, 0.4))
