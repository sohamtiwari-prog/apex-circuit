extends Node3D
## Home screen: your car on the turntable, your rank and credits, and the
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


## The car shown at home: the last one you picked that you own.
func home_car() -> String:
	var c := String(save.get_setting("garage_car"))
	return c if save.owns(c) else String((save.data["owned_cars"] as Array)[0])


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
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(sp)
	var spec: Dictionary = save.car_spec(home_car())
	left.add_child(UIStyle.outlined(UIStyle.label("Your car", 22, UIStyle.FOG, "bold", true), 4))
	left.add_child(UIStyle.outlined(UIStyle.label(String(spec["name"]), 46, UIStyle.PAPER, "extrabold", true), 6))
	left.add_child(UIStyle.outlined(UIStyle.label("PR %.1f   ·   %d cars in your garage" % [Garage.pr(spec), (save.data["owned_cars"] as Array).size()], 22, UIStyle.PAPER, "semibold", true), 4))

	# Right: credits and the ways to play.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	var head: Array = UIStyle.header("", Callable(), save.credits())
	right.add_child(head[0])
	var stars := Career.total_stars(save)
	var tier := 0
	for si in Career.SERIES.size():
		if Career.unlocked(save, si):
			tier = si
	_tile(right, "career", "Career", "%s  ·  %d of %d stars" % [Career.SERIES[tier]["name"], stars, Career.SERIES.size() * 18], "res://scenes/career.tscn", true)
	_tile(right, "championship", "Championship", Championship.summary(save), "res://scenes/championship.tscn")
	_tile(right, "quick", "Quick race", "Any car, any track, any rules", "res://scenes/menu.tscn")
	_tile(right, "friends", "Friends", "Race together on Wi-Fi or online", "res://scenes/lobby.tscn")
	var jobs := 0
	for c in save.data["owned_cars"]:
		jobs += (save.upgrade_jobs(String(c)) as Array).size()
	_tile(right, "garage", "Garage", ("Buy cars  ·  upgrades" if jobs == 0 else "%d upgrade%s installing" % [jobs, "" if jobs == 1 else "s"]), "res://scenes/garage.tscn")


func _tile(parent: Control, key: String, title: String, sub: String, scene: String, primary := false) -> void:
	var b := UIStyle.tile(title, sub, func(): get_tree().change_scene_to_file(scene), primary, 44 if primary else 34)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	_tiles[key] = b
