extends SceneTree
## Screenshots of a pit stop: the pit board, turning into the entry road,
## the crew at work (from the chase camera and from the side), the release.
##   godot --rendering-driver opengl3 --script res://tests/pit_stop_shots.gd -- <out_dir> [track]
func _initialize() -> void:
	_run()


func _shot(path: String) -> void:
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(path)
	RenderingServer.render_loop_enabled = false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var tid: String = args[1] if args.size() > 1 else "styria"
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 4; st["opponents"] = 7; st["track"] = tid; st["car"] = "gp26"
	st["qualifying"] = false; st["weather"] = "dry"; st["team"] = 0
	RenderingServer.render_loop_enabled = false
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var tr = race.track
	var wk = race.weekend
	var me = race.player
	while race.race_time < 4.0:
		await physics_frame
	wk.pit_menu()
	await _shot(out + "/stop_1_board.png")
	race.hud.box_choice.emit("hard")
	# Into the entry road.
	while tr.pit_ps(me.idx) < tr.PIT_ENTRY_LEN * 0.45 or me.pit_phase != 1:
		await physics_frame
	await _shot(out + "/stop_2_entry.png")
	while me.pit_phase != 2:
		await physics_frame
	while me.pit_timer < me.pit_need * 0.45:
		await physics_frame
	await _shot(out + "/stop_3_crew_chase.png")
	# From the side, across the pit lane.
	var cam := Camera3D.new()
	cam.fov = 50.0
	race.add_child(cam)
	var c: Vector3 = me.car.global_position
	var r: Vector3 = tr.rights[me.idx] * tr.pit_side
	var f: Vector3 = tr.htangents[me.idx]
	cam.look_at_from_position(c - r * 7.5 + f * 6.0 + Vector3(0, 3.2, 0), c + Vector3(0, 0.3, 0), Vector3.UP)
	cam.make_current()
	race.process_mode = Node.PROCESS_MODE_DISABLED
	await _shot(out + "/stop_4_crew_side.png")
	race.process_mode = Node.PROCESS_MODE_INHERIT
	cam.queue_free()
	race.cam.make_current()
	while me.pit_phase == 2:
		await physics_frame
	for i in 30:
		await physics_frame
	await _shot(out + "/stop_5_release.png")
	quit(0)
