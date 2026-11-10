extends SceneTree
## Screens for judging the graphics, without the HUD: the chase view, the
## player's car close up (front and rear three-quarter), low at the side of
## the track, the view ahead down the track, and high over the circuit.
## The race is frozen for all but the chase view, so each set is one moment.
##   godot --rendering-method mobile --resolution 1600x720 --script res://tests/gfx_shots.gd -- <out_dir> <track>[:day|sunset|night][,...] [car] [seconds] [weather] [race type]
func _initialize() -> void:
	_run()


func _shot(path: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _hide_hud(race: Node, on: bool) -> void:
	for n in race.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = not on


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var car_id: String = args[2] if args.size() > 2 else "gp26"
	var secs: float = float(args[3]) if args.size() > 3 else 14.0
	var weather: String = args[4] if args.size() > 4 else "dry"
	var race_type: String = args[5] if args.size() > 5 else "race"
	await process_frame
	for spec in String(args[1]).split(","):
		var tid := spec.get_slice(":", 0)
		var tod := spec.get_slice(":", 1) if spec.contains(":") else "auto"
		var save: Node = root.get_node("Save")
		save.data = save.default_profile()
		var st: Dictionary = save.data["settings"]
		st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 19; st["graphics"] = "high"; st["track"] = tid
		st["car"] = car_id; st["qualifying"] = false; st["time_of_day"] = tod; st["weather"] = weather
		st["race_type"] = race_type
		save.pending_event = load("res://scripts/menu.gd").quick_event(save) if race_type != "race" else {}
		var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
		root.add_child(race)
		await physics_frame
		race.autopilot = load("res://scripts/ai_driver.gd").new()
		race.autopilot.skill = 0.9
		Engine.max_physics_steps_per_frame = 48
		while race.race_time < secs:
			await physics_frame
		var tag := "%s/%s_%s" % [out, tid, tod]
		await _shot(tag + "_hud.png")
		_hide_hud(race, true)
		# Every other camera (onboard, nose...) first, then back to the chase.
		var cam0: int = race.cam.mode
		for m in range(1, race.cam._modes.size()):
			race.cam.set_mode(m)
			for f in 30:
				await physics_frame
			await _shot(tag + "_cam%d.png" % m)
		race.cam.set_mode(cam0)
		for f in 30:
			await physics_frame
		await _shot(tag + "_chase.png")
		print("    %s: %d draw calls, %d primitives, %d objects in the chase view" % [tid,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		paused = true
		var cam: Camera3D = race.cam
		cam.set_physics_process(false)
		cam.set_process(false)
		var c: Node3D = race.car
		var x := c.global_basis.x
		var z := c.global_basis.z
		var p := c.global_position
		var fov := cam.fov
		cam.fov = 40.0
		# Close up: front three-quarter, then rear three-quarter.
		cam.global_position = p + z * 4.2 + x * 3.0 + Vector3.UP * 1.1
		cam.look_at(p + Vector3.UP * 0.35, Vector3.UP)
		await _shot(tag + "_front.png")
		cam.global_position = p - z * 4.6 + x * 2.6 + Vector3.UP * 1.5
		cam.look_at(p + Vector3.UP * 0.35, Vector3.UP)
		await _shot(tag + "_rear.png")
		cam.fov = 55.0
		# Low at the side of the track, looking back at the field.
		var tr: Track = race.track
		var i: int = race.player.idx
		var n := tr.size()
		var j := (i + 12) % n
		cam.global_position = tr.points[j] + tr.rights[j] * (tr.road_half + 2.5) + Vector3.UP * 1.0
		cam.look_at(p + Vector3.UP * 0.6, Vector3.UP)
		await _shot(tag + "_side.png")
		# Standing on the track ahead of the car, looking on down it.
		var k := (i + 20) % n
		cam.global_position = tr.points[k] + Vector3.UP * 1.6
		cam.look_at(tr.points[(k + 60) % n] + Vector3.UP * 1.2, Vector3.UP)
		await _shot(tag + "_ahead.png")
		# High over the circuit.
		cam.global_position = p - z * 60.0 + x * 40.0 + Vector3.UP * 55.0
		cam.look_at(p + z * 80.0, Vector3.UP)
		await _shot(tag + "_aerial.png")
		cam.fov = fov
		paused = false
		race.queue_free()
		await process_frame
		await process_frame
	quit(0)
