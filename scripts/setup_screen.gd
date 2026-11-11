extends Node3D
## Car setup: wing, gearing, brake balance, handling balance and tyre
## pressure for each car, a step at a time either side of the car's own,
## with what each does and what it comes to (top speed, grip at 200 km/h).
## Saved per car (save.set_setup) and used wherever you drive it.

const ROWS := [
	["wing", "Wing", "More: grip in fast corners, less top speed. Less: the other way."],
	["gearing", "Gearing", "Longer: higher top speed, slower out of corners. Shorter: quicker pick-up."],
	["bias", "Brake balance", "More front: steady under braking. More rear: turns in better, locks the rears sooner."],
	["balance", "Handling", "Up: steadier (understeer). Down: the rear helps it turn (oversteer)."],
	["pressure", "Tyre pressure", "Lower: more grip, the tyres wear faster. Higher: less grip, they last."],
]

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


## The car's own setup values (bias from its spec).
func default_setup() -> Dictionary:
	var s := CarSpecs.get_spec(car_id)
	return {"wing": 0, "gearing": 0, "bias": int(round(float(s["brake_bias"]) * 100.0)), "balance": 0, "pressure": 0}


func setup() -> Dictionary:
	var st := default_setup()
	var mine: Dictionary = save.my_setup(car_id)
	for k in mine:
		st[k] = int(mine[k])
	return st


func step(key: String, d: int) -> void:
	var st := setup()
	var r: Array = CarSpecs.SETUP_RANGE[key]
	st[key] = clampi(int(st[key]) + d, int(r[0]), int(r[1]))
	save.set_setup(car_id, st)
	_refresh()


func _select(id: String) -> void:
	car_id = id
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
	var head: Array = UIStyle.header("Car setup", func(): get_tree().change_scene_to_file("res://scenes/garage.tscn"))
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
		var b := UIStyle.button("‹" if d < 0 else "›", func():
			var ids: Array = Array(CarSpecs.CATALOG)
			_select(ids[posmod(ids.find(car_id) + dd, ids.size())]), false, 44)
		b.custom_minimum_size = Vector2(76, 64)
		b.visible = CarSpecs.CATALOG.size() > 1
		cars.add_child(b)
	_title = UIStyle.label("", 26, UIStyle.PAPER, "display")
	cars.add_child(_title)
	var panel := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.93), false)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(640, 0)
	body.add_child(panel)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 4)
	panel.add_child(_panel)


func _refresh() -> void:
	for c in _panel.get_children():
		c.queue_free()
	_title.text = CarSpecs.display_name(car_id)
	var st := setup()
	var base := default_setup()
	for row in ROWS:
		var key: String = row[0]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		_panel.add_child(h)
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", -4)
		h.add_child(names)
		names.add_child(UIStyle.label(String(row[1]), 24, UIStyle.PAPER, "bold", true))
		var hint := UIStyle.label(String(row[2]), 15, UIStyle.FOG, "medium")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		names.add_child(hint)
		var minus := UIStyle.button("-", func(): step(key, -1), false, 30)
		minus.custom_minimum_size = Vector2(58, 52)
		h.add_child(minus)
		var val := int(st[key])
		var txt := ("%d%%" % val) if key == "bias" else ("%+d" % val if val != 0 else "0")
		var vl := UIStyle.label(txt, 28, UIStyle.PAPER if val != int(base[key]) else UIStyle.FOG, "extrabold", true)
		vl.custom_minimum_size = Vector2(76, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(vl)
		var plus := UIStyle.button("+", func(): step(key, 1), false, 30)
		plus.custom_minimum_size = Vector2(58, 52)
		h.add_child(plus)
	# What it comes to.
	var spec: Dictionary = save.car_spec(car_id)
	var stock := CarSpecs.get_spec(car_id)
	var out := HBoxContainer.new()
	out.add_theme_constant_override("separation", 20)
	_panel.add_child(out)
	out.add_child(UIStyle.label("Top speed  %d km/h" % int(top_speed(spec)), 22, UIStyle.PAPER, "bold", true))
	out.add_child(UIStyle.label("Grip at 200  %.2f g" % grip_200(spec), 22, UIStyle.PAPER, "bold", true))
	var d_top := top_speed(spec) - top_speed(stock)
	var d_grip := grip_200(spec) - grip_200(stock)
	var diff := UIStyle.label("(%+d km/h, %+.2f g on the car's own)" % [int(round(d_top)), d_grip], 18, UIStyle.FOG, "semibold")
	_panel.add_child(diff)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(sp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	var reset := UIStyle.button("Car's own setup", func():
		save.set_setup(car_id, {})
		_refresh(), false, 22)
	reset.custom_minimum_size = Vector2(0, 66)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset)
	var go := UIStyle.button("Drive it", func():
		save.set_setting("car", car_id)
		get_tree().change_scene_to_file("res://scenes/menu.tscn"), true, 28)
	UIStyle.make_go(go, 28)
	go.custom_minimum_size = Vector2(0, 66)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)


## Top speed: where power meets drag, or the top gear's limit.
static func top_speed(spec: Dictionary) -> float:
	var v_drag := pow(float(spec["power"]) / float(spec["drag"]), 1.0 / 3.0) * 0.98
	var gears: Array = spec["gears"]
	var v_gear := float(spec["redline"]) / 60.0 * TAU * float(spec["radius_rear"]) / float(gears[gears.size() - 1])
	return minf(v_drag, v_gear) * 3.6


static func grip_200(spec: Dictionary) -> float:
	var v := 55.6
	return float(spec["mu_front"]) * (1.0 + float(spec["downforce"]) * v * v / float(spec["mass"]) / 9.81)
