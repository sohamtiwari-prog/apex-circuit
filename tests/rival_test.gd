extends SceneTree
## Career rivals and star rewards: each series' rival is on the grid of its
## races (named, quicker), is the duel's opponent, isn't in time trials or
## quick races; the head-to-head record is kept; rewards unlock with stars.
##   godot --headless --fixed-fps 120 --script res://tests/rival_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _race(ev: Dictionary) -> Node:
	var save: Node = root.get_node("Save")
	ev["car"] = String((ev["cars"] as Array)[0])
	save.pending_event = ev
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	return race


func _run() -> void:
	await process_frame
	Engine.max_physics_steps_per_frame = 48
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	# A club race (1 lap, to be quick).
	var ev := Career.event(0, 0)
	ev["laps"] = 1
	var race := _race(ev)
	await physics_frame
	var rival = null
	var best_other := 0.0
	for e in race.entrants:
		if e.rival:
			rival = e
		elif e.ai != null:
			best_other = maxf(best_other, e.ai.skill)
	_check(rival != null and rival.name == "Marco Vella", "club race: Marco Vella is on the grid")
	_check(rival != null and rival.ai.skill > best_other, "and quicker than the rest (%.3f vs %.3f)" % [rival.ai.skill if rival != null else 0.0, best_other])
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.99
	var t := 0
	while not race._results_shown and t < 120 * 200:
		await physics_frame
		t += 1
	var rw: Dictionary = race.last_reward
	_check(rw.has("rival") and not (rw["rival"] as Dictionary).is_empty(), "the results say how you did against him")
	var rec: Dictionary = save.data["rivals"].get("club", {})
	_check(int(rec.get("won", 0)) + int(rec.get("lost", 0)) == 1, "the head-to-head is kept (%s)" % str(rec))
	race.queue_free()
	await process_frame
	# The duel is against the rival; a time trial has none.
	race = _race(Career.event(0, 2))
	await physics_frame
	_check(race.entrants.size() == 2 and race.entrants[1].rival, "the duel is against your rival")
	race.queue_free()
	await process_frame
	race = _race(Career.event(0, 1))
	await physics_frame
	var any := false
	for e in race.entrants:
		any = any or e.rival
	_check(not any, "no rival in a time trial")
	race.queue_free()
	await process_frame
	# Rewards with stars.
	save.data["career"] = {}
	_check(Career.rewards_unlocked(save).is_empty() and int(Career.next_reward(save)[0]) == 10, "no stars: nothing yet, the first reward at 10")
	for i in 4:
		save.data["career"]["club_%d" % (i + 1)] = 3
	_check(Career.rewards_unlocked(save) == ["colours"], "12 stars: the metallic colours (%s)" % str(Career.rewards_unlocked(save)))
	var s := CarSpecs.apply_paint(CarSpecs.get_spec("gp26"), {"on": true, "base": "#e01a1a", "pattern": "carbon"})
	_check((s["livery"]["base"] as Color).get_luminance() < 0.1 and (s["livery"]["stripe"] as Color).is_equal_approx(Color.html("#e01a1a")), "carbon pattern: carbon body, your colour as the trim")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
