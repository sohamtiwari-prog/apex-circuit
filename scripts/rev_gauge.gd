class_name RevGauge
extends Control
## Bottom-centre instrument: a rev arc whose segments double as shift
## lights (green, yellow, red, then all purple at the shift point), the gear
## in the middle and the speed underneath.

const SEGMENTS := 22
const A0 := deg_to_rad(160.0)
const A1 := deg_to_rad(380.0)

var gear := 1
var speed := 0
var _frac := 0.0
var _shift := false
var _lit := -1
var _blink := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 176)


func set_engine(g: int, rpm: float, shift_rpm: float, redline: float, idle: float, kmh: float) -> void:
	var start := lerpf(idle, shift_rpm, 0.35)
	var frac := clampf((rpm - start) / maxf(shift_rpm - start, 1.0), 0.0, 1.0)
	var lit := int(round(frac * SEGMENTS))
	var shift := rpm >= shift_rpm
	var spd := int(round(kmh))
	if g != gear or spd != speed or lit != _lit or shift != _shift:
		gear = g
		speed = spd
		_lit = lit
		_frac = frac
		_shift = shift
		queue_redraw()


func _process(delta: float) -> void:
	if _shift:
		_t += delta
		var b := fmod(_t, 0.16) < 0.08
		if b != _blink:
			_blink = b
			queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.66)
	var r := minf(size.x * 0.42, size.y * 0.62)
	# Backing disc for legibility over the scene.
	draw_circle(c, r - 16.0, Color(UIStyle.TARMAC, 0.72))
	var step := (A1 - A0) / SEGMENTS
	for k in range(SEGMENTS):
		var a := A0 + step * k + step * 0.12
		var b := A0 + step * (k + 1) - step * 0.12
		var col := Color(UIStyle.PAPER, 0.16)
		var t := float(k) / SEGMENTS
		if _shift:
			col = UIStyle.PURPLE if _blink else Color(UIStyle.PURPLE, 0.35)
		elif k < _lit:
			col = UIStyle.GREEN if t < 0.5 else (UIStyle.YELLOW if t < 0.78 else UIStyle.RED)
		draw_arc(c, r, a, b, 6, col, 13.0, true)
	var g_txt := "R" if gear < 0 else ("N" if gear == 0 else str(gear))
	var gf := UIStyle.font("extrabold", true)
	var gs := 74
	var gw := gf.get_string_size(g_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, gs)
	draw_string(gf, c + Vector2(-gw.x * 0.5, 4), g_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, gs,
		UIStyle.APEX if _shift else UIStyle.PAPER)
	var sf := UIStyle.font("bold", true)
	var s_txt := str(speed)
	var sw := sf.get_string_size(s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
	draw_string(sf, c + Vector2(-sw.x * 0.5 - 14, 44), s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UIStyle.PAPER)
	draw_string(UIStyle.font("medium"), c + Vector2(sw.x * 0.5 - 8, 44), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UIStyle.FOG)
