extends SceneTree
## Bug sweep: a full race on every track (a different car and conditions
## each time: rain, changing weather, night, manual or auto pits, assists
## off, race control on or off, qualifying first), with the player's car
## driven by the autopilot. Prints a line per race; the caller collects any
## engine or script errors printed in between (tests/error_sweep.sh).
## Each race must finish, with every car either finished or retired for a
## reason, no car anywhere invalid (NaN), and nobody parked for long.
##   godot --headless --fixed-fps 120 --script res://tests/error_sweep.gd [-- track,track laps]

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
	var ids: Array = []
	if args.size() > 0 and args[0] != "all":
		ids = Array(String(args[0]).split(","))
	else:
		for t in Track.CATALOG:
			ids.append(t["id"])
	var laps := int(args[1]) if args.size() > 1 else 2
	var cars: Array = CarSpecs.CATALOG
	var k := 0
	for tid in ids:
		await _race(String(tid), String(cars[k % cars.size()]), k, laps)
		k += 1
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _race(tid: String, car_id: String, k: int, laps: int) -> void:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	var weathers := ["dry", "wet", "changing", "dry"]
	var times := ["auto", "night", "sunset", "day"]
	st["mode"] = "race"; st["laps"] = laps; st["opponents"] = 19; st["track"] = tid; st["car"] = car_id
	st["weather"] = weathers[k % 4]; st["time_of_day"] = times[(k / 2) % 4]
	st["pit_mode"] = "manual" if k % 2 == 0 else "auto"
	st["race_control"] = k % 5 != 4
	st["qualifying"] = k % 6 == 3
	st["difficulty"] = ["easy", "medium", "hard"][k % 3]
	if k % 3 == 2:
		st["steer_assist"] = "off"; st["brake_assist"] = "off"; st["traction_control"] = false; st["abs"] = false
	st["ideal_ghost"] = k % 4 == 1
	st["racing_line"] = k % 2 == 1
	print("=== %s in %s: %s, %s, pits %s, race control %s, qualifying %s, %s" % [tid, car_id, st["weather"], st["time_of_day"], st["pit_mode"], st["race_control"], st["qualifying"], st["difficulty"]])
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	Engine.max_physics_steps_per_frame = 48
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var t := 0
	var still := {}
	var worst_still := 0.0
	var worst_who := ""
	var nan := 0
	var limit := 120 * (90 + laps * 200 + (600 if st["qualifying"] else 0))
	while t < limit and not race._results_shown:
		await physics_frame
		t += 1
		if t % 12 != 0:
			continue
		for e in race.entrants:
			var p: Vector3 = e.car.global_position
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
				nan += 1
				continue
			var parked: bool = race.state == 1 and e.car.visible and not e.finished and not e.dnf and e.pit_phase == 0 \
				and race.control != null and race.control.sc_phase == 0 and e.car.linear_velocity.length() < 2.0
			if race.control == null:
				parked = race.state == 1 and e.car.visible and not e.finished and not e.dnf and e.pit_phase == 0 and e.car.linear_velocity.length() < 2.0
			still[e.slot] = (float(still.get(e.slot, 0.0)) + 0.1) if parked else 0.0
			if float(still.get(e.slot, 0.0)) > worst_still:
				worst_still = still[e.slot]
				worst_who = "%s at %.0f m" % [e.name, race.track.cum[e.idx]]
	var dnfs: Array = []
	for e in race.entrants:
		if e.dnf:
			dnfs.append(String(e.dnf_reason))
	print("    %s: results %s after %.0f s, P%d, %d retired %s, worst parked %.1f s (%s)" % [tid, "shown" if race._results_shown else "NOT shown", t / 120.0,
		race.player.position, dnfs.size(), dnfs, worst_still, worst_who])
	_check(race._results_shown, "%s: the race finishes and shows results" % tid)
	_check(nan == 0, "%s: no car anywhere invalid (%d)" % [tid, nan])
	_check(worst_still < 20.0, "%s: nobody parked on track for long (worst %.0f s, %s)" % [tid, worst_still, worst_who])
	race.queue_free()
	await process_frame
	await process_frame
