extends Node3D
## Garage: every car on the left (all of them are yours to drive), the
## selected car on the turntable, and on the right how it performs, where
## it races, and buttons to make it your home car or take it for a drive.

var save: Node
var room: Showroom
var ui: CanvasLayer
var car_id := ""
var _list: VBoxContainer
var _panel: VBoxContainer
var _tick := 0.0


func _ready() -> void:
	UIStyle.use_menus()
	save = get_node("/root/Save")
	room = Showroom.new()
	add_child(room)
	room.build(Vector3(5.2, 1.7, 6.0), Vector3(0.2, 0.25, -0.4), 38.0)
	car_id = String(save.get_setting("garage_car"))
	if not CarSpecs.is_known(car_id):
		car_id = Garage.STARTER
	_build_ui()
	UIStyle.reveal_boards.call_deferred(self)
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
	var head: Array = UIStyle.header("Garage", func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"), "%d stars" % Career.total_stars(save))
	v.add_child(head[0])
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
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.92), false)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(500, 0)
	body.add_child(panel)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	panel.add_child(_panel)


func _select(id: String) -> void:
	car_id = id
	room.show_spec(save.car_spec(id, int(save.get_setting("team")) if CarSpecs.has_teams(id) else 0))
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for c in _panel.get_children():
		c.queue_free()
	if CarSpecs.CATALOG.size() == 1:
		_team_list()
		_build_panel()
		return
	var ids: Array = Array(CarSpecs.CATALOG).duplicate()
	ids.sort_custom(func(x, y): return Garage.pr(CarSpecs.get_spec(x)) < Garage.pr(CarSpecs.get_spec(y)))
	ids.append_array(CarSpecs.BOATS)
	var team := int(save.get_setting("team"))
	for id in ids:
		var spec: Dictionary = save.car_spec(id)
		# The class first (the ladder: Karting, F4, F3, F2, Grand Prix), the
		# car under it; edged in your team's colour in that class.
		var si := Career.series_for_car(id)
		var title: String = String(Career.SERIES[si]["name"]) if si >= 0 else String(spec.get("series", spec["name"]))
		var sub := "%s, PR %.1f" % [spec["name"], Garage.pr(spec)]
		if String(save.get_setting("garage_car")) == id:
			sub += ", home car"
		var b := UIStyle.tile(title, sub, func(): _select(id), id == car_id, 30)
		b.custom_minimum_size = Vector2(0, 66)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if CarSpecs.has_teams(id):
			var tc: Color = CarSpecs.team(team, id)["base"]
			for st in ["normal", "hover", "pressed", "focus"]:
				var sb0 := b.get_theme_stylebox(st)
				if sb0 is StyleBoxFlat:
					var sbx := (sb0 as StyleBoxFlat).duplicate() as StyleBoxFlat
					sbx.border_color = tc
					sbx.border_width_left = 8
					b.add_theme_stylebox_override(st, sbx)
		_list.add_child(b)
	_build_panel()


