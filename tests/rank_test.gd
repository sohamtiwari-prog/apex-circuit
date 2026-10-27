extends SceneTree
## Driver ranking: the points table makes sense, the ladder climbs to Legend,
## and a real race awards points once, saved, and shown on the results.
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _pts(pos: int, field := 20, diff := "medium", laps := 3, fl := false, friends := false) -> int:
	return int(Ranks.race_points(pos, field, diff, laps, fl, friends)["total"])
func _run() -> void:
	await process_frame
	# Points table.
	var prev := 1000000
	var ordered := true
	for p in range(1, 21):
		var v := _pts(p)
		if v > prev or (p <= 3 and v == prev):
			ordered = false
		prev = v
	_check(ordered, "better finishes earn more (P1 %d, P2 %d, P3 %d, P10 %d, P20 %d)" % [_pts(1), _pts(2), _pts(3), _pts(10), _pts(20)])
	_check(_pts(20) >= 1, "even last place earns something")
	_check(_pts(1, 20, "hard") > _pts(1) and _pts(1) > _pts(1, 20, "easy"), "harder bots earn more")
	_check(_pts(1, 20, "medium", 10) > _pts(1, 20, "medium", 5) and _pts(1, 20, "medium", 5) > _pts(1, 20, "medium", 1), "longer races earn more")
	_check(_pts(1, 20) > _pts(1, 6), "bigger grids earn more")
	_check(_pts(4, 20, "medium", 3, true) > _pts(4) and _pts(4, 20, "medium", 3, false, true) > _pts(4), "fastest lap and racing friends add points")
	# Ladder.
	var ok_ladder := true
	for i in range(1, Ranks.TIERS.size()):
		if int(Ranks.TIERS[i][1]) <= int(Ranks.TIERS[i - 1][1]):
			ok_ladder = false
	_check(ok_ladder, "%d ranks, each needing more points" % Ranks.TIERS.size())
	_check(Ranks.tier_name(0) == "Rookie" and Ranks.tier_name(6000) == "Legend" and Ranks.tier_name(8100) == "Legend, 2 stars", "Rookie at 0, Legend at 6000, stars after")
	var races := 0
	var rp := 0
	while Ranks.tier_name(rp) != "Legend" and races < 1000:
		rp += _pts(3, 20, "medium", 3)
		races += 1
	var hard_races := 0
	rp = 0
	while not Ranks.tier_name(rp).begins_with("Legend") and hard_races < 1000:
		rp += _pts(1, 20, "hard", 5)
		hard_races += 1
	print("    Legend after %d medium 3-lap podiums (P3), or %d hard 5-lap wins" % [races, hard_races])
	_check(races > 60 and races < 250, "Legend is a long but reachable climb")
	var pr := Ranks.progress(700)
	_check(pr == Vector2i(0, 200) and Ranks.next_name(700) == "Silver I", "progress: Silver II at 700, 200 RP to Silver I")

	# A real race: 1 lap, 6 cars, AI driving the player's car.
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["track"] = "kestrel_park"; st["car"] = "gp26"; st["laps"] = 1; st["opponents"] = 5
	st["difficulty"] = "medium"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	var frames := 0
	while not race._results_shown and frames < 120 * 240:
		await physics_frame
		frames += 1
	_check(race._results_shown, "the race finishes and shows results")
	var got := int(save.data["rank_points"])
	var expect := _pts(race.player.position, race.entrants.size(), "medium", 1, false, false)
	var expect_fl := _pts(race.player.position, race.entrants.size(), "medium", 1, true, false)
	_check(got == expect or got == expect_fl, "finished P%d of %d: %d RP awarded and saved" % [race.player.position, race.entrants.size(), got])
	_check(int(save.data["ranked_races"]) == 1, "one ranked race counted")
	await process_frame
	var found := false
	for n in race.hud.results_panel.find_children("*", "Label", true, false):
		if (n as Label).text == "Rank points":
			found = true
	_check(found, "the results screen shows the rank points")
	race._show_results()
	_check(int(save.data["rank_points"]) == got, "showing results again doesn't award twice")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
