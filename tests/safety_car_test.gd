extends SceneTree
## The Safety Car and holding position (scripts/safety_car.gd, race_control.gd):
##   - deployed: the car comes out of the pit exit ahead of the leader and
##     the field closes up behind it, single file;
##   - nobody passes anybody (bots don't pass a slow you either), and the
##     Safety Car stays in front;
##   - "in this lap": it goes into the pit lane; the leader takes them to
##     the line; racing resumes there;
##   - under the VSC, bots don't pass a slow you;
##   - pass the Safety Car yourself and you're told to drop back, then
##     penalised.
##   godot --headless --fixed-fps 120 --script res://tests/safety_car_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _race(laps: int, opponents: int, track := "silvermoor") -> Node:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = laps; st["opponents"] = opponents; st["track"] = track
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"; st["race_control"] = true
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	race.control._fail.clear()                 # (no surprise breakdowns)
	return race


func _until(cond: Callable, secs: float) -> bool:
	for t in int(secs * 120.0):
		await physics_frame
		if cond.call():
			return true
	return false


## Who's ahead of whom (cars on track, not in the pits), by distance raced.
func _order(race: Node) -> Array:
	var on: Array = []
	for e in race.entrants:
		if e.pit_phase == 0 and not e.dnf and not e.finished:
			on.append(e)
	on.sort_custom(func(a, b): return a.progress > b.progress)
	return on


## Overtakes between two looks: pairs (both still out, neither pitted in
## between) that swapped.
func _swaps(before: Array, after: Array, stops0: Dictionary, crawled := {}) -> Array[String]:
	var out: Array[String] = []
	for i in before.size():
		for j in range(i + 1, before.size()):
			var a = before[i]
			var b = before[j]
			if not after.has(a) or not after.has(b) or a.stops != stops0[a] or b.stops != stops0[b] or crawled.has(a):
				continue                   # (a crawling car may be passed)
			if after.find(b) < after.find(a):
				out.append("%s past %s" % [b.name, a.name])
	return out


func _run() -> void:
	await process_frame
	await _safety_car()
	await _vsc_slow_you()
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)


func _safety_car() -> void:
	var race: Node = await _race(6, 9)
	var rc = race.control
	var sc: SafetyCar = rc.sc
	var tr: Track = race.track
	# You drive slowly, so the bots behind would like to get by.
	race.autopilot.skill = 0.8
	await _until(func(): return race.race_time > 40.0, 90.0)
	rc.deploy_sc("test")
	_check(sc.phase == 1, "Safety Car deployed")
	var ok: bool = await _until(func(): return sc.out, 120.0)
	_check(ok, "it comes out on track")
	var leader = sc._leader()
	var L := tr.total_length
	var lead_gap := fposmod(sc.s_pos() - float(tr.cum[leader.idx]), L)
	_check(lead_gap < 300.0, "ahead of the leader (%.0f m)" % lead_gap)
	var before := _order(race)
	var stops0 := {}
	for e in race.entrants:
		stops0[e] = e.stops
	# Bunch up: after a while the field is close behind it.
	var max_lead_gap := 0.0
	var behind_ok := true
	var t := 0
	while sc.phase == 1 and t < 120 * 150:
		await physics_frame
		t += 1
		if t % 60 == 0 and sc.out:
			var ld = sc._leader()
			var g := fposmod(sc.s_pos() - float(tr.cum[ld.idx]), L)
			behind_ok = behind_ok and (g < L * 0.5)
			if t > 120 * 30:
				max_lead_gap = maxf(max_lead_gap, g)
	_check(sc.phase == 2, "\"Safety Car in this lap\" after about a lap leading")
	_check(behind_ok, "nobody gets ahead of the Safety Car")
	_check(max_lead_gap < 70.0, "the leader closes up behind it (worst %.0f m)" % max_lead_gap)
	var spread := float(_order(race)[0].progress) - float(_order(race)[-1].progress)
	print("    (field spread behind the Safety Car: %.0f m)" % spread)
	ok = await _until(func(): return sc.phase == 3, 120.0)
	_check(ok and not sc.out, "it goes into the pit lane at the end of the lap")
	ok = await _until(func(): return sc.phase == 0, 120.0)
	_check(ok, "racing resumes at the line (%s)" % (rc.messages[rc.messages.size() - 1] if not rc.messages.is_empty() else ""))
	var swaps := _swaps(before, _order(race), stops0)
	_check(swaps.is_empty(), "nobody overtook anybody under the Safety Car %s" % str(swaps))
	# Passing it yourself.
	rc.deploy_sc("test 2")
	sc.count = 0
	await _until(func(): return sc.out, 120.0)
	var me = race.player
	var pen0: float = me.pen_total
	race._place(me, tr.pose_at((sc._idx() + 12) % tr.size(), me.car.spawn_height(), 0.0))
	me.car.linear_velocity = me.car.global_basis.z * 40.0
	race.autopilot.idx = me.idx
	ok = await _until(func(): return me.pen_total > pen0, 12.0)
	_check(ok, "pass the Safety Car and stay ahead: penalty")
	race.queue_free()
	await process_frame


func _vsc_slow_you() -> void:
	var race: Node = await _race(5, 9, "styria")
	var rc = race.control
	race.autopilot.skill = 0.75
	await _until(func(): return race.race_time > 35.0, 90.0)
	rc.deploy_vsc("test")
	# (A pass already half done when it comes out is let go: like the
	# real VSC, a few seconds to settle.)
	await _until(func(): return false, 3.0)
	var before := _order(race)
	var stops0 := {}
	for e in race.entrants:
		stops0[e] = e.stops
	# Watch who's ahead of whom every half second (for the record if it fails).
	var log: Array[String] = []
	var prev := before
	var slow := {}                 # cars that crawled at some point (may be passed)
	while rc.vsc:
		await _until(func(): return not rc.vsc, 0.5)
		for e in race.entrants:
			if absf(e.car.forward_speed()) < 15.0:
				slow[e] = true
		var now := _order(race)
		for sw in _swaps(prev, now, stops0):
			log.append("t%.1f %s" % [race.race_time, sw])
		prev = now
	for l in log:
		print("    ", l)
	var swaps := _swaps(before, _order(race), stops0, slow)
	_check(swaps.is_empty(), "VSC: nobody overtakes anybody, not even a slow you %s" % str(swaps))
	race.queue_free()
	await process_frame
