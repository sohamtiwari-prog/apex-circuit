extends Node3D
## Your driver: name, race number and helmet (your picture everywhere),
## the menus' look (light, dark, or as the phone is set), everyone who
## drives on this phone, and keeping your progress: a backup code to copy
## and restore on another phone or in the browser.
##
## The first time the game opens there's no driver yet, so this is the
## first screen: "Create your driver", then home.

const HELMETS := [
	"ffd200", "ff7310", "e01a1a", "9e0b2a", "ff5fb0", "6b2ccf", "1f5cd6", "38b6ff",
	"14b8b0", "18a84a", "b8f22e", "f2f2f2", "a9adb5", "3b4048", "000000", "c9a227",
]

var save: Node
var ui: CanvasLayer
var creating := false
var _name: LineEdit
var _helmet: HelmetBadge
var _num_lbl: Label
var _left: VBoxContainer
var _status: Label
var _restore: LineEdit
var _rstatus: Label
var _confirm_remove := ""


func _ready() -> void:
	UIStyle.use_menus()
	save = get_node("/root/Save")
	creating = not bool(save.driver().get("created", false))
	var room := Showroom.new()
	add_child(room)
	room.build(Vector3(5.0, 1.8, 6.2), Vector3(-2.6, 0.0, 2.4), 40.0)
	room.spin = 0.12
	var home := String(save.get_setting("garage_car"))
	room.show_spec(save.car_spec(home if CarSpecs.CATALOG.has(home) else Garage.STARTER))
	_build_ui()


func go_back() -> void:
	if creating:
		return                   # (a driver first)
	get_tree().change_scene_to_file("res://scenes/hub.tscn")


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
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)
	var head: Array = UIStyle.header("Create your driver" if creating else "Your driver",
		Callable() if creating else go_back)
	v.add_child(head[0])
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)

	var boards: Array = []
	boards.append(_identity_board(body))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(right)
	if creating:
		boards.append(_welcome_board(right))
	else:
		boards.append(_look_board(right))
		boards.append(_drivers_board(right))
		boards.append(_backup_board(right))
	UIStyle.reveal(boards)


func _board(parent: Control, title: String, expand := false) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := UIStyle.lift(UIStyle.panel(UIStyle.TARMAC, false))
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	if expand:
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	if title != "":
		v.add_child(UIStyle.label(title, 19, UIStyle.PAPER, "display"))
	return v


# ------------------------------------------------------------ who you are

func _identity_board(parent: Control) -> Control:
	var d: Dictionary = save.driver()
	var v := _board(parent, "", true)
	v.get_parent().custom_minimum_size = Vector2(700, 0)
	_left = v
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	v.add_child(top)
	_helmet = HelmetBadge.for_driver(d, 190.0)
	top.add_child(_helmet)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(col)
	col.add_child(UIStyle.label("Name", 20, UIStyle.FOG, "bold"))
	_name = LineEdit.new()
	_name.placeholder_text = "What should we call you?"
	_name.max_length = 16
	_name.text = String(d.get("name", ""))
	_name.add_theme_font_override("font", UIStyle.font("extrabold"))
	_name.add_theme_font_size_override("font_size", 30)
	_name.custom_minimum_size = Vector2(0, 64)
	UIStyle.field(_name)
	_name.text_changed.connect(func(_t): _store())
	col.add_child(_name)
	col.add_child(UIStyle.label("Race number", 20, UIStyle.FOG, "bold"))
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	col.add_child(nr)
	for dn in [-10, -1]:
		var dd: int = dn
		var b := UIStyle.button(str(dn), func(): _bump(dd), false, 22)
		b.custom_minimum_size = Vector2(64, 54)
		nr.add_child(b)
	_num_lbl = UIStyle.label(str(int(d.get("number", 26))), 30, UIStyle.PAPER, "display")
	_num_lbl.custom_minimum_size = Vector2(84, 0)
	_num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nr.add_child(_num_lbl)
	for dn in [1, 10]:
		var dd: int = dn
		var b := UIStyle.button("+%d" % dn, func(): _bump(dd), false, 22)
		b.custom_minimum_size = Vector2(64, 54)
		nr.add_child(b)
	_swatches(v, "Helmet", "helmet")
	_swatches(v, "Stripe", "helmet2")
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	if creating:
		var go := UIStyle.go_button("Start racing", _finish_create, 34)
		go.custom_minimum_size = Vector2(0, 76)
		v.add_child(go)
		_status = UIStyle.label("", 19, UIStyle.STOP, "bold")
		v.add_child(_status)
	return v.get_parent()


