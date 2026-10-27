class_name RankBadge
extends Control
## Rank emblem drawn in code: a shield in the tier colour with 1-3 chevrons
## for divisions III-I; a ring for Rookie; a crown for Champion; a star for
## Legend, with its earned stars below.

var rp := 0:
	set(v):
		rp = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(64, 64)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(size.x * 0.5, s * 0.5)
	var k := Ranks.tier_index(rp)
	var col := Ranks.tier_color(rp)
	var name: String = Ranks.TIERS[k][0]
	var dark := Color(0.06, 0.07, 0.09)
	if k == 0:
		draw_arc(c, s * 0.38, 0, TAU, 40, col, s * 0.09, true)
		draw_circle(c, s * 0.12, col)
		return
	if name == "Legend":
		var pts := _star(c, s * 0.46, s * 0.2, 5)
		draw_colored_polygon(pts, col)
		draw_colored_polygon(_star(c, s * 0.27, s * 0.12, 5), col.lightened(0.45))
		var stars := Ranks.stars_of(rp)
		for i in mini(stars, 5):
			var p := Vector2(c.x + (i - (mini(stars, 5) - 1) * 0.5) * s * 0.2, s * 1.04)
			draw_colored_polygon(_star(p, s * 0.085, s * 0.04, 5), Color(1, 0.85, 0.3))
		return
	if name == "Champion":
		var w := s * 0.4
		var crown := PackedVector2Array([
			c + Vector2(-w, s * 0.28), c + Vector2(-w, -s * 0.1), c + Vector2(-w * 0.5, s * 0.06),
			c + Vector2(0, -s * 0.34), c + Vector2(w * 0.5, s * 0.06), c + Vector2(w, -s * 0.1),
			c + Vector2(w, s * 0.28)])
		draw_colored_polygon(crown, col)
		draw_circle(c + Vector2(0, s * 0.14), s * 0.07, col.lightened(0.5))
		return
	# Shield with chevrons.
	var w2 := s * 0.36
	var shield := PackedVector2Array([
		c + Vector2(-w2, -s * 0.42), c + Vector2(w2, -s * 0.42), c + Vector2(w2, s * 0.08),
		c + Vector2(0, s * 0.46), c + Vector2(-w2, s * 0.08)])
	draw_colored_polygon(shield, col)
	draw_polyline(shield + PackedVector2Array([shield[0]]), col.lightened(0.4), s * 0.035, true)
	var div := 1
	if name.ends_with(" II"):
		div = 2
	elif name.ends_with(" I"):
		div = 3
	for i in div:
		var y := -s * 0.22 + i * s * 0.17
		var chev := PackedVector2Array([
			c + Vector2(-w2 * 0.62, y), c + Vector2(0, y + s * 0.12), c + Vector2(w2 * 0.62, y),
			c + Vector2(w2 * 0.62, y + s * 0.07), c + Vector2(0, y + s * 0.19), c + Vector2(-w2 * 0.62, y + s * 0.07)])
		draw_colored_polygon(chev, dark)


static func _star(c: Vector2, r_out: float, r_in: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := -PI / 2 + PI * i / n
		var r := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
