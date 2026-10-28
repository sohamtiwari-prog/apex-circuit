extends Node3D
## Quick race. Left: the car on a turntable, its name and how it performs,
## with arrows to change car (and team, for the GP car). Any car can be
## raced here. Right: the circuit
## map, race options and the Race button. Everything you choose is saved.

var save: Node
var showcase: Node3D
var preview: RaceCar
var ui: CanvasLayer

var car_ids: Array = []
var track_ids: Array = []
var _car_name: Label
var _car_kind: Label
var _car_count: Label
var _bars := {}                # stat -> [fill ColorRect, value Label]
var _team_row: HBoxContainer
var team_buttons: Array[Button] = []
var _team_name: Label
var _map: MiniMap
var _track_name: Label
var _track_meta: Label
var _track_tag: Label
var _track_count: Label
var best_label: Label
var _mode_buttons := {}
var _chips := {}
var _owned_lbl: Label


func _ready() -> void:
	save = get_node("/root/Save")
	DisplayServer.screen_set_keep_on(true)
	car_ids = Array(CarSpecs.CATALOG)
	for t in Track.CATALOG:
		track_ids.append(t["id"])
	_build_stage()
	_build_ui()
	_select_team(int(save.get_setting("team")), false)
	_select_car(String(save.get_setting("car")), false)
	_select_track(String(save.get_setting("track")), false)
	_refresh_mode()


# ------------------------------------------------------------ 3D stage

func _build_stage() -> void:
	Look.build(self, "studio")
	var rim := OmniLight3D.new()
	rim.position = Vector3(-4, 2.5, -3.5)
	rim.light_color = Color(0.75, 0.85, 1.0)
	rim.light_energy = 1.6
	rim.omni_range = 9.0
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(3, 3.5, 4)
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 1.6
	fill.omni_range = 12.0
	add_child(fill)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 4.0
	floor_mesh.bottom_radius = 4.2
	floor_mesh.height = 0.1
	floor_mesh.radial_segments = 72
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.1, 0.11, 0.13)
	floor_mat.metallic = 0.4
	floor_mat.roughness = 0.45
	var stage := MeshInstance3D.new()
	stage.mesh = floor_mesh
	stage.material_override = floor_mat
	stage.position.y = -0.05
	add_child(stage)
	# A thin orange ring around the turntable.
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 4.12
	ring_mesh.outer_radius = 4.2
	ring_mesh.rings = 72
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = UIStyle.APEX
	ring_mat.emission_enabled = true
	ring_mat.emission = UIStyle.APEX
	ring_mat.emission_energy_multiplier = 0.25
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_mat
	ring.position.y = 0.0
	add_child(ring)

	showcase = Node3D.new()
	add_child(showcase)

	var cam := Camera3D.new()
	cam.fov = 36.0
	cam.position = Vector3(5.6, 1.9, 6.4)
	add_child(cam)
	cam.look_at(Vector3(0.9, 0.15, -1.6), Vector3.UP)
	cam.current = true


func _show_car(id: String) -> void:
	if preview != null:
		preview.queue_free()
	preview = RaceCar.new()
	preview.setup(save.car_spec(id, int(save.get_setting("team")) if id == "gp26" else 0))
	preview.freeze = true
	showcase.add_child(preview)
	preview.position.y = preview.spawn_height() - 0.05


func _process(delta: float) -> void:
	showcase.rotate_y(delta * 0.3)


# ------------------------------------------------------------ UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cols)
	_build_car_side(cols)
	_build_track_side(cols)


