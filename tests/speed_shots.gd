extends SceneTree
## Screens for judging the sense of speed: the GP car flat out on a long
## straight (chase and cockpit), and through a corner.
##   godot --rendering-method mobile --resolution 1600x720 --script res://tests/speed_shots.gd -- <out_dir> [track] [car] [kmh]
func _initialize() -> void:
	_run()


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var tid: String = args[1] if args.size() > 1 else "brianza"
	var car_id: String = args[2] if args.size() > 2 else "gp26"
	var kmh: float = float(args[3]) if args.size() > 3 else 300.0
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 19; st["graphics"] = "high"; st["track"] = tid
	st["car"] = car_id; st["qualifying"] = false; st["weather"] = "dry"; st["time_of_day"] = "day"
	st["race_control"] = false
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 1.0
	Engine.max_physics_steps_per_frame = 48
	# Flat out.
	var t := 0
	while race.car.speed_kmh() < kmh and t < 120 * 150:
		await physics_frame
		t += 1
	await _shot("%s/%s_%s_fast_chase.png" % [out, tid, car_id])
	race.cam.cycle()
	race.cam.cycle()                 # (chase -> far chase -> cockpit)
	for i in 50:
		await physics_frame
	await _shot("%s/%s_%s_fast_cockpit.png" % [out, tid, car_id])
	race.cam.set_mode(0)
	# Braking for the next corner.
	t = 0
	while race.car.brake_input < 0.5 and t < 120 * 30:
		await physics_frame
		t += 1
	for i in 40:
		await physics_frame
	await _shot("%s/%s_%s_braking.png" % [out, tid, car_id])
	quit(0)
