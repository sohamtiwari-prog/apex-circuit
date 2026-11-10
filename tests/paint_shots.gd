extends SceneTree
## The paint shop, for review: the GP car in your own paint (each pattern),
## and a road car.
##   godot --resolution 1600x720 --script res://tests/paint_shots.gd -- <out_dir>
func _initialize() -> void:
	_run()


func _shot(path: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.data["settings"]["paint_car"] = "gp26"
	change_scene_to_file("res://scenes/paint.tscn")
	for i in 4:
		await process_frame
	var shop: Node = current_scene
	await _shot(out + "/paint1_team.png")
	shop.set_value("base", "#121c4a")
	shop.set_value("accent", "#c9a227")
	shop.set_value("stripe", "#f2f2f2")
	shop.set_value("number", 7)
	await _shot(out + "/paint2_classic.png")
	shop.set_value("pattern", "stripes")
	await _shot(out + "/paint3_stripes.png")
	shop.set_value("pattern", "split")
	shop.set_value("base", "#e01a1a")
	shop.set_value("accent", "#14181f")
	shop.set_value("stripe", "#ffd919")
	await _shot(out + "/paint4_split.png")
	shop._select("vanta_gt")
	shop.set_value("base", "#14b8b0")
	shop.set_value("pattern", "stripes")
	await _shot(out + "/paint5_road.png")
	quit(0)
