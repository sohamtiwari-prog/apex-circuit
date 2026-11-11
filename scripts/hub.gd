extends Node3D
## Home screen: who's driving (helmet, name, rank), the car on the
## turntable, what's next in your career with Race straight into it, and
## the ways to play: daily challenge, championship, career, quick race,
## friends and the garage.

var save: Node
var room: Showroom
var ui: CanvasLayer
var _tiles := {}


static var _url_race_done := false


func _ready() -> void:
	UIStyle.use_menus()
	save = get_node("/root/Save")
	save.pending_event = {}
	# (Browser checks: index.html?race=<track> starts a quick race.)
	# Once per page load (the hub again after the race is the menu), and
	# only for a real track.
	if WebBridge.is_web() and not _url_race_done:
		_url_race_done = true
		var q := String(JavaScriptBridge.eval("location.search", true))
		var tid := q.get_slice("race=", 1).get_slice("&", 0)
		if q.contains("race=") and String(Track.catalog_entry(tid)["id"]) == tid:
			var st: Dictionary = save.data["settings"]
			st["mode"] = "race"; st["track"] = tid; st["qualifying"] = false
			if q.contains("saver"):
				st["graphics"] = "saver"
			get_tree().change_scene_to_file.call_deferred("res://scenes/race.tscn")
			return
	DisplayServer.screen_set_keep_on(true)
	# An iPhone browser draws a lot less than the app: lighter graphics to
	# begin with (Pause -> Graphics puts them back up).
	if WebBridge.is_ios() and not bool(save.get_setting("web_tuned")):
		save.set_setting("web_tuned", true)
		save.set_setting("graphics", "saver")
	if not bool(save.driver().get("created", false)):
		get_tree().change_scene_to_file.call_deferred("res://scenes/driver.tscn")
		return
	room = Showroom.new()
	add_child(room)
	room.build(Vector3(5.0, 1.8, 6.2), Vector3(1.6, 0.2, -1.0))
	room.show_spec(save.car_spec(home_car()))
	_build_ui()


