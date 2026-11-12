class_name Championship
extends RefCounted
## Championship seasons: the same 20 drivers over several rounds, points
## for the top ten (25-18-15-12-10-8-6-4-2-1, +1 for the fastest lap in the
## top ten), driver and team standings, and a
## trophy at the end. Every round is a race weekend:
## qualifying sets the grid, then the race (tyres, pit stops, weather).
##
## The season lives in save.data["championship"] so it survives restarts.

const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
## One per career series (the same ids), each in its own class of car on
## its own calendar; `field` cars, `laps` a round, AI `skill` around.
const CLASSES := [
	{"id": "kart", "name": "Karting Championship", "cars": ["kart"], "field": 12, "laps": 6, "skill": 0.88,
		"rounds": ["pinecrest", "redrock", "harbourline", "redrock", "pinecrest", "harbourline"]},
	{"id": "f4", "name": "F4 Championship", "cars": ["f4"], "field": 16, "laps": 4, "skill": 0.9,
		"rounds": ["kestrel_park", "styria", "pannonia", "silvermoor", "duinen", "brianza"]},
	{"id": "f3", "name": "F3 Championship", "cars": ["f3"], "field": 20, "laps": 3, "skill": 0.92,
		"rounds": ["desert", "silvermoor", "styria", "pannonia", "ardennes", "brianza"]},
	{"id": "f2", "name": "F2 Championship", "cars": ["f2"], "field": 20, "laps": 3, "skill": 0.94,
		"rounds": ["desert", "jiading", "riviera", "lakeside", "marina", "gulf"]},
	{"id": "gp", "name": "Grand Prix World Championship", "cars": ["gp26"], "field": 20, "laps": 3, "skill": 0.95,
		"rounds": ["lakeside", "jiading", "isebay", "desert", "red_sea", "riviera", "ile_royale", "styria", "silvermoor", "ardennes", "pannonia", "duinen", "brianza", "caspian", "marina", "lone_star", "entrelagos", "gulf"]},
]


static func class_info(id: String) -> Dictionary:
	for c in CLASSES:
		if c["id"] == id:
			return c
	return CLASSES[CLASSES.size() - 1]


## The classes you can race a season in: those whose career series you've
## reached.
static func open_classes(save: Node) -> Array:
	var out := []
	for c in CLASSES:
		var si := Career.series_index(String(c["id"]))
		if si < 0 or Career.is_open(save, si):
			out.append(c)
	return out


static func active(save: Node) -> Dictionary:
	var s: Dictionary = save.data.get("championship", {})
	return s if s.has("rounds") else {}


## One line for the home screen.
static func summary(save: Node) -> String:
	var s := active(save)
	if s.is_empty():
		var n: int = (save.data.get("trophies", []) as Array).size()
		return "Start a season" + (", %d trophies" % n if n > 0 else "")
	if bool(s.get("done", false)):
		return "Season over: see the final standings"
	var me := standing_of(s, 0)
	return "Round %d of %d, you're P%d" % [int(s["round"]) + 1, (s["rounds"] as Array).size(), me]


## Starts a new season (replacing any season in progress).
static func start(save: Node, class_id: String, car_id: String, career_event := "", rounds := 6, laps := -1) -> void:
	var info := class_info(class_id)
	var tracks: Array = (info["rounds"] as Array).slice(0, rounds)
	if laps <= 0:
		laps = int(info.get("laps", 3))
	var field := int(info.get("field", 20))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system())
	var base := float(info.get("skill", 0.95))
	var drivers: Array = [{"name": "You", "team": int(save.get_setting("team")), "skill": 0.0, "car": car_id}]
	var names: Array = (load("res://scripts/race.gd").DRIVER_NAMES as Array).duplicate()
	names.shuffle()
	var models: Array = info["cars"]
	for i in field - 1:
		var team := 0
		if CarSpecs.has_teams(car_id):
			# Two per team; the player's team-mate first.
			var player_team := int(save.get_setting("team"))
			var order: Array = [player_team]
			for t in CarSpecs.teams_for(car_id).size():
				if t != player_team:
					order.append(t)
					order.append(t)
			team = order[i % order.size()]
		else:
			team = i + 1
		drivers.append({"name": String(names[i % names.size()]), "team": team,
			"skill": clampf(base + rng.randf_range(-0.03, 0.025), 0.82, 0.995),
			"car": String(models[i % models.size()]) if models.size() > 1 else String(models[0])})
	var points: Array = []
	points.resize(field)
	points.fill(0)
	save.data["championship"] = {
		"class": class_id, "name": info["name"], "car": car_id, "rounds": tracks, "laps": laps,
		"round": 0, "drivers": drivers, "points": points, "results": [], "fastest": [],
		"career_event": career_event, "done": false,
	}
	save.save()


