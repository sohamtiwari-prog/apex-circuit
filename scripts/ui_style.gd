class_name UIStyle
extends RefCounted
## Shared look for every screen, in two materials from the paddock:
##
##   "garage"  the menus: a team garage in daylight. Flat white boards and
##             grey wells, black type, nothing slanted.
##   "board"   racing: pit boards. Solid black with white figures, readable
##             over a bright track at a glance.
##
## Colours carry meaning, the way flags do: green is go (the button that
## starts something), yellow is you and what you've picked, red is leave or
## stop; purple and green on lap times keep their timing meaning.
##
## Type: Archivo Expanded (wide, heavy) only for the few loudest things:
## screen titles, go buttons, your position. Barlow Semi Condensed for
## everything else, with tabular figures so timing digits don't jump.
##
## Each scene calls UIStyle.use("garage") or UIStyle.use("board") first.

# Role colours (set by use()): names kept from the first style so every
# screen's code still reads the same way.
static var TARMAC := Color("000000")     # board / panel
static var TARMAC_2 := Color("1b1e23")   # well, chip, secondary button
static var LINE := Color("3a3f46")       # rules, empty bars
static var PAPER := Color("ffffff")      # text on a board
static var FOG := Color("9ba3ad")        # quieter text on a board
static var APEX := Color("ffd200")       # you / selected (signal yellow)
static var INK := Color("000000")        # text on yellow
static var GO := Color("00b852")         # flag green: start something
static var GO_INK := Color("ffffff")
static var STOP := Color("e0281e")       # flag red: leave, abandon
# Timing colours.
static var PURPLE := Color("b45cff")     # fastest overall
static var GREEN := Color("2fd36f")      # personal best / improvement
static var YELLOW := Color("ff9f1a")     # slower / caution (amber, apart from your yellow)
static var RED := Color("ff4438")        # invalid / lights

## Pit-board black, whatever the theme (the stars board, the race clock).
const BLACK := Color("000000")
const SIGNAL := Color("ffd200")
## The garage floor's tone, for screens with no 3D room behind them.
const CONCRETE := Color("d3d7dc")

const SLANT := 0.0                 # (kept for old callers: nothing leans now)

static var theme := "board"
static var _fonts := {}

const THEMES := {
	"garage": {"TARMAC": "ffffff", "TARMAC_2": "e4e7ea", "LINE": "c7ccd2", "PAPER": "000000",
		"FOG": "5a6169", "APEX": "ffd200", "INK": "000000", "GO": "00a04a", "GO_INK": "ffffff",
		"STOP": "d4261c", "PURPLE": "7a2ed6", "GREEN": "0b9447", "YELLOW": "c27a00", "RED": "d4261c"},
	"board": {"TARMAC": "000000", "TARMAC_2": "1b1e23", "LINE": "3a3f46", "PAPER": "ffffff",
		"FOG": "9ba3ad", "APEX": "ffd200", "INK": "000000", "GO": "00b852", "GO_INK": "ffffff",
		"STOP": "e0281e", "PURPLE": "b45cff", "GREEN": "2fd36f", "YELLOW": "ff9f1a", "RED": "ff4438"},
}


static func use(name: String) -> void:
	theme = name
	var t: Dictionary = THEMES[name]
	TARMAC = Color(t["TARMAC"]); TARMAC_2 = Color(t["TARMAC_2"]); LINE = Color(t["LINE"])
	PAPER = Color(t["PAPER"]); FOG = Color(t["FOG"]); APEX = Color(t["APEX"]); INK = Color(t["INK"])
	GO = Color(t["GO"]); GO_INK = Color(t["GO_INK"]); STOP = Color(t["STOP"])
	PURPLE = Color(t["PURPLE"]); GREEN = Color(t["GREEN"]); YELLOW = Color(t["YELLOW"]); RED = Color(t["RED"])


static func light() -> bool:
	return theme == "garage"


## weight: "medium", "semibold", "bold", "extrabold" (Barlow Semi Condensed)
## or "display" (Archivo Expanded). `slanted` is ignored: nothing leans.
static func font(weight := "semibold", _slanted := false) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var v := FontVariation.new()
	if weight == "display":
		v.base_font = load("res://fonts/Archivo-Variable.ttf")
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800,
			TextServerManager.get_primary_interface().name_to_tag("wdth"): 125}
	else:
		var file: String = {"medium": "Medium", "semibold": "SemiBold", "bold": "Bold", "extrabold": "ExtraBold"}.get(weight, "SemiBold")
		v.base_font = load("res://fonts/BarlowSemiCondensed-%s.ttf" % file)
	v.opentype_features = {"tnum": 1}
	_fonts[weight] = v
	return v


## The lettering on the cars and around the circuits (numbers, signs): the
## old condensed face, part of the world rather than the interface.
static func world_font(weight := "bold", slanted := false) -> Font:
	var key := "world/" + weight + ("/s" if slanted else "")
	if _fonts.has(key):
		return _fonts[key]
	var file: String = {"medium": "Medium", "semibold": "SemiBold", "bold": "Bold", "extrabold": "ExtraBold"}[weight]
	var v := FontVariation.new()
	v.base_font = load("res://fonts/SairaCondensed-%s.ttf" % file)
	v.opentype_features = {"tnum": 1}
	if slanted:
		v.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.15, 1), Vector2.ZERO)
	_fonts[key] = v
	return v


## Barlow sets a touch wider than the old face: sizes asked for in the old
## scale come out a little smaller so layouts keep their widths.
static func px(size: int, weight := "semibold") -> int:
	return size if weight == "display" else int(round(size * 0.94))


