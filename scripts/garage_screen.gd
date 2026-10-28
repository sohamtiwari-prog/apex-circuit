extends Node3D
## Garage: every car (yours with their PR, the rest with prices) on the
## left, the selected car on the turntable, and on the right how it
## performs, where it races, and Buy (or make it the car on your home
## screen, or take it for a drive).

var save: Node
var room: Showroom
var ui: CanvasLayer
var car_id := ""
var _credits: Label
var _list: VBoxContainer
var _panel: VBoxContainer
var _tick := 0.0


func _ready() -> void:
	save = get_node("/root/Save")
	room = Showroom.new()
	add_child(room)
	room.build(Vector3(5.2, 1.7, 6.0), Vector3(0.2, 0.25, -0.4), 38.0)
	car_id = String(save.get_setting("garage_car"))
	if not CarSpecs.CATALOG.has(car_id):
		car_id = Garage.STARTER
	_build_ui()
	_select(car_id)


func _build_ui() -> void:
	ui = CanvasLayer.new()
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
	var head: Array = UIStyle.header("Garage", func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"), save.credits())
	v.add_child(head[0])
	_credits = head[1]
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(320, 0)
	_list.add_theme_constant_override("separation", 6)
	body.add_child(_list)
	var mid := Control.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(mid)
	var panel := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.92), false, UIStyle.APEX, 8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(500, 0)
	body.add_child(panel)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	panel.add_child(_panel)


func _select(id: String) -> void:
	car_id = id
	if save.owns(id):
		save.set_setting("garage_car", id)
	room.show_spec(save.car_spec(id))
	_refresh()


func _refresh() -> void:
	_credits.text = UIStyle.money(save.credits())
	for c in _list.get_children():
		c.queue_free()
	for c in _panel.get_children():
		c.queue_free()
	var ids: Array = Array(CarSpecs.CATALOG).duplicate()
	ids.sort_custom(func(x, y): return Garage.price(x) < Garage.price(y))
	for id in ids:
		var spec: Dictionary = save.car_spec(id)
		var owned: bool = save.owns(id)
		var sub := ("PR %.1f" % Garage.pr(spec)) if owned else UIStyle.money(Garage.price(id))
		if owned and String(save.get_setting("garage_car")) == id:
			sub += "  ·  home car"
		var b := UIStyle.tile(String(spec["name"]), sub, func(): _select(id), id == car_id, 24)
		b.custom_minimum_size = Vector2(0, 66)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if not owned and id != car_id:
			b.modulate.a = 0.75
		_list.add_child(b)
	_build_panel()


func _build_panel() -> void:
	var spec: Dictionary = save.car_spec(car_id)
	var owned: bool = save.owns(car_id)
	var top := HBoxContainer.new()
	_panel.add_child(top)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", -4)
	top.add_child(names)
	var parts: PackedStringArray = String(spec["desc"]).split(" · ")
	names.add_child(UIStyle.label(parts[0] if parts.size() > 0 else "", 19, UIStyle.FOG, "bold", true))
	names.add_child(UIStyle.label(String(spec["name"]), 34, UIStyle.PAPER, "extrabold", true))
	var prbox := VBoxContainer.new()
	prbox.add_theme_constant_override("separation", -8)
	top.add_child(prbox)
	prbox.add_child(UIStyle.label("PR", 18, UIStyle.FOG, "bold", true))
	prbox.add_child(UIStyle.label("%.1f" % Garage.pr(spec), 44, UIStyle.APEX, "extrabold", true))

	# How it performs.
	var v := 55.6
	var grip: float = float(spec["mu_front"]) * (1.0 + float(spec["downforce"]) * v * v / float(spec["mass"]) / 9.81)
	var brake: float = float(spec["brake_base"]) + float(spec["brake_aero"]) * v * v
	var top_kmh := Garage.top_speed_kmh(spec)
	_stat("Power", "%d hp" % (int(round(float(spec["power"]) / 745.7 / 10.0)) * 10), float(spec["power"]) / 1.1e6)
	_stat("Weight", "%d kg" % int(float(spec["mass"])), 1.0 - (float(spec["mass"]) - 700.0) / 1500.0)
	_stat("Top speed", "%d km/h" % int(top_kmh), (top_kmh - 200.0) / 220.0)
	_stat("Grip at 200", "%.1f g" % grip, grip / 4.5)
	_stat("Braking", "%.1f g" % (minf(brake, float(spec["brake_max"])) / 9.81), minf(brake, float(spec["brake_max"])) / 30.0)
	var series: Array = []
	for se in Career.SERIES:
		if (se["cars"] as Array).has(car_id):
			series.append(String(se["name"]))
	if not series.is_empty():
		var l := UIStyle.label("Races in: " + ", ".join(series), 19, UIStyle.FOG, "semibold")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel.add_child(l)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(sp)

	if not owned:
		var price := Garage.price(car_id)
		var can: bool = save.credits() >= price
		var b := UIStyle.button(("Buy  ·  " + UIStyle.money(price)) if can else ("Need %s more" % UIStyle.money(price - save.credits())), func():
			if save.buy_car(car_id):
				_select(car_id), can, 32)
		b.disabled = not can
		b.custom_minimum_size = Vector2(0, 80)
		_panel.add_child(b)
		_panel.add_child(UIStyle.label("You can still test-drive it in Quick race.", 18, UIStyle.FOG, "medium"))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	var home: bool = String(save.get_setting("garage_car")) == car_id
	var hb := UIStyle.button("Your home car" if home else "Show at home", func():
		save.set_setting("garage_car", car_id)
		_refresh(), false, 24)
	hb.disabled = home
	hb.custom_minimum_size = Vector2(0, 76)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hb)
	var drive := UIStyle.button("Drive it", func():
		save.set_setting("car", car_id)
		get_tree().change_scene_to_file("res://scenes/menu.tscn"), true, 30)
	drive.custom_minimum_size = Vector2(0, 76)
	drive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(drive)


func _stat(name: String, value: String, frac: float) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_panel.add_child(h)
	var n := UIStyle.label(name, 20, UIStyle.FOG, "semibold")
	n.custom_minimum_size = Vector2(118, 0)
	h.add_child(n)
	var back := ColorRect.new()
	back.color = Color(UIStyle.PAPER, 0.12)
	back.custom_minimum_size = Vector2(0, 8)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(back)
	var fill := ColorRect.new()
	fill.color = UIStyle.APEX
	back.add_child(fill)
	back.resized.connect(func(): fill.size = Vector2(back.size.x * clampf(frac, 0.04, 1.0), 8))
	var val := UIStyle.label(value, 21, UIStyle.PAPER, "bold", true)
	val.custom_minimum_size = Vector2(104, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