## The event dict the race scene runs for the next round.
static func round_event(save: Node) -> Dictionary:
	var s := active(save)
	var r := int(s["round"])
	var info := class_info(String(s["class"]))
	return {
		"id": "", "type": "champ_round", "series": maxi(Career.series_index(String(s["class"])), 0), "series_name": String(s["name"]),
		"track": String(s["rounds"][r]), "laps": int(s["laps"]), "opponents": (s["drivers"] as Array).size() - 1,
		"skill": 0.93, "cars": info["cars"], "car": String(s["car"]),
		"drivers": s["drivers"], "round": r, "rounds": (s["rounds"] as Array).size(),
		"qualifying": true, "weekend": true,
		"return_to": "res://scenes/championship.tscn",
	}


## Records a round: `order` is driver indices in finishing order, `fastest`
## the index of the driver with the fastest lap.
static func record_round(save: Node, order: Array, fastest: int) -> Dictionary:
	var s := active(save)
	var before := standings(s)
	var pts: Array = s["points"]
	for p in order.size():
		if p < POINTS.size():
			pts[int(order[p])] = int(pts[int(order[p])]) + POINTS[p]
	if fastest >= 0 and order.find(fastest) >= 0 and order.find(fastest) < 10:
		pts[fastest] = int(pts[fastest]) + 1
	(s["results"] as Array).append(order)
	(s["fastest"] as Array).append(fastest)
	s["round"] = int(s["round"]) + 1
	var out := {"gained": POINTS[order.find(0)] if order.find(0) < 10 and order.find(0) >= 0 else 0,
		"before": before.find(0) + 1, "after": standings(s).find(0) + 1}
	if fastest == 0 and order.find(0) < 10:
		out["gained"] = int(out["gained"]) + 1
	if int(s["round"]) >= (s["rounds"] as Array).size():
		s["done"] = true
		out["final"] = _finish(save, s)
	save.save()
	return out


## Driver indices by points (ties: better best finish).
static func standings(s: Dictionary) -> Array:
	var idx: Array = range((s["drivers"] as Array).size())
	var pts: Array = s["points"]
	var best := {}
	for i in idx:
		best[i] = 99
	for res in s["results"]:
		for p in (res as Array).size():
			best[int(res[p])] = mini(int(best[int(res[p])]), p + 1)
	idx.sort_custom(func(a, b):
		if int(pts[a]) != int(pts[b]):
			return int(pts[a]) > int(pts[b])
		return int(best[a]) < int(best[b]))
	return idx


static func standing_of(s: Dictionary, driver: int) -> int:
	return standings(s).find(driver) + 1


## Team standings (Grand Prix): [{team, points}] best first.
static func team_standings(s: Dictionary) -> Array:
	var tp := {}
	var drivers: Array = s["drivers"]
	for i in drivers.size():
		var t := int(drivers[i]["team"])
		tp[t] = int(tp.get(t, 0)) + int(s["points"][i])
	var out: Array = []
	for t in tp:
		out.append({"team": t, "points": tp[t]})
	out.sort_custom(func(a, b): return int(a["points"]) > int(b["points"]))
	return out


static func _finish(save: Node, s: Dictionary) -> Dictionary:
	var pos := standing_of(s, 0)
	var info := class_info(String(s["class"]))
	(save.data["trophies"] as Array).append({"series": String(s["name"]), "position": pos,
		"date": Time.get_date_string_from_system()})
	var stars := clampi(4 - pos, 0, 3)
	var fresh := 0
	if String(s.get("career_event", "")) != "":
		fresh = save.set_career_stars(String(s["career_event"]), stars)
	return {"position": pos, "stars": stars, "new_stars": fresh}
