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
# Wheel steering: a floating steering-wheel arc wherever the left thumb lands.
# The thumb sits on the rim; the hub is below it. Rotation = steering.
var _drag_finger := -1
var _drag_origin := Vector2.ZERO     # wheel hub
var _drag_pos := Vector2.ZERO        # thumb
var _wheel_angle := 0.0              # rad, + = clockwise (right)
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


## Wheel rim radius in pixels.
func drag_range() -> float:
	return clampf(size.y * 0.24, 110.0, 250.0)


## Wheel rotation for full lock; higher sensitivity = less rotation.
func max_wheel_angle() -> float:
	return deg_to_rad(55.0) / clampf(sensitivity, 0.5, 2.5)


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
				_drag_origin = event.position + Vector2(0, drag_range())
				_drag_pos = event.position
				_wheel_angle = 0.0
		else:
			_touches.erase(event.index)
			if event.index == _drag_finger:
				_drag_finger = -1
		_update_state()
	elif event is InputEventScreenDrag:
		if event.index == _drag_finger:
			_drag_pos = event.position
			var arm := _drag_pos - _drag_origin
			var r := drag_range()
			# Thumb too close to the hub: keep the last angle, pull the hub away.
			if arm.length() < r * 0.35:
				_drag_origin = _drag_pos - Vector2(sin(_wheel_angle), -cos(_wheel_angle)) * r * 0.35
				arm = _drag_pos - _drag_origin
			var ang := atan2(arm.x, -arm.y)          # 0 = thumb straight above the hub
			var lim := max_wheel_angle()
			if absf(ang) > lim:
				# The wheel follows the thumb past full lock, so turning back
				# always steers the other way straight away.
				var dir := Vector2(sin(signf(ang) * lim), -cos(signf(ang) * lim))
				_drag_origin = _drag_pos - dir * arm.length()
				ang = signf(ang) * lim
			_wheel_angle = ang
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
			var x := clampf(_wheel_angle / max_wheel_angle(), -1.0, 1.0)
			# Small dead zone, then linear (the car maps input to grip linearly).
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
	var hub := _drag_origin if active else Vector2(_steer_zone.position.x + _steer_zone.size.x * 0.45, _steer_zone.end.y - size.y * 0.13 + r)
	var lim := max_wheel_angle()
	var ang := _wheel_angle if active else 0.0
	var up := -PI * 0.5                       # canvas angle of "straight up"
	var a := 0.9 if active else 0.45
	# The rim: a thick arc covering the steering range plus a margin.
	var span := lim + deg_to_rad(16)
	draw_arc(hub, r, up - span, up + span, 48, Color(0, 0, 0, 0.35 * a), 30.0, true)
	draw_arc(hub, r, up - span, up + span, 48, Color(UIStyle.TARMAC, 0.7 * a), 24.0, true)
	# Grip texture: short ticks every 6 degrees, end stops at full lock.
	var k := -span
	while k <= span:
		var d := Vector2(cos(up + k), sin(up + k))
		draw_line(hub + d * (r - 9), hub + d * (r + 9), Color(UIStyle.PAPER, 0.12 * a), 2.0, true)
		k += deg_to_rad(6)
	for side in [-1.0, 1.0]:
		var d := Vector2(cos(up + side * lim), sin(up + side * lim))
		draw_line(hub + d * (r - 14), hub + d * (r + 14), Color(UIStyle.PAPER, 0.55 * a), 3.0, true)
	# Centre mark, rotating with the wheel (like the stripe at 12 o'clock).
	var dc := Vector2(cos(up + ang), sin(up + ang))
	draw_line(hub + dc * (r - 13), hub + dc * (r + 13), UIStyle.APEX if active else Color(UIStyle.PAPER, 0.5), 5.0, true)
	if active:
		# Lock used, as an orange fill from the top of the rim.
		if absf(ang) > 0.01:
			draw_arc(hub, r, up, up + ang, 24, Color(UIStyle.APEX, 0.85), 10.0, true)
		draw_circle(hub + dc * r, 25.0, Color(UIStyle.PAPER, 0.9))
		draw_circle(hub + dc * r, 19.0, UIStyle.APEX)
	else:
		var f := UIStyle.font("bold", true)
		var text := "Steer here"
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		var at := hub + Vector2(-ts.x * 0.5, -r - 30)
		draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0, 0.45))
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UIStyle.PAPER, 0.8))
		draw_circle(hub + dc * r, 20.0, Color(UIStyle.PAPER, 0.35))
