extends SceneTree
## Records the ideal laps for the ideal-lap ghost (data/ideal/<track>__<car>.bin):
## a time trial driven by the AI at full pace on the racing line, the
## fastest of its first flying laps. Run when tracks or cars change.
##   godot --headless --fixed-fps 120 --script res://tests/make_ideal_laps.gd -- <track|all> [car|all]
const CARS := ["gp26"]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var tracks: Array = []
	if args.is_empty() or args[0] == "all":
		for t in Track.CATALOG:
			tracks.append(String(t["id"]))
	else:
		tracks = String(args[0]).split(",")
	var cars: Array = CARS if args.size() < 2 or args[1] == "all" else Array(String(args[1]).split(","))
	DirAccess.make_dir_recursive_absolute("res://data/ideal")
	for tid in tracks:
		for cid in cars:
			# Full pace; if that can't string a clean lap together, a touch less.
			for skill in [1.0, 0.98, 0.96]:
				if await _record(String(tid), String(cid), skill):
					break
	quit(0)


func _record(tid: String, cid: String, skill: float) -> bool:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = tid; st["car"] = cid; st["weather"] = "dry"; st["ghost"] = false
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = skill
	var best := INF
	var rec := PackedFloat32Array()
	var t := 0
	var last_lap := 0
	while race.player.lap < 3 and t < 120 * 600:
		await physics_frame
		t += 1
		if race.player.lap != last_lap:
			last_lap = race.player.lap
			# A clean lap faster than the last: keep its recording.
			if race.player.lap >= 2 and race.player.last_lap < best and race.lap_valid_last:
				best = race.player.last_lap
				rec = race._last_lap_rec.duplicate()
	var ok := rec.size() >= 14 * 7
	if not ok:
		print("FAIL %-12s %-10s no clean flying lap at %.2f" % [tid, cid, skill])
	else:
		# 10 samples a second is plenty (the playback interpolates).
		var half := PackedFloat32Array()
		for k in range(0, rec.size() / 7, 2):
			half.append_array(rec.slice(k * 7, k * 7 + 7))
		var f := FileAccess.open_compressed("res://data/ideal/%s__%s.bin" % [tid, cid], FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		f.store_var({"time": best, "hz": race.GHOST_HZ / 2.0, "xf": half})
		f.close()
		print("IDEAL %-12s %-10s %s (%d samples)" % [tid, cid, Hud.fmt_time(best), rec.size() / 7])
	race.queue_free()
	await process_frame
	await process_frame
	return ok
