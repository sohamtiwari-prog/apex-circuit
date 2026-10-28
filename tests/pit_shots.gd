extends SceneTree
## Pit lane views: entry, boxes and exit, from above and from a car.
##   godot --rendering-driver opengl3 --script res://tests/pit_shots.gd -- <out_dir> <track>
func _initialize() -> void:
	_run()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var tid: String = args[1] if args.size() > 1 else "styria"
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 3; st["opponents"] = 1; st["track"] = tid; st["car"] = "gp26"; st["qualifying"] = false
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	for i in 20:
		await process_frame
	var tr: Track = race.track
	print("pit lane: %s side %+.0f entry %.0f lane %.0f exit %.0f" % [tr.has_pit_lane, tr.pit_side, tr.PIT_ENTRY_LEN, tr.PIT_STRAIGHT_LEN, tr.PIT_EXIT_LEN])
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 3000.0
	race.add_child(cam)
	var views := [["entry", tr.PIT_ENTRY_LEN * 0.4, 30.0, 26.0], ["boxes", tr.PIT_ENTRY_LEN + 90.0, 26.0, 18.0],
		["exit", tr.PIT_ENTRY_LEN + tr.PIT_STRAIGHT_LEN + tr.PIT_EXIT_LEN * 0.5, 34.0, 28.0]]
	for v in views:
		var ps: float = v[1]
		var s := fposmod(tr.pit_s0 + ps, tr.total_length)
		var i := int(s / Track.SPACING) % tr.size()
		var r: Vector3 = tr.rights[i] * tr.pit_side
		var target: Vector3 = tr.points[i] + r * tr.pit_lane_lat(ps)
		var eye: Vector3 = target - tr.htangents[i] * float(v[2]) - r * 8.0 + Vector3(0, float(v[3]), 0)
		cam.look_at_from_position(eye, target, Vector3.UP)
		cam.make_current()
		for k in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s/pit_%s_%s.png" % [out, tid, v[0]])
	quit(0)
