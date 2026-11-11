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
	UIStyle.use_menus()
	save = get_node("/root/Save")
	DisplayServer.screen_set_keep_on(true)
	car_ids = Array(CarSpecs.CATALOG)
	for t in Track.CATALOG:
		track_ids.append(t["id"])
	_build_stage()
	_build_ui()
	UIStyle.reveal_boards.call_deferred(self)
	_select_team(int(save.get_setting("team")), false)
	_select_car(String(save.get_setting("car")), false)
	_select_track(String(save.get_setting("track")), false)
	_refresh_mode()


# ------------------------------------------------------------ 3D stage

func _build_stage() -> void:
	var room := Showroom.new()
	add_child(room)
	room.build(Vector3(5.6, 1.9, 6.4), Vector3(0.9, 0.15, -1.6), 36.0)
	showcase = room.showcase


func _show_car(id: String) -> void:
	if preview != null:
		preview.queue_free()
	preview = RaceCar.new()
	preview.setup(save.car_spec(id, int(save.get_setting("team")) if id == "gp26" else 0))
	preview.freeze = true
	showcase.add_child(preview)
	preview.position.y = preview.spawn_height() - 0.05




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
	var head: Array = UIStyle.header("Quick race", func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"), "%d stars" % Career.total_stars(save))
	left.add_child(head[0])
	_owned_lbl = UIStyle.outlined(UIStyle.label("", 22, UIStyle.FOG, "bold", true), 4)
	left.add_child(_owned_lbl)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(sp)

	var stats := PanelContainer.new()
	var ssb := UIStyle.panel(Color(UIStyle.TARMAC, 0.78))
	ssb.set_content_margin_all(14)
	stats.add_theme_stylebox_override("panel", ssb)
	stats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stats.custom_minimum_size = Vector2(460, 0)
	left.add_child(stats)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 2)
	stats.add_child(sv)
	_car_kind = UIStyle.outlined(UIStyle.label("", 20, UIStyle.FOG, "bold", true), 4)
	sv.add_child(_car_kind)
	_car_name = UIStyle.outlined(UIStyle.label("", 30, UIStyle.PAPER, "display"), 6)
	sv.add_child(_car_name)
	for stat in ["Power", "Grip", "Top speed"]:
		_stat_row(sv, stat)

	_team_row = HBoxContainer.new()
	_team_row.add_theme_constant_override("separation", 8)
	_team_name = UIStyle.outlined(UIStyle.label("", 20, UIStyle.PAPER, "semibold"), 4)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	sv.add_child(gap)
	sv.add_child(_team_name)
	sv.add_child(_team_row)
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
	prev.visible = CarSpecs.CATALOG.size() > 1      # (one car for now: nothing to step through)
	next.visible = prev.visible
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
	track_bg.color = UIStyle.TARMAC_2
	track_bg.custom_minimum_size = Vector2(200, 8)
	track_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(track_bg)
	var fill := ColorRect.new()
	fill.color = UIStyle.PAPER
	fill.size = Vector2(0, 8)
	track_bg.add_child(fill)
	var val := UIStyle.label("", 20, UIStyle.PAPER, "bold", true)
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	_bars[stat] = [fill, val]


func _build_track_side(cols: Control) -> void:
	var right := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.88), false)
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
	_map.custom_minimum_size = Vector2(0, 56)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_map)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	_track_tag = UIStyle.label("", 20, UIStyle.PAPER, "medium")
	_track_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_track_tag)
	_track_count = UIStyle.label("", 18, UIStyle.FOG, "semibold")
	foot.add_child(_track_count)

	# Your best here, and the kind of race (a chip, tap to change).
	var chips0 := HBoxContainer.new()
	chips0.add_theme_constant_override("separation", 8)
	v.add_child(chips0)
	var bests := VBoxContainer.new()
	bests.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bests.add_theme_constant_override("separation", -4)
	chips0.add_child(bests)
	best_label = UIStyle.label("", 20, UIStyle.PURPLE, "bold", true)
	bests.add_child(best_label)
	_type_rule = UIStyle.label("", 16, UIStyle.FOG, "medium")
	_type_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bests.add_child(_type_rule)
	_chip(chips0, "race_type", RACE_TYPES)
	(_chips["race_type"][0] as Button).size_flags_horizontal = Control.SIZE_FILL
	(_chips["race_type"][0] as Button).custom_minimum_size = Vector2(210, 46)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	v.add_child(chips)
	_chip(chips, "laps", [[3, "3 laps"], [5, "5 laps"], [10, "10 laps"], [15, "15 laps"], [20, "20 laps"], [30, "30 laps"], [1, "1 lap"]])
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
	_chip(chips3, "race_control", [[true, "Flags & penalties"], [false, "No penalties"]])
	var chips4 := HBoxContainer.new()
	chips4.add_theme_constant_override("separation", 8)
	v.add_child(chips4)
	_chip(chips4, "pit_mode", [["manual", "You drive the pits"], ["auto", "Auto pit stops"]])
	_chip(chips4, "racing_line", [[false, "No racing line"], [true, "Racing line"]])
	_chip(chips4, "ideal_ghost", [[false, "No ghost"], [true, "Ideal-lap ghost"]])

	# Time trial: race a friend's lap (a ghost code they sent you).
	_ghost_row = HBoxContainer.new()
	_ghost_row.add_theme_constant_override("separation", 8)
	v.add_child(_ghost_row)
	_ghost_code = LineEdit.new()
	_ghost_code.placeholder_text = "Friend's ghost code"
	_ghost_code.max_length = 8
	_ghost_code.add_theme_font_override("font", UIStyle.font("bold", true))
	_ghost_code.add_theme_font_size_override("font_size", 24)
	UIStyle.field(_ghost_code)
	_ghost_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ghost_code.custom_minimum_size = Vector2(0, 52)
	_ghost_row.add_child(_ghost_code)
	var gb := UIStyle.button("Race their lap", _fetch_ghost, false, 22)
	gb.custom_minimum_size = Vector2(0, 52)
	_ghost_row.add_child(gb)
	_ghost_status = UIStyle.label("", 18, UIStyle.FOG, "semibold")
	_ghost_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_ghost_status)
	# ...and send yours: your best lap on this track in this car, as a code.
	_share_row = HBoxContainer.new()
	_share_row.add_theme_constant_override("separation", 8)
	v.add_child(_share_row)
	_share_lbl = UIStyle.label("", 21, UIStyle.PAPER, "bold")
	_share_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_share_row.add_child(_share_lbl)
	_share_btn = UIStyle.button("Share my lap", _share_ghost, false, 22)
	_share_btn.custom_minimum_size = Vector2(0, 52)
	_share_row.add_child(_share_btn)
	var go := UIStyle.go_button("Race", _start, 46)
	go.custom_minimum_size = Vector2(0, 76)
	v.add_child(go)
	_chips["go"] = go


