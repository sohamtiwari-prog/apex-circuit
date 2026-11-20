extends SceneTree
## The sponsors round a circuit: a painted run-off logo, a billboard at a
## braking zone, the timing clock, the start gantry and wall boards, and a
## car up close.
##   godot --rendering-method mobile --resolution 1600x720 --script res://tests/sponsor_shots.gd -- <out_dir> [track]
func _initialize() -> void:
	_run()


func _shot(cam: Camera3D, pos: Vector3, look: Vector3, path: String, fov := 50.0) -> void:
	cam.position = pos
	cam.fov = fov
	cam.look_at(look, Vector3.UP)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 2; st["opponents"] = 7
	st["track"] = args[1] if args.size() > 1 else "silvermoor"; st["car"] = "gp26"; st["time_of_day"] = "day"; st["weather"] = "dry"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	for i in 30:
		await process_frame
	var tr: Track = race.track
	var side: Trackside = race.find_children("*", "Trackside", true, false)[0]
	for c in race.get_children():
		if c is CanvasLayer:
			c.visible = false
	var cam := Camera3D.new()
	race.add_child(cam)
	cam.current = true
	cam.far = 2000.0
	var spots: Dictionary = side.sponsor_spots
	print("spots: ", spots.keys())
	var n := tr.size()
	if spots.has("runoff"):
		var p: Vector3 = spots["runoff"]
		var i := _nearest(tr, p)
		await _shot(cam, p + (tr.points[i] - p).normalized() * 14.0 + Vector3(0, 6.0, 0), p, out + "/r1_runoff.png")
	if spots.has("billboard"):
		var p: Vector3 = spots["billboard"]
		var i := _nearest(tr, p)
		var from: Vector3 = tr.points[posmod(i - 22, n)] + Vector3(0, 1.2, 0)
		await _shot(cam, from, p, out + "/r2_billboard.png", 40.0)
	if spots.has("clock"):
		var p: Vector3 = spots["clock"]
		var i := _nearest(tr, p)
		await _shot(cam, tr.points[posmod(i - 8, n)] + Vector3(0, 1.4, 0), p + Vector3(0, -1.0, 0), out + "/r3_clock.png", 40.0)
	# The start: grid, gantry, boards.
	await _shot(cam, tr.points[posmod(-30, n)] + Vector3(0, 2.0, 0), tr.points[8] + Vector3(0, 3.0, 0), out + "/r4_start.png", 55.0)
	quit(0)


func _nearest(tr: Track, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in tr.size():
		var d := tr.points[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best