func _build_car_side(cols: Control) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 2)
	cols.add_child(left)
	var head: Array = UIStyle.header("Quick race", func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"), save.credits())
	left.add_child(head[0])
	_owned_lbl = UIStyle.outlined(UIStyle.label("", 22, UIStyle.FOG, "bold", true), 4)
	left.add_child(_owned_lbl)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(sp)

	_car_kind = UIStyle.outlined(UIStyle.label("", 22, UIStyle.FOG, "bold", true), 4)
	left.add_child(_car_kind)
	_car_name = UIStyle.outlined(UIStyle.label("", 58, UIStyle.PAPER, "extrabold", true), 6)
	left.add_child(_car_name)

	var stats := PanelContainer.new()
	stats.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.78)))
	stats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stats.custom_minimum_size = Vector2(430, 0)
	left.add_child(stats)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 2)
	stats.add_child(sv)
	for stat in ["Power", "Grip", "Top speed"]:
		_stat_row(sv, stat)

	_team_row = HBoxContainer.new()
	_team_row.add_theme_constant_override("separation", 8)
	_team_name = UIStyle.outlined(UIStyle.label("", 20, UIStyle.PAPER, "semibold"), 4)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	left.add_child(gap)
	left.add_child(_team_name)
	left.add_child(_team_row)
	for i in range(CarSpecs.TEAMS.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(46, 46)
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func(): _select_team(idx, true))
		_team_row.add_child(b)
		team_buttons.append(b)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 10)
	left.add_child(gap2)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	left.add_child(nav)
	var prev := UIStyle.button("‹", func(): _step_car(-1), false, 64)
	prev.custom_minimum_size = Vector2(84, 66)
	nav.add_child(prev)
	var next := UIStyle.button("›", func(): _step_car(1), false, 64)
	next.custom_minimum_size = Vector2(84, 66)
	nav.add_child(next)
	_car_count = UIStyle.outlined(UIStyle.label("", 22, UIStyle.PAPER, "semibold"), 4)
	_car_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_car_count.size_flags_vertical = Control.SIZE_FILL
	nav.add_child(_car_count)


func _stat_row(parent: Node, stat: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var name := UIStyle.label(stat, 20, UIStyle.FOG, "semibold")
	name.custom_minimum_size = Vector2(92, 0)
	h.add_child(name)
	var track_bg := ColorRect.new()
	track_bg.color = Color(UIStyle.PAPER, 0.12)
	track_bg.custom_minimum_size = Vector2(200, 8)
	track_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(track_bg)
	var fill := ColorRect.new()
	fill.color = UIStyle.APEX
	fill.size = Vector2(0, 8)
	track_bg.add_child(fill)
	var val := UIStyle.label("", 20, UIStyle.PAPER, "bold", true)
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	_bars[stat] = [fill, val]


func _build_track_side(cols: Control) -> void:
	var right := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.88), false, UIStyle.APEX, 8)
	sb.set_content_margin_all(18)
	right.add_theme_stylebox_override("panel", sb)
	right.custom_minimum_size = Vector2(440, 0)
	cols.add_child(right)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	right.add_child(v)

	# Mode: a two-way switch.
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	v.add_child(modes)
	for m in [["race", "Race"], ["time_trial", "Time trial"], ["friends", "Friends"]]:
		var key: String = m[0]
		var b := UIStyle.button(m[1], func():
			if key == "friends":
				get_tree().change_scene_to_file("res://scenes/lobby.tscn")
				return
			save.set_setting("mode", key)
			_refresh_mode(), false, 22)
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(b)
		_mode_buttons[key] = b

	# Track: map, name, details, arrows.
	var head := HBoxContainer.new()
	v.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", -4)
	head.add_child(names)
	_track_name = UIStyle.label("", 30, UIStyle.PAPER, "extrabold", true)
	_track_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_track_name)
	_track_meta = UIStyle.label("", 20, UIStyle.FOG, "semibold")
	names.add_child(_track_meta)
	var prev := UIStyle.button("‹", func(): _step_track(-1), false, 56)
	prev.custom_minimum_size = Vector2(64, 60)
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(prev)
	var next := UIStyle.button("›", func(): _step_track(1), false, 56)
	next.custom_minimum_size = Vector2(64, 60)
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(next)

	_map = MiniMap.new()
	_map.show_panel = false
	_map.line_width = 5.0
	_map.custom_minimum_size = Vector2(0, 100)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_map)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	_track_tag = UIStyle.label("", 20, UIStyle.PAPER, "medium")
	_track_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_track_tag)
	_track_count = UIStyle.label("", 18, UIStyle.FOG, "semibold")
	foot.add_child(_track_count)

	best_label = UIStyle.label("", 22, UIStyle.PURPLE, "bold", true)
	v.add_child(best_label)

	# Race options as chips: tap to change.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	v.add_child(chips)
	_chip(chips, "laps", [[3, "3 laps"], [5, "5 laps"], [10, "10 laps"], [1, "1 lap"]])
	_chip(chips, "opponents", [[19, "20 cars"], [11, "12 cars"], [5, "6 cars"]])
	_chip(chips, "difficulty", [["medium", "Medium AI"], ["hard", "Hard AI"], ["easy", "Easy AI"]])
	var chips2 := HBoxContainer.new()
	chips2.add_theme_constant_override("separation", 8)
	v.add_child(chips2)
	_chip(chips2, "time_of_day", [["auto", "Track's own time"], ["day", "Daytime"], ["sunset", "Sunset"], ["night", "Night"]])
	_chip(chips2, "weather", [["dry", "Dry"], ["wet", "Rain"], ["changing", "Rain later"]])
	var chips3 := HBoxContainer.new()
	chips3.add_theme_constant_override("separation", 8)
	v.add_child(chips3)
	_chip(chips3, "qualifying", [[false, "No qualifying"], [true, "Qualifying"]])
	_chip(chips3, "tyres", [["medium", "Medium tyres"], ["soft", "Soft tyres"], ["hard", "Hard tyres"]])

	var go := UIStyle.button("Race", _start, true, 46)
	go.custom_minimum_size = Vector2(0, 90)
	v.add_child(go)
	_chips["go"] = go


