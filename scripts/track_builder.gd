extends Node3D
## Track builder: draw your own circuit, shape it, choose its scenery, time
## of day, hills and width, then race it (Quick race, any car) or send it to
## a friend as a code. Left: the drawing board (scripts/builder_map.gd).
## Right: the track's name, what it's like, the choices, and the buttons.

## What's on the board, kept while you go and race it and come back.
static var draft := {}
static var draft_from := ""      # the saved track being edited ("" new)
## A track from a link (?track=...), to open when the builder starts.
static var incoming := {}

var save: Node
var ui: CanvasLayer
var map: BuilderMap
var track := {}                  # name, style, tod, hills, width, seed (ctrl lives on the map)
var _undo: Array = []
var _name: LineEdit
var _stats: Label
var _status: Label
var _chips := {}
var _mode_btns := {}
var _del_btn: Button
var _code: LineEdit
var _race_btn: Button
var _mine_btn: Button
var _overlay: Control


func _ready() -> void:
	UIStyle.use_menus()
	save = get_node("/root/Save")
	var room := Showroom.new()
	add_child(room)
	room.build(Vector3(5.0, 1.8, 6.2), Vector3(1.6, 0.2, -1.0))
	_build_ui()
	if not incoming.is_empty():
		_open(incoming, "")
		_say("%s, from a friend. Race it, or Save to keep it in your tracks." % String(incoming.get("name", "A track")), UIStyle.GREEN)
		MyTracks.extra[String(incoming["id"])] = incoming
		incoming = {}
	elif not draft.is_empty():
		_open(draft, draft_from)
	else:
		var list := MyTracks.all()
		if not list.is_empty():
			_open(list[0], String(list[0]["id"]))
		else:
			_open(MyTracks.new_track([], "My track"), "")
			map.ctrl = []
			map.refresh()
	map.frame_all.call_deferred()


func go_back() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		return
	_keep_draft()
	get_tree().change_scene_to_file("res://scenes/hub.tscn")


# ------------------------------------------------------------ layout

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cols)

	# --- left: header, the board, the tools under it
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	var head: Array = UIStyle.header("Track builder", go_back)
	left.add_child(head[0])
	var bar: HBoxContainer = head[0]
	for m in [["draw", "Draw"], ["shape", "Shape"]]:
		var key: String = m[0]
		var b := UIStyle.button(m[1], func(): _set_mode(key), false, 22)
		b.custom_minimum_size = Vector2(112, 56)
		bar.add_child(b)
		_mode_btns[key] = b

	var board := PanelContainer.new()
	var bsb := UIStyle.panel(Color(0, 0, 0, 0.9), false)
	bsb.set_content_margin_all(4)
	board.add_theme_stylebox_override("panel", bsb)
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(board)
	map = BuilderMap.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_child(map)
	map.edit_started.connect(_push_undo)
	map.edited.connect(_changed)
	map.picked.connect(func(i): _del_btn.visible = i >= 0 and map.ctrl.size() > 4)
	map.traced_badly.connect(func(msg): _say(msg, UIStyle.YELLOW))

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	left.add_child(tools)
	for t in [["Undo", _undo_last], ["−", func(): map.zoom_by(1.0 / 1.3)], ["+", func(): map.zoom_by(1.3)], ["Whole track", func(): map.frame_all()]]:
		var b := UIStyle.button(t[0], t[1], false, 22)
		b.custom_minimum_size = Vector2(64 if t[0].length() == 1 else 0, 52)
		tools.add_child(b)
	_del_btn = UIStyle.stop_button("Remove point", _delete_point, 20)
	_del_btn.custom_minimum_size = Vector2(0, 52)
	_del_btn.visible = false
	tools.add_child(_del_btn)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tools.add_child(gap)
	var shapes := UIStyle.label("Start from", 18, UIStyle.FOG, "semibold")
	shapes.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shapes.size_flags_vertical = Control.SIZE_FILL
	tools.add_child(shapes)
	for s in [["gp", "GP"], ["kidney", "Kidney"], ["oval", "Oval"], ["club", "Club"]]:
		var kind: String = s[0]
		var b := UIStyle.button(s[1], func(): _template(kind), false, 20)
		b.custom_minimum_size = Vector2(0, 52)
		tools.add_child(b)

	# --- right: about the track, choices, save / share / race
	var right := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.9), false)
	sb.set_content_margin_all(16)
	right.add_theme_stylebox_override("panel", sb)
	right.custom_minimum_size = Vector2(410, 0)
	cols.add_child(right)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	right.add_child(v)
	_name = LineEdit.new()
	_name.placeholder_text = "Name your track"
	_name.max_length = 28
	_name.add_theme_font_override("font", UIStyle.font("extrabold", true))
	_name.add_theme_font_size_override("font_size", 28)
	UIStyle.field(_name)
	_name.custom_minimum_size = Vector2(0, 56)
	_name.text_changed.connect(func(t): track["name"] = t)
	v.add_child(_name)
	_stats = UIStyle.label("", 20, UIStyle.PAPER, "semibold")
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stats)
	_status = UIStyle.label("", 18, UIStyle.FOG, "semibold")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 50)
	v.add_child(_status)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	_chip(grid, "style", MyTracks.STYLES, MyTracks.STYLE_NAMES)
	_chip(grid, "tod", MyTracks.TODS, MyTracks.TOD_NAMES)
	_chip(grid, "hills", [0, 1, 2, 3], {0: "Flat", 1: "Gentle hills", 2: "Rolling hills", 3: "Mountain"})
	_chip(grid, "width", [0, 1, 2], {0: "Narrow road", 1: "Standard road", 2: "Wide road"})

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for b in [UIStyle.button("Save", _save_track, false, 22), UIStyle.button("Share", _share, false, 22)]:
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_mine_btn = UIStyle.button("", _show_mine, false, 22)
	_mine_btn.custom_minimum_size = Vector2(0, 54)
	_mine_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_mine_btn)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	v.add_child(crow)
	_code = LineEdit.new()
	_code.placeholder_text = "A friend's track code"
	_code.add_theme_font_override("font", UIStyle.font("bold"))
	_code.add_theme_font_size_override("font_size", 20)
	UIStyle.field(_code)
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.custom_minimum_size = Vector2(0, 52)
	crow.add_child(_code)
	var paste := UIStyle.button("Paste a code", _paste_code, false, 20)
	paste.custom_minimum_size = Vector2(0, 52)
	crow.add_child(paste)
	_race_btn = UIStyle.go_button("Race it", _race, 44)
	_race_btn.custom_minimum_size = Vector2(0, 72)
	v.add_child(_race_btn)
	_refresh_mine()


