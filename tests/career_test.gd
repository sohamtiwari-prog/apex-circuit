extends SceneTree
## The game around the racing: the garage (every car open, no money), career
## events (race, eliminator, time trial: stars), the daily challenge, and a
## championship season (qualifying, points, standings, trophy).
##   godot --headless --fixed-fps 120 --script res://tests/career_test.gd
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []
var save: Node


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


## Runs the pending event with the AI driving you; returns the race node
## after its results are up.
func _race(skip_quali := true) -> Node:
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.99
	if race.weekend != null and race.weekend.in_quali and skip_quali:
		race.weekend.finish_qualifying(-1.0)
		race.weekend._end_qualifying()
	var t := 0
	while not race._results_shown and t < 120 * 600:
		await physics_frame
		t += 1
	return race


func _run() -> void:
	await process_frame
	save = root.get_node("Save")
	save.data = save.default_profile()
	var car_mod = load("res://scripts/career.gd")
	var champ = load("res://scripts/championship.gd")

	# --- Garage
	_check(not save.data.has("credits") and not save.data.has("owned_cars") and not save.has_method("buy_car"), "new profile: no money, no buying")
	var spec: Dictionary = save.car_spec("stuttgart9")
	_check(spec == load("res://scripts/car_specs.gd").get_spec("stuttgart9") and not save.data.has("upgrades"), "every car races as it comes (no upgrades)")

	var all_open := true
	for si in car_mod.SERIES.size():
		var e0: Dictionary = car_mod.event(si, 0)
		all_open = all_open and not e0.has("reward") and (e0["cars"] as Array).size() > 0
	_check(all_open, "career events carry no prize money")

	# Old saves: money, owned cars and upgrades are cleared; stars stay.
	var old: Dictionary = save.default_profile()
	old["schema"] = 5
	old["credits"] = 1000
	old["owned_cars"] = ["marauder", "veloce"]
	old["upgrade_refund"] = 300
	old["upgrades"] = {"marauder": {"engine": 2}}
	old["career"] = {"club_1": 3}
	save._migrate(old)
	_check(not old.has("credits") and not old.has("owned_cars") and not old.has("upgrade_refund") and not old.has("upgrades") and int(old["career"]["club_1"]) == 3, "old saves: money and owned cars removed, stars kept")

	# --- Career: a race
	var ev: Dictionary = car_mod.event(0, 0)
	ev["car"] = "marauder"
	ev["return_to"] = "res://scenes/career.tscn"
	save.pending_event = ev
	var race := await _race()
	var rw: Dictionary = race.last_reward
	print("    club race: P%d of %d, %d stars" % [race.player.position, race.entrants.size(), int(rw.get("stars", -1))])
	_check(race.entrants.size() == 8 and race._results_shown, "career race: 8 cars, finished")
	_check(int(rw.get("stars", -1)) == car_mod.stars_for_position("race", race.player.position) and save.career_stars("club_1") == int(rw["stars"]), "stars by finishing place, saved")
	_check(not rw.has("credits") and not save.data.has("credits"), "no money paid out")
	race.queue_free()
	await process_frame

	# --- Career: eliminator
	ev = car_mod.event(0, 4)
	ev["car"] = "marauder"
	save.pending_event = ev
	race = await _race()
	var out := 0
	var order_ok := true
	var ordered: Array = race.entrants.duplicate()
	ordered.sort_custom(race._by_position)
	var seen_out := false
	for e in ordered:
		if e.eliminated:
			out += 1
			seen_out = true
		elif seen_out:
			order_ok = false
	print("    eliminator: %d knocked out; you P%d (%s)" % [out, race.player.position, "out" if race.player.eliminated else "survived"])
	_check(out >= 4 or race.player.eliminated, "one car out per lap (%d)" % out)
	_check(order_ok, "knocked-out cars are classified behind the survivors")
	race.queue_free()
	await process_frame

	# --- Career: time trial
	ev = car_mod.event(0, 1)
	ev["car"] = "marauder"
	save.pending_event = ev
	race = await _race()
	rw = race.last_reward
	var tg: Array = race.tt_targets
	print("    time trial: best %.3f; targets %s; %d stars" % [race.player.best_lap, str(tg), int(rw.get("stars", -1))])
	_check(race.entrants.size() == 1 and tg.size() == 3 and float(tg[0]) < float(tg[1]) and float(tg[1]) < float(tg[2]), "time trial: gold < silver < bronze")
	_check(race.player.lap == 3 and race._results_shown, "ends after its 3 laps")
	_check(int(rw.get("stars", -1)) == car_mod.stars_for_lap(race.player.best_lap, tg), "stars from your best lap")
	race.queue_free()
	await process_frame

	# --- Daily challenge
	var daily = load("res://scripts/daily.gd")
	var a: Dictionary = daily.event("20261028")
	var kinds := {}
	for d in 30:
		var ev2: Dictionary = daily.event("202611%02d" % (d + 1))
		kinds[String(ev2["track"]) + String(ev2["type"])] = true
	_check(a == daily.event("20261028") and kinds.size() >= 15, "daily challenge: the same all day, different every day (%d kinds in 30 days)" % kinds.size())
	var dev: Dictionary = {}
	for d in 60:
		var ev3: Dictionary = daily.event("2026%04d" % (1101 + d))
		if ev3["type"] == "race" and ev3.has("tod"):
			dev = ev3
			break
	save.pending_event = dev
	race = await _race()
	print("    daily: %s -> P%d, %d stars" % [daily.describe(dev), race.player.position, int(race.last_reward.get("stars", -1))])
	_check(String(race._tod) == "night" and String(race.car.spec["id"]) == String(dev["car"]), "the daily's twist and loaned car are used (night, %s)" % dev["car"])
	_check(save.career_stars(String(dev["id"])) == int(race.last_reward.get("stars", -9)) , "daily stars saved")
	race.queue_free()
	await process_frame

	# --- Championship
	champ.start(save, "muscle", "marauder", "", 2, 1)
	var s: Dictionary = champ.active(save)
	_check(s["rounds"].size() == 2 and s["drivers"].size() == 20, "season: 2 rounds, 20 drivers")
	for r in 2:
		save.pending_event = champ.round_event(save)
		race = await _race()
		var named := true
		for e in race.entrants:
			if not e.is_player:
				named = named and e.driver > 0 and e.name == String(s["drivers"][e.driver]["name"])
		_check(named, "round %d: the season's drivers line up" % (r + 1))
		_check(race.last_reward.has("champ"), "round %d: points scored (+%d)" % [r + 1, int(race.last_reward.get("champ", {}).get("gained", -1))])
		race.queue_free()
		await process_frame
	s = champ.active(save)
	var total := 0
	for p in s["points"]:
		total += int(p)
	_check(total >= 2 * (25 + 18 + 15 + 12 + 10 + 8 + 6 + 4 + 2 + 1), "points handed out every round (%d)" % total)
	_check(bool(s["done"]) and (save.data["trophies"] as Array).size() == 1, "season over: trophy cabinet updated (P%d)" % champ.standing_of(s, 0))

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
