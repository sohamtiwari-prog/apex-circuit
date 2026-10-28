class_name StarRow
extends Control
## Up to three stars, drawn (no font glyphs needed): filled gold or hollow.

@export var stars := 0:
	set(v):
		stars = v
		queue_redraw()
var total := 3
var gold := Color("ffc93c")
var hollow := Color(1, 1, 1, 0.22)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := minf(size.y * 0.5, size.x / (total * 2.2))
	var gap := r * 2.2
	var x0 := (size.x - gap * total) * 0.5 + gap * 0.5
	for k in total:
		var c := Vector2(x0 + k * gap, size.y * 0.5)
		var pts := PackedVector2Array()
		for p in 10:
			var a := -PI / 2.0 + p * PI / 5.0
			var rr := r if p % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		if k < stars:
			draw_colored_polygon(pts, gold)
		else:
			pts.append(pts[0])
			draw_polyline(pts, hollow, maxf(r * 0.12, 1.5), true)
