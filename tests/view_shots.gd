extends SceneTree
## Fast visual review of a track's shape: no driving, just cameras.
## For each distance (m from the line): a driver's-eye view up the road with
## the car parked there, and a view from the side; plus one aerial overview.
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/view_shots.gd -- <out_dir> <track> <m> [m ...]
func _initialize() -> void:
	_run()
func _shot(path: String) -> void:
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, "  triangles drawn: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "  draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var track_id: String = args[1]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = track_id; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await process_frame
	var track = race.track
	var cam := Camera3D.new()
	race.add_child(cam)
	cam.fov = 62
	cam.far = 4000
	cam.current = true
	var n: int = track.size()
	for k in range(2, args.size()):
		var m := float(args[k])
		var i := int(m / 2.0) % n
		race._place(race.player, track.pose_at(i, race.car.spawn_height()))
		race.car.freeze = true
		var p: Vector3 = track.points[i]
		var back: Vector3 = track.points[posmod(i - 7, n)]
		var ahead: Vector3 = track.points[(i + 40) % n]
		cam.global_position = back + Vector3(0, 2.6, 0)
		cam.look_at(ahead + Vector3(0, 1.0, 0), Vector3.UP)
		await _shot("%s/%s_%04d_drive.png" % [out, track_id, int(m)])
		var side: Vector3 = track.rights[i] * (track.wall_at(i, 1.0) + 26.0)
		cam.global_position = p + side + Vector3(0, 7.0, 0)
		cam.look_at(p + Vector3(0, 1.0, 0), Vector3.UP)
		await _shot("%s/%s_%04d_side.png" % [out, track_id, int(m)])
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for q in track.points:
		lo = Vector3(minf(lo.x, q.x), minf(lo.y, q.y), minf(lo.z, q.z))
		hi = Vector3(maxf(hi.x, q.x), maxf(hi.y, q.y), maxf(hi.z, q.z))
	var c := (lo + hi) * 0.5
	var span := maxf(hi.x - lo.x, hi.z - lo.z)
	cam.global_position = c + Vector3(span * 0.55, span * 0.42, span * 0.75)
	cam.look_at(c, Vector3.UP)
	await _shot("%s/%s_aerial.png" % [out, track_id])
	quit(0)
