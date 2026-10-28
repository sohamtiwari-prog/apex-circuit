class_name Career
extends RefCounted
## Career: five series from club racing to Grand Prix. Each series has six
## events of different kinds; each event awards up to 3 stars. Stars unlock
## the next series; each series is raced in its own class of car.
##
## Event types:
##   race        a race; 3 stars for a win, 2 for second, 1 for third
##   duel        one rival, head to head; win it for 3 stars
##   overtake    start at the back; 3 stars for a win, 2 for the podium, 1 for the top 5
##   eliminator  the last car is out at the end of every lap; last one standing wins
##   time_trial  your best lap against gold / silver / bronze times
##   season      (Grand Prix finale) a full championship season


## Each series: id, name, allowed cars, stars needed to unlock, events.
## Event: [type, track, laps, opponents, AI skill]
const SERIES := [
	{"id": "club", "name": "Club Muscle Cup", "cars": ["marauder"], "unlock": 0,
		"blurb": "Big V8s, short races. Learn the tracks.",
		"events": [
			["race", "kestrel_park", 3, 7, 0.86],
			["time_trial", "styria", 3, 0, 0.0],
			["duel", "entrelagos", 2, 1, 0.9],
			["overtake", "silvermoor", 2, 7, 0.86],
			["eliminator", "kestrel_park", 5, 5, 0.87],
			["race", "brianza", 2, 11, 0.89],
		]},
	{"id": "sports", "name": "Sports Car Trophy", "cars": ["stuttgart9"], "unlock": 10,
		"blurb": "Rear-engined and twitchy. Smooth wins.",
		"events": [
			["race", "pannonia", 3, 9, 0.89],
			["duel", "riviera", 2, 1, 0.91],
			["time_trial", "entrelagos", 3, 0, 0.0],
			["eliminator", "styria", 5, 5, 0.9],
			["overtake", "desert", 2, 9, 0.9],
			["race", "ardennes", 2, 11, 0.91],
		]},
	{"id": "super", "name": "Supercar Series", "cars": ["vanta_gt", "toro_furia"], "unlock": 25,
		"blurb": "Mid-engined missiles on the great circuits.",
		"events": [
			["race", "silvermoor", 2, 11, 0.91],
			["time_trial", "brianza", 3, 0, 0.0],
			["overtake", "styria", 3, 11, 0.91],
			["duel", "ardennes", 2, 1, 0.93],
			["eliminator", "ile_royale", 6, 6, 0.92],
			["race", "gulf", 3, 15, 0.93],
		]},
	{"id": "hyper", "name": "Hypercar Challenge", "cars": ["veloce", "toro_furia"], "unlock": 42,
		"blurb": "Over 400 km/h. Brake early.",
		"events": [
			["race", "brianza", 2, 11, 0.92],
			["duel", "silvermoor", 2, 1, 0.94],
			["time_trial", "ardennes", 2, 0, 0.0],
			["overtake", "entrelagos", 3, 11, 0.93],
			["eliminator", "desert", 6, 6, 0.93],
			["race", "marina", 3, 15, 0.94],
		]},
	{"id": "gp", "name": "Grand Prix", "cars": ["gp26"], "unlock": 60,
		"blurb": "The top of the sport: 1000 hp and 20-car grids.",
		"events": [
			["race", "styria", 3, 19, 0.93],
			["time_trial", "silvermoor", 3, 0, 0.0],
			["duel", "pannonia", 3, 1, 0.96],
			["overtake", "brianza", 3, 19, 0.94],
			["eliminator", "styria", 8, 8, 0.95],
			["season", "", 0, 19, 0.95],
		]},
]

const TYPE_NAMES := {
	"race": "Race", "duel": "Duel", "overtake": "Overtake", "eliminator": "Eliminator",
	"time_trial": "Time trial", "season": "World Championship",
}
const TYPE_RULES := {
	"race": "Win for 3 stars, 2nd for 2, 3rd for 1.",
	"duel": "One rival, head to head. Beat them for 3 stars.",
	"overtake": "Start at the back. Win for 3 stars, podium for 2, top 5 for 1.",
	"eliminator": "Last place is out at the end of every lap. Last car standing wins.",
	"time_trial": "Your best lap against gold, silver and bronze times.",
	"season": "A full Grand Prix season: qualifying, tyres, pit stops, points.",
}

## Time trial: target = a flying lap at the car's limits x factor (gold is
## about what the quickest AI drivers manage).
const TT_FACTORS := [1.0, 1.04, 1.09]       # gold, silver, bronze


static func series(i: int) -> Dictionary:
	return SERIES[i]


static func event_id(si: int, ei: int) -> String:
	return "%s_%d" % [SERIES[si]["id"], ei + 1]


## Full description of event ei of series si.
static func event(si: int, ei: int) -> Dictionary:
	var s: Dictionary = SERIES[si]
	var e: Array = s["events"][ei]
	return {
		"id": event_id(si, ei), "series": si, "index": ei,
		"type": e[0], "track": e[1], "laps": int(e[2]), "opponents": int(e[3]),
		"skill": float(e[4]),
		"cars": s["cars"], "series_name": s["name"],
	}


static func total_stars(save: Node) -> int:
	var n := 0
	for si in SERIES.size():
		for ei in (SERIES[si]["events"] as Array).size():
			n += save.career_stars(event_id(si, ei))
	return n


static func series_stars(save: Node, si: int) -> int:
	var n := 0
	for ei in (SERIES[si]["events"] as Array).size():
		n += save.career_stars(event_id(si, ei))
	return n


static func unlocked(save: Node, si: int) -> bool:
	return total_stars(save) >= int(SERIES[si]["unlock"])


## Stars for a finishing position in a race-type event.
static func stars_for_position(type: String, position: int) -> int:
	match type:
		"duel":
			return 3 if position == 1 else 0
		"overtake":
			if position == 1:
				return 3
			if position <= 3:
				return 2
			return 1 if position <= 5 else 0
		_:
			return clampi(4 - position, 0, 3)


static func stars_for_lap(best: float, targets: Array) -> int:
	if best <= 0.0:
		return 0
	for k in 3:
		if best <= float(targets[k]):
			return 3 - k
	return 0


## Gold / silver / bronze lap times for a car on a track (s).
static func lap_targets(track: Track, spec: Dictionary) -> Array:
	var t := track.lap_estimate(spec)
	var out := []
	for f in TT_FACTORS:
		out.append(snappedf(t * f, 0.1))
	return out
