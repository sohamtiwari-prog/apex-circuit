extends SceneTree
## Screens for judging the look: chase view, a high view over the car, and
## onboard, at a few seconds into a race.
##   godot --resolution 1600x720 --script res://tests/look_shots.gd -- <out_dir> <track>[:day|sunset|night][,...] [car]
func _initialize() -> void:
	_run()


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var car_id: String = args[2] if args.size() > 2 else "gp26"
	await process_frame                # (the Save autoload loads first)
	for spec in String(args[1]).split(","):
		var tid := spec.get_slice(":", 0)
		var tod := spec.get_slice(":", 1) if spec.contains(":") else "auto"
		var save: Node = root.get_node("Save")
		save.data = save.default_profile()
		var st: Dictionary = save.data["settings"]
		st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 19; st["graphics"] = "high"; st["track"] = tid
		st["car"] = car_id; st["qualifying"] = false; st["time_of_day"] = tod; st["weather"] = "dry"
		var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
		root.add_child(race)
		await physics_frame
		race.autopilot = load("res://scripts/ai_driver.gd").new()
		race.autopilot.skill = 0.9
		Engine.max_physics_steps_per_frame = 48
		while race.race_time < 14.0:
			await physics_frame
		var tag := "%s/%s_%s" % [out, tid, tod]
		await _shot(tag + "_chase.png")
		# High over the car, looking down the track.
		var cam: Camera3D = race.cam
		cam.set_physics_process(false)
		var c: Node3D = race.car
		cam.global_position = c.global_position - c.global_basis.z * 16.0 + Vector3.UP * 9.0
		cam.look_at(c.global_position + c.global_basis.z * 30.0, Vector3.UP)
		await _shot(tag + "_high.png")
		# Low at the side of the track, the car passing.
		cam.global_position = c.global_position + c.global_basis.x * 6.0 + Vector3.UP * 0.6 + c.global_basis.z * 8.0
		cam.look_at(c.global_position + Vector3.UP * 0.5, Vector3.UP)
		await _shot(tag + "_side.png")
		cam.set_physics_process(true)
		race.queue_free()
		await process_frame
		await process_frame
	quit(0)