## Same setting value? (The save file is JSON: a number saved as 10 comes
## back as 10.0, and str() of the two never matched: the chip showed its
## first choice, "3 laps", for a 10-lap race.)
static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


## A chip that cycles through `choices` ([value, label] pairs) for a setting.
const RACE_TYPES := [["race", "Grand Prix race"], ["eliminator", "Eliminator"], ["duel", "Duel"],
	["overtake", "From the back"], ["checkpoint", "Checkpoint run"]]
const TYPE_HINTS := {
	"race": "A normal race from mid-grid.",
	"eliminator": "Last car out at the end of every lap.",
	"duel": "You and one rival, head to head.",
	"overtake": "Start last: how far up can you get?",
	"checkpoint": "Beat the clock to every gate. How far can you get?",
}
var _type_rule: Label


func _chip(parent: Node, key: String, choices: Array) -> void:
	var b := UIStyle.button("", func():
		var cur: Variant = save.get_setting(key)
		var i := 0
		for k in range(choices.size()):
			if _same(choices[k][0], cur):
				i = k
		save.set_setting(key, choices[(i + 1) % choices.size()][0])
		_refresh_mode()
		_refresh_info(), false, 20)
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_chips[key] = [b, choices]


func _refresh_mode() -> void:
	var mode := String(save.get_setting("mode"))
	for key in _mode_buttons:
		var b: Button = _mode_buttons[key]
		var on: bool = key == mode
		var sb := UIStyle.panel(UIStyle.APEX if on else Color(UIStyle.TARMAC_2, 0.9))
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", UIStyle.INK if on else UIStyle.FOG)
		b.add_theme_color_override("font_hover_color", UIStyle.INK if on else UIStyle.FOG)
	var rt := String(save.get_setting("race_type"))
	# What each kind of race leaves out.
	var off := {
		"checkpoint": ["laps", "opponents", "qualifying", "tyres", "race_control", "pit_mode", "ideal_ghost"],
		"duel": ["opponents", "qualifying"],
		"eliminator": ["qualifying"],
		"overtake": ["qualifying"],
	}
	for key in _chips:
		if key == "go":
			continue
		var b: Button = _chips[key][0]
		var choices: Array = _chips[key][1]
		var cur: Variant = save.get_setting(key)
		b.text = choices[0][1]
		for c in choices:
			if _same(c[0], cur):
				b.text = c[1]
		b.visible = (mode == "race" and not (off.get(rt, []) as Array).has(key)) or key == "time_of_day"
	if _ghost_row != null:
		_ghost_row.visible = mode == "time_trial"
		_ghost_status.visible = mode == "time_trial"
		if _ghost_status.text == "":
			_ghost_status.text = "A friend's code races their best lap as a ghost, on their track in their car."
		_share_row.visible = mode == "time_trial"
		var best: int = save.get_best_lap(save.lap_key(String(save.get_setting("track")), String(save.get_setting("car"))))
		_share_lbl.text = ("Your best here  %s" % UIStyle.fmt_time(best / 1000.0)) if best >= 0 else "No lap here yet in this car"
		_share_btn.disabled = best < 0 or GhostShare.saved_lap(save.lap_key(String(save.get_setting("track")), String(save.get_setting("car")))).size() <= 14 * 7
	if _type_rule != null:
		_type_rule.visible = mode == "race"
		_type_rule.text = String(TYPE_HINTS.get(rt, ""))
	(_chips["go"] as Button).text = ("Race" if rt != "checkpoint" else "Go") if mode == "race" else "Drive"


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
	_owned_lbl.text = "PR %.1f" % Garage.pr(spec)
	_owned_lbl.add_theme_color_override("font_color", UIStyle.PAPER)
	var parts: PackedStringArray = String(spec["desc"]).split(" · ")
	_car_kind.text = parts[0] if parts.size() > 0 else ""
	_car_count.text = ("Car %d of %d" % [car_ids.find(id) + 1, car_ids.size()]) if car_ids.size() > 1 else ""
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
	if String(save.get_setting("race_type")) == "checkpoint" and String(save.get_setting("mode")) == "race":
		var cpb: float = save.checkpoint_best(save.lap_key(track_id, car_id))
		best_label.text = ("Your furthest run here  %.2f km" % (cpb / 1000.0)) if cpb > 0.0 else "No checkpoint run here yet"
		best = 0 if cpb > 0.0 else -1
	best_label.add_theme_color_override("font_color", UIStyle.PURPLE if best >= 0 else UIStyle.FOG)


