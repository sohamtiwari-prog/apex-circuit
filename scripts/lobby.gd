extends Control
## Multiplayer lobby.
##   Not connected: enter your name, then host or join, on the same Wi-Fi /
##   hotspot (games nearby are listed; or type the host's address) or online
##   (create a game and share its code, or enter a friend's code).
##   Connected: everyone's name and car; the host picks the track and race
##   settings and starts; bots fill the grid.

var save: Node
var Net: Node
var _connect_view: Control
var _lobby_view: Control
var _status: Label
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _code_edit: LineEdit
var _server_edit: LineEdit
var _found_box: VBoxContainer
var _title: Label
var _subtitle: Label
var _players_box: VBoxContainer
var _settings_box: VBoxContainer
var _track_label: Label
var _chips := {}
var _car_label: Label
var _start_btn: Button
var _wait_label: Label
var _invite_row: HBoxContainer
var _chat_lines: Array[String] = []
var _chat_lbl: Label

# Shared lobby state lives on Net (it survives going to a race and back):
#   Net.players: {peer id: {name, car, team}}, Net.settings: {...}


func _ready() -> void:
	save = get_node("/root/Save")
	Net = get_node("/root/Net")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIStyle.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = UIStyle.APEX
	stripe.position = Vector2(0, 0)
	stripe.size = Vector2(8, 4000)
	add_child(stripe)
	_build_connect_view()
	_build_lobby_view()
	Net.joined.connect(_on_joined)
	Net.failed.connect(func(r: String): _show_status(r, UIStyle.RED))
	Net.closed.connect(_on_closed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.message.connect(_on_message)
	Net.games_found.connect(_on_games_found)
	Net.chat_received.connect(_on_chat)
	var pt := Timer.new()
	pt.wait_time = 2.0
	pt.autostart = true
	pt.timeout.connect(_share_pings)
	add_child(pt)
	if not Net.has_meta("players"):
		Net.set_meta("players", {})
		Net.set_meta("settings", _default_settings())
	if Net.is_online() and Net.my_id != 0:
		Net.start_info = {}
		_show_lobby()
		# Back from a race: ranks may have gone up.
		if Net.is_host():
			if _players().has(1):
				_players()[1]["rp"] = _my_rp()
			_broadcast_lobby()
		else:
			var me: Dictionary = _players().get(Net.my_id, {})
			Net.send(1, {"t": "hello", "name": String(me.get("name", _my_name())), "car": String(save.get_setting("car")), "team": int(save.get_setting("team")), "rp": _my_rp()})
	else:
		_show_connect()


func _players() -> Dictionary:
	return Net.get_meta("players", {})


func _settings() -> Dictionary:
	return Net.get_meta("settings", _default_settings())


func _default_settings() -> Dictionary:
	return {"track": String(save.get_setting("track")), "laps": int(save.get_setting("laps")),
		"grid": 20, "difficulty": String(save.get_setting("difficulty")), "tod": String(save.get_setting("time_of_day"))}


func _my_name() -> String:
	var n := _name_edit.text.strip_edges() if _name_edit != null else ""
	if n == "":
		n = "Player"
	return n.substr(0, 14)


# ------------------------------------------------------------ connect view

func _field(placeholder: String, text: String, width := 0.0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.add_theme_font_override("font", UIStyle.font("semibold"))
	e.add_theme_font_size_override("font_size", 24)
	var sb := UIStyle.panel(Color(UIStyle.TARMAC_2, 1.0), false, Color(0, 0, 0, 0), 4)
	sb.content_margin_left = 14
	sb.border_color = Color(UIStyle.PAPER, 0.2)
	sb.set_border_width_all(2)
	var fsb := sb.duplicate() as StyleBoxFlat
	fsb.border_color = UIStyle.APEX
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", fsb)
	e.add_theme_color_override("font_color", UIStyle.PAPER)
	e.add_theme_color_override("font_placeholder_color", UIStyle.FOG)
	e.custom_minimum_size = Vector2(width, 56)
	if width == 0.0:
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


func _section(parent: Node, title: String, note: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.95), false, UIStyle.APEX, 6)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UIStyle.label(title, 30, UIStyle.PAPER, "extrabold", true))
	var n := UIStyle.label(note, 19, UIStyle.FOG, "medium")
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	return v


