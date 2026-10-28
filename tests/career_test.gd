extends SceneTree
## The game around the racing: garage (buying cars; old upgrades refunded),
## career events (race, eliminator, time trial: stars and credits), and a
## championship season (qualifying, points, standings, trophy, prize).
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
	var gar = load("res://scripts/garage.gd")
	var car_mod = load("res://scripts/career.gd")
	var champ = load("res://scripts/championship.gd")

	# --- Garage
	_check(save.credits() == 10000 and save.owns("marauder") and not save.owns("stuttgart9"), "new profile: 10,000 CR and the Marauder")
	_check(not save.buy_car("stuttgart9") and save.credits() == 10000, "can't buy a car you can't afford")
	save.add_credits(20000)
	_check(save.buy_car("stuttgart9") and save.owns("stuttgart9") and save.credits() == 12000, "buying the Stuttgart 9 Turbo (18,000 CR)")
	var spec: Dictionary = save.car_spec("stuttgart9")
	_check(spec == load("res://scripts/car_specs.gd").get_spec("stuttgart9") and not save.data.has("upgrades"), "every car races as it comes (no upgrades)")

	# Old saves: credits spent on upgrades come back.
	var old: Dictionary = save.default_profile()
	old["schema"] = 4
	old["credits"] = 1000
	old["upgrades"] = {"marauder": {"engine": 2}}
	old["upgrade_jobs"] = {"marauder|aero": {"car": "marauder", "part": "aero", "level": 1, "done": 0}}
	save._migrate(old)
	var want: int = gar.old_upgrade_cost("marauder", 1) * 2 + gar.old_upgrade_cost("marauder", 2)
	_check(int(old["credits"]) == 1000 + want and not old.has("upgrades") and not old.has("upgrade_jobs"), "old upgrades refunded (+%d CR)" % want)

	# --- Career: a race
	var ev: Dictionary = car_mod.event(0, 0)
	ev["car"] = "marauder"
	ev["return_to"] = "res://scenes/career.tscn"
	save.pending_event = ev
	var cr0: int = save.credits()
	var race := await _race()
	var rw: Dictionary = race.last_reward
	print("    club race: P%d of %d, %d stars, +%d CR" % [race.player.position, race.entrants.size(), int(rw.get("stars", -1)), int(rw.get("credits", 0))])
	_check(race.entrants.size() == 8 and race._results_shown, "career race: 8 cars, finished")
	_check(int(rw.get("stars", -1)) == car_mod.stars_for_position("race", race.player.position) and save.career_stars("club_1") == int(rw["stars"]), "stars by finishing place, saved")
	_check(save.credits() == cr0 + int(rw["credits"]) and int(rw["credits"]) > 0, "credits paid")
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