func _swatches(parent: Control, title: String, key: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	parent.add_child(h)
	var l := UIStyle.label(title, 20, UIStyle.FOG, "bold")
	l.custom_minimum_size = Vector2(80, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	for hex in HELMETS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("hex", hex)
		b.set_meta("key", key)
		var hh: String = hex
		b.pressed.connect(func():
			save.driver()[key] = hh
			_store()
			_mark_swatches())
		h.add_child(b)
	_mark_swatches.call_deferred()


func _mark_swatches() -> void:
	if _left == null:
		return
	for b in _left.find_children("*", "Button", true, false):
		if not b.has_meta("hex"):
			continue
		var hex := String(b.get_meta("hex"))
		var on := String(save.driver().get(String(b.get_meta("key")), "")) == hex
		var sb := UIStyle.panel(Color(hex), false)
		sb.border_color = UIStyle.PAPER if on else Color(UIStyle.PAPER, 0.2)
		sb.set_border_width_all(4 if on else 1)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)


func _bump(d: int) -> void:
	var n := clampi(int(save.driver().get("number", 26)) + d, 1, 99)
	save.driver()["number"] = n
	_num_lbl.text = str(n)
	_store()


## Keep what's on screen (the helmet updates as you go).
func _store() -> void:
	var d: Dictionary = save.driver()
	_helmet.base = Color(String(d["helmet"]))
	_helmet.stripe = Color(String(d["helmet2"]))
	_helmet.number = int(d["number"])
	if creating:
		return                   # (saved when you tap Start racing)
	var name := _name.text.strip_edges()
	save.set_driver(name if name != "" else String(d.get("name", "Driver")), int(d["number"]), String(d["helmet"]), String(d["helmet2"]))


func _finish_create() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		_status.text = "Type a name first: it's what friends see on the grid."
		_name.grab_focus()
		return
	var d: Dictionary = save.driver()
	save.set_driver(name, int(d["number"]), String(d["helmet"]), String(d["helmet2"]))
	get_tree().change_scene_to_file("res://scenes/hub.tscn")


# ------------------------------------------------------------ first visit

func _welcome_board(parent: Control) -> Control:
	var v := _board(parent, "Welcome to the paddock")
	var t := UIStyle.label("Pick a name, a number and your helmet colours. Your helmet is your picture on the home screen and next to your name on the grid.", 20, UIStyle.PAPER, "medium")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	v.add_child(UIStyle.label("Raced before on another phone?", 21, UIStyle.PAPER, "extrabold"))
	var t2 := UIStyle.label("Paste the backup code you copied there and carry on where you left off.", 19, UIStyle.FOG, "medium")
	t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t2)
	_restore_row(v)
	return v.get_parent()


func _restore_row(v: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_restore = LineEdit.new()
	_restore.placeholder_text = "APEX1:..."
	_restore.add_theme_font_override("font", UIStyle.font("semibold"))
	_restore.add_theme_font_size_override("font_size", 20)
	_restore.custom_minimum_size = Vector2(0, 54)
	_restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.field(_restore)
	row.add_child(_restore)
	var paste := UIStyle.button("Paste", func():
		if WebBridge.is_web():
			_restore.grab_focus()          # (the page's text box: hold in it, then Paste)
		else:
			_restore.text = DisplayServer.clipboard_get(), false, 20)
	paste.custom_minimum_size = Vector2(0, 54)
	row.add_child(paste)
	var go := UIStyle.button("Restore", _do_restore, true, 20)
	go.custom_minimum_size = Vector2(0, 54)
	row.add_child(go)
	_rstatus = UIStyle.label("", 18, UIStyle.FOG, "semibold")
	_rstatus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_rstatus)


func _do_restore() -> void:
	var err: String = save.restore_backup(_restore.text)
	if err != "":
		_rstatus.text = err
		_rstatus.add_theme_color_override("font_color", UIStyle.STOP)
		return
	get_tree().change_scene_to_file("res://scenes/hub.tscn")


# ------------------------------------------------------------ look

func _look_board(parent: Control) -> Control:
	var v := _board(parent, "Look")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var cur := String(save.get_setting("look"))
	for opt in [["light", "Light"], ["dark", "Dark"], ["auto", "Match phone"]]:
		var key: String = opt[0]
		var b := UIStyle.button(String(opt[1]), func():
			save.set_setting("look", key)
			get_tree().reload_current_scene(), cur == key, 22)
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return v.get_parent()


# ------------------------------------------------------------ drivers

func _drivers_board(parent: Control) -> Control:
	var v := _board(parent, "Drivers on this phone")
	for d in save.drivers():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		row.add_child(HelmetBadge.for_driver(d, 48.0))
		var nm := UIStyle.label("%s  #%d" % [String(d["name"]), int(d["number"])], 22, UIStyle.PAPER, "extrabold" if d["active"] else "bold")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nm)
		row.add_child(UIStyle.label(Ranks.tier_name(int(d["rp"])), 19, UIStyle.FOG, "bold"))
		if d["active"]:
			var you := UIStyle.button("Driving", Callable(), true, 18)
			you.disabled = false
			you.mouse_filter = Control.MOUSE_FILTER_IGNORE
			you.custom_minimum_size = Vector2(118, 46)
			row.add_child(you)
		else:
			var id := String(d["id"])
			var rm := UIStyle.stop_button("Remove" if _confirm_remove != id else "Sure?", func():
				if _confirm_remove == id:
					save.delete_driver(id)
					_confirm_remove = ""
				else:
					_confirm_remove = id
				get_tree().reload_current_scene.call_deferred(), 18)
			rm.custom_minimum_size = Vector2(0, 46)
			row.add_child(rm)
			var sw := UIStyle.button("Drive", func():
				save.switch_driver(id)
				get_tree().change_scene_to_file("res://scenes/hub.tscn"), false, 18)
			sw.custom_minimum_size = Vector2(118, 46)
			row.add_child(sw)
	var add := UIStyle.button("Add a driver", func():
		save.new_driver()
		get_tree().change_scene_to_file("res://scenes/driver.tscn"), false, 20)
	add.custom_minimum_size = Vector2(0, 52)
	v.add_child(add)
	return v.get_parent()


# ------------------------------------------------------------ backup

func _backup_board(parent: Control) -> Control:
	var v := _board(parent, "Keep your progress", true)
	var t := UIStyle.label("Saved on this phone as you play, and Android keeps a copy with your Google account. To move to another phone or the browser, copy your code here and paste it there.", 18, UIStyle.FOG, "medium")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var copy := UIStyle.button("Copy my backup code", func():
		DisplayServer.clipboard_set(save.backup_code())
		_rstatus.text = "Copied. Paste it somewhere safe: a chat to yourself, or a note."
		_rstatus.add_theme_color_override("font_color", UIStyle.GREEN), false, 20)
	copy.custom_minimum_size = Vector2(0, 54)
	v.add_child(copy)
	_restore_row(v)
	return v.get_parent()