func _build_connect_view() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26 if side != "left" else 34)
	add_child(margin)
	_connect_view = margin
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	scroll.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var back := UIStyle.button("‹", func(): _to_menu(), false, 44)
	back.custom_minimum_size = Vector2(76, 60)
	head.add_child(back)
	head.add_child(UIStyle.label("Race with friends", 44, UIStyle.PAPER, "extrabold", true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UIStyle.label("Your name", 22, UIStyle.FOG, "semibold"))
	_name_edit = _field("Your name", String(save.get_setting("player_name")), 260)
	_name_edit.max_length = 14
	_name_edit.text_changed.connect(func(t: String): save.set_setting("player_name", t.strip_edges()))
	head.add_child(_name_edit)

	_status = UIStyle.label("", 22, UIStyle.YELLOW, "bold", true)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	root.add_child(cols)

	# Same Wi-Fi / hotspot.
	var lan := _section(cols, "Same Wi-Fi or hotspot", "Everyone on one Wi-Fi network, or connected to the host's phone hotspot. No internet needed.")
	var host_lan := UIStyle.button("Host a game here", func():
		if Net.host_lan(_my_name()):
			_enter_as_host(), true, 26)
	host_lan.custom_minimum_size = Vector2(0, 66)
	lan.add_child(host_lan)
	lan.add_child(UIStyle.label("Games nearby", 20, UIStyle.FOG, "semibold"))
	_found_box = VBoxContainer.new()
	_found_box.add_theme_constant_override("separation", 6)
	lan.add_child(_found_box)
	var none := UIStyle.label("Looking for games on this network…", 20, UIStyle.FOG, "medium")
	_found_box.add_child(none)
	_my_ip_lbl = UIStyle.label("", 18, UIStyle.FOG, "medium", true)
	_my_ip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lan.add_child(_my_ip_lbl)
	_update_my_ip()
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(_update_my_ip)
	add_child(t)
	var iprow := HBoxContainer.new()
	iprow.add_theme_constant_override("separation", 8)
	lan.add_child(iprow)
	_ip_edit = _field("Host's address, e.g. 192.168.43.1", String(save.get_setting("last_ip")))
	iprow.add_child(_ip_edit)
	var join_ip := UIStyle.button("Join", func(): _join_ip(_ip_edit.text), false, 24)
	join_ip.custom_minimum_size = Vector2(110, 56)
	iprow.add_child(join_ip)

	# Online.
	var online := _section(cols, "Online", "Friends anywhere, over mobile data or any Wi-Fi. Create a game and send them its 4-letter code. Uses free public servers: nothing to set up.")
	var host_online := UIStyle.button("Create an online game", func(): _create_online(), true, 26)
	host_online.custom_minimum_size = Vector2(0, 66)
	online.add_child(host_online)
	var coderow := HBoxContainer.new()
	coderow.add_theme_constant_override("separation", 8)
	online.add_child(coderow)
	_code_edit = _field("Game code", "", 0)
	_code_edit.max_length = 4
	_code_edit.add_theme_font_size_override("font_size", 30)
	coderow.add_child(_code_edit)
	var join_code := UIStyle.button("Join", func(): _join_code(_code_edit.text), false, 24)
	join_code.custom_minimum_size = Vector2(110, 56)
	coderow.add_child(join_code)
	online.add_child(UIStyle.label("Own server (optional: everyone must use the same one)", 18, UIStyle.FOG, "semibold"))
	var saved := String(save.get_setting("server_url"))
	if saved == Net.DEFAULT_SERVER:
		saved = ""                   # old default: back to the free servers
	_server_edit = _field("Leave empty for the free servers", saved)
	_server_edit.add_theme_font_size_override("font_size", 18)
	_server_edit.custom_minimum_size = Vector2(0, 46)
	_server_edit.text_changed.connect(func(t: String): save.set_setting("server_url", t.strip_edges()))
	online.add_child(_server_edit)


var _my_ip_lbl: Label

## Shows this phone's Wi-Fi address, so friends can check they're on the
## same network (the first three numbers must match).
func _update_my_ip() -> void:
	if _my_ip_lbl == null:
		return
	var ips: Array[String] = Net.lan_addresses()
	if ips.is_empty():
		_my_ip_lbl.text = "This phone isn't on Wi-Fi or a hotspot yet."
		_my_ip_lbl.add_theme_color_override("font_color", UIStyle.YELLOW)
	else:
		_my_ip_lbl.text = "This phone: %s" % "  ·  ".join(ips)
		_my_ip_lbl.add_theme_color_override("font_color", UIStyle.FOG)


## Own relay server address, or "" for the free public servers.
func _server_url() -> String:
	return _server_edit.text.strip_edges()


func _create_online() -> void:
	if _server_url() == "":
		_show_status("Connecting to the free online servers…", UIStyle.FOG)
		Net.host_public(_my_name())
	else:
		_show_status("Connecting to your server… (up to a minute if it was asleep)", UIStyle.FOG)
		Net.host_online(_server_url(), _my_name())


func _join_code(text: String) -> void:
	var code := text.strip_edges().to_upper()
	if code.length() != 4:
		_show_status("Game codes are 4 letters or numbers.", UIStyle.YELLOW)
		return
	if _server_url() == "":
		_show_status("Looking for game %s…" % code, UIStyle.FOG)
		Net.join_public(code)
	else:
		_show_status("Connecting to your server… (up to a minute if it was asleep)", UIStyle.FOG)
		Net.join_online(_server_url(), code)


func _join_ip(ip: String) -> void:
	ip = ip.strip_edges()
	if ip == "":
		_show_status("Type the address shown on the host's screen.", UIStyle.YELLOW)
		return
	save.set_setting("last_ip", ip)
	_show_status("Joining %s…" % ip, UIStyle.FOG)
	Net.join_lan(ip)


func _on_games_found(games: Array) -> void:
	for c in _found_box.get_children():
		c.queue_free()
	if games.is_empty():
		_found_box.add_child(UIStyle.label("Looking for games on this network…", 20, UIStyle.FOG, "medium"))
		return
	for g in games:
		var ip: String = g["ip"]
		var b := UIStyle.button("%s's game  (%d in lobby)" % [g["name"], g["players"]], func(): _join_ip(ip), false, 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 56)
		_found_box.add_child(b)


func _show_connect() -> void:
	_connect_view.visible = true
	_lobby_view.visible = false
	Net.start_discovery()


func _show_status(text: String, colour: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)


# ------------------------------------------------------------ lobby view

func _build_lobby_view() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26 if side != "left" else 34)
	add_child(margin)
	_lobby_view = margin
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	_title = UIStyle.label("", 40, UIStyle.PAPER, "extrabold", true)
	left.add_child(_title)
	_subtitle = UIStyle.label("", 22, UIStyle.FOG, "semibold")
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_subtitle)
	_invite_row = HBoxContainer.new()
	_invite_row.add_theme_constant_override("separation", 10)
	left.add_child(_invite_row)
	var wa := UIStyle.button("Invite on WhatsApp", func(): _invite_whatsapp(), true, 22)
	wa.custom_minimum_size = Vector2(250, 54)
	_invite_row.add_child(wa)
	var cp := UIStyle.button("Copy code", func():
		DisplayServer.clipboard_set(Net.room_code)
		_toast("Code %s copied" % Net.room_code), false, 22)
	cp.custom_minimum_size = Vector2(160, 54)
	_invite_row.add_child(cp)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_players_box)
	_chat_lbl = UIStyle.label("", 20, UIStyle.PAPER, "semibold")
	_chat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_chat_lbl)
	var mine := HBoxContainer.new()
	mine.add_theme_constant_override("separation", 10)
	left.add_child(mine)
	mine.add_child(UIStyle.label("Your car", 22, UIStyle.FOG, "semibold"))
	var prev := UIStyle.button("‹", func(): _step_car(-1), false, 40)
	prev.custom_minimum_size = Vector2(70, 56)
	mine.add_child(prev)
	_car_label = UIStyle.label("", 26, UIStyle.PAPER, "bold", true)
	_car_label.custom_minimum_size = Vector2(230, 0)
	_car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mine.add_child(_car_label)
	var next := UIStyle.button("›", func(): _step_car(1), false, 40)
	next.custom_minimum_size = Vector2(70, 56)
	mine.add_child(next)
	# Quick chat: tap a phrase, everyone sees it.
	var chat := HBoxContainer.new()
	chat.add_theme_constant_override("separation", 6)
	left.add_child(chat)
	for i in Net.CHAT.size():
		var k: int = i
		var b := UIStyle.button(Net.CHAT[i], func(): Net.chat(k), false, 18)
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat.add_child(b)

	var right := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.95), false, UIStyle.APEX, 6)
	sb.set_content_margin_all(18)
	right.add_theme_stylebox_override("panel", sb)
	right.custom_minimum_size = Vector2(430, 0)
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 10)
	rv.add_child(_settings_box)
	var trow := HBoxContainer.new()
	_settings_box.add_child(trow)
	_track_label = UIStyle.label("", 26, UIStyle.PAPER, "extrabold", true)
	_track_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trow.add_child(_track_label)
	for d in [-1, 1]:
		var dd: int = d
		var b := UIStyle.button("‹" if d < 0 else "›", func(): _step_track(dd), false, 40)
		b.custom_minimum_size = Vector2(62, 56)
		trow.add_child(b)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	_settings_box.add_child(chips)
	_chip(chips, "laps", [[3, "3 laps"], [5, "5 laps"], [10, "10 laps"], [1, "1 lap"]])
	_chip(chips, "grid", [[20, "20 cars"], [12, "12 cars"], [6, "6 cars"]])
	var chips2 := HBoxContainer.new()
	chips2.add_theme_constant_override("separation", 8)
	_settings_box.add_child(chips2)
	_chip(chips2, "difficulty", [["medium", "Medium bots"], ["hard", "Hard bots"], ["easy", "Easy bots"]])
	_chip(chips2, "tod", [["auto", "Track's own time"], ["day", "Daytime"], ["sunset", "Sunset"], ["night", "Night"]])
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sp)
	_wait_label = UIStyle.label("The host picks the track and starts the race.", 22, UIStyle.FOG, "semibold")
	_wait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_wait_label)
	_start_btn = UIStyle.button("Start race", func(): _start_race(), true, 40)
	_start_btn.custom_minimum_size = Vector2(0, 86)
	rv.add_child(_start_btn)
	var leave := UIStyle.button("Leave", func():
		Net.leave()
		_players().clear()
		_show_connect(), false, 24)
	leave.custom_minimum_size = Vector2(0, 56)
	rv.add_child(leave)


