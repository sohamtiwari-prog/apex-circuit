extends Node3D
## Main menu: the selected car on a turntable, car and track pickers,
## best lap for the combination, and a button to start the session.

var save: Node
var showcase: Node3D
var preview: RaceCar
var ui: CanvasLayer
var car_buttons := {}
var track_buttons := {}
var best_label: Label
var info_label: Label


func _ready() -> void:
	save = get_node("/root/Save")
	DisplayServer.screen_set_keep_on(true)
	_build_stage()
	_build_ui()
	_select_car(String(save.get_setting("car")), false)
	_select_track(String(save.get_setting("track")), false)


# ------------------------------------------------------------ 3D stage

func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 30, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-4, 3, -4)
	rim.light_color = Color(1.0, 0.55, 0.2)
	rim.light_energy = 3.0
	rim.omni_range = 12.0
	add_child(rim)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 4.2
	floor_mesh.bottom_radius = 4.4
	floor_mesh.height = 0.1
	floor_mesh.radial_segments = 64
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.13, 0.15)
	floor_mat.metallic = 0.6
	floor_mat.roughness = 0.25
	var stage := MeshInstance3D.new()
	stage.mesh = floor_mesh
	stage.material_override = floor_mat
	stage.position.y = -0.05
	add_child(stage)

	showcase = Node3D.new()
	add_child(showcase)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(5.2, 1.7, 5.6)
	add_child(cam)
	cam.look_at(Vector3(-1.4, 0.2, 0), Vector3.UP)
	cam.current = true


func _show_car(id: String) -> void:
	if preview != null:
		preview.queue_free()
	preview = RaceCar.new()
	preview.setup(CarSpecs.get_spec(id))
	preview.freeze = true
	showcase.add_child(preview)
	preview.position.y = preview.spawn_height() - 0.05


func _process(delta: float) -> void:
	showcase.rotate_y(delta * 0.35)


# ------------------------------------------------------------ UI

func _label(text: String, size: int, parent: Node, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(16)
	return sb


func _card(title: String, sub: String, parent: Node, cb: Callable) -> Button:
	var b := Button.new()
	b.text = title + "\n" + sub
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 96)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _set_selected(b: Button, on: bool) -> void:
	var normal := _style(Color(0.08, 0.09, 0.12, 0.88), Color(1.0, 0.42, 0.1) if on else Color(1, 1, 1, 0.12))
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, normal)


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
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cols)

	# Left column: title + selections.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	var title := _label("APEX CIRCUIT", 54, left, Color(1.0, 0.45, 0.12))
	title.add_theme_constant_override("outline_size", 0)
	_label("CAR", 20, left, Color(1, 1, 1, 0.55))
	for id in CarSpecs.CATALOG:
		var spec := CarSpecs.get_spec(id)
		var cid: String = id
		car_buttons[id] = _card(spec["name"], spec["desc"], left, func(): _select_car(cid, true))
	_label("TRACK", 20, left, Color(1, 1, 1, 0.55))
	for t in Track.CATALOG:
		var tid: String = t["id"]
		track_buttons[tid] = _card(t["name"], t["desc"], left, func(): _select_track(tid, true))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(spacer)

	# Right column: session info + race button, bottom-aligned.
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.custom_minimum_size = Vector2(360, 0)
	right.add_theme_constant_override("separation", 12)
	cols.add_child(right)
	info_label = _label("", 22, right, Color(1, 1, 1, 0.8))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_label = _label("", 30, right)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var race := Button.new()
	race.text = "RACE"
	race.focus_mode = Control.FOCUS_NONE
	race.custom_minimum_size = Vector2(360, 110)
	race.add_theme_font_size_override("font_size", 44)
	var sb := _style(Color(1.0, 0.42, 0.1), Color(1.0, 0.6, 0.3))
	race.add_theme_stylebox_override("normal", sb)
	race.add_theme_stylebox_override("hover", sb)
	var sbp := _style(Color(0.85, 0.32, 0.05), Color(1.0, 0.6, 0.3))
	race.add_theme_stylebox_override("pressed", sbp)
	race.pressed.connect(_start)
	right.add_child(race)


func _select_car(id: String, persist: bool) -> void:
	if not car_buttons.has(id):
		id = CarSpecs.CATALOG[0]
	for k in car_buttons:
		_set_selected(car_buttons[k], k == id)
	if persist:
		save.set_setting("car", id)
	_show_car(id)
	_refresh_info()


func _select_track(id: String, persist: bool) -> void:
	if not track_buttons.has(id):
		id = Track.CATALOG[0]["id"]
	for k in track_buttons:
		_set_selected(track_buttons[k], k == id)
	if persist:
		save.set_setting("track", id)
	_refresh_info()


func _refresh_info() -> void:
	if best_label == null:
		return
	var car_id := String(save.get_setting("car"))
	var track_id := String(save.get_setting("track"))
	info_label.text = "%s\n%s" % [CarSpecs.display_name(car_id), Track.catalog_name(track_id)]
	var best: int = save.get_best_lap(save.lap_key(track_id, car_id))
	best_label.text = "BEST LAP  " + (Hud.fmt_time(best / 1000.0) if best >= 0 else "--:--.---")


func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/race.tscn")
