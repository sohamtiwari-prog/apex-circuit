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
	save.data["rank_points"] = 640
	# APEX_LOOK=light|dark picks the menus' look for the shots.
	save.data["settings"]["look"] = OS.get_environment("APEX_LOOK") if OS.get_environment("APEX_LOOK") != "" else "light"
	save.data["settings"]["player_name"] = "Soham"
	save.data["driver"] = {"created": true, "name": "Soham", "number": 26, "helmet": "ffd200", "helmet2": "000000", "id": "d1"}
	# Promoted out of karting (10 stars), into F4.
	save.data["career"] = {"kart_1": 3, "kart_2": 3, "kart_3": 2, "kart_4": 2, "kart_6": 1, "f4_1": 2}
	save.data["settings"]["career_series"] = 1
	await _open("res://scenes/hub.tscn")
	await _shot(out + "/g1_hub.png")
	await _open("res://scenes/career.tscn")
	await _shot(out + "/g2_career.png")
	var garage = await _open("res://scenes/garage.tscn")
	garage._select("gp26")
	await _shot(out + "/g3_garage.png")
	garage._select("kart")
	await _shot(out + "/g4_garage_car.png")
	await _open("res://scenes/championship.tscn")
	await _shot(out + "/g5_champ_setup.png")
	Championship.start(save, "kart", "kart", "", 6)
	Championship.record_round(save, [3, 0, 5, 1, 2, 4, 6, 7, 8, 9, 10, 11], 0)
	await _open("res://scenes/championship.tscn")
	await _shot(out + "/g6_champ_season.png")
	save.data["settings"]["car"] = "kart"
	await _open("res://scenes/menu.tscn")
	await _shot(out + "/g7_quick.png")
	save.data["settings"]["car"] = "f3"
	await _open("res://scenes/menu.tscn")
	await _shot(out + "/g7b_quick_f3.png")
	save.data["trophies"] = [{"series": "Sports Car Cup", "position": 1, "date": "2026-10-28"}, {"series": "Muscle Car Series", "position": 3, "date": "2026-10-20"}]
	save.data["best_laps"] = {"silvermoor|gp26": 102345, "marina|gp26": 101020, "styria|gp26": 71640}
	await _open("res://scenes/profile.tscn")
	await _shot(out + "/g8_profile.png")
	await _open("res://scenes/driver.tscn")
	await _shot(out + "/g9_driver.png")
	# The first visit: no driver yet, so home sends you to make one.
	save.data["driver"]["created"] = false
	save.data["driver"]["name"] = ""
	await _open("res://scenes/hub.tscn")
	for i in 4:
		await process_frame
	await _shot(out + "/g0_create.png")
	save.data = save.default_profile()
	quit(0)
