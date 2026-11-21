class_name WorldBoardPanel
extends Control
## The world leaderboard for a track and a car (scripts/world_board.gd), over
## whatever screen opened it. Laid out like a timing screen on the pit wall:
## on the left the circuit and where you stand (your place, big, the one
## loud thing here); on the right the running order of the world's best
## laps, a hairline between rows, the fastest in purple, yours marked in
## your yellow, and a Race button on every lap with a ghost to chase.

var track_id := ""
var car_id := ""
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _place: Label
var _place_of: Label
var _best: Label
var _gap: Label
var _leader_ms := -1
var _my_ms := -1


static func open(parent: Node, track: String, car: String) -> WorldBoardPanel:
	var p := WorldBoardPanel.new()
	p.track_id = track
	p.car_id = car
	# (Over everything: the menus draw their boards on their own layers.)
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(layer)
	layer.add_child(p)
	p.tree_exited.connect(layer.queue_free)
	return p


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			queue_free())
	add_child(dim)

	var sheet := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.97), false)
	sb.bg_color.a = 0.97
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sheet.add_theme_stylebox_override("panel", sb)
	sheet.custom_minimum_size = Vector2(1040, 600)
	add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	sheet.add_child(cols)

	# --- left: the circuit and where you stand
	var left := PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(UIStyle.TARMAC_2, 0.55)
	lsb.corner_radius_top_left = 6
	lsb.corner_radius_bottom_left = 6
	lsb.content_margin_left = 30
	lsb.content_margin_right = 30
	lsb.content_margin_top = 28
	lsb.content_margin_bottom = 28
	left.add_theme_stylebox_override("panel", lsb)
	left.custom_minimum_size = Vector2(340, 0)
	cols.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	left.add_child(lv)
	lv.add_child(UIStyle.label("World leaderboard", 19, UIStyle.FOG, "semibold"))
	var tname := UIStyle.label(String(Track.catalog_entry(track_id)["name"]), 30, UIStyle.PAPER, "display")
	tname.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(tname)
	var spec := CarSpecs.get_spec(car_id)
	lv.add_child(UIStyle.label("%s, clean time-trial laps" % String(spec.get("name", car_id)), 19, UIStyle.FOG))
	var map := MiniMap.new()
	map.show_panel = false
	map.line_width = 4.0
	map.custom_minimum_size = Vector2(0, 150)
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(map)
	map.set_points(Track.outline(track_id))
	lv.add_child(UIStyle.label("Your place", 19, UIStyle.FOG, "semibold"))
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	lv.add_child(ph)
	_place = UIStyle.label("–", 76, UIStyle.APEX if UIStyle.dark_menus() else UIStyle.PAPER, "display")
	ph.add_child(_place)
	_place_of = UIStyle.label("", 21, UIStyle.FOG, "semibold")
	_place_of.size_flags_vertical = Control.SIZE_SHRINK_END
	_place_of.custom_minimum_size = Vector2(0, 0)
	ph.add_child(_place_of)
	_best = UIStyle.label("", 26, UIStyle.PAPER, "bold")
	lv.add_child(_best)
	_gap = UIStyle.label("", 19, UIStyle.FOG)
	_gap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_gap)

	# --- right: the running order
	var right := MarginContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("margin_left", 30)
	right.add_theme_constant_override("margin_right", 26)
	right.add_theme_constant_override("margin_top", 22)
	right.add_theme_constant_override("margin_bottom", 22)
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	var top := HBoxContainer.new()
	rv.add_child(top)
	var cap := UIStyle.label("Top 50 in the world", 24, UIStyle.PAPER, "bold")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(cap)
	var close := UIStyle.button("Close", queue_free, false, 20)
	close.custom_minimum_size = Vector2(0, 46)
	top.add_child(close)
	rv.add_child(_head())
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 0)
	scroll.add_child(_rows)
	_status = UIStyle.label("Loading the world's laps...", 21, UIStyle.FOG)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 60)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rows.add_child(_status)

	var board := get_node_or_null("/root/Board")
	if board == null or not board.configured():
		_status.text = "The online leaderboard isn't in this version yet."
		_gap.text = ""
		return
	if not board.sharing():
		_gap.text = "Sharing your laps is off (Settings): turn it on to get a place here."
	board.top(track_id, car_id, _show_top)
	if board.sharing():
		board.rank(track_id, car_id, _show_rank)


## Column titles over the running order.
func _head() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.modulate.a = 0.9
	for c in [["Pos", 52, HORIZONTAL_ALIGNMENT_CENTER, false], ["Driver", 0, HORIZONTAL_ALIGNMENT_LEFT, true],
			["Gap", 92, HORIZONTAL_ALIGNMENT_RIGHT, false], ["Lap", 124, HORIZONTAL_ALIGNMENT_RIGHT, false], ["", 112, HORIZONTAL_ALIGNMENT_RIGHT, false]]:
		var l := UIStyle.label(c[0], 17, UIStyle.FOG, "semibold")
		l.custom_minimum_size = Vector2(c[1], 0)
		l.horizontal_alignment = c[2]
		if c[3]:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	return h


