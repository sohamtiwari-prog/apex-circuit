extends SceneTree
## Main menu screenshots: default selection, then another car and track.
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	for i in range(4):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var menu: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _shot(out + "/m1.png")
	menu._select_car("vanta_gt", true)
	menu._select_track("riviera", true)
	save.set_setting("mode", "time_trial")
	menu._refresh_mode()
	await _shot(out + "/m2.png")
	quit(0)