var _ghost_row: HBoxContainer
var _ghost_code: LineEdit
var _share_row: HBoxContainer
var _share_lbl: Label
var _share_btn: Button
var _ghost_status: Label


## Fetch a friend's lap by its code, then race it.
## Your best lap here as a ghost code: copied, and on a phone straight into
## WhatsApp with a message saying what to do with it.
func _share_ghost() -> void:
	var tid := String(save.get_setting("track"))
	var cid := String(save.get_setting("car"))
	_share_btn.disabled = true
	_share_btn.text = "Sending..."
	var gs := GhostShare.new()
	add_child(gs)
	gs.done.connect(func(ok, res):
		gs.queue_free()
		_share_btn.disabled = false
		_share_btn.text = "Share my lap"
		if not ok:
			_ghost_status.text = String(res)
			return
		var code := String(res)
		DisplayServer.clipboard_set(code)
		_ghost_status.text = "Your ghost code is %s (copied). A friend types it here, in Time trial." % code
		if OS.has_feature("mobile"):
			OS.shell_open("https://wa.me/?text=" + GhostShare.invite_text(save, String(Track.catalog_entry(tid)["name"]), save.get_best_lap(save.lap_key(tid, cid)), code).uri_encode()))
	gs.share_best(save, tid, cid, 20.0)


func _fetch_ghost() -> void:
	var code := GhostShare.clean_code(_ghost_code.text)
	if code.length() < 6:
		_ghost_status.text = "Codes are 6 letters and numbers."
		return
	_ghost_status.text = "Fetching %s..." % code
	var gs := GhostShare.new()
	add_child(gs)
	gs.done.connect(func(ok, res):
		gs.queue_free()
		if not ok:
			_ghost_status.text = String(res)
			return
		var ch: Dictionary = res
		if String(Track.catalog_entry(String(ch.get("track", "")))["id"]) != String(ch.get("track", "")) or not CarSpecs.CATALOG.has(String(ch.get("car", ""))):
			_ghost_status.text = "That lap is on a track or car this version doesn't have: update the game."
			return
		save.challenge = ch
		save.pending_event = {}
		get_tree().change_scene_to_file("res://scenes/race.tscn"))
	gs.download(code)


func _start() -> void:
	save.pending_event = {}
	save.challenge = {}
	var rt := String(save.get_setting("race_type"))
	if String(save.get_setting("mode")) == "race" and rt != "race":
		save.pending_event = quick_event(save)
	get_tree().change_scene_to_file("res://scenes/race.tscn")


## A quick race of another kind, as an event (no stars: it isn't the career).
static func quick_event(sv: Node) -> Dictionary:
	var rt := String(sv.get_setting("race_type"))
	var car := String(sv.get_setting("car"))
	var opp := int(sv.get_setting("opponents"))
	var laps := int(sv.get_setting("laps"))
	var ev := {
		"id": "", "type": rt, "track": String(sv.get_setting("track")), "car": car, "cars": [car],
		"laps": laps, "opponents": opp, "series_name": "Quick race", "return_to": "res://scenes/menu.tscn",
		"skill": {"easy": 0.87, "medium": 0.91, "hard": 0.95}.get(String(sv.get_setting("difficulty")), 0.91),
		"tod": String(sv.get_setting("time_of_day")), "weather": String(sv.get_setting("weather")),
		"tyres": String(sv.get_setting("tyres")), "team": int(sv.get_setting("team")),
	}
	match rt:
		"duel":
			ev["opponents"] = 1
		"checkpoint":
			ev["opponents"] = 0
			ev["laps"] = 99
		"eliminator":
			# Out at the end of every lap but the last; with a big grid, more
			# than one a lap, so it's down to the last two or three.
			laps = maxi(laps, 3)
			ev["laps"] = laps
			ev["elim_per_lap"] = maxi(1, int(ceil(float(opp - 1) / float(laps - 1))))
	return ev