static func label(text: String, size: int, color := PAPER, weight := "semibold", slanted := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, slanted))
	l.add_theme_font_size_override("font_size", px(size, weight))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Readable over a bright 3D scene without a panel behind it (on the black
## boards' side; in the garage the type is black on a light room already).
static func outlined(l: Label, px_size := 6) -> Label:
	if light():
		return l
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", px_size)
	return l


## A flat board. `edge` draws a coloured bar down the leading side (a team
## colour, a timing colour). Corners are barely rounded: cut sheet, not card.
static func panel(bg := Color(TARMAC, 0.9), _slant := true, edge := Color(0, 0, 0, 0), radius := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if light():
		sb.bg_color.a = maxf(bg.a, 0.96)     # (white boards are solid: milky glass reads as a mistake)
	sb.set_corner_radius_all(mini(radius, 3))
	if edge.a > 0.0:
		sb.border_color = edge
		sb.border_width_left = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.anti_aliasing = false
	return sb


## The selection mark: a grid box, as painted on a starting grid. A thick
## bar across the front and lines down both sides, open at the back.
static func grid_box(sb: StyleBoxFlat, colour := APEX) -> StyleBoxFlat:
	sb.border_color = colour
	sb.border_width_top = 7
	sb.border_width_left = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 0
	return sb


static func _button_styles(b: Button, fill: Color, text: Color, pressed_fill: Color, pressed_text: Color) -> void:
	var normal := panel(fill, false)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed_fill
	var off := normal.duplicate() as StyleBoxFlat
	off.bg_color = Color(fill, fill.a * 0.45)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", text)
	b.add_theme_color_override("font_hover_color", text)
	b.add_theme_color_override("font_pressed_color", pressed_text)
	b.add_theme_color_override("font_disabled_color", Color(text, 0.45))


## `primary` marks what is picked (yellow, black type); the rest sit in
## grey wells. The button that starts something is go_button().
static func button(text: String, cb: Callable, primary := false, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("bold"))
	b.add_theme_font_size_override("font_size", px(size, "bold"))
	if primary:
		_button_styles(b, APEX, INK, APEX.darkened(0.12), INK)
	else:
		_button_styles(b, Color(TARMAC_2, 0.96), PAPER, APEX, INK)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Flag green, wide heavy type: the one button on a screen that starts
## something (a race, a season, a game).
static func go_button(text: String, cb: Callable, size := 30) -> Button:
	var b := button(text, cb, false, size)
	b.add_theme_font_override("font", font("display"))
	b.add_theme_font_size_override("font_size", int(size * 0.72))
	_button_styles(b, GO, GO_INK, GO.darkened(0.18), GO_INK)
	return b


## Red: leave, abandon, quit.
static func stop_button(text: String, cb: Callable, size := 22) -> Button:
	var b := button(text, cb, false, size)
	var t := Color(TARMAC_2, 0.96)
	_button_styles(b, t, STOP, STOP, Color.WHITE)
	return b


## Restyle an existing button as the go button (screens that build theirs
## with button(..., true) for "start").
static func make_go(b: Button, size := 30) -> Button:
	b.add_theme_font_override("font", font("display"))
	b.add_theme_font_size_override("font_size", int(size * 0.72))
	_button_styles(b, GO, GO_INK, GO.darkened(0.18), GO_INK)
	return b


## Top bar for the menu screens: back, title, and the stars board on the
## right. Returns [bar, stars label].
static func header(title: String, on_back: Callable, pill_text := "") -> Array:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on_back.is_valid():
		bar.add_child(back_button(on_back))
	var t := outlined(label(title, 30, PAPER, "display"), 4)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(t)
	var pill := PanelContainer.new()
	var sb := panel(BLACK, false)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(pill)
	var c := label(pill_text, 28, SIGNAL, "extrabold")
	pill.visible = pill_text != ""
	pill.add_child(c)
	return [bar, c]


## Back: a solid square in the type colour (black in the garage).
static func back_button(cb: Callable) -> Button:
	var b := button("‹", cb, false, 50)
	_button_styles(b, PAPER, TARMAC, APEX, INK)
	b.custom_minimum_size = Vector2(72, 60)
	return b


## A big menu tile: a white board (yellow when it's the main way in) with
## the title in the wide face and one plain line under it.
static func tile(title: String, sub: String, cb: Callable, primary := false, size := 40) -> Button:
	var b := button("", cb, primary, size)
	if not primary:
		_button_styles(b, Color(TARMAC, 0.97), PAPER, APEX, INK)
	b.custom_minimum_size = Vector2(0, 96)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 24
	v.offset_right = -12
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.add_child(label(title, int(size * 0.62), INK if primary else PAPER, "display"))
	var s := label(sub, 20, Color(INK, 0.7) if primary else FOG, "semibold")
	s.name = "Sub"
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(s)
	return b


## A text field: a grey well with black type (white on the boards), a
## yellow underline while you type.
static func field(e: LineEdit) -> LineEdit:
	var sb := panel(Color(TARMAC_2, 1.0), false)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	var on := sb.duplicate() as StyleBoxFlat
	on.border_color = APEX.darkened(0.1) if light() else APEX
	on.border_width_bottom = 4
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", on)
	e.add_theme_stylebox_override("read_only", sb)
	e.add_theme_color_override("font_color", PAPER)
	e.add_theme_color_override("font_placeholder_color", Color(FOG, 0.8))
	e.add_theme_color_override("caret_color", PAPER)
	e.add_theme_color_override("selection_color", Color(APEX, 0.5))
	return e


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
