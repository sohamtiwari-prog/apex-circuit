class_name Career
extends RefCounted
## Career: the Grand Prix series, six events of different kinds, each worth
## up to 3 stars. (The junior single-seater series, karts, F4, F3, F2, join
## it in a later update, each in its own class of car.)
##
## Event types:
##   race        a race; 3 stars for a win, 2 for second, 1 for third
##   duel        one rival, head to head; win it for 3 stars
##   overtake    start at the back; 3 stars for a win, 2 for the podium, 1 for the top 5
##   eliminator  the last car is out at the end of every lap; last one standing wins
##   time_trial  your best lap against gold / silver / bronze times
##   season      (Grand Prix finale) a full championship season


## Each series: id, name, allowed cars, events.
## Event: [type, track, laps, opponents, AI skill]
const SERIES := [
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

## Each series has a rival: a named driver a little quicker than the rest
## of the field, in every race of it (the duel is against them), with a
## head-to-head record kept (save "rivals").
const RIVALS := {
	"gp": {"name": "Kai Lindgren", "skill": 0.02, "blurb": "Reigning champion. The one to beat."},
}

## Rewards for career stars (total): paint colours and patterns for the
## paint shop.
const REWARDS := [
	[3, "colours", "Metallic colours: gunmetal, copper, mint and pearl"],
	[6, "carbon", "Carbon pattern: bare carbon with your colours as trim"],
	[10, "gold", "Champion's gold paint"],
	[15, "chequer", "Chequered flag pattern"],
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
	"time_trial": "Time trial", "season": "World Championship", "checkpoint": "Checkpoint run",
}
const TYPE_RULES := {
	"race": "Win for 3 stars, 2nd for 2, 3rd for 1.",
	"duel": "One rival, head to head. Beat them for 3 stars.",
	"overtake": "Start at the back. Win for 3 stars, podium for 2, top 5 for 1.",
	"eliminator": "Last place is out at the end of every lap. Last car standing wins.",
	"time_trial": "Your best lap against gold, silver and bronze times.",
	"season": "A full Grand Prix season: qualifying, tyres, pit stops, points.",
	"checkpoint": "Beat the clock to every gate; each gate tops it up a little less. 1 lap for a star, 1.5 for 2, 2 for 3.",
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