func _chip(parent: Node, key: String, values: Array, names: Dictionary) -> void:
	var b := UIStyle.button("", func():
		var i := values.find(track.get(key, values[0]))
		track[key] = values[(i + 1) % values.size()]
		_refresh_chips()
		_changed(), false, 20)
	b.custom_minimum_size = Vector2(0, 50)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_chips[key] = [b, values, names]


func _refresh_chips() -> void:
	for key in _chips:
		var b: Button = _chips[key][0]
		var names: Dictionary = _chips[key][2]
		b.text = String(names.get(track.get(key), "?"))
	map.style = String(track.get("style", "park"))
	map.half_width = MyTracks.half_width(track)
	map.refresh()


func _set_mode(m: String) -> void:
	map.mode = m
	map.selected = -1
	_del_btn.visible = false
	for key in _mode_btns:
		var b: Button = _mode_btns[key]
		var on: bool = key == m
		UIStyle._button_styles(b, UIStyle.APEX if on else Color(UIStyle.TARMAC_2, 0.96), UIStyle.INK if on else UIStyle.PAPER, UIStyle.APEX, UIStyle.INK)
	map.queue_redraw()
	_hint()


func _refresh_mine() -> void:
	var n := MyTracks.all().size()
	_mine_btn.text = "My tracks (%d)" % n if n > 0 else "My tracks"


# ------------------------------------------------------------ the track

func _open(t: Dictionary, from_id: String) -> void:
	track = t.duplicate(true)
	draft_from = from_id
	_name.text = String(track.get("name", ""))
	map.set_layout(MyTracks.control(track))
	map.selected = -1
	_undo.clear()
	_refresh_chips()
	_set_mode("shape" if map.ctrl.size() >= 3 else "draw")
	_changed()


func _template(kind: String) -> void:
	_push_undo()
	map.set_layout(MyTracks.template(kind))
	map.selected = -1
	if String(track.get("name", "")) == "" or String(track.get("name", "")) == "My track":
		track["name"] = "My track"
	track["seed"] = randi() % 65536
	_set_mode("shape")
	map.frame_all()
	_changed()


func _push_undo() -> void:
	_undo.append(map.ctrl.duplicate())
	if _undo.size() > 40:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		return
	map.set_layout(_undo.pop_back())
	map.selected = -1
	_del_btn.visible = false
	_changed()


func _delete_point() -> void:
	if map.selected < 0 or map.ctrl.size() <= 4:
		return
	_push_undo()
	map.ctrl.remove_at(map.selected)
	map.selected = -1
	_del_btn.visible = false
	map.refresh()
	_changed()


