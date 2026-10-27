extends SceneTree
## Screenshots of replays: every camera, the controls, a highlight caption,
## a clean (hidden UI) shot, the results and pause menus with their Replay
## buttons, and the slipstream indicator.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/replay_shots.gd -- <out_dir> [track]
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
func _frames(n: int) -> void:
	for i in n:
		await physics_frame
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 1; st["opponents"] = 19
	st["track"] = args[1] if args.size() > 1 else "styria"; st["car"] = "gp26"; st["team"] = 0
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	# Race without drawing (fast), drawing only for the pictures.
	RenderingServer.render_loop_enabled = false
	var tow_shot := false
	while not race._results_shown:
		await physics_frame
		if not tow_shot and race.car.tow > 0.45 and race.state == 1:
			tow_shot = true
			RenderingServer.render_loop_enabled = true
			await _shot(out + "/s0_slipstream.png")
			RenderingServer.render_loop_enabled = false
	RenderingServer.render_loop_enabled = true
	await _frames(30)
	await _shot(out + "/s1_results.png")
	race.hud.set_paused(true)
	await _shot(out + "/s2_pause.png")
	race.hud.set_paused(false)

	race.watch_replay(false)
	var rp = race.replay
	var cam = rp.cam
	var start: float = rp.race_start_frame()
	rp.seek(start + 20 * 14.0)
	await _frames(30)
	await _shot(out + "/s3_replay_auto.png")
	var i := 4
	for m in ["TV", "Helicopter", "Blimp", "Drone", "Chase", "T-cam", "Cockpit", "Rear-facing"]:
		cam.mode = cam.modes.find(m)
		cam.cut()
		rp.seek(start + 20 * (16.0 + i))
		await _frames(100)
		await _shot(out + "/s%d_%s.png" % [i, m.to_lower()])
		i += 1
	# A highlight with its caption.
	cam.mode = 1
	for ev in rp.events:
		if ev["kind"] == "contact" or ev["kind"] == "lead":
			rp.seek(float(ev["f"]) - 20.0)
			if int(ev["car"]) >= 0:
				rp.set_focus(int(ev["car"]))
			break
	await _frames(40)
	await _shot(out + "/s%d_caption.png" % i)
	i += 1
	# Slow motion, then the controls fade away for a clean picture.
	rp.cycle_speed()
	rp.cycle_speed()
	await _frames(60)
	await _shot(out + "/s%d_slowmo.png" % i)
	i += 1
	rp.speed_i = 0
	rp.ui._hidden_by_user = true
	await _frames(90)
	await _shot(out + "/s%d_clean.png" % i)
	quit(0)