## The car shown at home: the one picked in the Garage.
func home_car() -> String:
	var c := String(save.get_setting("garage_car"))
	return c if CarSpecs.CATALOG.has(c) else Garage.STARTER


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cols)
	var boards: Array = []

	# Left: who's driving (tap: your driver), and the car (tap: the garage).
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	boards.append(_driver_card(left))
	if WebBridge.is_ios() and not WebBridge.is_standalone():
		var tip := PanelContainer.new()
		var tsb := UIStyle.panel(UIStyle.BLACK, false)
		tsb.set_content_margin_all(12)
		tip.add_theme_stylebox_override("panel", tsb)
		tip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tip.custom_minimum_size = Vector2(500, 0)
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tl := UIStyle.label("Full screen: tap Share, then Add to Home Screen, and play from the icon.", 19, UIStyle.SIGNAL, "bold")
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.add_child(tl)
		left.add_child(tip)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(sp)
	boards.append(_car_card(left))

	# Right: the look switch, records, stars; what's next; the ways to play.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(800, 0)
	right.add_theme_constant_override("separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_END
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(top)
	var dark := UIStyle.theme == "garage_dark"
	var look := _icon_button("sun" if dark else "moon", func():
		save.set_setting("look", "light" if dark else "dark")
		get_tree().reload_current_scene())
	top.add_child(look)
	_tiles["look"] = look
	var records := _icon_button("trophy", func(): get_tree().change_scene_to_file("res://scenes/profile.tscn"), "Records")
	top.add_child(records)
	_tiles["profile"] = records
	var stars := PanelContainer.new()
	var ssb := UIStyle.panel(UIStyle.BLACK, false)
	ssb.content_margin_left = 14
	ssb.content_margin_right = 18
	stars.add_theme_stylebox_override("panel", ssb)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(stars)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.add_child(sh)
	var st := StarRow.new()
	st.total = 1
	st.stars = 1
	st.gold = UIStyle.SIGNAL
	st.custom_minimum_size = Vector2(30, 30)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(st)
	var sl := UIStyle.label("%d" % Career.total_stars(save), 30, UIStyle.SIGNAL, "display")
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sh.add_child(sl)
	boards.append(top)

	boards.append(_next_card(right))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(grid)
	var daily := Daily.event()
	var dstars: int = save.career_stars(String(daily["id"]))
	var hours_left := 24 - int(Time.get_time_dict_from_system()["hour"])
	_tile(grid, "daily", "calendar", "Daily challenge", Daily.describe(daily), func():
		save.pending_event = daily
		get_tree().change_scene_to_file("res://scenes/race.tscn"),
		("%d of 3 stars" % dstars) if dstars > 0 else ("New in %d h" % hours_left if hours_left > 1 else "New within the hour"))
	_tile(grid, "championship", "podium", "Championship", Championship.summary(save), func(): get_tree().change_scene_to_file("res://scenes/championship.tscn"))
	_tile(grid, "career", "trophy", "Career", "Every series and event", func(): get_tree().change_scene_to_file("res://scenes/career.tscn"),
		"%d of %d stars" % [Career.total_stars(save), Career.SERIES.size() * 18])
	_tile(grid, "quick", "flag", "Quick race", "Any car, any track, any rules", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	_tile(grid, "friends", "friends", "Friends", "Race on the same Wi-Fi or online", func(): get_tree().change_scene_to_file("res://scenes/lobby.tscn"))
	_tile(grid, "garage", "spanner", "Garage", "Paint, setup and every car", func(): get_tree().change_scene_to_file("res://scenes/garage.tscn"),
		"%d cars" % CarSpecs.CATALOG.size())
	for k in ["daily", "championship", "career", "quick", "friends", "garage"]:
		boards.append(_tiles[k])
	UIStyle.reveal(boards)


## A board you can tap: lifted off the room, yellow under your thumb.
func _tap_board(cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var sb := UIStyle.lift(UIStyle.panel(UIStyle.TARMAC, false))
	var down := sb.duplicate() as StyleBoxFlat
	down.bg_color = UIStyle.APEX
	for k in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("pressed", down)
	b.pressed.connect(cb)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func(): b.scale = Vector2(0.98, 0.98))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	return b


## Lays `inner` over the whole of a tap board, inset.
func _fill(b: Control, inner: Control, m := 16) -> void:
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = m
	inner.offset_top = m * 0.8
	inner.offset_right = -m
	inner.offset_bottom = -m * 0.8
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)


func _icon_button(icon: String, cb: Callable, text := "") -> Button:
	var b := UIStyle.button(text, cb, false, 22)
	UIStyle._button_styles(b, UIStyle.TARMAC, UIStyle.PAPER, UIStyle.APEX, UIStyle.INK)
	(b.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_left = 54 if text != "" else 22
	b.custom_minimum_size = Vector2(60 if text == "" else 160, 56)
	var i := UIIcon.make(icon, UIStyle.PAPER, 30.0, UIStyle.TARMAC)
	i.position = Vector2(15, 13)
	i.size = Vector2(30, 30)
	b.add_child(i)
	return b


## You: helmet, name and number, rank and how far to the next one.
func _driver_card(parent: Control) -> Control:
	var d: Dictionary = save.driver()
	var b := _tap_board(func(): get_tree().change_scene_to_file("res://scenes/driver.tscn"))
	b.custom_minimum_size = Vector2(500, 116)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(b)
	_tiles["driver"] = b
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_fill(b, h, 14)
	h.add_child(HelmetBadge.for_driver(d, 88.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var name := String(d.get("name", ""))
	v.add_child(UIStyle.label(name if name != "" else "Driver", 26, UIStyle.PAPER, "display"))
	var rp := int(save.data.get("rank_points", 0))
	var pr := Ranks.progress(rp)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 8)
	rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rr)
	var badge := RankBadge.new()
	badge.custom_minimum_size = Vector2(24, 28)
	badge.rp = rp
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rr.add_child(badge)
	var tl := UIStyle.label("#%d   %s   %d RP" % [int(d.get("number", 26)), Ranks.tier_name(rp), rp], 21, UIStyle.FOG, "bold")
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rr.add_child(tl)
	var back := ColorRect.new()
	back.color = UIStyle.TARMAC_2
	back.custom_minimum_size = Vector2(0, 6)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(back)
	var fill := ColorRect.new()
	fill.color = UIStyle.PAPER if UIStyle.light() else Ranks.tier_color(rp)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	back.resized.connect(func(): fill.size = Vector2(back.size.x * float(pr.x) / maxf(pr.y, 1), 6))
	return b


func _car_card(parent: Control) -> Control:
	var spec: Dictionary = save.car_spec(home_car())
	var b := _tap_board(func(): get_tree().change_scene_to_file("res://scenes/garage.tscn"))
	b.custom_minimum_size = Vector2(420, 96)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(b)
	_tiles["car"] = b
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	_fill(b, cv, 18)
	cv.add_child(UIStyle.label("%s, PR %.1f" % [String(spec["desc"]).split(" · ")[0], Garage.pr(spec)], 21, UIStyle.FOG, "bold"))
	cv.add_child(UIStyle.label(String(spec["name"]), 30, UIStyle.PAPER, "display"))
	return b


## Next in your career: the first event in your series not yet three-
## starred, its track, and Race straight into it in the car you last used
## in that series.
func _next_card(parent: Control) -> Control:
	var si := clampi(int(save.get_setting("career_series")), 0, Career.SERIES.size() - 1)
	var n: int = (Career.SERIES[si]["events"] as Array).size()
	var ei := 0
	for k in n:
		if save.career_stars(Career.event_id(si, k)) < 3:
			ei = k
			break
	var ev := Career.event(si, ei)
	var p := PanelContainer.new()
	var sb := UIStyle.lift(UIStyle.panel(UIStyle.TARMAC, false))
	sb.set_content_margin_all(18)
	sb.border_color = UIStyle.GO
	sb.border_width_left = 8
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(0, 214)
	parent.add_child(p)
	_tiles["next"] = p
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIStyle.label("Next in %s" % String(Career.SERIES[si]["name"]), 20, UIStyle.FOG, "bold"))
	v.add_child(UIStyle.label("%d. %s" % [ei + 1, Career.TYPE_NAMES[ev["type"]]], 30, UIStyle.PAPER, "display"))
	var where := "A six-round season, 20 cars"
	if ev["type"] != "season":
		where = "%s, %d laps" % [String(Track.catalog_entry(String(ev["track"]))["name"]), int(ev["laps"])]
	v.add_child(UIStyle.label(where, 21, UIStyle.PAPER, "semibold"))
	var srow := StarRow.new()
	srow.stars = save.career_stars(String(ev["id"]))
	srow.custom_minimum_size = Vector2(120, 32)
	srow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(srow)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var go := UIStyle.go_button("Race" if ev["type"] != "season" else "Open the season", func(): _race_next(si, ev), 34)
	go.custom_minimum_size = Vector2(320, 68)
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(go)
	_tiles["race_next"] = go
	if ev["type"] != "season":
		var well := PanelContainer.new()
		var wsb := UIStyle.panel(UIStyle.TARMAC_2, false)
		wsb.set_content_margin_all(12)
		well.add_theme_stylebox_override("panel", wsb)
		well.custom_minimum_size = Vector2(260, 0)
		h.add_child(well)
		var map := MiniMap.new()
		map.show_panel = false
		map.line_width = 5.0
		map.line_color = UIStyle.PAPER
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well.add_child(map)
		map.set_points(Track.outline(String(ev["track"])))
	return p


func _race_next(si: int, ev: Dictionary) -> void:
	if ev["type"] == "season":
		save.set_setting("career_series", si)
		get_tree().change_scene_to_file("res://scenes/career.tscn")
		return
	var cars: Array = []
	for c in ev["cars"]:
		cars.append(String(c))
	var last := String((save.get_setting("career_car") as Dictionary).get(String(Career.SERIES[si]["id"]), ""))
	ev["car"] = last if cars.has(last) else String(cars[0])
	ev["return_to"] = "res://scenes/career.tscn"
	save.pending_event = ev
	get_tree().change_scene_to_file("res://scenes/race.tscn")


## One way to play: its icon, a figure, its name and one line on it.
func _tile(parent: Control, key: String, icon: String, title: String, sub: String, cb: Callable, figure := "") -> void:
	var b := _tap_board(cb)
	b.custom_minimum_size = Vector2(0, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_tiles[key] = b
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_fill(b, v, 16)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(UIIcon.make(icon, UIStyle.PAPER, 46.0, UIStyle.APEX))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	if figure != "":
		var f := UIStyle.label(figure, 18, UIStyle.FOG, "bold")
		f.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(f)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	v.add_child(UIStyle.label(title, 20, UIStyle.PAPER, "display"))
	var s := UIStyle.label(sub, 18, UIStyle.FOG, "semibold")
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.max_lines_visible = 2
	s.custom_minimum_size = Vector2(200, 0)
	v.add_child(s)
