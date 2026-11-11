class_name HelmetBadge
extends Control
## Your driver's helmet, side on and facing right: the shell in your main
## colour, a stripe over the crown in the second, the visor, and your race
## number on the side. Used as your picture everywhere (home, the driver
## screen, the list of drivers on this phone).

var base := Color("ffd200"):
	set(v):
		base = v
		queue_redraw()
var stripe := Color("000000"):
	set(v):
		stripe = v
		queue_redraw()
var number := 26:
	set(v):
		number = v
		queue_redraw()
var show_number := true


static func for_driver(d: Dictionary, px := 64.0) -> HelmetBadge:
	var h := HelmetBadge.new()
	h.base = Color(String(d.get("helmet", "ffd200")))
	h.stripe = Color(String(d.get("helmet2", "000000")))
	h.number = int(d.get("number", 26))
	h.custom_minimum_size = Vector2(px, px)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _p(x: float, y: float) -> Vector2:
	var s := minf(size.x, size.y) / 100.0
	return Vector2((size.x - 100.0 * s) * 0.5 + x * s, (size.y - 100.0 * s) * 0.5 + y * s)


func _shell() -> PackedVector2Array:
	var pts := PackedVector2Array()
	# Over the crown from the back of the neck to the brow...
	for i in 25:
		var a := deg_to_rad(168.0 + 182.0 * i / 24.0)
		pts.append(_p(47 + cos(a) * 41, 52 + sin(a) * 41))
	# ...down the chin bar, along the bottom, up the back.
	for p in [[92, 58], [90, 80], [82, 88], [24, 88], [10, 78], [7, 62]]:
		pts.append(_p(p[0], p[1]))
	return pts


func _draw() -> void:
	var s := minf(size.x, size.y) / 100.0
	var shell := _shell()
	var dark := base.get_luminance() < 0.25
	draw_colored_polygon(shell, base)
	# Stripe over the crown, front to back.
	draw_arc(_p(47, 52), 33.0 * s, deg_to_rad(196), deg_to_rad(318), 24, stripe, 11.0 * s, true)
	# Lower edge trim in the stripe colour.
	var trim := PackedVector2Array()
	for p in [[22, 82], [84, 82], [82, 88], [24, 88]]:
		trim.append(_p(p[0], p[1]))
	draw_colored_polygon(trim, stripe)
	# Visor: dark glass with a light streak.
	var visor := PackedVector2Array()
	for p in [[54, 40], [93, 41], [92, 60], [50, 60], [48, 50]]:
		visor.append(_p(p[0], p[1]))
	draw_colored_polygon(visor, Color(0.06, 0.07, 0.09))
	draw_line(_p(60, 45), _p(86, 45), Color(1, 1, 1, 0.35), 2.5 * s, true)
	# Outline, so a white helmet still reads on a white board.
	var edge := shell.duplicate()
	edge.append(shell[0])
	draw_polyline(edge, Color(0, 0, 0, 0.55) if not dark else Color(1, 1, 1, 0.5), maxf(1.5, 2.2 * s), true)
	if show_number:
		var f := UIStyle.font("display")
		var fs := int(19 * s)
		var txt := str(number)
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := _p(32, 77) - Vector2(w * 0.5, 0)
		var ink := Color.BLACK if base.get_luminance() > 0.5 else Color.WHITE
		draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
