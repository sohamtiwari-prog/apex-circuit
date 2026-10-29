extends SceneTree
## Race control and the timing screens (scripts/race_control.gd, race.gd):
##   - a bot breaks down: out (DNF), parked, a VSC; bots keep under the VSC
##     limit; the VSC ends; the car is cleared away;
##   - track limits: three warnings, then 5 s penalties;
##   - a penalty is served at the next pit stop (held before the crew work);
##   - a penalty not served goes on the race time (and can cost a place);
##   - overtaking under yellow: give the place back, or a penalty;
##   - the tower lists everyone with tyres, gaps from the timing lines,
##     PIT / DNF; the results and stats keep up with the race.
##   godot --headless --fixed-fps 120 --script res://tests/race_control_test.gd
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _race(laps: int, opponents: int, rules := true) -> Node:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = laps; st["opponents"] = opponents; st["track"] = "silvermoor"
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = rules
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	return race


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _until(race: Node, cond: Callable, secs: float) -> bool:
	var t := 0
	while t < int(secs * 120.0):
		await physics_frame
		t += 1
		if cond.call():
			return true
	return false


func _run() -> void:
	await process_frame
	await _retirement_and_vsc()
	await _penalties()
	await _timing()
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)


func _retirement_and_vsc() -> void:
	var race: Node = await _race(4, 7)
	var rc = race.control
	_check(rc != null and rc.penalties, "race control is on for a race (flags & penalties)")
	var victim = null
	for e in race.entrants:
		if e.ai != null and e.grid == 3:
			victim = e
	rc._fail[victim] = race.track.total_length * 0.45
	var ok: bool = await _until(race, func(): return victim.dnf, 140.0)
	_check(ok, "a bot breaks down: out of the race (DNF, %s)" % victim.dnf_reason)
	ok = await _until(race, func(): return rc.vsc or rc._retiring.get(victim, [0])[0] == 1, 15.0)
	await _frames(240)
	_check(absf(victim.car.forward_speed()) < 1.5, "it parks (%.1f m/s)" % victim.car.forward_speed())
	if not rc.vsc:
		rc.deploy_vsc("test")
	_check(rc.vsc, "the VSC is out")
	# Give the field 4 s to slow down, then check everyone keeps to the limit.
	await _frames(480)
	var worst := 0.0
	var t := 0
	while rc.vsc and t < 120 * 8:
		await physics_frame
		t += 1
		for e in race.entrants:
			if e.ai != null and not e.dnf and e.pit_phase == 0:
				worst = maxf(worst, e.car.forward_speed() - rc.vsc_limit(e.car))
	_check(worst < 2.5, "bots keep under the VSC limit (worst %.1f m/s over)" % worst)
	ok = await _until(race, func(): return not rc.vsc, 45.0)
	_check(ok, "the VSC ends (\"%s\")" % (rc.messages[rc.messages.size() - 1] if not rc.messages.is_empty() else ""))
	ok = await _until(race, func(): return not victim.car.visible, 45.0)
	_check(ok, "the broken-down car is cleared away")
	var rows: Array = race.tower_rows()
	var last: Dictionary = rows[rows.size() - 1]
	_check(String(last["status"]) == "DNF" and String(last["name"]) == victim.name, "the tower shows it last, DNF")
	var bots_pen := 0.0
	for e in race.entrants:
		if e.ai != null:
			bots_pen += e.pen_total
	print("    (bots' penalties this race: %.0f s; race control said %d things)" % [bots_pen, rc.messages.size()])
	race.queue_free()
	await process_frame


