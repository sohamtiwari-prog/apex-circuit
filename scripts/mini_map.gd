class_name MiniMap
extends Control
## Live circuit map: the track outline with every car as a dot in its team
## colour (you in Apex orange, drawn on top). Also used for track previews
## in the menu (no cars).

var _line := PackedVector2Array()
var _start := Vector2.ZERO
var _start_dir := Vector2.RIGHT
var _cars: Array = []           # [Vector2 map pos, Color, is_player]
var _scale := 1.0
var _offset := Vector2.ZERO
var _lo := Vector2.ZERO
var _points := PackedVector3Array()
var show_panel := true
var line_color := UIStyle.PAPER
var line_width := 3.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_fit)


func set_points(points: PackedVector3Array) -> void:
	_points = points
	_fit()


func _fit() -> void:
	if _points.is_empty() or size.x <= 0.0:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in _points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var pad := 14.0
	var ext := hi - lo
	_scale = minf((size.x - pad * 2.0) / maxf(ext.x, 1.0), (size.y - pad * 2.0) / maxf(ext.y, 1.0))
	_lo = lo
	_offset = (size - ext * _scale) * 0.5
	_line = PackedVector2Array()
	var step := maxi(1, _points.size() / 400)
	for i in range(0, _points.size(), step):
		_line.append(to_map(_points[i]))
	_line.append(_line[0])
	_start = to_map(_points[0])
	if _points.size() > 3:
		_start_dir = (to_map(_points[3]) - _start).normalized()
	queue_redraw()


func to_map(p: Vector3) -> Vector2:
	return _offset + (Vector2(p.x, p.z) - _lo) * _scale


## cars: Array of [Vector3 world position, Color, bool is_player]
func set_cars(cars: Array) -> void:
	_cars = cars
	queue_redraw()


func _draw() -> void:
	if show_panel:
		draw_style_box(UIStyle.panel(Color(UIStyle.TARMAC, 0.62), false, Color(0, 0, 0, 0), 10), Rect2(Vector2.ZERO, size))
	if _line.size() < 2:
		return
	draw_polyline(_line, Color(0, 0, 0, 0.55), line_width + 3.0, true)
	draw_polyline(_line, line_color, line_width, true)
	var n := Vector2(-_start_dir.y, _start_dir.x) * 6.0
	draw_line(_start - n, _start + n, UIStyle.APEX, 3.0, true)
	var me: Array = []
	for c in _cars:
		if c[2]:
			me = c
			continue
		draw_circle(to_map(c[0]), 4.2, Color(0, 0, 0, 0.7))
		draw_circle(to_map(c[0]), 3.2, c[1])
	if not me.is_empty():
		var p := to_map(me[0])
		draw_circle(p, 7.5, UIStyle.PAPER)
		draw_circle(p, 5.5, UIStyle.APEX)
