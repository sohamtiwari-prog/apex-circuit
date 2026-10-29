extends SceneTree
## Screens for review: the full-field tower with tyres, a VSC with a race
## control message, the pit board, and the results' Race stats tab and a
## driver's laps.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/rc_shots.gd -- <out_dir>
func _initialize() -> void:
	_run()


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 1; st["opponents"] = 11; st["graphics"] = "saver"; st["track"] = "silvermoor"; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	Engine.max_physics_steps_per_frame = 48
	while race.race_time < 20.0:
		await physics_frame
	for e in race.entrants:
		if e.ai != null and e.grid % 4 == 0:
			e.pit_req = true
			e.next_compound = "hard"
	race.entrants[3].pen_pending = 5.0
	race.hud.cycle_tower()
	while race.race_time < 45.0:
		await physics_frame
	race.control.deploy_vsc("debris at turn 4")
	race.control.announce("NOV: 5 SECOND TIME PENALTY, track limits.")
	for i in 90:
		await physics_frame
	await _shot(out + "/rc_1_tower_vsc.png")
	race.weekend.pit_menu()
	await _shot(out + "/rc_2_pit_board.png")
	race.hud.cycle_tower()
	race.hud.cycle_tower()
	while not race._results_shown:
		await physics_frame
	await _shot(out + "/rc_3_results.png")
	race.hud._set_res_tab(1)
	await _shot(out + "/rc_4_stats.png")
	race.hud._res_detail = race.entrants[5].name
	race.hud._fill_results()
	await _shot(out + "/rc_5_driver.png")
	quit(0)
