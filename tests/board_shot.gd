extends SceneTree
## Views of trackside details: a braking zone with its boards.
func _initialize() -> void:
	_run()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var tid: String = args[1] if args.size() > 1 else "styria"
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.data["settings"]["mode"] = "time_trial"
	save.data["settings"]["track"] = tid
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	for i in range(10):
		await process_frame
	var tr = race.track
	var cam := Camera3D.new()
	race.add_child(cam)
	cam.fov = 62
	cam.current = true
	var shots := 0
	for i in tr.trackside.board_spots:
		var n: int = tr.size()
		var p: Vector3 = tr.points[i] + Vector3(0, 2.2, 0) - tr.tangents[i] * 10.0
		cam.global_position = p + tr.rights[i] * 2.0
		cam.look_at(tr.points[(i + 45) % n] + Vector3(0, 0.8, 0), Vector3.UP)
		for k in range(4):
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/board_%s_%d.png" % [out, tid, shots])
		shots += 1
		if shots >= 2:
			break
	print("shots ", shots)
	quit()
