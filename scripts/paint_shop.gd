extends Node3D
## Paint shop: your own livery for each car. Body, accent and stripe
## colours, the helmet (Grand Prix car), a pattern and your race number;
## the car on the turntable changes as you tap. Saved per car
## (save.set_paint) and used wherever you drive it, friends' phones too
## (the lobby sends it with your car).

const PALETTE := [
	"#ff7310", "#e01a1a", "#9e0b2a", "#ffd919", "#b8f22e", "#18a84a", "#0b5c45", "#14b8b0",
	"#38b6ff", "#1f5cd6", "#121c4a", "#6b2ccf", "#ff5fb0", "#f2f2f2", "#a9adb5", "#14181f",
	"#c9a227", "#5a3b22",
]
const PATTERNS := [["classic", "Classic"], ["stripes", "Twin stripes"], ["split", "Two-tone"],
	["carbon", "Carbon"], ["chequer", "Chequered"]]
const LOCKED_PATTERNS := {"carbon": "carbon", "chequer": "chequer"}     # pattern -> career reward

var save: Node
var room: Showroom
var car_id := ""
var _panel: VBoxContainer
var _title: Label


func _ready() -> void:
	UIStyle.use_menus()
	save = get_node("/root/Save")
	room = Showroom.new()
	add_child(room)
	room.build(Vector3(5.2, 1.7, 6.0), Vector3(0.2, 0.25, -0.4), 38.0)
	car_id = String(save.get_setting("paint_car"))
	if not CarSpecs.CATALOG.has(car_id):
		car_id = String(save.get_setting("garage_car"))
	if not CarSpecs.CATALOG.has(car_id):
		car_id = Garage.STARTER
	_build_ui()
	UIStyle.reveal_boards.call_deferred(self)
	_select(car_id)


## Your paint for this car, or a starting point: the car's own colours.
func paint() -> Dictionary:
	var p: Dictionary = save.my_paint(car_id).duplicate()
	if p.is_empty():
		var s := CarSpecs.get_spec(car_id, int(save.get_setting("team")) if car_id == "gp26" else 0)
		if s["body"] == "gp":
			var lv: Dictionary = s["livery"]
			p = {"base": Color(lv["base"]).to_html(false), "accent": Color(lv["accent"]).to_html(false),
				"stripe": Color(lv["stripe"]).to_html(false), "helmet": Color(lv["helmet"]).to_html(false)}
		else:
			p = {"base": Color(s["color"]).to_html(false), "accent": Color(s.get("accent", Color.BLACK)).to_html(false),
				"stripe": "#f2f2f2", "helmet": "#f2f2f2"}
		p["pattern"] = "classic"
		p["number"] = 26
		p["on"] = false
	return p


func set_value(key: String, value: Variant) -> void:
	var p := paint()
	p[key] = value
	if key != "on":
		p["on"] = true                   # (changing anything puts it on)
	save.set_paint(car_id, p)
	_show()


func _select(id: String) -> void:
	car_id = id
	_show()


func _show() -> void:
	room.show_spec(save.car_spec(car_id, int(save.get_setting("team")) if car_id == "gp26" else 0))
	_refresh()


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)
	var head: Array = UIStyle.header("Paint shop", func(): get_tree().change_scene_to_file("res://scenes/garage.tscn"))
	v.add_child(head[0])
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(left)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(sp)
	var cars := HBoxContainer.new()
	cars.add_theme_constant_override("separation", 10)
	left.add_child(cars)
	for d in [-1, 1]:
		var dd: int = d
		var b := UIStyle.button("‹" if d < 0 else "›", func(): _step_car(dd), false, 44)
		b.custom_minimum_size = Vector2(76, 64)
		cars.add_child(b)
	_title = UIStyle.label("", 26, UIStyle.PAPER, "display")
	cars.add_child(_title)
	var panel := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.93), false)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(600, 0)
	body.add_child(panel)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	panel.add_child(_panel)


