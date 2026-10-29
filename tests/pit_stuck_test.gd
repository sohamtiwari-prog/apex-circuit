extends SceneTree
## Pit stops that go wrong must never leave you stuck. On every circuit with
## a pit lane, the player boxes in the awkward ways real players do:
##   normal    box well before the entry
##   late      tap Box just before the pit entry at full speed
##   offline   arrive on the grass on the far side, at an angle, slowly
##   crowd     the whole field pits on the same lap (queues at team boxes)
##   reset1    tap Reset on the entry road
##   reset2    tap Reset while the crew are at work
##   reset3    tap Reset in the pit lane on the way out
##   resetlane tap Reset in the lane behind the pit wall on the way in
##   spin      spin the car round just as the pit entry starts
##   jam       the car can't move in the lane for 6 s (the crew push it on)
## Each must end with you back racing (with or without the stop done) and
## no long stretch sitting still outside the box.
##   godot --headless --fixed-fps 120 --script res://tests/pit_stuck_test.gd [-- scenario [track ...]]
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []
const ALL := ["normal", "late", "offline", "crowd", "reset1", "reset2", "reset3", "resetlane", "spin", "jam"]


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var args: Array = OS.get_cmdline_user_args()
	var scen: Array = ALL
	var tracks: Array = ["silvermoor", "styria", "ile_royale", "brianza", "pannonia", "ardennes", "desert", "entrelagos", "gulf", "kestrel_park", "riviera", "marina"]
	if not args.is_empty():
		scen = [args[0]] if args[0] != "all" else ALL
		if args.size() > 1:
			tracks = args.slice(1)
	for s in scen:
		for tid in tracks:
			await _one(String(tid), String(s))
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)


func _one(tid: String, scen: String) -> void:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 5; st["opponents"] = 11 if scen == "crowd" else 5
	st["track"] = tid; st["car"] = "gp26"
	st["qualifying"] = false; st["weather"] = "dry"; st["team"] = 3
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	var tr = race.track
	if not tr.has_pit_lane:
		race.queue_free()
		await process_frame
		return
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var wk = race.weekend
	var me = race.player
	while race.race_time < 3.0:
		await physics_frame
	var n: int = tr.size()
	if scen == "crowd":
		for e in race.entrants:
			if not e.is_player:
				e.wear = 0.95
		wk.set_box("hard")
	else:
		# Start 600 m before the pit entry at speed.
		var i0: int = 0
		for i in n:
			if absf(tr.pit_ps(i) + 600.0) < 2.0:
				i0 = i
				break
		var xf: Transform3D = tr.pose_at(i0, me.car.spawn_height(), tr.line_offset[i0])
		race._place(me, xf)
		me.car.linear_velocity = xf.basis.z * 60.0
		me.car.controls_enabled = true
		me.lap = 1
		if scen != "late":
			wk.set_box("hard")
	var t := 0
	var boxed_t := -1
	var did := false
	var still := 0.0
	var worst_still := 0.0
	var resets := 0
	var back_at := -1
	var phase_seen := 0
	var jam_t := -1
	while t < 120 * (260 if scen == "crowd" else 150):
		await physics_frame
		t += 1
		var ps: float = tr.pit_ps(me.idx)
		var v: float = absf(me.car.forward_speed())
		phase_seen = maxi(phase_seen, me.pit_phase)
		if scen == "late" and not me.pit_req and me.pit_phase == 0 and boxed_t < 0 and ps > -35.0 and ps < -25.0:
			wk.set_box("hard")
			boxed_t = t
		if not did:
			match scen:
				"offline":
					if me.pit_phase == 1:
						var i: int = me.idx
						var side: float = -tr.pit_side
						var xf: Transform3D = tr.pose_at(i, me.car.spawn_height(), side * (tr.road_half + 2.5))
						xf.basis = xf.basis.rotated(Vector3.UP, side * 0.45)
						me.car.global_transform = xf
						me.car.linear_velocity = xf.basis.z * 18.0
						did = true
				"spin":
					if me.pit_phase == 1:
						me.car.angular_velocity = Vector3(0, 6.0, 0)
						did = true
				"jam":
					if me.pit_phase == 1 and ps > tr.PIT_ENTRY_LEN + 15.0:
						me.car.freeze = true
						jam_t = t
						did = true
				"reset1":
					if me.pit_phase == 1 and ps > tr.PIT_ENTRY_LEN * 0.5:
						race._reset_to_track(me, true); resets += 1; did = true
				"resetlane":
					if me.pit_phase == 1 and ps > tr.PIT_ENTRY_LEN + 20.0:
						race._reset_to_track(me, true); resets += 1; did = true
				"reset2":
					if me.pit_phase == 2 and me.pit_timer > 0.5:
						race._reset_to_track(me, true); resets += 1; did = true
				"reset3":
					if me.pit_phase == 3 and ps > tr.pit_total() - 70.0:
						race._reset_to_track(me, true); resets += 1; did = true
		if jam_t > 0 and t == jam_t + 120 * 6:
			me.car.freeze = false
		# Sitting still anywhere but the box (or the queue for it).
		var waiting: bool = me.pit_phase == 2 or (me.pit_phase == 1 and wk._stop_ps(me) < me.pit_box) or (jam_t > 0 and t < jam_t + 120 * 6)
		if v < 1.0 and not waiting:
			still += 1.0 / 120.0
			worst_still = maxf(worst_still, still)
		else:
			still = 0.0
		if phase_seen > 0 and me.pit_phase == 0 and back_at < 0:
			back_at = t
		if back_at > 0 and t > back_at + 120 * 8:
			break
	var lat: float = absf(tr.lateral(me.car.global_position, me.idx))
	var racing: bool = back_at > 0 and me.pit_phase == 0 and absf(me.car.forward_speed()) > 15.0 and lat < tr.road_half + 3.0
	print("    %-10s %-12s phase seen %d, now %d, stops %d, still %.1f s, back after %s, %.0f km/h, lat %.1f" % [scen, tid, phase_seen,
		me.pit_phase, me.stops, worst_still, ("%.0f s" % ((back_at) / 120.0)) if back_at > 0 else "never", me.car.speed_kmh(), lat])
	_check(racing and worst_still < 4.0, "%s %s: never stuck, racing again afterwards" % [scen, tid])
	if scen in ["normal", "offline", "crowd", "spin", "reset1", "reset2", "resetlane", "jam"]:
		_check(me.stops == 1, "%s %s: the stop still happens" % [scen, tid])
	race.queue_free()
	await process_frame
	await process_frame
