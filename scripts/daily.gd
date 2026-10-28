class_name Daily
extends RefCounted
## The daily challenge: one event a day, the same for everyone (picked from
## the date), in a car lent to you for the day, with a twist (night, rain,
## a short sprint, a rival). Up to 3 stars.

const TWISTS := [
	["race", "Sprint race", {}],
	["race", "Night race", {"tod": "night"}],
	["race", "Wet race", {"weather": "wet"}],
	["overtake", "Charge from the back", {}],
	["duel", "Duel", {}],
	["time_trial", "Hot lap", {}],
	["race", "Rain on the way", {"weather": "changing"}],
	["time_trial", "Hot lap at sunset", {"tod": "sunset"}],
]


static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d%02d%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Today's event (or another day's, for tests).
static func event(day := "") -> Dictionary:
	if day == "":
		day = today()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("apex-daily-" + day)
	var tracks: Array = []
	for t in Track.CATALOG:
		tracks.append(String(t["id"]))
	var track: String = tracks[rng.randi() % tracks.size()]
	var car: String = CarSpecs.CATALOG[rng.randi() % CarSpecs.CATALOG.size()]
	var tw: Array = TWISTS[rng.randi() % TWISTS.size()]
	var type: String = tw[0]
	var laps := 2 if type != "time_trial" else 3
	var opponents := 11
	match type:
		"duel":
			opponents = 1
		"overtake":
			opponents = 9
		"time_trial":
			opponents = 0
	var ev := {
		"id": "daily_" + day, "type": type, "track": track, "laps": laps, "opponents": opponents,
		"skill": 0.93, "cars": [car], "car": car, "series": 2,
		"series_name": "Daily challenge", "title": String(tw[1]),
		"return_to": "res://scenes/hub.tscn",
	}
	var extra: Dictionary = tw[2]
	for k in extra:
		ev[k] = extra[k]
	return ev


## "Night race · Marina Lights in the Toro Furia"
static func describe(ev: Dictionary) -> String:
	var tname := String(Track.catalog_entry(String(ev["track"]))["name"]).trim_suffix(" International Circuit").trim_suffix(" Street Circuit").trim_suffix(" Circuit")
	return "%s at %s in the %s" % [String(ev["title"]), tname, CarSpecs.display_name(String(ev["car"]))]