func _step_car(d: int) -> void:
	var ids: Array = Array(CarSpecs.CATALOG)
	_select(ids[posmod(ids.find(car_id) + d, ids.size())])


func _refresh() -> void:
	for c in _panel.get_children():
		c.queue_free()
	var p := paint()
	var gp := String(CarSpecs.get_spec(car_id)["body"]) == "gp"
	_title.text = CarSpecs.display_name(car_id)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_panel.add_child(top)
	for opt in [[false, "Team colours" if gp else "Factory paint"], [true, "My paint"]]:
		var on: bool = opt[0]
		var b := UIStyle.button(String(opt[1]), func(): set_value("on", on), bool(p.get("on", false)) == on, 22)
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(b)
	_swatches("Body", "base", p)
	_swatches("Accent", "accent", p)
	_swatches("Stripes", "stripe", p)
	if gp:
		_swatches("Helmet", "helmet", p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_panel.add_child(row)
	var have: Array = Career.rewards_unlocked(save)
	for pt in PATTERNS:
		var key: String = pt[0]
		var locked: bool = LOCKED_PATTERNS.has(key) and not have.has(String(LOCKED_PATTERNS[key]))
		var b := UIStyle.button(String(pt[1]), func(): set_value("pattern", key), String(p.get("pattern", "classic")) == key, 18)
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if locked:
			b.disabled = true
			b.text = "%s  %d★" % [String(pt[1]), _stars_for(String(LOCKED_PATTERNS[key]))]
		row.add_child(b)
	if gp:
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 10)
		_panel.add_child(nr)
		var nl := UIStyle.label("Race number", 22, UIStyle.FOG, "bold", true)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nr.add_child(nl)
		var n := int(p.get("number", 26))
		for d in [-10, -1]:
			var dd: int = d
			var b := UIStyle.button(str(d), func(): set_value("number", clampi(n + dd, 1, 99)), false, 22)
			b.custom_minimum_size = Vector2(64, 50)
			nr.add_child(b)
		var nv := UIStyle.label(str(n), 30, UIStyle.PAPER, "display")
		nv.custom_minimum_size = Vector2(70, 0)
		nv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nr.add_child(nv)
		for d in [1, 10]:
			var dd: int = d
			var b := UIStyle.button("+%d" % d, func(): set_value("number", clampi(n + dd, 1, 99)), false, 22)
			b.custom_minimum_size = Vector2(64, 50)
			nr.add_child(b)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(sp)
	var go := UIStyle.button("Drive it", func():
		save.set_setting("car", car_id)
		get_tree().change_scene_to_file("res://scenes/menu.tscn"), true, 30)
	UIStyle.make_go(go, 30)
	go.custom_minimum_size = Vector2(0, 70)
	_panel.add_child(go)


func _stars_for(reward: String) -> int:
	for r in Career.REWARDS:
		if String(r[1]) == reward:
			return int(r[0])
	return 0


## A row of colour swatches for one part of the paint.
func _swatches(title: String, key: String, p: Dictionary) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	_panel.add_child(h)
	var l := UIStyle.label(title, 20, UIStyle.FOG, "bold", true)
	l.custom_minimum_size = Vector2(86, 0)
	h.add_child(l)
	var cur := String(p.get(key, "")).trim_prefix("#").to_lower()
	var colours: Array = PALETTE.duplicate()
	for r in Career.rewards_unlocked(save):
		colours.append_array(Career.REWARD_COLOURS.get(r, []))
	for hex in colours:
		var col := Color.html(hex)
		var chosen: bool = hex.trim_prefix("#").to_lower() == cur.substr(0, 6)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(26, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sbx := UIStyle.panel(col, false, Color(0, 0, 0, 0), 4)
		sbx.border_color = UIStyle.PAPER if chosen else Color(1, 1, 1, 0.22)
		sbx.set_border_width_all(4 if chosen else 1)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sbx)
		var hh: String = hex
		b.pressed.connect(func(): set_value(key, hh))
		h.add_child(b)
