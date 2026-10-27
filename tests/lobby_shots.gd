extends SceneTree
## Lobby screenshots: the connect screen, then a hosted Wi-Fi lobby.
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
	var net: Node = root.get_node("Net")
	save.data = save.default_profile()
	save.data["settings"]["player_name"] = "Soham"
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	await _shot(out + "/lobby1_connect.png")
	net.host_lan("Soham")
	lobby._enter_as_host()
	lobby._players()[2] = {"name": "Aarav", "car": "gp26", "team": 3}
	lobby._players()[3] = {"name": "Kabir", "car": "vanta_gt", "team": 0}
	lobby._refresh_lobby()
	await _shot(out + "/lobby2_host.png")
	net.leave()
	quit(0)
