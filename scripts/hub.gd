extends Node3D
## Home screen: your car on the turntable, your rank and stars, and the
## ways to play: Career, Championship, Quick race, Friends and the Garage.

var save: Node
var room: Showroom
var ui: CanvasLayer
var _tiles := {}


func _ready() -> void:
	save = get_node("/root/Save")
	save.pending_event = {}
	DisplayServer.screen_set_keep_on(true)
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
		margin.add_theme_constant_override("margin_" + side, 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cols)

	# Left: name, rank, the car.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	var mark := HBoxContainer.new()
	mark.add_theme_constant_override("separation", 10)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(mark)
	var chev := ColorRect.new()
	chev.color = UIStyle.APEX
	chev.custom_minimum_size = Vector2(12, 46)
	mark.add_child(chev)
	mark.add_child(UIStyle.outlined(UIStyle.label("Apex Circuit", 50, UIStyle.PAPER, "extrabold", true), 5))
	RankCard.build(left, ui, save)
	var prof := UIStyle.button("Profile & trophies", func(): get_tree().change_scene_to_file("res://scenes/profile.tscn"), false, 22)
	prof.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	prof.custom_minimum_size = Vector2(400, 56)
	left.add_child(prof)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(sp)
	var spec: Dictionary = save.car_spec(home_car())
	left.add_child(UIStyle.outlined(UIStyle.label("Your car", 22, UIStyle.FOG, "bold", true), 4))
	left.add_child(UIStyle.outlined(UIStyle.label(String(spec["name"]), 46, UIStyle.PAPER, "extrabold", true), 6))
	left.add_child(UIStyle.outlined(UIStyle.label("PR %.1f   ·   %s" % [Garage.pr(spec), String(spec["desc"]).split(" · ")[0]], 22, UIStyle.PAPER, "semibold", true), 4))

	# Right: stars and the ways to play.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	var head: Array = UIStyle.header("", Callable(), "%d stars" % Career.total_stars(save))
	right.add_child(head[0])
	var stars := Career.total_stars(save)
	var tier := clampi(int(save.get_setting("career_series")), 0, Career.SERIES.size() - 1)
	_tile(right, "career", "Career", "%s  ·  %d of %d stars" % [Career.SERIES[tier]["name"], stars, Career.SERIES.size() * 18], "res://scenes/career.tscn", true)
	var daily := Daily.event()
	var dstars: int = save.career_stars(String(daily["id"]))
	var db := UIStyle.tile("Daily challenge", Daily.describe(daily) + ("  ·  %d/3 stars" % dstars if dstars > 0 else "  ·  up to 3 stars"), func():
		save.pending_event = daily
		get_tree().change_scene_to_file("res://scenes/race.tscn"), false, 30)
	db.size_flags_vertical = Control.SIZE_EXPAND_FILL
	db.custom_minimum_size = Vector2(0, 76)
	right.add_child(db)
	_tiles["daily"] = db
	_tile(right, "championship", "Championship", Championship.summary(save), "res://scenes/championship.tscn")
	_tile(right, "quick", "Quick race", "Any car, any track, any rules", "res://scenes/menu.tscn")
	_tile(right, "friends", "Friends", "Race together on Wi-Fi or online", "res://scenes/lobby.tscn")
	_tile(right, "garage", "Garage", "%d cars, all ready to drive" % CarSpecs.CATALOG.size(), "res://scenes/garage.tscn")


func _tile(parent: Control, key: String, title: String, sub: String, scene: String, primary := false) -> void:
	var b := UIStyle.tile(title, sub, func(): get_tree().change_scene_to_file(scene), primary, 40 if primary else 30)
	b.custom_minimum_size = Vector2(0, 76)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_tiles[key] = b
