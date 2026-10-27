extends SceneTree
## Screenshots of the ranking UI: menu card, ladder, results with a promotion,
## lobby with ranks.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/rank_shots.gd -- <out_dir>
func _initialize() -> void:
	_run()
func _shot(path: String, frames := 4) -> void:
	for i in frames:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.data["rank_points"] = 1290
	var menu: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _shot(out + "/r1_menu.png")
	menu._show_ladder()
	await _shot(out + "/r2_ladder.png")
	menu.queue_free()
	await process_frame
	# Results with a promotion (Gold III -> Gold II).
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.24, 0.22)
	bg.size = Vector2(1600, 720)
	root.add_child(bg)
	var hud = load("res://scripts/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var rows := []
	var names := ["Novak", "You", "Okafor", "Lindqvist", "Moreau", "Tanaka"]
	for i in names.size():
		rows.append({"pos": i + 1, "name": names[i], "team": i, "gap": "" if i == 0 else "+%.3f" % (i * 1.7), "best": "1:2%d.4%d1" % [i, i],
			"player": names[i] == "You", "color": Color.ORANGE, "fastest": i == 1})
	var award: Dictionary = Ranks.race_points(2, 20, "hard", 5, true, false)
	hud.show_results(rows, func(): pass, func(): pass, "Race again", {"award": award, "before": 1290, "after": 1290 + int(award["total"])})
	await _shot(out + "/r3_results.png", 150)
	quit(0)
