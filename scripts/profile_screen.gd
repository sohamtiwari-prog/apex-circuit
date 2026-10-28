extends Node3D
## Driver profile: your rank, career totals, records at every track, and the
## trophy cabinet from championships.

var save: Node
var ui: CanvasLayer


func _ready() -> void:
	save = get_node("/root/Save")
	var room := Showroom.new()
	add_child(room)
	room.build(Vector3(5.0, 1.8, 6.2), Vector3(-2.4, 0.0, 2.2), 40.0)
	room.spin = 0.12
	var home := String(save.get_setting("garage_car"))
	room.show_spec(save.car_spec(home if CarSpecs.CATALOG.has(home) else Garage.STARTER))
	_build_ui()


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
	var name := String(save.get_setting("player_name"))
	var head: Array = UIStyle.header(name if name != "" else "Driver profile", func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"), "%d stars" % Career.total_stars(save))
	v.add_child(head[0])
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)

	# Left: rank and totals.
	var left := _panel(body, 400)
	RankCard.build(left, ui, save)
	var st: Dictionary = save.data["stats"]
	var rows := [
		["Races", "%d" % int(st["races"])],
		["Wins", "%d" % int(st["wins"])],
		["Podiums", "%d" % int(st["podiums"])],
		["Laps", "%d" % int(st["laps"])],
		["Distance", "%d km" % int(float(st["distance_m"]) / 1000.0)],
		["Career stars", "%d of %d" % [Career.total_stars(save), Career.SERIES.size() * 18]],
	]
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	left.add_child(gap)
	for r in rows:
		var h := HBoxContainer.new()
		left.add_child(h)
		var n := UIStyle.label(String(r[0]), 22, UIStyle.FOG, "semibold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(UIStyle.label(String(r[1]), 24, UIStyle.PAPER, "extrabold", true))

	var mid := Control.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(mid)

	# Right: track records and trophies.
	var right := _panel(body, 520)
	right.add_child(UIStyle.label("Best laps", 26, UIStyle.PAPER, "extrabold", true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var any := false
	for t in Track.CATALOG:
		var best := -1
		var best_car := ""
		for c in CarSpecs.CATALOG:
			var ms: int = save.get_best_lap(save.lap_key(String(t["id"]), String(c)))
			if ms > 0 and (best < 0 or ms < best):
				best = ms
				best_car = String(c)
		var h := HBoxContainer.new()
		list.add_child(h)
		var n := UIStyle.label(String(t["name"]).trim_suffix(" International Circuit").trim_suffix(" Circuit"), 20, UIStyle.PAPER if best > 0 else UIStyle.FOG, "semibold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		h.add_child(n)
		if best > 0:
			any = true
			h.add_child(UIStyle.label(CarSpecs.display_name(best_car), 17, UIStyle.FOG, "semibold"))
			var tl := UIStyle.label(UIStyle.fmt_time(best / 1000.0), 21, UIStyle.PURPLE, "bold", true)
			tl.custom_minimum_size = Vector2(100, 0)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(tl)
		else:
			h.add_child(UIStyle.label("-", 20, UIStyle.FOG, "bold"))
	if not any:
		list.add_child(UIStyle.label("Set a lap anywhere to start your records.", 18, UIStyle.FOG, "medium"))
	right.add_child(UIStyle.label("Trophy cabinet", 26, UIStyle.PAPER, "extrabold", true))
	var cabinet := HFlowContainer.new()
	cabinet.add_theme_constant_override("h_separation", 8)
	cabinet.add_theme_constant_override("v_separation", 8)
	right.add_child(cabinet)
	var trophies: Array = save.data.get("trophies", [])
	if trophies.is_empty():
		cabinet.add_child(UIStyle.label("Finish a championship in the top 3 to win a trophy.", 18, UIStyle.FOG, "medium"))
	for tr in trophies:
		var pos := int(tr["position"])
		var card := PanelContainer.new()
		var col: Color = [Color("ffc93c"), Color("c9d1db"), Color("d08a4f")][clampi(pos - 1, 0, 2)] if pos <= 3 else UIStyle.FOG
		card.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC_2, 0.95), true, col))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", -4)
		card.add_child(cv)
		cv.add_child(UIStyle.label("P%d" % pos if pos > 1 else "Champion", 20, col, "extrabold", true))
		cv.add_child(UIStyle.label(String(tr["series"]).replace(" World Championship", "").replace("Championship", ""), 15, UIStyle.PAPER, "semibold"))
		cabinet.add_child(card)


func _panel(parent: Control, min_w: float) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.92), false, UIStyle.APEX, 8)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(min_w, 0)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v
