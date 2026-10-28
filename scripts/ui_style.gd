class_name UIStyle
extends RefCounted
## Shared look for every screen: "pit wall telemetry". Slanted panels from
## motorsport broadcast graphics, Saira Condensed throughout, tarmac-grey
## translucent panels, Apex orange only for the player and primary actions,
## and F1 timing colours used strictly for their meaning.

const TARMAC := Color("161a21")
const TARMAC_2 := Color("222833")
const LINE := Color("39414f")
const PAPER := Color("f1f3f6")
const FOG := Color("8c96a6")
const APEX := Color("ff6b1a")
const INK := Color("0d0f13")
# Timing colours.
const PURPLE := Color("b45cff")    # fastest overall
const GREEN := Color("2fd36f")     # personal best / improvement
const YELLOW := Color("ffc93c")    # slower / caution
const RED := Color("ff4438")       # invalid / lights

const SLANT := 0.22                # panel and type slant

static var _fonts := {}


## weight: "medium", "semibold", "bold", "extrabold". Slanted variants lean
## like the panels; all use tabular figures so timing digits don't jump.
static func font(weight := "semibold", slanted := false) -> Font:
	var key := weight + ("/s" if slanted else "")
	if _fonts.has(key):
		return _fonts[key]
	var file: String = {"medium": "Medium", "semibold": "SemiBold", "bold": "Bold", "extrabold": "ExtraBold"}[weight]
	var base: FontFile = load("res://fonts/SairaCondensed-%s.ttf" % file)
	var v := FontVariation.new()
	v.base_font = base
	v.opentype_features = {"tnum": 1}
	if slanted:
		v.variation_transform = Transform2D(Vector2(1, 0), Vector2(-SLANT * 0.7, 1), Vector2.ZERO)
	_fonts[key] = v
	return v


static func label(text: String, size: int, color := PAPER, weight := "semibold", slanted := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, slanted))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Readable over a bright 3D scene without a panel behind it.
static func outlined(l: Label, px := 6) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", px)
	return l


## Slanted translucent panel; `edge` draws a coloured leading edge.
static func panel(bg := Color(TARMAC, 0.82), slant := true, edge := Color(0, 0, 0, 0), radius := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if slant:
		sb.skew = Vector2(SLANT, 0)
	sb.set_corner_radius_all(radius)
	if edge.a > 0.0:
		sb.border_color = edge
		sb.border_width_left = 5
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.anti_aliasing = true
	return sb


## Primary buttons are orange; secondary are tarmac with a light edge.
static func button(text: String, cb: Callable, primary := false, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("bold", true))
	b.add_theme_font_size_override("font_size", size)
	var normal := panel(APEX if primary else Color(TARMAC, 0.88))
	normal.content_margin_left = 26
	normal.content_margin_right = 26
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	if not primary:
		normal.border_color = Color(PAPER, 0.18)
		normal.set_border_width_all(2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = (APEX.lightened(0.15) if primary else Color(APEX, 0.85))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", INK if primary else PAPER)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_hover_color", INK if primary else PAPER)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## "12,450 CR"
static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out + " CR"


## Top bar for the menu screens: back arrow, title, and your credits.
## Returns [bar, credits label].
static func header(title: String, on_back: Callable, credits: int) -> Array:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on_back.is_valid():
		var b := button("‹", on_back, false, 52)
		b.custom_minimum_size = Vector2(84, 62)
		bar.add_child(b)
	var t := outlined(label(title, 44, PAPER, "extrabold", true), 5)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(t)
	var pill := PanelContainer.new()
	var sb := panel(Color(TARMAC, 0.9), true, GREEN, 4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(pill)
	var c := label(money(credits), 30, PAPER, "extrabold", true)
	pill.add_child(c)
	return [bar, c]


## A big menu tile: title, a line under it, the whole thing tappable.
static func tile(title: String, sub: String, cb: Callable, primary := false, size := 40) -> Button:
	var b := button("", cb, primary, size)
	b.custom_minimum_size = Vector2(0, 96)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 30
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.add_child(label(title, size, INK if primary else PAPER, "extrabold", true))
	var s := label(sub, 19, Color(INK, 0.75) if primary else FOG, "semibold", true)
	s.name = "Sub"
	v.add_child(s)
	return b


## Three-letter timing code from a driver name ("L. Novak" -> "NOV").
static func code(name: String) -> String:
	var parts := name.split(" ")
	var last: String = parts[parts.size() - 1]
	return last.substr(0, 3).to_upper()


static func fmt_time(seconds: float) -> String:
	if seconds < 0.0:
		return "-:--.---"
	var ms := int(round(seconds * 1000.0))
	return "%d:%02d.%03d" % [ms / 60000, (ms / 1000) % 60, ms % 1000]
