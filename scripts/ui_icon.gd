class_name UIIcon
extends Control
## Small drawn icons for the menus, all on one 48-unit grid with the same
## heavy, square-ended strokes, so they read as one set: trophy, calendar,
## podium, flag, friends, spanner, sun, moon, copy, plus, ghost, people.

@export var kind := "trophy"
@export var colour := Color.BLACK
@export var accent := Color(0, 0, 0, 0)     # a second colour some icons use

const W := 4.2      # stroke, in grid units


static func make(k: String, c: Color, px := 44.0, acc := Color(0, 0, 0, 0)) -> UIIcon:
	var i := UIIcon.new()
	i.kind = k
	i.colour = c
	i.accent = acc
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _s() -> float:
	return minf(size.x, size.y) / 48.0


func _p(x: float, y: float) -> Vector2:
	var s := _s()
	return Vector2((size.x - 48.0 * s) * 0.5 + x * s, (size.y - 48.0 * s) * 0.5 + y * s)


func _poly(pts: Array, c := colour) -> void:
	var a := PackedVector2Array()
	for p in pts:
		a.append(_p(p[0], p[1]))
	draw_colored_polygon(a, c)


func _line(pts: Array, c := colour, w := W) -> void:
	var a := PackedVector2Array()
	for p in pts:
		a.append(_p(p[0], p[1]))
	draw_polyline(a, c, w * _s(), true)


func _rect(x: float, y: float, w: float, h: float, c := colour) -> void:
	draw_rect(Rect2(_p(x, y), Vector2(w, h) * _s()), c)


func _circle(x: float, y: float, r: float, c := colour) -> void:
	draw_circle(_p(x, y), r * _s(), c)


func _ring(x: float, y: float, r: float, c := colour, w := W) -> void:
	draw_arc(_p(x, y), r * _s(), 0.0, TAU, 40, c, w * _s(), true)


func _draw() -> void:
	var acc := accent if accent.a > 0.0 else colour
	match kind:
		"trophy":
			_poly([[12, 6], [36, 6], [34, 22], [30, 28], [18, 28], [14, 22]])
			_line([[12, 10], [5, 10], [6, 17], [13, 21]])
			_line([[36, 10], [43, 10], [42, 17], [35, 21]])
			_rect(21, 28, 6, 8)
			_rect(13, 36, 22, 6)
			_poly([[24, 10], [25.6, 14.2], [30, 14.4], [26.6, 17.2], [27.8, 21.6], [24, 19.1], [20.2, 21.6], [21.4, 17.2], [18, 14.4], [22.4, 14.2]], acc if accent.a > 0.0 else Color(0, 0, 0, 0))
		"calendar":
			_rect(6, 10, 36, 8)
			_line([[6, 10], [42, 10], [42, 42], [6, 42], [6, 10]], colour, 3.6)
			_rect(13, 5, 4, 9)
			_rect(31, 5, 4, 9)
			for r in 2:
				for c in 3:
					_rect(12 + c * 9, 23 + r * 8, 6, 5, acc if (r == 1 and c == 2) else colour)
		"podium":
			_rect(17, 16, 14, 28)
			_rect(3, 26, 14, 18)
			_rect(31, 31, 14, 13)
			_poly([[24, 3], [25.4, 6.8], [29.4, 7], [26.3, 9.5], [27.4, 13.4], [24, 11.2], [20.6, 13.4], [21.7, 9.5], [18.6, 7], [22.6, 6.8]], acc)
		"flag":
			_rect(8, 5, 4, 39)
			# Chequers: 4 x 3 over the cloth.
			for r in 3:
				for c in 4:
					var col := colour if (r + c) % 2 == 0 else Color(colour, 0.0)
					_rect(12 + c * 7.5, 6 + r * 7.5, 7.5, 7.5, col)
			_line([[12, 6], [42, 6], [42, 28.5], [12, 28.5]], colour, 2.0)
		"friends":
			_helmet_shape(4, 12, 0.62, colour)
			_helmet_shape(20, 18, 0.62, acc)
		"helmet":
			_helmet_shape(5, 6, 0.8, colour)
		"spanner":
			_line([[10, 38], [29, 19]], colour, 7.0)
			draw_arc(_p(34, 14), 8.0 * _s(), deg_to_rad(80), deg_to_rad(370), 24, colour, 5.0 * _s(), true)
			_circle(10, 38, 4.5)
		"sun":
			_circle(24, 24, 8)
			for k in 8:
				var a := k * TAU / 8.0
				_line([[24 + cos(a) * 13, 24 + sin(a) * 13], [24 + cos(a) * 19, 24 + sin(a) * 19]], colour, 3.6)
		"moon":
			# A crescent: the disc, with the cut-out in the colour behind.
			_circle(24, 24, 16)
			_circle(31, 18, 13, accent if accent.a > 0.0 else Color.WHITE)
		"copy":
			_line([[16, 6], [40, 6], [40, 32]], colour, 3.6)
			_line([[8, 14], [32, 14], [32, 42], [8, 42], [8, 14]], colour, 3.6)
		"plus":
			_rect(21, 8, 6, 32)
			_rect(8, 21, 32, 6)
		"ghost":
			var pts := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				pts.append(_p(24 + cos(a) * 15, 20 + sin(a) * 15))
			for p in [[39, 42], [34, 37], [29, 42], [24, 37], [19, 42], [14, 37], [9, 42]]:
				pts.append(_p(p[0], p[1]))
			draw_colored_polygon(pts, colour)
			_circle(19, 20, 3, acc if accent.a > 0.0 else Color.WHITE)
			_circle(29, 20, 3, acc if accent.a > 0.0 else Color.WHITE)
		"restore":
			_line([[24, 8], [24, 30]], colour, 4.4)
			_poly([[14, 22], [34, 22], [24, 33]])
			_line([[8, 30], [8, 40], [40, 40], [40, 30]], colour, 4.4)


## A helmet in profile facing right, `k` = scale of the 48 grid.
func _helmet_shape(ox: float, oy: float, k: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var a := deg_to_rad(180.0 + 170.0 * i / 20.0)
		pts.append(_p(ox + (24 + cos(a) * 22) * k, oy + (24 + sin(a) * 22) * k))
	for p in [[46, 26], [46, 40], [8, 40], [2, 30]]:
		pts.append(_p(ox + p[0] * k, oy + p[1] * k))
	draw_colored_polygon(pts, c)
	var visor := PackedVector2Array()
	for p in [[26, 16], [46, 17], [46, 27], [24, 27]]:
		visor.append(_p(ox + p[0] * k, oy + p[1] * k))
	draw_colored_polygon(visor, Color(0, 0, 0, 0.0) if c.get_luminance() < 0.2 else Color(0, 0, 0, 0.85))
	if c.get_luminance() < 0.2:
		draw_polyline(visor + PackedVector2Array([visor[0]]), Color(1, 1, 1, 0.9), 2.0 * _s(), true)
