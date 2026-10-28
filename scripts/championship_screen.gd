extends Node3D
## Championship. No season running: pick a class (you need a car for it),
## how many rounds and how long the races are, and start. During a season:
## the rounds (done ones with your result), the standings, and the next
## race weekend. At the end: your final position, trophy and prize.

var save: Node
var room: Showroom
var ui: CanvasLayer
var _body: Control
var _pick_class := "gp"
var _rounds := 6
var _laps := 3


func _ready() -> void:
	save = get_node("/root/Save")
	save.pending_event = {}
	room = Showroom.new()
	add_child(room)
	room.build(Vector3(5.0, 1.8, 6.2), Vector3(-1.2, 0.0, 1.8), 40.0)
	room.spin = 0.12
	for c in Championship.CLASSES:
		if _owned_in(c) != "":
			_pick_class = String(c["id"])
			break
	_build_ui()
	_refresh()


func _owned_in(c: Dictionary) -> String:
	for car in c["cars"]:
		if save.owns(String(car)):
			return String(car)
	return ""


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
	var head: Array = UIStyle.header("Championship", func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"), save.credits())
	v.add_child(head[0])
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_body as HBoxContainer).add_theme_constant_override("separation", 16)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_body)


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	var s := Championship.active(save)
	if s.is_empty():
		_build_setup()
	else:
		room.show_spec(save.car_spec(String(s["car"]), int(save.get_setting("team"))))
		_build_season(s)


func _panel(min_w: float, expand := false) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.92), false, UIStyle.APEX, 8)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(min_w, 0)
	if expand:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


# ------------------------------------------------------------ new season

func _build_setup() -> void:
	var left := _panel(520)
	left.add_child(UIStyle.label("Choose a championship", 30, UIStyle.PAPER, "extrabold", true))
	for c in Championship.CLASSES:
		var mine := _owned_in(c)
		var cars: Array = []
		for car in c["cars"]:
			cars.append(CarSpecs.display_name(String(car)))
		var sub := (" or ".join(cars) + "  ·  prize " + UIStyle.money(int(c["prize"]))) if mine != "" else ("Needs a " + " or ".join(cars))
		var id := String(c["id"])
		var b := UIStyle.tile(String(c["name"]), sub, func():
			if _owned_in(Championship.class_info(id)) != "":
				_pick_class = id
				_refresh(), id == _pick_class, 24)
		b.custom_minimum_size = Vector2(0, 70)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.modulate.a = 1.0 if mine != "" else 0.45
		left.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(sp)
	var right := _panel(400)
	var info := Championship.class_info(_pick_class)
	var car := _owned_in(info)
	right.add_child(UIStyle.label(String(info["name"]), 28, UIStyle.PAPER, "extrabold", true))
	if car == "":
		var l := UIStyle.label("Buy a car for this championship in the Garage.", 21, UIStyle.YELLOW, "bold")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(l)
		var g := UIStyle.button("Go to the Garage", func(): get_tree().change_scene_to_file("res://scenes/garage.tscn"), true, 28)
		g.custom_minimum_size = Vector2(0, 76)
		right.add_child(g)
		return
	room.show_spec(save.car_spec(car, int(save.get_setting("team"))))
	var spec: Dictionary = save.car_spec(car)
	right.add_child(UIStyle.label("%s  ·  PR %.1f" % [spec["name"], Garage.pr(spec)], 21, UIStyle.FOG, "bold", true))
	var tracks: Array = []
	for t in (info["rounds"] as Array).slice(0, _rounds):
		tracks.append(String(Track.catalog_entry(String(t))["name"]).replace(" Circuit", "").replace("Circuit ", ""))
	var l2 := UIStyle.label(", ".join(tracks), 18, UIStyle.PAPER, "medium")
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(l2)
	var rules := UIStyle.label("Every round: qualifying, then the race. Choose tyres, pit when they're worn, watch the weather. Points 25-18-15-12-10-8-6-4-2-1, +1 for the fastest lap.", 17, UIStyle.FOG, "medium")
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(rules)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp2)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	right.add_child(chips)
	var rb := UIStyle.button("%d rounds" % _rounds, func():
		var opts := [6, 4, 3]
		_rounds = opts[(opts.find(_rounds) + 1) % opts.size()]
		_refresh(), false, 22)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rb.custom_minimum_size = Vector2(0, 56)
	chips.add_child(rb)
	var lb := UIStyle.button("%d laps each" % _laps, func():
		var opts := [3, 5, 2]
		_laps = opts[(opts.find(_laps) + 1) % opts.size()]
		_refresh(), false, 22)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.custom_minimum_size = Vector2(0, 56)
	chips.add_child(lb)
	var go := UIStyle.button("Start the season", func():
		Championship.start(save, _pick_class, car, "", _rounds, _laps)
		_refresh(), true, 34)
	go.custom_minimum_size = Vector2(0, 80)
	right.add_child(go)