## A chip that cycles through `choices` ([value, label] pairs) for a setting.
func _chip(parent: Node, key: String, choices: Array) -> void:
	var b := UIStyle.button("", func():
		var cur := str(save.get_setting(key))
		var i := 0
		for k in range(choices.size()):
			if str(choices[k][0]) == cur:
				i = k
		save.set_setting(key, choices[(i + 1) % choices.size()][0])
		_refresh_mode(), false, 20)
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_chips[key] = [b, choices]


func _refresh_mode() -> void:
	var mode := String(save.get_setting("mode"))
	for key in _mode_buttons:
		var b: Button = _mode_buttons[key]
		var on: bool = key == mode
		var sb := UIStyle.panel(UIStyle.PAPER if on else Color(UIStyle.TARMAC_2, 0.9))
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", UIStyle.INK if on else UIStyle.FOG)
		b.add_theme_color_override("font_hover_color", UIStyle.INK if on else UIStyle.FOG)
	for key in _chips:
		if key == "go":
			continue
		var b: Button = _chips[key][0]
		var choices: Array = _chips[key][1]
		var cur := str(save.get_setting(key))
		b.text = choices[0][1]
		for c in choices:
			if str(c[0]) == cur:
				b.text = c[1]
		b.visible = mode == "race" or key == "time_of_day"
	(_chips["go"] as Button).text = "Race" if mode == "race" else "Drive"


# ------------------------------------------------------------ selection

func _step_car(d: int) -> void:
	var i := car_ids.find(String(save.get_setting("car")))
	_select_car(car_ids[posmod(i + d, car_ids.size())], true)


func _step_track(d: int) -> void:
	var i := track_ids.find(String(save.get_setting("track")))
	_select_track(track_ids[posmod(i + d, track_ids.size())], true)