func _show_top(rows: Variant) -> void:
	if not is_inside_tree():
		return
	if rows == null:
		_status.text = "Couldn't reach the leaderboard. Check your connection and try again."
		return
	if (rows as Array).is_empty():
		_status.text = "Nobody's set a lap here yet. Drive a clean lap in Time trial and the top spot is yours."
		return
	_status.queue_free()
	_leader_ms = int((rows as Array)[0]["lap_ms"])
	var i := 0
	var yours: Control = null
	for r in rows:
		i += 1
		var row := _row(i, r)
		_rows.add_child(row)
		if bool(r.get("mine", false)):
			yours = row
	_update_gap()
	# (Fifty rows don't fit: open with yours in the middle, wherever it is.)
	if yours != null:
		await get_tree().process_frame
		if is_instance_valid(yours) and is_instance_valid(_scroll):
			_scroll.scroll_vertical = int(maxf(yours.position.y - (_scroll.size.y - yours.size.y) * 0.5, 0.0))


func _row(pos: int, r: Dictionary) -> Control:
	var mine := bool(r.get("mine", false))
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UIStyle.APEX, 0.12) if mine else Color(0, 0, 0, 0)
	sb.border_color = UIStyle.LINE
	sb.border_width_bottom = 1
	if mine:
		sb.border_color = UIStyle.APEX
		sb.border_width_bottom = 0
		sb.border_width_left = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var p := UIStyle.label(str(pos), 26, UIStyle.PURPLE if pos == 1 else UIStyle.PAPER, "display" if pos <= 3 else "bold")
	if pos <= 3:
		p.add_theme_font_size_override("font_size", 22)
	p.custom_minimum_size = Vector2(52, 54)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(p)
	var name := String(r.get("nickname", "Driver"))
	var n := UIStyle.label(name, 24, UIStyle.APEX if mine and UIStyle.dark_menus() else UIStyle.PAPER, "bold")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if mine:
		n.text += "  (you)"
	h.add_child(n)
	var ms := int(r["lap_ms"])
	var gap := UIStyle.label("Leader" if pos == 1 else "+%.3f" % ((ms - _leader_ms) / 1000.0), 19, UIStyle.FOG, "semibold")
	gap.custom_minimum_size = Vector2(92, 0)
	gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(gap)
	var t := UIStyle.label(UIStyle.fmt_time(ms / 1000.0), 25, UIStyle.PURPLE if pos == 1 else UIStyle.PAPER, "bold")
	t.custom_minimum_size = Vector2(124, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(112, 46)
	h.add_child(slot)
	if not mine and bool(r.get("has_ghost", false)):
		var b := UIStyle.button("Race", Callable(), false, 19)
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# (Quiet until pressed: a hairline outline, not a block on every row.)
		for st in ["normal", "hover"]:
			var o := (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate() as StyleBoxFlat
			o.bg_color = Color(UIStyle.PAPER, 0.04)
			o.border_color = Color(UIStyle.PAPER, 0.22)
			o.set_border_width_all(1)
			b.add_theme_stylebox_override(st, o)
		b.pressed.connect(func():
			b.disabled = true
			b.text = "Loading"
			_race(int(r["lap_id"]), b))
		slot.add_child(b)
	return row


func _show_rank(r: Variant) -> void:
	if not is_inside_tree() or r == null:
		return
	if (r as Dictionary).is_empty():
		_place.text = "–"
		_gap.text = "No lap of yours here yet: drive a clean lap in Time trial to get on the board."
		return
	_place.text = "P%d" % int(r["rank"])
	_place_of.text = "of %d" % int(r["total"])
	_my_ms = int(r["best_ms"])
	_best.text = UIStyle.fmt_time(_my_ms / 1000.0)
	_update_gap()


func _update_gap() -> void:
	if _my_ms < 0 or _leader_ms < 0:
		return
	_gap.text = "You hold the world record here." if _my_ms <= _leader_ms else "%.3f s off the world record" % ((_my_ms - _leader_ms) / 1000.0)


## Fetch a lap's ghost and race it: a time trial on its track in its car.
func _race(lap_id: int, b: Button) -> void:
	var board := get_node_or_null("/root/Board")
	board.ghost(lap_id, func(ch: Dictionary):
		if not is_inside_tree():
			return
		if ch.is_empty():
			b.text = "Race"
			b.disabled = false
			_gap.text = "Couldn't fetch that lap. Try again."
			return
		if String(Track.catalog_entry(String(ch["track"]))["id"]) != String(ch["track"]) or not CarSpecs.is_known(String(ch["car"])):
			_gap.text = "That lap is on a track or car this version doesn't have: update the game."
			return
		var save := get_node("/root/Save")
		save.challenge = ch
		save.pending_event = {}
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/race.tscn"))
