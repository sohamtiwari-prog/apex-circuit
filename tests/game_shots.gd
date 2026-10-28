extends SceneTree
## Screenshots of the game screens: home, career, garage (owned car with an
## upgrade installing, and a car for sale), championship setup and season.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/game_shots.gd -- <out_dir>
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
func _open(scene: String) -> Node:
	change_scene_to_file(scene)
	for i in 4:
		await process_frame
	return current_scene
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.data["credits"] = 42350
	save.data["rank_points"] = 640
	(save.data["owned_cars"] as Array).append("stuttgart9")
	save.data["career"] = {"club_1": 3, "club_2": 2, "club_3": 3, "club_4": 1, "club_5": 2}
	save.data["upgrades"] = {"marauder": {"engine": 2, "tyres": 1}}
	save.start_upgrade("marauder", "aero")
	await _open("res://scenes/hub.tscn")
	await _shot(out + "/g1_hub.png")
	await _open("res://scenes/career.tscn")
	await _shot(out + "/g2_career.png")
	var garage = await _open("res://scenes/garage.tscn")
	garage._select("marauder")
	await _shot(out + "/g3_garage.png")
	garage._select("vanta_gt")
	await _shot(out + "/g4_garage_buy.png")
	await _open("res://scenes/championship.tscn")
	await _shot(out + "/g5_champ_setup.png")
	Championship.start(save, "sports", "stuttgart9", "", 6, 3)
	Championship.record_round(save, [3, 0, 5, 1, 2, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19], 0)
	await _open("res://scenes/championship.tscn")
	await _shot(out + "/g6_champ_season.png")
	await _open("res://scenes/menu.tscn")
	await _shot(out + "/g7_quick.png")
	quit(0)
