extends SceneTree
## Party modes with friends, without the network: the start message for a
## team race (players split, bots even the teams up), for an eliminator
## (at least 3 laps, several out a lap on a big grid), a series (its tracks
## and the points carried from race to race) and a rematch (the winner
## lines up behind); and the scoring at the flag (party_result).
##   godot --headless --script res://tests/party_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var Lobby = load("res://scripts/lobby.gd")
	var players := {1: {"name": "Ann", "car": "gp26", "team": 0}, 2: {"name": "Ben", "car": "gp26", "team": 1},
		3: {"name": "Cat", "car": "gp26", "team": 2}}
	var st := {"track": "styria", "laps": 3, "grid": 20, "difficulty": "medium", "tod": "day", "pits": "on", "weather": "dry", "rules": "on", "party": "teams"}
	var info: Dictionary = Lobby.make_start(st, players)
	var counts := [0, 0]
	var human_squads := []
	for g in info["grid"]:
		counts[int(g.get("squad", 0))] += 1
		if g["kind"] == "player":
			human_squads.append(int(g["squad"]))
	_check(counts[0] == 10 and counts[1] == 10, "team race: 10 cars a team (%s)" % str(counts))
	_check(human_squads.has(0) and human_squads.has(1), "team race: the players are split between the teams (%s)" % str(human_squads))
	# Eliminator.
	st["party"] = "eliminator"
	st["laps"] = 1
	info = Lobby.make_start(st, players)
	_check(int(info["settings"]["laps"]) == 3, "eliminator: at least 3 laps (%d)" % int(info["settings"]["laps"]))
	_check(int(info["settings"]["elim_per_lap"]) == 9, "eliminator: 9 out a lap on a 20-car grid over 3 laps (%d)" % int(info["settings"]["elim_per_lap"]))
	# A rematch: the given order lines the players up (winner, Cat, at the back).
	st["party"] = "race"
	info = Lobby.make_start(st, players, [2, 1, 3])
	var line: Array = []
	for g in info["grid"]:
		if g["kind"] == "player":
			line.append(int(g["id"]))
	_check(line == [2, 1, 3], "rematch: the players line up in the order given (%s)" % str(line))
	# Scoring at the flag: a race with the team settings.
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var net: Node = root.get_node("Net")
	st["party"] = "teams"
	st["laps"] = 2
	st["grid"] = 6
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	# (No network: build the race as a single player, then pretend.)
	save.data["settings"]["opponents"] = 5
	root.add_child(race)
	await physics_frame
	race.party = "teams"
	var k := 0
	for e in race.entrants:
		e.squad = k % 2
		e.position = k + 1
		k += 1
	race.player.squad = 0
	var pr: Dictionary = race.party_result()
	# Squad 0 in places 1, 3, 5 (25+15+10), squad 1 in 2, 4, 6 (18+12+8).
	_check(pr["points"] == [50, 38] and int(pr["winner"]) == 0, "team race: points for the top 10 add up per team (%s)" % str(pr["points"]))
	# Series: points carried over, a table with what each scored.
	race.party = "series3"
	race._net_cfg = {"series": {"round": 1, "rounds": 3, "tracks": ["styria", "brianza", "isebay"], "points": {"7": 30, "8": 18}}}
	k = 0
	for e in race.entrants:
		e.net_id = 0
		k += 1
	race.entrants[0].net_id = 7
	race.entrants[0].name = "Ann"
	race.entrants[0].position = 2
	race.entrants[1].net_id = 8
	race.entrants[1].name = "Ben"
	race.entrants[1].position = 1
	for i in range(2, race.entrants.size()):
		race.entrants[i].position = i + 1
	race.player.net_id = 7
	pr = race.party_result()
	var table: Array = pr["table"]
	_check(table.size() == 2 and int(table[0][1]) == 48 and int(table[1][1]) == 43, "series: points carry from race to race (%s)" % str(table))
	_check(not pr["final"] and String(pr["next_track"]) == "isebay", "series: race 2 of 3, Ise Bay next")
	race.queue_free()
	await process_frame
	# (Leave a clean profile behind: the next test in the same run reads it.)
	var sv: Node = root.get_node("Save")
	sv.data = sv.default_profile()
	sv.save()
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
