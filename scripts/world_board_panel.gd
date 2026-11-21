class_name WorldBoardPanel
extends Control
## The world leaderboard for a track and a car (scripts/world_board.gd), over
## whatever screen opened it: the top ten, where you stand among everyone,
## and a Race button on each lap with a ghost (a time trial against it).

var track_id := ""
var car_id := ""
var _list: VBoxContainer
var _you: Label
var _status: Label


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
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			queue_free())
	add_child(dim)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.TARMAC, 0.97), false, UIStyle.LINE))
	box.custom_minimum_size = Vector2(760, 560)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	box.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	top.add_child(titles)
	titles.add_child(UIStyle.label("World leaderboard", 30, UIStyle.PAPER, "bold"))
	var spec := CarSpecs.get_spec(car_id)
	titles.add_child(UIStyle.label("%s, %s. Clean time-trial laps." % [String(Track.catalog_entry(track_id)["name"]), String(spec.get("name", car_id))], 18, UIStyle.FOG))
	var close := UIStyle.button("Close", queue_free, false, 20)
	close.custom_minimum_size = Vector2(0, 48)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(close)

	var rule := ColorRect.new()
	rule.color = UIStyle.LINE
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_status = UIStyle.label("Loading...", 20, UIStyle.FOG)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_status)
	_you = UIStyle.label("", 21, UIStyle.PAPER, "bold")
	_you.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_you)

	var board := get_node_or_null("/root/Board")
	if board == null or not board.configured():
		_status.text = "The online leaderboard isn't switched on in this version yet."
		return
	if not board.sharing():
		_you.text = "Your laps aren't being shared (Settings). Turn sharing on to get on the board."
	board.top(track_id, car_id, _show_top)
	if board.sharing():
		board.rank(track_id, car_id, _show_rank)


func _show_top(rows: Variant) -> void:
	if not is_inside_tree():
		return
	if rows == null:
		_status.text = "Couldn't reach the leaderboard. Check your connection and try again."
		return
	if (rows as Array).is_empty():
		_status.text = "No laps here yet. Drive a clean time-trial lap and you're first."
		return
	_status.queue_free()
	var first := int((rows as Array)[0]["lap_ms"])
	var i := 0
	for r in rows:
		i += 1
		_list.add_child(_row(i, r, first))


func _row(pos: int, r: Dictionary, first: int) -> Control:
	var mine := bool(r.get("mine", false))
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIStyle.panel(UIStyle.APEX if mine else Color(UIStyle.TARMAC_2, 0.9), false))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var ink := UIStyle.INK if mine else UIStyle.PAPER
	var p := UIStyle.label(str(pos), 24, UIStyle.PURPLE if pos == 1 and not mine else ink, "bold")
	p.custom_minimum_size = Vector2(44, 50)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(p)
	var n := UIStyle.label(String(r.get("nickname", "Driver")) + ("  (you)" if mine else ""), 22, ink, "bold")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.clip_text = true
	h.add_child(n)
	var ms := int(r["lap_ms"])
	var gap := UIStyle.label("" if pos == 1 else "+%.3f" % ((ms - first) / 1000.0), 18, ink if mine else UIStyle.FOG)
	gap.custom_minimum_size = Vector2(86, 0)
	gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(gap)
	var t := UIStyle.label(UIStyle.fmt_time(ms / 1000.0), 23, ink, "bold")
	t.custom_minimum_size = Vector2(118, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	var b := UIStyle.button("Race", func(): pass, false, 19)
	b.custom_minimum_size = Vector2(96, 46)
	b.disabled = mine or not bool(r.get("has_ghost", false))
	b.modulate.a = 0.0 if b.disabled else 1.0
	b.pressed.connect(func():
		b.disabled = true
		b.text = "..."
		_race(int(r["lap_id"]), b))
	h.add_child(b)
	return row


func _show_rank(r: Variant) -> void:
	if not is_inside_tree():
		return
	if r == null:
		return
	if (r as Dictionary).is_empty():
		_you.text = "You're not on this board yet: set a clean lap in Time trial."
		return
	_you.text = "You: P%d of %d   %s" % [int(r["rank"]), int(r["total"]), UIStyle.fmt_time(int(r["best_ms"]) / 1000.0)]


## Fetch a lap's ghost and race it: a time trial on its track in its car.
func _race(lap_id: int, b: Button) -> void:
	var board := get_node_or_null("/root/Board")
	board.ghost(lap_id, func(ch: Dictionary):
		if not is_inside_tree():
			return
		if ch.is_empty():
			b.text = "Race"
			b.disabled = false
			_you.text = "Couldn't fetch that lap. Try again."
			return
		if String(Track.catalog_entry(String(ch["track"]))["id"]) != String(ch["track"]) or not CarSpecs.is_known(String(ch["car"])):
			_you.text = "That lap is on a track or car this version doesn't have: update the game."
			return
		var save := get_node("/root/Save")
		save.challenge = ch
		save.pending_event = {}
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/race.tscn"))