func _penalties() -> void:
	var race: Node = await _race(5, 5)
	var rc = race.control
	var tr = race.track
	var me = race.player
	await _until(race, func(): return race.race_time > 4.0, 30.0)
	# Track limits: run the car well wide four times on a straight.
	var strikes := []
	for k in 4:
		var i: int = me.idx
		var xf: Transform3D = tr.pose_at(i, me.car.spawn_height(), tr.road_half + 4.0)
		me.car.global_transform = xf
		me.car.linear_velocity = xf.basis.z * 30.0
		await _frames(60)
		strikes.append(me.tl_strikes)
		race._reset_to_track(me, true)
		me.ghost = 0.0
		await _frames(120)
	_check(me.tl_strikes == 4, "track limits: four times wide, four strikes (%s)" % str(strikes))
	_check(absf(me.pen_pending - 5.0) < 0.01, "three warnings, then a 5 s penalty (%.0f s to serve)" % me.pen_pending)
	# Served at the stop: held before the crew start.
	race.weekend.set_box("hard")
	var ok: bool = await _until(race, func(): return me.pit_phase == 2, 160.0)
	_check(ok and me.pit_pen >= 5.0 and me.pit_need >= 7.0, "at the stop the penalty is served first (stop %.1f s incl. %.0f s)" % [me.pit_need, me.pit_pen])
	ok = await _until(race, func(): return me.pit_phase == 0, 60.0)
	_check(ok and me.pen_pending == 0.0 and me.pen_total == 5.0, "served: nothing left to add to the race time")
	# A penalty not served goes on the race time.
	var a = null
	var b = null
	for e in race.entrants:
		if e.ai != null and a == null:
			a = e
		elif e.ai != null and b == null:
			b = e
	a.finished = true; a.finish_time = 100.0; a.pen_pending = 5.0
	b.finished = true; b.finish_time = 103.0
	_check(race._by_position(b, a), "an unserved 5 s penalty costs a place at the finish (+3 s on the road)")
	a.finished = false; b.finished = false; a.pen_pending = 0.0
	# Overtaking under yellow: the place must be given back.
	var target = null
	for e in race.entrants:
		if e.ai != null and not e.finished:
			target = e
	rc._order[me] = {target: true}
	rc._owe[me] = {}
	var pen0: float = me.pen_total
	# A stopped car (somewhere) 100 m up the road: yellow here.
	rc._inc["test"] = [fposmod(tr.cum[me.idx] + 100.0, tr.total_length), 1, 600.0]
	_check(rc.flag_at(me.idx) == 1 and rc.no_passing(me.idx), "a car stopped 100 m ahead: yellow, no overtaking")
	me.progress = target.progress + 20.0
	rc._overtakes(me)
	_check(rc._owe[me].has(target), "passing a car under yellow: told to give the place back")
	me.progress = target.progress - 20.0
	rc._overtakes(me)
	_check(not rc._owe[me].has(target) and me.pen_total == pen0, "handing it back clears it (no penalty)")
	me.progress = target.progress + 20.0
	rc._overtakes(me)
	rc._owe[me][target] = race.race_time - 1.0          # (the 10 s are up)
	me.progress = target.progress + 25.0
	rc._overtakes(me)
	_check(me.pen_total == pen0 + 5.0, "keeping it: 5 s penalty")
	race.queue_free()
	await process_frame


func _timing() -> void:
	var race: Node = await _race(2, 7)
	var me = race.player
	race.weekend.set_box("soft")
	await _until(race, func(): return race.race_time > 50.0, 90.0)
	var rows: Array = race.tower_rows()
	_check(rows.size() == race.entrants.size(), "the tower lists the whole field (%d)" % rows.size())
	var ok := true
	var gaps_ok := true
	for i in rows.size():
		ok = ok and String(rows[i]["compound"]) != "" and int(rows[i]["pos"]) == i + 1
		if i > 0:
			var s := String(rows[i]["int"])
			gaps_ok = gaps_ok and (s.begins_with("+") or s == "")
	_check(ok, "every car with its tyre, in order")
	_check(gaps_ok and String(rows[0]["int"]) == "Leader", "intervals from the timing lines (%s, %s, ...)" % [rows[1]["int"], rows[2]["int"]])
	# Gaps are steady: two looks a tick apart give the same numbers.
	await physics_frame
	var rows2: Array = race.tower_rows()
	var same := 0
	for i in mini(rows.size(), rows2.size()):
		if rows[i]["name"] == rows2[i]["name"] and rows[i]["int"] == rows2[i]["int"]:
			same += 1
	_check(same >= rows.size() - 2, "gaps don't flicker frame to frame (%d of %d the same)" % [same, rows.size()])
	var pit_seen := await _until(race, func():
		for r in race.tower_rows():
			if r["status"] == "PIT":
				return true
		return false, 80.0)
	_check(pit_seen, "a car in the pits shows PIT")
	await _until(race, func(): return race._results_shown, 200.0)
	_check(race._results_shown, "the race finishes")
	var live: Dictionary = race.live_results()
	var stats: Array = live["stats"]
	var mine: Dictionary = {}
	for s in stats:
		if s["player"]:
			mine = s
	_check(not mine.is_empty() and int(mine["grid"]) > 0 and (mine["laps"] as Array).size() == 2, "race stats: your grid slot and lap by lap (%s)" % str(mine.get("laps", [])))
	_check(not mine.is_empty() and (mine["stints"] as Array).size() >= 2 and int(mine["stops"]) >= 1, "race stats: your stints %s" % str(mine.get("stints", [])))
	var tops := true
	for s in stats:
		tops = tops and float(s["top"]) > 150.0
	_check(tops, "race stats: everyone's top speed")
	# The results keep up: a car finishing after you changes from "Lap" to a gap.
	var running := 0
	for r in live["rows"]:
		if String(r["gap"]).begins_with("Lap"):
			running += 1
	await _until(race, func():
		for e in race.entrants:
			if not e.finished:
				return false
		return true, 90.0)
	var after := 0
	for r in race.live_results()["rows"]:
		if String(r["gap"]).begins_with("Lap"):
			after += 1
	_check(after <= running and after == 0, "results update as the others finish (%d still running -> %d)" % [running, after])
	_check(race.hud.results_panel.visible, "results screen up")
	race.queue_free()
	await process_frame
