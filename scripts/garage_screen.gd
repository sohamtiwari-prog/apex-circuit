extends Node3D
## Garage: every car (yours with their PR, the rest with prices) on the
## left, the selected car on the turntable, and on the right either Buy or
## its five upgrades. An upgrade takes 30 s to 2 min (or finish it now for
## a small fee) and you can race other cars meanwhile.

var save: Node
var room: Showroom
var ui: CanvasLayer
var car_id := ""
var _credits: Label
var _list: VBoxContainer
var _panel: VBoxContainer
var _timers: Array = []               # [part, label, bar, rush button]
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
	_timers.clear()
	var ids: Array = Array(CarSpecs.CATALOG).duplicate()
	ids.sort_custom(func(x, y): return Garage.price(x) < Garage.price(y))
	for id in ids:
		var spec: Dictionary = save.car_spec(id)
		var owned: bool = save.owns(id)
		var sub := ("PR %.1f" % Garage.pr(spec)) if owned else UIStyle.money(Garage.price(id))
		if owned and not save.upgrade_job(id).is_empty():
			sub += "  ·  upgrading"
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
	_panel.add_child(UIStyle.label("%d hp  ·  %d kg  ·  %d km/h" % [int(round(float(spec["power"]) / 745.7)), int(float(spec["mass"])), int(Garage.top_speed_kmh(spec))], 20, UIStyle.PAPER, "semibold"))

	if not owned:
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel.add_child(sp)
		var series: Array = []
		for s in Career.SERIES:
			if (s["cars"] as Array).has(car_id):
				series.append(String(s["name"]))
		if not series.is_empty():
			var l := UIStyle.label("Races in: " + ", ".join(series), 19, UIStyle.FOG, "semibold")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_panel.add_child(l)
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

	_panel.add_child(UIStyle.label("Upgrades", 24, UIStyle.FOG, "bold", true))
	var levels: Dictionary = save.upgrade_levels(car_id)
	for p in Garage.PARTS:
		_part_row(p, int(levels.get(p, 0)), save.part_job(car_id, p))


func _part_row(part: String, level: int, job: Dictionary) -> void:
	var row := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC_2, 0.9), false)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(names)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	names.add_child(title)
	title.add_child(UIStyle.label(Garage.PART_NAMES[part], 24, UIStyle.PAPER, "extrabold", true))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(pips)
	for k in Garage.MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(22, 9)
		pip.color = UIStyle.APEX if k < level else Color(UIStyle.PAPER, 0.18)
		pips.add_child(pip)
	if not job.is_empty():
		var lbl := UIStyle.label("", 18, UIStyle.YELLOW, "bold", true)
		names.add_child(lbl)
		var back := ColorRect.new()
		back.color = Color(UIStyle.PAPER, 0.15)
		back.custom_minimum_size = Vector2(0, 6)
		names.add_child(back)
		var bar := ColorRect.new()
		bar.color = UIStyle.YELLOW
		bar.size = Vector2(0, 6)
		back.add_child(bar)
		var rush := UIStyle.button("", func():
			if save.rush_upgrade(car_id, part):
				_select(car_id), true, 20)
		rush.custom_minimum_size = Vector2(170, 56)
		h.add_child(rush)
		_timers.append([part, lbl, bar, rush])
		_update_timer()
		return
	names.add_child(UIStyle.label(Garage.PART_EFFECT[part] + " per level", 17, UIStyle.FOG, "semibold"))
	if level >= Garage.MAX_LEVEL:
		h.add_child(UIStyle.label("Maxed", 22, UIStyle.GREEN, "extrabold", true))
		return
	var cost := Garage.upgrade_cost(car_id, level + 1)
	var secs := Garage.upgrade_seconds(level + 1)
	var b := UIStyle.button("%s  ·  %s" % [UIStyle.money(cost), _dur(secs)], func():
		if save.start_upgrade(car_id, part):
			_select(car_id), save.credits() >= cost, 20)
	b.custom_minimum_size = Vector2(190, 56)
	b.disabled = save.credits() < cost
	h.add_child(b)


static func _dur(s: int) -> String:
	return "%d s" % s if s < 60 else "%d min" % (s / 60)


func _update_timer() -> void:
	for t in _timers:
		var part: String = t[0]
		var lbl: Label = t[1]
		if not is_instance_valid(lbl):
			continue
		var job: Dictionary = save.part_job(car_id, part)
		if job.is_empty():
			_select(car_id)             # done: show the new level and PR
			return
		var left: float = save.part_seconds_left(car_id, part)
		var full := float(Garage.upgrade_seconds(int(job["level"])))
		lbl.text = "Level %d installing  ·  %d:%02d" % [int(job["level"]), int(ceil(left)) / 60, int(ceil(left)) % 60]
		var bar: ColorRect = t[2]
		bar.size.x = (bar.get_parent() as Control).size.x * clampf(1.0 - left / full, 0.0, 1.0)
		var fee := Garage.rush_cost(car_id, int(job["level"]), left)
		var rush: Button = t[3]
		rush.text = "Finish now  ·  %s" % UIStyle.money(fee)
		rush.disabled = save.credits() < fee


func _process(delta: float) -> void:
	_tick += delta
	if _tick > 0.25:
		_tick = 0.0
		_update_timer()
