class_name Career
extends RefCounted
## Career: the ladder, from karts to Grand Prix. Five series, one class of
## car each, six events of different kinds in each, every event worth up
## to 3 stars. You start in karting; 10 stars in a series promotes you to
## the next one (and everything below stays open to go back to).
##
## Event types:
##   race        a race; 3 stars for a win, 2 for second, 1 for third
##   duel        one rival, head to head; win it for 3 stars
##   overtake    start at the back; 3 stars for a win, 2 for the podium, 1 for the top 5
##   eliminator  the last car is out at the end of every lap; last one standing wins
##   time_trial  your best lap against gold / silver / bronze times
##   season      (each series' finale) a full championship season


## Each series: id, name, allowed cars, events.
## Event: [type, track, laps, opponents, AI skill]
const SERIES := [
	{"id": "kart", "name": "Karting", "cars": ["kart"],
		"blurb": "Where everyone starts: 125 cc, 30 hp, 125 km/h, inches off the ground.",
		"events": [
			["race", "pinecrest", 5, 11, 0.86],
			["time_trial", "redrock", 3, 0, 0.0],
			["duel", "harbourline", 4, 1, 0.89],
			["overtake", "pinecrest", 6, 11, 0.87],
			["eliminator", "redrock", 8, 8, 0.88],
			["season", "", 0, 11, 0.88],
		]},
	{"id": "f4", "name": "F4", "cars": ["f4"],
		"blurb": "First single-seater: 160 hp, slicks and wings, no driver aids.",
		"events": [
			["race", "kestrel_park", 4, 15, 0.88],
			["time_trial", "styria", 3, 0, 0.0],
			["duel", "pannonia", 3, 1, 0.91],
			["overtake", "kestrel_park", 5, 15, 0.89],
			["eliminator", "styria", 8, 8, 0.9],
			["season", "", 0, 15, 0.9],
		]},
	{"id": "f3", "name": "F3", "cars": ["f3"],
		"blurb": "380 hp, real downforce and DRS: the Grand Prix support races.",
		"events": [
			["race", "silvermoor", 3, 19, 0.9],
			["time_trial", "pannonia", 3, 0, 0.0],
			["duel", "styria", 3, 1, 0.93],
			["overtake", "ardennes", 3, 19, 0.91],
			["eliminator", "kestrel_park", 8, 8, 0.92],
			["season", "", 0, 19, 0.92],
		]},
	{"id": "f2", "name": "F2", "cars": ["f2"],
		"blurb": "620 hp and nearly Grand Prix pace. One step from the top.",
		"events": [
			["race", "desert", 3, 19, 0.92],
			["time_trial", "ile_royale", 3, 0, 0.0],
			["duel", "lakeside", 3, 1, 0.95],
			["overtake", "marina", 3, 19, 0.93],
			["eliminator", "styria", 8, 8, 0.94],
			["season", "", 0, 19, 0.94],
		]},
	{"id": "gp", "name": "Grand Prix", "cars": ["gp26"],
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

## Stars in a series that promote you to the next.
const PROMOTION := 10

## Each series has a rival: a named driver a little quicker than the rest
## of the field, in every race of it (the duel is against them), with a
## head-to-head record kept (save "rivals").
const RIVALS := {
	"kart": {"name": "Ollie Brandt", "skill": 0.02, "blurb": "Karting champion at twelve. Never lifts."},
	"f4": {"name": "Noa Kessler", "skill": 0.02, "blurb": "Came up through karts a year ahead of you."},
	"f3": {"name": "Rafael Okoye", "skill": 0.02, "blurb": "Academy driver with a works seat waiting."},
	"f2": {"name": "Ines Marchetti", "skill": 0.02, "blurb": "Fastest in testing. Wants the same Grand Prix seat as you."},
	"gp": {"name": "Kai Lindgren", "skill": 0.02, "blurb": "Reigning champion. The one to beat."},
}

## Rewards for career stars (total): paint colours and patterns for the
## paint shop.
const REWARDS := [
	[6, "colours", "Metallic colours: gunmetal, copper, mint and pearl"],
	[20, "carbon", "Carbon pattern: bare carbon with your colours as trim"],
	[40, "chequer", "Chequered flag pattern"],
	[70, "gold", "Champion's gold paint"],
]
const REWARD_COLOURS := {"colours": ["#3b4048", "#b0623a", "#8de0c4", "#f4efe6"], "gold": ["#d4af37"]}


## Rewards you have (by their id), from your career stars.
static func rewards_unlocked(save: Node) -> Array:
	var stars := total_stars(save)
	var out: Array = []
	for r in REWARDS:
		if stars >= int(r[0]):
			out.append(String(r[1]))
	return out


## The next reward: [stars needed, what], or [] when you have them all.
static func next_reward(save: Node) -> Array:
	var stars := total_stars(save)
	for r in REWARDS:
		if stars < int(r[0]):
			return [int(r[0]), String(r[2])]
	return []


const TYPE_NAMES := {
	"race": "Race", "duel": "Duel", "overtake": "Overtake", "eliminator": "Eliminator",
	"time_trial": "Time trial", "season": "Championship", "checkpoint": "Checkpoint run",
}
const TYPE_RULES := {
	"race": "Win for 3 stars, 2nd for 2, 3rd for 1.",
	"duel": "One rival, head to head. Beat them for 3 stars.",
	"overtake": "Start at the back. Win for 3 stars, podium for 2, top 5 for 1.",
	"eliminator": "Last place is out at the end of every lap. Last car standing wins.",
	"time_trial": "Your best lap against gold, silver and bronze times.",
	"season": "A full season: qualifying and six rounds for points.",
	"checkpoint": "Beat the clock to every gate; each gate tops it up a little less. 1 lap for a star, 1.5 for 2, 2 for 3.",
}

## Time trial: target = a flying lap at the car's limits x factor (gold is
## about what the quickest AI drivers manage).
const TT_FACTORS := [1.0, 1.04, 1.09]       # gold, silver, bronze


static func series(i: int) -> Dictionary:
	return SERIES[i]


static func series_index(id: String) -> int:
	for i in SERIES.size():
		if String(SERIES[i]["id"]) == id:
			return i
	return -1


## The highest series you've reached: promoted up the ladder by stars
## (PROMOTION in each one below), or further if your save was already
## there (save "career_open": a driver who raced Grand Prix before the
## ladder keeps it).
static func reached(save: Node) -> int:
	var top := 0
	while top < SERIES.size() - 1 and series_stars(save, top) >= PROMOTION:
		top += 1
	return clampi(maxi(top, int(save.data.get("career_open", 0))), 0, SERIES.size() - 1)


static func is_open(save: Node, si: int) -> bool:
	return si <= reached(save)


## The series a car's class is raced in (-1 for none).
static func series_for_car(car_id: String) -> int:
	for i in SERIES.size():
		if (SERIES[i]["cars"] as Array).has(car_id):
			return i
	return -1


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


## Checkpoint run: stars by how many laps you lasted.
static func stars_for_checkpoint(laps: float) -> int:
	if laps >= 2.0:
		return 3
	if laps >= 1.5:
		return 2
	return 1 if laps >= 1.0 else 0


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
