extends SceneTree
## A picture of Ise Bay's crossover with a car on each level.
##   godot --rendering-method mobile --resolution 1600x720 --script res://tests/bridge_shot.gd -- <out.png> [side]
func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 2; st["opponents"] = 3; st["track"] = "isebay"; st["car"] = "gp26"
	st["graphics"] = "high"; st["time_of_day"] = "day"; st["weather"] = "dry"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	var tr: Track = race.track
	var b: Dictionary = tr.bridges[0]
	var lo := int(b["lower"])
	var up := (int(b["i0"]) + int(b["i1"])) / 2
	var e0 = race.entrants[0]
	var e1 = race.entrants[1]
	race._place(e0, tr.pose_at(up - 2, e0.car.spawn_height(), 0.0))
	race._place(e1, tr.pose_at(lo - 14, e1.car.spawn_height(), 1.5))
	for e in [e0, e1]:
		e.car.freeze = true
	var side := float(args[1]) if args.size() > 1 else 1.0
	var p: Vector3 = tr.points[lo]
	var cam := Camera3D.new()
	root.add_child(cam)
	var dir: Vector3 = (tr.points[posmod(lo - 1, tr.size())] - tr.points[posmod(lo + 1, tr.size())]).normalized()
	cam.global_position = p + dir * 42.0 + tr.rights[lo] * 16.0 * side + Vector3.UP * 7.0
	cam.look_at(p + Vector3.UP * 2.5)
	cam.fov = 60.0
	cam.current = true
	race.hud.visible = false
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0])
	print("saved ", args[0])
	quit()