## The board changed: check it, and say what it's like.
func _changed() -> void:
	var ctrl := map.ctrl
	map.problems = MyTracks.problems(ctrl, int(track.get("width", 1))) if ctrl.size() >= 3 else []
	map.queue_redraw()
	_keep_draft()
	if ctrl.size() < 3:
		_stats.text = ""
		_race_btn.disabled = true
		_hint()
		return
	var pts := MyTracks.sample(ctrl, 4.0)
	var info := _describe(pts)
	_stats.text = "%.2f km   %d corners   longest straight %d m" % [MyTracks.length_of(pts) / 1000.0, info[0], info[1]]
	_race_btn.disabled = not map.problems.is_empty()
	if not map.problems.is_empty():
		_say(String(map.problems[0]["text"]), UIStyle.RED)
	else:
		_hint()


func _hint() -> void:
	if map == null or _status == null:
		return
	if not map.problems.is_empty():
		return
	if map.ctrl.size() < 3:
		_say("Trace a loop on the map with your finger. Two fingers zoom and move the map.", UIStyle.FOG)
	elif map.mode == "draw":
		_say("Ready to race. Draw again to start over, or Shape to adjust it.", UIStyle.GREEN)
	else:
		_say("Ready to race. Drag a point to move the road, tap the road to add a point.", UIStyle.GREEN)


func _say(text: String, col: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", col)


## [corners, longest straight in m], the way the race counts them.
static func _describe(pts: PackedVector2Array) -> Array:
	var n := pts.size()
	var step := 4.0
	var k := 3
	var curv := PackedFloat32Array()
	curv.resize(n)
	for i in n:
		var t1 := (pts[i] - pts[(i - k + n) % n]).normalized()
		var t2 := (pts[(i + k) % n] - pts[i]).normalized()
		curv[i] = t1.angle_to(t2) / (k * step)
	var corners := 0
	var straight := 0
	var run := 0
	var in_corner := false
	var last_sign := 0.0
	var gap := 0
	for j in n * 2:
		var c := curv[j % n]
		var tight := absf(c) > 1.0 / 180.0
		if j >= n:
			if absf(c) < 1.0 / 500.0:
				run += 1
				straight = maxi(straight, run)
			else:
				run = 0
			continue
		if tight and (not in_corner or signf(c) != last_sign):
			if not (gap * step < 40.0 and signf(c) == last_sign and corners > 0):
				corners += 1
			in_corner = true
			last_sign = signf(c)
			gap = 0
		elif not tight:
			in_corner = false
			gap += 1
	return [corners, int(straight * step)]


func _keep_draft() -> void:
	var t := track.duplicate(true)
	var pts := []
	for p in map.ctrl:
		pts.append([int(p.x), int(p.y)])
	t["ctrl"] = pts
	draft = t


## The board as a track to keep (control points tidied, a name).
func _finished() -> Dictionary:
	var t := MyTracks.new_track(map.ctrl, String(track.get("name", "")).strip_edges())
	for k in ["style", "tod", "hills", "width", "seed"]:
		t[k] = track.get(k, t[k])
	if String(t["name"]) == "":
		t["name"] = "My track"
	return t


func _save_track() -> String:
	if map.ctrl.size() < 3 or not map.problems.is_empty():
		_say("Fix the track first: " + (String(map.problems[0]["text"]) if not map.problems.is_empty() else "draw a loop."), UIStyle.RED)
		return ""
	var t := _finished()
	var id := MyTracks.store(t)
	if draft_from != "" and draft_from != id:
		MyTracks.remove(draft_from)
	draft_from = id
	track = t.duplicate(true)
	_keep_draft()
	_refresh_mine()
	_say("Saved in My tracks. Race it from here or from Quick race.", UIStyle.GREEN)
	return id


func _race() -> void:
	var id := _save_track()
	if id == "":
		return
	var car := String(save.get_setting("car"))
	if CarSpecs.is_boat(car) or not CarSpecs.is_known(car):
		var land := String(save.get_setting("land_car"))
		save.set_setting("car", land if CarSpecs.CATALOG.has(land) else Garage.STARTER)
	save.set_setting("track", id)
	save.set_setting("mode", "race")
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _share() -> void:
	if map.ctrl.size() < 3 or not map.problems.is_empty():
		_say("Fix the track before you share it.", UIStyle.RED)
		return
	var t := _finished()
	var km := MyTracks.length_of(MyTracks.sample(MyTracks.control(t), 4.0)) / 1000.0
	var text := MyTracks.share_text(t, km)
	DisplayServer.clipboard_set(text)
	_code.text = MyTracks.encode(t)
	_say("Copied, with a link. Send it to a friend: they tap the link, or Paste a code here.", UIStyle.GREEN)
	if OS.has_feature("mobile") or WebBridge.is_ios():
		OS.shell_open("https://wa.me/?text=" + text.uri_encode())


func _paste_code() -> void:
	var text := _code.text
	if MyTracks.decode(text).is_empty() and not WebBridge.is_web():
		text = DisplayServer.clipboard_get()
	var t := MyTracks.decode(text)
	if t.is_empty():
		_say("That isn't a whole track code. Copy all of it, from APX1- to the end.", UIStyle.RED)
		return
	_push_undo()
	var mine := MyTracks.ids().has(String(t["id"]))
	if not mine:
		MyTracks.extra[String(t["id"])] = t
	_open(t, String(t["id"]) if mine else "")
	map.frame_all()
	_code.text = ""
	_say("%s is on the board. Race it, or Save to keep it." % String(t["name"]), UIStyle.GREEN)


# ------------------------------------------------------------ my tracks

func _show_mine() -> void:
	if _overlay != null:
		_overlay.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	_overlay = root
	root.tree_exited.connect(layer.queue_free)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			root.queue_free()
			_overlay = null)
	root.add_child(dim)
	var sheet := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.97), false)
	sb.set_content_margin_all(22)
	sheet.add_theme_stylebox_override("panel", sb)
	sheet.custom_minimum_size = Vector2(900, 560)
	root.add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	sheet.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := UIStyle.label("My tracks", 30, UIStyle.PAPER, "display")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := UIStyle.button("Close", func():
		root.queue_free()
		_overlay = null, false, 22)
	close.custom_minimum_size = Vector2(120, 52)
	top.add_child(close)
	var newb := UIStyle.button("New track", func():
		root.queue_free()
		_overlay = null
		_open(MyTracks.new_track([], "My track"), "")
		map.ctrl = []
		map.refresh()
		_changed()
		map.frame_all(), false, 22)
	newb.custom_minimum_size = Vector2(150, 52)
	top.add_child(newb)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var tracks := MyTracks.all()
	if tracks.is_empty():
		var l := UIStyle.label("No tracks yet. Draw one and tap Save.", 22, UIStyle.FOG, "semibold")
		list.add_child(l)
	for t in tracks:
		list.add_child(_track_row(t, root))


