extends SceneTree
## Ise Bay's figure of eight: the track crosses over itself on a bridge.
## A 20-car race: every car keeps to its own level (nobody drops through the
## bridge or is put on the other road), laps count normally (no lap gained
## or lost at the crossing), cars on different levels never "touch", and
## nobody is reset there.
##   godot --headless --fixed-fps 120 --script res://tests/crossover_test.gd [-- laps]

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var laps := int(args[0]) if args.size() > 0 else 2
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = laps; st["opponents"] = 19; st["track"] = "isebay"
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = true
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	Engine.max_physics_steps_per_frame = 48
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.95
	var tr: Track = race.track
	_check(tr.bridges.size() == 1, "the track has its bridge (%d found)" % tr.bridges.size())
	if tr.bridges.is_empty():
		quit(1)
		return
	var b: Dictionary = tr.bridges[0]
	var lower_mid := int(b["lower"])
	var n := tr.size()
	var wrong_level := 0
	var under := 0
	var over := 0
	var cross_touch := [0]
	race.car_contact.connect(func(a, c, _cl):
		if absf((a as RaceCar).global_position.y - (c as RaceCar).global_position.y) > 3.0:
			cross_touch[0] += 1)
	var resets0: int = race.reset_log.size()
	var t := 0
	var last_lap := {}
	var lap_jumps := 0
	while t < 120 * (60 + laps * 130) and not race.player.finished:
		await physics_frame
		t += 1
		for e in race.entrants:
			if not e.car.visible:
				continue
			var p: Vector3 = e.car.global_position
			var i: int = e.idx
			# On the level its track index says: within 2.5 m of that road's height.
			if absf(p.y - tr.points[i].y) > 2.5 and e.pit_phase == 0:
				wrong_level += 1
			if posmod(i - int(b["i0"]), n) < int(b["i1"]) - int(b["i0"]):
				over += 1
			if absi(i - lower_mid) < 5:
				under += 1
			var l: int = e.lap
			if last_lap.has(e.slot) and l > int(last_lap[e.slot]) + 1:
				lap_jumps += 1
			last_lap[e.slot] = l
	var resets: Array = race.reset_log.slice(resets0)
	for r in resets:
		print("    reset: ", r)
	print("    car-ticks over the bridge %d, under it %d" % [over, under])
	_check(over > 1000 and under > 1000, "cars drove both over the bridge and under it")
	_check(wrong_level == 0, "every car stays on its own level (%d car-ticks off it)" % wrong_level)
	_check(lap_jumps == 0, "laps count normally across the crossing (%d jumps)" % lap_jumps)
	_check(cross_touch[0] == 0, "cars on the bridge and under it never touch (%d)" % cross_touch[0])
	_check(race.player.finished, "the race finishes (%d laps)" % laps)
	_check(resets.size() <= 1, "nobody needs resetting (%d)" % resets.size())
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