## One car (Grand Prix only, for now): the list is the ten teams instead,
## each in its livery colour; tap one to race in its colours.
func _team_list() -> void:
	_list.add_child(UIStyle.label("Teams", 20, UIStyle.PAPER, "display"))
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_child(grid)
	var cur := int(save.get_setting("team"))
	var teams: Array = CarSpecs.teams_for(car_id)
	for i in teams.size():
		var t: Dictionary = teams[i]
		var k: int = i
		var b := UIStyle.button(String(t["name"]), func():
			save.set_setting("team", k)
			_select(car_id), k == cur, 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(300, 44)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for st in ["normal", "hover", "pressed"]:
			var sb := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
			sb.border_color = t["base"]
			sb.border_width_left = 8
			sb.content_margin_left = 16
			b.add_theme_stylebox_override(st, sb)
		grid.add_child(b)


## The team you race for in this class: its name, and the ten teams as
## colour swatches (their livery: base, a stripe of the accent); tap one.
func _team_swatches() -> void:
	var cur := posmod(int(save.get_setting("team")), CarSpecs.teams_for(car_id).size())
	var teams: Array = CarSpecs.teams_for(car_id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_panel.add_child(head)
	head.add_child(UIStyle.label("Team", 19, UIStyle.FOG, "bold"))
	head.add_child(UIStyle.label(String(teams[cur]["name"]), 21, UIStyle.PAPER, "bold"))
	# The team's title sponsor and main partner, as they appear on the car.
	var deal := Sponsors.team_deal(String(teams[cur].get("id", "")), cur, car_id)
	var backers := HBoxContainer.new()
	backers.add_theme_constant_override("separation", 8)
	_panel.add_child(backers)
	backers.add_child(UIStyle.label("Backed by", 17, UIStyle.FOG, "medium"))
	for k in 2:
		var logo := TextureRect.new()
		logo.texture = Sponsors.sticker(String(deal[k]))
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(124, 31)
		logo.tooltip_text = String(Sponsors.brand(String(deal[k]))["name"]).capitalize()
		backers.add_child(logo)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_panel.add_child(grid)
	for i in teams.size():
		var t: Dictionary = teams[i]
		var k: int = i
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(t["name"])
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = t["base"]
			sb.border_color = t["accent"]
			sb.border_width_bottom = 8
			if k == cur:
				sb.border_color = UIStyle.PAPER
				sb.set_border_width_all(4)
				sb.border_width_bottom = 8
			sb.set_corner_radius_all(3)
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			save.set_setting("team", k)
			_select(car_id))
		grid.add_child(b)


func _build_panel() -> void:
	var spec: Dictionary = save.car_spec(car_id)
	var top := HBoxContainer.new()
	_panel.add_child(top)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", -4)
	top.add_child(names)
	var parts: PackedStringArray = String(spec["desc"]).split(" · ")
	names.add_child(UIStyle.label(parts[0] if parts.size() > 0 else "", 19, UIStyle.FOG, "bold", true))
	names.add_child(UIStyle.label(String(spec["name"]), 26, UIStyle.PAPER, "display"))
	var prbox := VBoxContainer.new()
	prbox.add_theme_constant_override("separation", -8)
	top.add_child(prbox)
	prbox.add_child(UIStyle.label("PR", 18, UIStyle.FOG, "bold", true))
	prbox.add_child(UIStyle.label("%.1f" % Garage.pr(spec), 32, UIStyle.PAPER, "display"))

	# How it performs.
	var v := 55.6
	var grip: float = float(spec["mu_front"]) * (1.0 + float(spec["downforce"]) * v * v / float(spec["mass"]) / 9.81)
	var brake: float = float(spec["brake_base"]) + float(spec["brake_aero"]) * v * v
	var top_kmh := Garage.top_speed_kmh(spec)
	_stat("Power", "%d hp" % (int(round(float(spec["power"]) / 745.7 / 10.0)) * 10), float(spec["power"]) / 1.1e6)
	_stat("Weight", "%d kg" % int(float(spec["mass"])), 1.0 - float(spec["mass"]) / 1000.0)
	_stat("Top speed", "%d km/h" % int(top_kmh), (top_kmh - 80.0) / 300.0)
	_stat("Grip at 200", "%.1f g" % grip, grip / 4.5)
	_stat("Braking", "%.1f g" % (minf(brake, float(spec["brake_max"])) / 9.81), minf(brake, float(spec["brake_max"])) / 30.0)
	var series: Array = []
	for se in Career.SERIES:
		if (se["cars"] as Array).has(car_id):
			series.append(String(se["name"]))
	var si := Career.series_for_car(car_id)
	if si >= 0:
		var l := UIStyle.label(String(Career.SERIES[si].get("blurb", "")), 19, UIStyle.FOG, "semibold")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel.add_child(l)
	elif not series.is_empty():
		var l := UIStyle.label("Races in: " + ", ".join(series), 19, UIStyle.FOG, "semibold")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel.add_child(l)
	if CarSpecs.has_teams(car_id):
		_team_swatches()
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(sp)

	# Make it yours: paint and setup.
	var mods := HBoxContainer.new()
	mods.add_theme_constant_override("separation", 10)
	_panel.add_child(mods)
	var mod_list: Array = [["Paint", "res://scenes/paint.tscn"]]
	if not CarSpecs.is_boat(car_id):
		mod_list.append(["Setup", "res://scenes/setup.tscn"])          # (boats: no setup to change)
	for m in mod_list:
		var scene: String = m[1]
		var mb := UIStyle.button(String(m[0]), func():
			save.set_setting("paint_car", car_id)
			get_tree().change_scene_to_file(scene), false, 24)
		mb.custom_minimum_size = Vector2(0, 64)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mods.add_child(mb)
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
	hb.visible = CarSpecs.CATALOG.size() > 1
	row.add_child(hb)
	var drive := UIStyle.go_button("Drive it", func():
		save.set_setting("car", car_id)
		get_tree().change_scene_to_file("res://scenes/menu.tscn"), 34)
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
	back.color = UIStyle.TARMAC_2
	back.custom_minimum_size = Vector2(0, 10)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(back)
	var fill := ColorRect.new()
	fill.color = UIStyle.PAPER
	back.add_child(fill)
	back.resized.connect(func(): fill.size = Vector2(back.size.x * clampf(frac, 0.04, 1.0), 10))
	var val := UIStyle.label(value, 21, UIStyle.PAPER, "bold", true)
	val.custom_minimum_size = Vector2(104, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