func _track_row(t: Dictionary, root: Control) -> Control:
	var id := String(t["id"])
	var row := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC_2, 0.9), false)
	sb.set_content_margin_all(10)
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var mm := MiniMap.new()
	mm.show_panel = false
	mm.line_width = 3.0
	mm.custom_minimum_size = Vector2(150, 84)
	h.add_child(mm)
	var flat := MyTracks.sample(MyTracks.control(t), 8.0)
	var pts := PackedVector3Array()
	for p in flat:
		pts.append(Vector3(p.x, 0, p.y))
	mm.set_points.call_deferred(pts)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	h.add_child(info)
	info.add_child(UIStyle.label(String(t.get("name", "My track")), 24, UIStyle.PAPER, "extrabold", true))
	var best: int = save.get_best_lap(save.lap_key(id, String(save.get_setting("car"))))
	var e := MyTracks.entry(id)
	var line := "%.2f km, %s" % [MyTracks.length_of(flat) / 1000.0, String(e["desc"]).get_slice(" · ", 1).to_lower()]
	if best >= 0:
		line += ". Best %s" % UIStyle.fmt_time(best / 1000.0)
	info.add_child(UIStyle.label(line, 18, UIStyle.FOG, "semibold"))
	var open := UIStyle.button("Edit", func():
		root.queue_free()
		_overlay = null
		_open(t, id)
		map.frame_all(), false, 20)
	open.custom_minimum_size = Vector2(90, 52)
	open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(open)
	var race := UIStyle.go_button("Race", func():
		save.set_setting("track", id)
		var car := String(save.get_setting("car"))
		if CarSpecs.is_boat(car):
			var land := String(save.get_setting("land_car"))
			save.set_setting("car", land if CarSpecs.CATALOG.has(land) else Garage.STARTER)
		save.set_setting("mode", "race")
		get_tree().change_scene_to_file("res://scenes/menu.tscn"), 30)
	race.custom_minimum_size = Vector2(100, 52)
	race.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(race)
	var del := UIStyle.stop_button("Delete", Callable(), 20)
	del.custom_minimum_size = Vector2(100, 52)
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del.pressed.connect(func():
		if del.text != "Sure?":
			del.text = "Sure?"
			return
		MyTracks.remove(id)
		if draft_from == id:
			draft_from = ""
		row.queue_free()
		_refresh_mine())
	h.add_child(del)
	return row