# ------------------------------------------------------------ season

func _build_season(s: Dictionary) -> void:
	var drivers: Array = s["drivers"]
	var rounds: Array = s["rounds"]
	var r := int(s["round"])
	var done := bool(s.get("done", false))
	# Left: rounds.
	var left := _panel(380)
	left.add_child(UIStyle.label(String(s["name"]), 24, UIStyle.APEX, "extrabold", true))
	for k in rounds.size():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		left.add_child(h)
		var col := UIStyle.PAPER if k == r else (UIStyle.FOG if k > r else Color(UIStyle.PAPER, 0.7))
		var n := UIStyle.label("%d  %s" % [k + 1, String(Track.catalog_entry(String(rounds[k]))["name"])], 20, col, "extrabold" if k == r else "semibold", true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		h.add_child(n)
		if k < (s["results"] as Array).size():
			var pos: int = (s["results"][k] as Array).find(0) + 1
			h.add_child(UIStyle.label("P%d" % pos, 20, UIStyle.APEX if pos <= 3 else UIStyle.PAPER, "bold", true))
		elif k == r and not done:
			h.add_child(UIStyle.label("Next", 20, UIStyle.GREEN, "bold", true))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	if done:
		var fin := Championship.standing_of(s, 0)
		left.add_child(UIStyle.label("Champion!" if fin == 1 else "Final position: P%d" % fin, 32, UIStyle.YELLOW if fin == 1 else UIStyle.PAPER, "extrabold", true))
		var nb := UIStyle.button("New season", func():
			save.data["championship"] = {}
			save.save()
			_refresh(), true, 30)
		nb.custom_minimum_size = Vector2(0, 76)
		left.add_child(nb)
	else:
		var go := UIStyle.button("Round %d: race weekend" % (r + 1), func():
			save.pending_event = Championship.round_event(save)
			get_tree().change_scene_to_file("res://scenes/race.tscn"), true, 28)
		go.custom_minimum_size = Vector2(0, 80)
		left.add_child(go)
		var quit := UIStyle.button("Abandon season", func():
			save.data["championship"] = {}
			save.save()
			_refresh(), false, 18)
		quit.custom_minimum_size = Vector2(0, 46)
		left.add_child(quit)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(gap)

	# Right: standings.
	var right := _panel(470)
	right.add_child(UIStyle.label("Drivers' standings" if not done else "Final standings", 26, UIStyle.PAPER, "extrabold", true))
	var order := Championship.standings(s)
	var me := order.find(0)
	var shown := 0
	for k in order.size():
		if k >= 9 and k != me and not (k == 9 and me < 9):
			continue
		if shown >= 10:
			break
		shown += 1
		var i: int = order[k]
		var d: Dictionary = drivers[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		right.add_child(row)
		row.add_child(UIStyle.label("%2d" % (k + 1), 21, UIStyle.FOG, "bold", true))
		var stripe := ColorRect.new()
		stripe.custom_minimum_size = Vector2(5, 22)
		stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stripe.color = _driver_color(s, i)
		row.add_child(stripe)
		var nm := UIStyle.label(String(d["name"]), 21, UIStyle.APEX if i == 0 else UIStyle.PAPER, "bold", true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(UIStyle.label("%d" % int(s["points"][i]), 22, UIStyle.PAPER, "extrabold", true))
	if String(s["class"]) == "gp":
		var teams := Championship.team_standings(s)
		var tl := "Teams: " + "  ·  ".join(teams.slice(0, 3).map(func(t): return "%s %d" % [String(CarSpecs.team(int(t["team"]))["name"]), int(t["points"])]))
		var lt := UIStyle.label(tl, 16, UIStyle.FOG, "semibold")
		lt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(lt)


func _driver_color(s: Dictionary, i: int) -> Color:
	var d: Dictionary = s["drivers"][i]
	if String(s["class"]) == "gp":
		return CarSpecs.team(int(d["team"]))["base"]
	return CarSpecs.get_spec(String(d["car"]), int(d["team"]))["color"] if i > 0 else UIStyle.APEX