func _select_car(id: String, persist: bool) -> void:
	if not car_ids.has(id):
		id = car_ids[0]
	if persist:
		save.set_setting("car", id)
	_show_car(id)
	var spec: Dictionary = save.car_spec(id)
	_car_name.text = spec["name"]
	if save.owns(id):
		_owned_lbl.text = "Your car  ·  PR %.1f" % Garage.pr(spec)
		_owned_lbl.add_theme_color_override("font_color", UIStyle.GREEN)
	else:
		_owned_lbl.text = "Test drive  ·  PR %.1f  ·  buy it in the Garage" % Garage.pr(spec)
		_owned_lbl.add_theme_color_override("font_color", UIStyle.FOG)
	var parts: PackedStringArray = String(spec["desc"]).split(" · ")
	_car_kind.text = parts[0] if parts.size() > 0 else ""
	_car_count.text = "Car %d of %d" % [car_ids.find(id) + 1, car_ids.size()]
	# Performance: power-to-weight, cornering grip at 200 km/h, top speed.
	var pw: float = float(spec["power"]) / float(spec["mass"])            # W/kg
	var v := 55.6
	var grip: float = float(spec["mu_front"]) * (1.0 + float(spec["downforce"]) * v * v / float(spec["mass"]) / 9.81)
	var top: float = float(spec.get("top_kmh", 340.0))
	_set_bar("Power", pw / 950.0, "%d hp" % (int(round(float(spec["power"]) / 745.7 / 10.0)) * 10))
	_set_bar("Grip", grip / 4.5, "%.1f g" % grip)
	_set_bar("Top speed", (top - 200.0) / 220.0, "%d km/h" % int(top))
	var gp := id == "gp26"
	_team_row.visible = gp
	_team_name.visible = gp
	_refresh_info()


func _set_bar(stat: String, frac: float, text: String) -> void:
	var fill: ColorRect = _bars[stat][0]
	fill.size = Vector2(200.0 * clampf(frac, 0.04, 1.0), 8)
	(_bars[stat][1] as Label).text = text


func _select_team(i: int, persist: bool) -> void:
	i = posmod(i, CarSpecs.TEAMS.size())
	for k in range(team_buttons.size()):
		var t: Dictionary = CarSpecs.TEAMS[k]
		var sb := UIStyle.panel(t["base"], true, Color(0, 0, 0, 0), 4)
		sb.border_color = UIStyle.PAPER if k == i else Color(t["accent"], 0.9)
		sb.set_border_width_all(4 if k == i else 2)
		for st in ["normal", "hover", "pressed", "focus"]:
			team_buttons[k].add_theme_stylebox_override(st, sb)
	if persist:
		save.set_setting("team", i)
		_show_car(String(save.get_setting("car")))
	if _team_name != null:
		_team_name.text = String(CarSpecs.TEAMS[i]["name"])


func _select_track(id: String, persist: bool) -> void:
	if not track_ids.has(id):
		id = track_ids[0]
	if persist:
		save.set_setting("track", id)
	var entry := Track.catalog_entry(id)
	var pts := Track.outline(id)
	_map.set_points(pts)
	_track_name.text = entry["name"]
	var parts: PackedStringArray = String(entry["desc"]).split(" · ")
	_track_meta.text = "%s, %.2f km" % [parts[0], Track.outline_length(pts) / 1000.0] if parts.size() > 0 else ""
	var tag: String = parts[parts.size() - 1] if parts.size() > 1 else ""
	_track_tag.text = (tag.substr(0, 1).to_upper() + tag.substr(1)) if tag != "" else ""
	_track_count.text = "%d of %d" % [track_ids.find(id) + 1, track_ids.size()]
	_refresh_info()


func _refresh_info() -> void:
	if best_label == null:
		return
	var car_id := String(save.get_setting("car"))
	var track_id := String(save.get_setting("track"))
	var best: int = save.get_best_lap(save.lap_key(track_id, car_id))
	best_label.text = ("Your best lap here  " + UIStyle.fmt_time(best / 1000.0)) if best >= 0 else "No lap set with this car yet"
	best_label.add_theme_color_override("font_color", UIStyle.PURPLE if best >= 0 else UIStyle.FOG)


func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/race.tscn")
