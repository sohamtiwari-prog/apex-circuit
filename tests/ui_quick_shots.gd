extends SceneTree
## Quick look at the main menu screens (APEX_LOOK=light|dark); the world
## leaderboard reads a local test server (tests/online_board_test.gd).
##   godot --rendering-method mobile --resolution 1600x720 --script res://tests/ui_quick_shots.gd -- <out_dir> [hub,quick,tt,garage,career]
func _initialize() -> void:
	_run()
func _shot(path: String, n := 8) -> void:
	for i in n:
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
	var only: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.data["rank_points"] = 640
	save.data["settings"]["look"] = OS.get_environment("APEX_LOOK") if OS.get_environment("APEX_LOOK") != "" else "dark"
	save.data["settings"]["player_name"] = "Soham"
	save.data["driver"] = {"created": true, "name": "Soham", "number": 26, "helmet": "ffd200", "helmet2": "000000", "id": "d1"}
	save.data["career"] = {"kart_1": 3, "kart_2": 3, "kart_3": 2, "kart_4": 2, "kart_6": 1, "f4_1": 2}
	save.data["settings"]["career_series"] = 1
	save.data["best_laps"] = {"silvermoor|gp26": 90000}
	var board: Node = root.get_node("Board")
	board.url = "http://127.0.0.1:3100"
	board.key = "sb_publishable_test"
	save.data["settings"]["online_id"] = "00691541-0cce-484c-a776-d730eb7700d3"
	if only == "" or only.contains("hub"):
		await _open("res://scenes/hub.tscn")
		await _shot(out + "/hub.png")
	if only == "" or only.contains("quick"):
		save.data["settings"]["car"] = "gp26"
		save.data["settings"]["track"] = "silvermoor"
		save.data["settings"]["mode"] = "race"
		await _open("res://scenes/menu.tscn")
		await _shot(out + "/quick.png")
	if only == "" or only.contains("tt"):
		save.data["settings"]["mode"] = "time_trial"
		var menu = await _open("res://scenes/menu.tscn")
		await _shot(out + "/tt.png")
		WorldBoardPanel.open(menu, "silvermoor", "gp26")
		await _shot(out + "/world.png", 60)
	if only == "" or only.contains("garage"):
		var garage = await _open("res://scenes/garage.tscn")
		garage._select("gp26")
		await _shot(out + "/garage.png")
	if only == "" or only.contains("career"):
		await _open("res://scenes/career.tscn")
		await _shot(out + "/career.png")
	if only.contains("builder"):
		# The track builder: a shape on the board, a track with a problem,
		# My tracks, and the track in the Quick race picker.
		var b = await _open("res://scenes/builder.tscn")
		b._template("gp")
		b._name.text = "Soham Ring"
		b.track["name"] = "Soham Ring"
		b.track["hills"] = 2
		b._refresh_chips()
		b._changed()
		await _shot(out + "/builder.png", 12)
		b._save_track()
		b._push_undo()
		var bad: Array = b.map.ctrl.duplicate()
		bad[8] = Vector2(-150, 280)
		b.map.set_layout(bad)
		b._changed()
		await _shot(out + "/builder_problem.png")
		b._undo_last()
		b._set_mode("draw")
		# Mid-trace: a loop being drawn with a finger.
		var tr := PackedVector2Array()
		for k in 150:
			var a := TAU * k / 180.0
			tr.append(Vector2(cos(a) * 700.0 + sin(a * 3.0) * 90.0, sin(a) * 380.0))
		var keep: Array = b.map.ctrl.duplicate()
		b.map.set_layout([])
		b.map._trace = tr
		b._changed()
		b.map.queue_redraw()
		await _shot(out + "/builder_draw.png")
		b.map._trace = PackedVector2Array()
		b.map.set_layout(keep)
		b._changed()
		b._show_mine()
		await _shot(out + "/builder_mine.png")
		b._overlay.queue_free()
		b._overlay = null
		b._race()
		for i in 6:
			await process_frame
		await _shot(out + "/builder_quick.png")
	quit(0)