func _chip(parent: Node, key: String, choices: Array) -> void:
	var b := UIStyle.button("", func():
		if not Net.is_host():
			return
		var cur := str(_settings().get(key))
		var i := 0
		for k in range(choices.size()):
			if str(choices[k][0]) == cur:
				i = k
		_settings()[key] = choices[(i + 1) % choices.size()][0]
		_broadcast_lobby(), false, 20)
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_chips[key] = [b, choices]


func _show_lobby() -> void:
	Net.stop_discovery()
	_connect_view.visible = false
	_lobby_view.visible = true
	_refresh_lobby()


func _refresh_lobby() -> void:
	var host: bool = Net.is_host()
	_invite_row.visible = Net.transport == "online" or Net.transport == "public"
	if _invite_row.visible:
		_title.text = "Game code  %s" % Net.room_code
		_subtitle.text = "Friends anywhere open Friends, type this code under Online and tap Join."
	else:
		_title.text = "Wi-Fi game"
		var ips: Array[String] = Net.lan_addresses()
		var addr := "  or  ".join(ips) if not ips.is_empty() else "(turn on Wi-Fi or your hotspot)"
		_subtitle.text = ("Friends on this Wi-Fi see your game in their list, or type  %s" % addr) if host else "Connected to the host on this network."
	for c in _players_box.get_children():
		c.queue_free()
	var ps := _players()
	var ids := ps.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = ps[id]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIStyle.panel(Color(UIStyle.APEX, 0.95) if int(id) == Net.my_id else Color(UIStyle.TARMAC_2, 0.95)))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var ink := UIStyle.INK if int(id) == Net.my_id else UIStyle.PAPER
		var rp := int(p.get("rp", 0))
		var badge := RankBadge.new()
		badge.custom_minimum_size = Vector2(30, 34)
		badge.rp = rp
		h.add_child(badge)
		var tier := UIStyle.label(Ranks.tier_name(rp), 18, Ranks.tier_color(rp) if int(id) != Net.my_id else UIStyle.INK, "extrabold", true)
		tier.custom_minimum_size = Vector2(110, 0)
		h.add_child(tier)
		var n := UIStyle.label(String(p["name"]) + ("  (host)" if int(id) == 1 else ""), 24, ink, "bold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var ping := int(p.get("ping", -1))
		if int(id) != 1 and ping >= 0:
			var pc := UIStyle.GREEN if ping < 150 else (UIStyle.YELLOW if ping < 300 else UIStyle.RED)
			if int(id) == Net.my_id:
				pc = UIStyle.INK
			h.add_child(UIStyle.label("%d ms" % ping, 20, pc, "bold", true))
		h.add_child(UIStyle.label(CarSpecs.display_name(String(p["car"])), 22, Color(ink, 0.8), "semibold"))
		_players_box.add_child(row)
	var st := _settings()
	var grid := int(st.get("grid", 20))
	var bots := maxi(grid - ps.size(), 0)
	var info := UIStyle.label("%d bot%s fill the grid to %d cars" % [bots, "" if bots == 1 else "s", maxi(grid, ps.size())], 20, UIStyle.FOG, "medium")
	_players_box.add_child(info)
	_track_label.text = Track.catalog_name(String(st.get("track", "silvermoor")))
	for key in _chips:
		var b: Button = _chips[key][0]
		var choices: Array = _chips[key][1]
		var cur := str(st.get(key))
		b.text = choices[0][1]
		for c in choices:
			if str(c[0]) == cur:
				b.text = c[1]
		b.disabled = not host
	_start_btn.visible = host
	_wait_label.visible = not host
	var me: Dictionary = ps.get(Net.my_id, {"car": save.get_setting("car")})
	_car_label.text = CarSpecs.display_name(String(me.get("car", "gp26")))
	Net.lobby_players = ps.size()


func _step_car(d: int) -> void:
	var ids: Array = Array(CarSpecs.CATALOG)
	var cur := ids.find(String(save.get_setting("car")))
	var id: String = ids[posmod(cur + d, ids.size())]
	save.set_setting("car", id)
	var pick := {"name": _my_name(), "car": id, "team": int(save.get_setting("team")), "rp": _my_rp()}
	if Net.is_host():
		_players()[1] = pick
		_broadcast_lobby()
	else:
		Net.send(1, {"t": "hello", "name": pick["name"], "car": id, "team": pick["team"], "rp": pick["rp"]})
		_players()[Net.my_id] = pick
		_refresh_lobby()


func _step_track(d: int) -> void:
	if not Net.is_host():
		return
	var ids: Array = []
	for t in Track.CATALOG:
		ids.append(t["id"])
	var cur := ids.find(String(_settings().get("track")))
	_settings()["track"] = ids[posmod(cur + d, ids.size())]
	_broadcast_lobby()


# ------------------------------------------------------------ protocol

func _enter_as_host() -> void:
	_players().clear()
	_players()[1] = {"name": _my_name(), "car": String(save.get_setting("car")), "team": int(save.get_setting("team")), "rp": _my_rp()}
	Net.set_meta("settings", _default_settings())
	_show_status("", UIStyle.FOG)
	_show_lobby()


func _on_joined() -> void:
	if Net.is_host():
		_enter_as_host()        # online host: room created
		return
	_players().clear()
	_show_status("", UIStyle.FOG)
	Net.send(1, {"t": "hello", "name": _my_name(), "car": String(save.get_setting("car")), "team": int(save.get_setting("team")), "rp": _my_rp()})
	_show_lobby()


func _on_peer_joined(_id: int) -> void:
	pass                        # they introduce themselves with "hello"


func _on_peer_left(id: int) -> void:
	if Net.is_host() and _players().has(id):
		_players().erase(id)
		_broadcast_lobby()


func _on_closed(reason: String) -> void:
	_players().clear()
	_show_connect()
	_show_status(reason, UIStyle.YELLOW)


func _broadcast_lobby() -> void:
	if not Net.is_host():
		return
	Net.send(0, {"t": "lobby", "players": _players(), "settings": _settings()})
	_refresh_lobby()


func _on_message(from: int, m: Dictionary) -> void:
	match String(m.get("t", "")):
		"hello":
			if Net.is_host():
				_players()[from] = {"name": String(m.get("name", "Player")).substr(0, 14), "car": String(m.get("car", "gp26")), "team": int(m.get("team", 0)), "rp": maxi(int(m.get("rp", 0)), 0)}
				_broadcast_lobby()
		"lobby":
			Net.set_meta("players", m["players"])
			Net.set_meta("settings", m["settings"])
			_refresh_lobby()
		"start":
			Net.start_info = m["info"]
			get_tree().change_scene_to_file("res://scenes/race.tscn")
		"busy":
			Net.leave()
			_show_connect()
			_show_status("That game is mid-race. Try again when it finishes.", UIStyle.YELLOW)


## Host: grid with everyone mid-field and bots around them, then go.
func _start_race() -> void:
	var st := _settings()
	var ps := _players()
	var ids := ps.keys()
	ids.sort()
	var total := maxi(int(st.get("grid", 20)), ids.size())
	var first_human := clampi(total / 2 - ids.size(), 0, total - ids.size())
	var base_skill: float = {"easy": 0.86, "medium": 0.93, "hard": 0.985}.get(String(st.get("difficulty")), 0.93)
	var names: Array = load("res://scripts/race.gd").DRIVER_NAMES
	var host_car := String(ps[1]["car"]) if ps.has(1) else "gp26"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var grid: Array = []
	var bot := 0
	var human := 0
	for slot in range(total):
		if slot >= first_human and human < ids.size():
			var id: int = ids[human]
			var p: Dictionary = ps[id]
			grid.append({"slot": slot, "kind": "player", "id": id, "name": p["name"], "car": p["car"], "team": int(p.get("team", 0))})
			human += 1
		else:
			grid.append({"slot": slot, "kind": "bot", "id": 0, "name": names[bot % names.size()], "car": host_car,
				"team": (bot / 2) % CarSpecs.TEAMS.size() if host_car == "gp26" else bot + 1,
				"skill": clampf(base_skill + rng.randf_range(-0.02, 0.02) - slot * 0.0015, 0.75, 1.0)})
			bot += 1
	var info := {"settings": st, "grid": grid}
	Net.start_info = info
	Net.send(0, {"t": "start", "info": info})
	get_tree().change_scene_to_file("res://scenes/race.tscn")


## Host: put everyone's ping in the lobby (when it changes noticeably).
func _share_pings() -> void:
	if not Net.is_host() or not _lobby_view.visible:
		return
	var changed := false
	for id in _players():
		if int(id) == 1:
			continue
		var now := int(Net.pings.get(int(id), -1))
		var was := int(_players()[id].get("ping", -1))
		if absi(now - was) > 15 or (now >= 0) != (was >= 0):
			_players()[id]["ping"] = now
			changed = true
	if changed:
		_broadcast_lobby()


func _invite_whatsapp() -> void:
	var text := "Race me in Apex Circuit! Open Friends, type code %s under Online and tap Join.\nNo game yet? Get it here: https://github.com/sohamtiwari-prog/apex-circuit/releases/latest" % Net.room_code
	OS.shell_open("https://wa.me/?text=" + text.uri_encode())


func _on_chat(from: int, text: String) -> void:
	var who := "Someone"
	if _players().has(from):
		who = String(_players()[from]["name"])
	_chat_lines.append("%s: %s" % [who, text])
	while _chat_lines.size() > 3:
		_chat_lines.pop_front()
	_chat_lbl.text = "\n".join(_chat_lines)


func _toast(text: String) -> void:
	_chat_lines.append(text)
	while _chat_lines.size() > 3:
		_chat_lines.pop_front()
	_chat_lbl.text = "\n".join(_chat_lines)


func _my_rp() -> int:
	return int(save.data.get("rank_points", 0))


func _to_menu() -> void:
	Net.stop_discovery()
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
