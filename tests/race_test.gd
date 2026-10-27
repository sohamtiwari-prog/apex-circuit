extends SceneTree
## A full race: 20 cars, standing start, positions, finish and results.
## Also measures the simulation cost of a full grid.
##   godot --headless --fixed-fps 120 --script res://tests/race_test.gd [track] [laps]
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	# Let the Save autoload finish loading from disk before we override it.
	await process_frame
	var args := OS.get_cmdline_user_args()
	var track_id: String = args[0] if args.size() > 0 else "styria"
	var laps: int = int(args[1]) if args.size() > 1 else 2
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"
	st["laps"] = laps
	st["opponents"] = 19
	st["track"] = track_id
	st["car"] = "gp26"
	st["difficulty"] = "medium"
	save.save()

	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	await physics_frame
	_check(race.entrants.size() == 20, "20 cars on the grid (%d)" % race.entrants.size())
	_check(race.player.position >= 5, "player starts mid-grid (P%d)" % race.player.position)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = float(args[2]) if args.size() > 2 else 0.97
	# Count car-to-car hits by closing speed.
	var hits := {"soft": 0, "hard": 0}
	var last_hit := {}                 # pair -> race time of the last counted hit
	var hit_log: Array[String] = []
	# Car-to-car contacts come from CarContacts (cars don't collide through
	# the physics solver any more).
	race.car_contact.connect(func(c: RaceCar, other: RaceCar, closing: float) -> void:
		var rel: float = (c.linear_velocity - other.linear_velocity).length()
		# One incident per pair of cars per 2 s (a long scrape is one incident).
		var pair := "%d-%d" % [mini(c.get_instance_id(), other.get_instance_id()), maxi(c.get_instance_id(), other.get_instance_id())]
		if race.race_time - float(last_hit.get(pair, -99.0)) < 2.0:
			return
		var e = null
		var oe = null
		for x in race.entrants:
			if x.car == c:
				e = x
			if x.car == other:
				oe = x
		if rel > 4.0:
			last_hit[pair] = race.race_time
			hits["hard"] += 1
			if hit_log.size() < 12 and e != null and oe != null:
				var gap: float = race.track.cum[oe.idx] - race.track.cum[e.idx]
				var dl: float = race.track.lateral(other.global_position, oe.idx) - race.track.lateral(c.global_position, e.idx)
				hit_log.append("%.0f m/s at %.0f m, t=%.1fs: B is %+.1f m ahead, %+.1f m right; vA %.1f vB %.1f" % [rel, race.track.cum[e.idx], race.race_time, gap, dl, c.forward_speed(), other.forward_speed()])
		elif rel > 1.0:
			hits["soft"] += 1
	)
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var resets := 0
	var min_moved := INF
	var overtakes := 0
	var last_pos: int = race.player.position
	while not race._results_shown and frames < 120 * 200 * (laps + 1):
		await physics_frame
		frames += 1
		if race.player.position != last_pos:
			overtakes += 1
			last_pos = race.player.position
	var sim_ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxi(frames, 1)
	print("  %d frames, %.2f ms per physics tick with 20 cars (headless, this machine)" % [frames, sim_ms])
	print("  player finished P%d after %d position changes" % [race.player.position, overtakes])
	print("  car incidents: %d hard (>4 m/s), %d soft; %d automatic recoveries" % [hits["hard"], hits["soft"], race.recoveries])
	for h in hit_log:
		print("    hard hit: " + h)
	_check(hits["hard"] <= 6 * laps, "no pile-ups: at most %d hard incidents (%d)" % [6 * laps, hits["hard"]])
	_check(race.recoveries <= 2 * laps, "cars rarely need recovering (%d)" % race.recoveries)
	_check(race._results_shown, "race finishes and the results screen appears")
	_check(race.player.finished, "player crossed the line after %d laps" % laps)
	var finished := 0
	var seen := {}
	var furthest_last := INF
	for e in race.entrants:
		if e.finished:
			finished += 1
		seen[e.position] = true
		furthest_last = minf(furthest_last, e.progress)
	_check(seen.size() == race.entrants.size(), "positions are unique 1..%d" % race.entrants.size())
	print("  %d cars had finished when the results appeared" % finished)
	_check(furthest_last > race.track.total_length * (laps - 1), "no car stranded (last car covered %.0f m)" % furthest_last)
	var stats: Dictionary = save.data["stats"]
	_check(int(stats["races"]) == 1, "race recorded in profile")

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
