extends Node3D
## Career: the five series across the top (locked ones say how many stars
## they need), the selected series' six events below, and the chosen event's
## details on the right with a car picker and Start.

var save: Node
var room: Showroom
var ui: CanvasLayer
var si := 0                         # selected series
var ei := 0                         # selected event
var _series_box: HBoxContainer
var _events: GridContainer
var _detail: VBoxContainer
var _car_pick := ""


func _ready() -> void:
	save = get_node("/root/Save")
	save.pending_event = {}
	room = Showroom.new()
	add_child(room)
	room.build(Vector3(5.0, 1.8, 6.2), Vector3(-0.6, 0.0, 1.4), 40.0)
	room.spin = 0.15
	si = clampi(int(save.get_setting("career_series")), 0, Career.SERIES.size() - 1)
	if not Career.unlocked(save, si):
		si = 0
	ei = _first_open_event(si)
	_build_ui()
	_refresh()


func _first_open_event(s: int) -> int:
	var n: int = (Career.SERIES[s]["events"] as Array).size()
	for k in n:
		if save.career_stars(Career.event_id(s, k)) < 3:
			return k
	return 0


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
	var head: Array = UIStyle.header("Career", func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"), save.credits())
	v.add_child(head[0])
	_series_box = HBoxContainer.new()
	_series_box.add_theme_constant_override("separation", 8)
	v.add_child(_series_box)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	_events = GridContainer.new()
	_events.columns = 3
	_events.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_events.add_theme_constant_override("h_separation", 10)
	_events.add_theme_constant_override("v_separation", 10)
	body.add_child(_events)
	var panel := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.92), false, UIStyle.APEX, 8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(420, 0)
	body.add_child(panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	panel.add_child(_detail)


func _refresh() -> void:
	for c in _series_box.get_children():
		c.queue_free()
	for c in _events.get_children():
		c.queue_free()
	for c in _detail.get_children():
		c.queue_free()
	var total := Career.total_stars(save)
	# Series strip.
	for k in Career.SERIES.size():
		var s: Dictionary = Career.SERIES[k]
		var open := Career.unlocked(save, k)
		var sub := ("%d / 18 stars" % Career.series_stars(save, k)) if open else ("Needs %d stars (you have %d)" % [int(s["unlock"]), total])
		var b := UIStyle.tile(String(s["name"]), sub, func():
			if Career.unlocked(save, k):
				si = k
				ei = _first_open_event(k)
				save.set_setting("career_series", k)
				_refresh(), k == si, 24)
		b.custom_minimum_size = Vector2(0, 74)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.modulate.a = 1.0 if open else 0.5
		_series_box.add_child(b)
	# Events of the selected series.
	var events: Array = Career.SERIES[si]["events"]
	for k in events.size():
		_events.add_child(_event_card(k))
	_build_detail()


func _event_card(k: int) -> Control:
	var ev := Career.event(si, k)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var on := k == ei
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.9), false, UIStyle.APEX if on else Color(0, 0, 0, 0), 6)
	if on:
		sb.set_border_width_all(3)
		sb.border_color = UIStyle.APEX
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func():
		ei = k
		_refresh())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_right = -12
	v.offset_top = 8
	v.offset_bottom = -8
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var t := UIStyle.label("%d  %s" % [k + 1, Career.TYPE_NAMES[ev["type"]]], 26, UIStyle.APEX if ev["type"] == "season" else UIStyle.PAPER, "extrabold", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var st := StarRow.new()
	st.custom_minimum_size = Vector2(84, 28)
	st.stars = save.career_stars(String(ev["id"]))
	top.add_child(st)
	v.add_child(UIStyle.label(_where(ev), 20, UIStyle.FOG, "semibold"))
	var foot := HBoxContainer.new()
	foot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	var money := UIStyle.label(UIStyle.money(int(ev["reward"])), 20, UIStyle.GREEN, "bold", true)
	money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.size_flags_vertical = Control.SIZE_SHRINK_END
	foot.add_child(money)
	if String(ev["track"]) != "":
		var map := MiniMap.new()
		map.show_panel = false
		map.line_width = 3.0
		map.custom_minimum_size = Vector2(120, 0)
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foot.add_child(map)
		map.set_points(_outline(String(ev["track"])))
	return b


static var _outlines := {}

static func _outline(id: String) -> PackedVector3Array:
	if not _outlines.has(id):
		_outlines[id] = Track.outline(id)
	return _outlines[id]


func _where(ev: Dictionary) -> String:
	if ev["type"] == "season":
		return "6 rounds  ·  20 cars"
	var tname := String(Track.catalog_entry(String(ev["track"]))["name"])
	match String(ev["type"]):
		"time_trial":
			return "%s  ·  %d laps" % [tname, int(ev["laps"])]
		"duel":
			return "%s  ·  %d laps, 1 rival" % [tname, int(ev["laps"])]
	return "%s  ·  %d laps, %d cars" % [tname, int(ev["laps"]), int(ev["opponents"]) + 1]


func _build_detail() -> void:
	var ev := Career.event(si, ei)
	_detail.add_child(UIStyle.label(String(Career.SERIES[si]["name"]), 20, UIStyle.FOG, "bold", true))
	_detail.add_child(UIStyle.label("%d. %s" % [ei + 1, Career.TYPE_NAMES[ev["type"]]], 36, UIStyle.PAPER, "extrabold", true))
	var rules := UIStyle.label(String(Career.TYPE_RULES[ev["type"]]), 19, UIStyle.PAPER, "medium")
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(rules)
	if ev["type"] != "season":
		_detail.add_child(UIStyle.label(_where(ev), 19, UIStyle.FOG, "semibold"))
	var st := StarRow.new()
	st.custom_minimum_size = Vector2(160, 40)
	st.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	st.stars = save.career_stars(String(ev["id"]))
	_detail.add_child(st)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(sp)

	# Car: one you own that's allowed here.
	var allowed: Array = ev["cars"]
	var mine: Array = []
	for c in allowed:
		if save.owns(String(c)):
			mine.append(String(c))
	var series_id := String(Career.SERIES[si]["id"])
	var last := String((save.get_setting("career_car") as Dictionary).get(series_id, ""))
	_car_pick = last if mine.has(last) else (mine[0] if not mine.is_empty() else "")
	var need_pr := Garage.pr(CarSpecs.get_spec(String(allowed[0]))) + ei * 0.8
	if mine.is_empty():
		var names: Array = []
		for c in allowed:
			names.append(CarSpecs.display_name(String(c)))
		var l := UIStyle.label("You need a %s for this series." % " or ".join(names), 21, UIStyle.YELLOW, "bold")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(l)
		var g := UIStyle.button("Go to the Garage", func(): get_tree().change_scene_to_file("res://scenes/garage.tscn"), true, 30)
		g.custom_minimum_size = Vector2(0, 76)
		_detail.add_child(g)
		room.show_spec(CarSpecs.get_spec(String(allowed[0])))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail.add_child(row)
	var spec: Dictionary = save.car_spec(_car_pick)
	room.show_spec(spec)
	var pr := Garage.pr(spec)
	var car_lbl := UIStyle.label("%s  ·  PR %.1f" % [spec["name"], pr], 22, UIStyle.PAPER, "bold", true)
	car_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(car_lbl)
	if mine.size() > 1:
		var sw := UIStyle.button("Switch", func():
			var i := mine.find(_car_pick)
			var d: Dictionary = save.get_setting("career_car")
			d[series_id] = mine[(i + 1) % mine.size()]
			save.set_setting("career_car", d)
			_refresh(), false, 20)
		row.add_child(sw)
	var hint := UIStyle.label(("Recommended PR %.0f+" % need_pr) + ("  ·  upgrade in the Garage" if pr < need_pr else ""), 18, UIStyle.GREEN if pr >= need_pr else UIStyle.YELLOW, "semibold")
	_detail.add_child(hint)
	var job: Dictionary = save.upgrade_job(_car_pick)
	if not job.is_empty():
		_detail.add_child(UIStyle.label("Installing %s %d: ready in %ds" % [Garage.PART_NAMES[job["part"]], int(job["level"]), int(ceil(save.upgrade_seconds_left(_car_pick)))], 18, UIStyle.YELLOW, "semibold"))
	var go := UIStyle.button("Start" if ev["type"] != "season" else "Start the season", _start, true, 38)
	go.custom_minimum_size = Vector2(0, 84)
	_detail.add_child(go)


func _start() -> void:
	var ev := Career.event(si, ei)
	if _car_pick == "":
		return
	if ev["type"] == "season":
		Championship.start(save, "gp", _car_pick, String(ev["id"]))
		get_tree().change_scene_to_file("res://scenes/championship.tscn")
		return
	ev["car"] = _car_pick
	ev["return_to"] = "res://scenes/career.tscn"
	save.pending_event = ev
	get_tree().change_scene_to_file("res://scenes/race.tscn")
