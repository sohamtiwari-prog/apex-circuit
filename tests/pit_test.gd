extends SceneTree
## Pit lane: on several circuits (pits on the right, on the left, a street
## circuit) you box for hard tyres and an AI car on worn tyres boxes too.
## Both leave the track down the entry road, run the lane behind the pit
## wall, stop at their team's box while the crew change the wheels, and come
## back out onto the track, without being "rescued" back onto it on the way.
##   godot --headless --fixed-fps 120 --script res://tests/pit_test.gd
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var tracks: Array = OS.get_cmdline_user_args()
	if tracks.is_empty():
		tracks = ["styria", "ile_royale", "marina"]
	for tid in tracks:
		await _one(String(tid))
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)


func _one(tid: String) -> void:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 4; st["opponents"] = 5; st["track"] = tid; st["car"] = "gp26"
	st["qualifying"] = false; st["weather"] = "dry"; st["team"] = 3
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var tr = race.track
	var wk = race.weekend
	print("%s: pit lane %s, side %+.0f, lane %.0f m" % [tid, tr.has_pit_lane, tr.pit_side, tr.PIT_STRAIGHT_LEN])
	_check(tr.has_pit_lane, "%s: has a pit lane" % tid)
	# Wait for the race to be under way, then box.
	while race.race_time < 3.0:
		await physics_frame
	var me = race.player
	var ai = null
	for e in race.entrants:
		if not e.is_player:
			ai = e
			break
	ai.wear = 0.92
	wk.set_box("hard")
	var max_lat := 0.0
	var stop_ps := INF
	var stop_lat := 0.0
	var crew_seen := false
	var jumps := 0
	var prev: Vector3 = me.car.global_position
	var ai_stopped := false
	var held_at := Vector3.INF
	var creep := 0.0
	var ai_done := false
	var done := false
	var t := 0
	while t < 120 * 260 and not (done and ai_done):
		await physics_frame
		t += 1
		var pos: Vector3 = me.car.global_position
		if pos.distance_to(prev) > 12.0:
			jumps += 1
		prev = pos
		if me.pit_phase > 0:
			max_lat = maxf(max_lat, absf(tr.lateral(pos, me.idx)))
		if me.pit_phase == 2:
			if held_at == Vector3.INF:
				held_at = pos
			creep = maxf(creep, pos.distance_to(held_at))
			stop_ps = tr.pit_ps(me.idx)
			stop_lat = absf(tr.lateral(pos, me.idx))
			crew_seen = crew_seen or wk.crew.has(me)
		if me.stops > 0 and me.pit_phase == 0:
			done = true
		if ai.pit_phase == 2:
			ai_stopped = true
		if ai.stops > 0 and ai.pit_phase == 0:
			ai_done = true
	var box: float = tr.pit_boxes.get(3, -1.0)
	print("    you: stopped at %.1f (box %.1f), lateral %.1f (box lane %.1f), deepest %.1f; %d stop(s); %s tyres; lost %.1f s" % [
		stop_ps, box, stop_lat, tr.pit_box_lat(), max_lat, me.stops, me.compound, float(me.get_meta("last_pit_loss", -1.0))])
	_check(max_lat > tr.pit_off + 2.0, "%s: you drive down the lane behind the pit wall (%.1f m out)" % [tid, max_lat])
	_check(absf(stop_ps - box) < 2.5 and absf(stop_lat - tr.pit_box_lat()) < 1.8, "%s: you stop in your team's box" % tid)
	_check(crew_seen, "%s: the crew work on the car" % tid)
	_check(creep < 0.4, "%s: the car stays still while they do (moved %.2f m)" % [tid, creep])
	_check(done and me.compound == "hard" and me.wear < 0.1, "%s: back out on new hard tyres" % tid)
	_check(jumps == 0, "%s: never put back on the track on the way (%d jumps)" % [tid, jumps])
	var loss := float(me.get_meta("last_pit_loss", 999.0))
	_check(loss > 12.0 and loss < 60.0, "%s: the stop costs a sensible time (%.1f s in the pit lane)" % [tid, loss])
	_check(absf(tr.lateral(me.car.global_position, me.idx)) < tr.road_half + 2.0, "%s: and racing on the track again" % tid)
	_check(ai_stopped and ai_done and ai.wear < 0.2, "%s: an AI car on worn tyres pits too" % tid)
	race.queue_free()
	await process_frame
	await process_frame
