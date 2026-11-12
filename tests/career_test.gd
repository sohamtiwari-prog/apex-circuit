extends SceneTree
## The game around the racing: the garage (every car open, no money), the
## career ladder (karts first; 10 stars promote you a series; drivers from
## before the ladder keep Grand Prix), career events (race, eliminator, time
## trial: stars), the daily challenge, and championship seasons in each
## class (qualifying, points, standings, trophy).
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
	var spec: Dictionary = save.car_spec("gp26")
	_check(spec == load("res://scripts/car_specs.gd").get_spec("gp26") and not save.data.has("upgrades"), "every car races as it comes (no upgrades)")

	var all_open := true
	for si in car_mod.SERIES.size():
		var e0: Dictionary = car_mod.event(si, 0)
		all_open = all_open and not e0.has("reward") and (e0["cars"] as Array).size() > 0
	_check(all_open, "career events carry no prize money")
	# --- The ladder
	var ids: Array = []
	for se in car_mod.SERIES:
		ids.append(String(se["id"]))
	_check(ids == ["kart", "f4", "f3", "f2", "gp"], "the ladder: karting, F4, F3, F2, Grand Prix (%s)" % str(ids))
	var classes_ok := true
	for si in car_mod.SERIES.size():
		var car_id := String(car_mod.SERIES[si]["cars"][0])
		for ei in 5:
			var t := String(car_mod.event(si, ei)["track"])
			classes_ok = classes_ok and load("res://scripts/track.gd").ids_for(car_id).has(t)
	_check(classes_ok, "every event is on a circuit its class races on (karts on the kart circuits)")
	_check(car_mod.reached(save) == 0 and car_mod.is_open(save, 0) and not car_mod.is_open(save, 1), "a new driver starts in karting; F4 and up are locked")
	_check(champ.open_classes(save).size() == 1 and String(champ.open_classes(save)[0]["id"]) == "kart", "...and only the karting championship is open")
	for k in 3:
		save.data["career"]["kart_%d" % (k + 1)] = 3
	_check(car_mod.reached(save) == 0, "9 karting stars: not yet")
	save.data["career"]["kart_4"] = 1
	_check(car_mod.reached(save) == 1 and car_mod.is_open(save, 1) and not car_mod.is_open(save, 2), "10 karting stars: promoted to F4 (F3 still locked)")
	for k in 4:
		save.data["career"]["f4_%d" % (k + 1)] = 3
	_check(car_mod.reached(save) == 2, "then 10 in F4: F3")
	save.data["career"] = {}
	_check(car_mod.reached(save) == 0, "(back to a new driver)")
	# A driver from before the ladder was racing Grand Prix: they keep it.
	var v8: Dictionary = save.default_profile()
	v8["schema"] = 8
	v8["career"] = {"gp_1": 2}
	v8["settings"]["career_series"] = 0
	save._migrate(v8)
	_check(int(v8["career_open"]) == 4 and int(v8["settings"]["career_series"]) == 4 and int(v8["career"]["gp_1"]) == 2, "an older save keeps Grand Prix (and everything below), its stars and its place in the career")
	var fresh: Dictionary = save.default_profile()
	save._migrate(fresh)
	_check(int(fresh.get("career_open", 0)) == 0, "a brand-new save starts at the bottom")

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

	# --- Career: a karting race
	var ev: Dictionary = car_mod.event(0, 0)
	ev["car"] = "kart"
	ev["opponents"] = 7                     # (a short field keeps the test quick)
	ev["laps"] = 2
	ev["return_to"] = "res://scenes/career.tscn"
	save.pending_event = ev
	var race := await _race()
	var rw: Dictionary = race.last_reward
	print("    career race: P%d of %d, %d stars" % [race.player.position, race.entrants.size(), int(rw.get("stars", -1))])
	_check(race.entrants.size() == 8 and race._results_shown, "career race: 8 cars, finished")
	var karts := true
	for e in race.entrants:
		karts = karts and String(e.car.spec["id"]) == "kart"
	_check(karts and String(race.track.track_id) == "pinecrest", "karts, on a kart circuit")
	_check(int(rw.get("stars", -1)) == car_mod.stars_for_position("race", race.player.position) and save.career_stars("kart_1") == int(rw["stars"]), "stars by finishing place, saved")
	_check(not rw.has("credits") and not save.data.has("credits"), "no money paid out")
	race.queue_free()
	await process_frame

	# --- Career: eliminator (Grand Prix)
	ev = car_mod.event(4, 4)
	ev["car"] = "gp26"
	ev["opponents"] = 5
	ev["laps"] = 5
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

	# --- Career: time trial (karting)
	ev = car_mod.event(0, 1)
	ev["car"] = "kart"
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

	# --- Championship: each class its own
	champ.start(save, "kart", "kart", "", 6)
	var ks: Dictionary = champ.active(save)
	var kart_tracks := true
	for t in ks["rounds"]:
		kart_tracks = kart_tracks and load("res://scripts/track.gd").is_kart_track(String(t))
	_check(ks["drivers"].size() == 12 and (ks["points"] as Array).size() == 12 and kart_tracks and int(ks["laps"]) == 6, "karting season: 12 karts, 6 laps a round, kart circuits")
	_check(int(champ.round_event(save)["opponents"]) == 11 and int(champ.round_event(save)["series"]) == 0, "...its rounds run 12 karts in the karting series")
	ks["laps"] = 1
	save.pending_event = champ.round_event(save)
	race = await _race()
	var kfield: int = race.entrants.size()
	print("    karting round at %s: P%d of %d" % [race.track.track_id, race.player.position, kfield])
	_check(kfield == 12 and race._results_shown and race.last_reward.has("champ"), "a karting round: a race weekend on a kart circuit, 12 karts, points")
	_check(int(champ.active(save)["round"]) == 1, "...and the season moves on a round")
	race.queue_free()
	await process_frame
	champ.start(save, "gp", "gp26", "", 2, 1)
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
