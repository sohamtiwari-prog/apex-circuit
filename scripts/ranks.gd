class_name Ranks
extends RefCounted
## Driver ranking: rank points (RP) from every race finish, climbing from
## Rookie through Bronze, Silver, Gold, Platinum, Diamond and Champion to
## Legend. Points only ever go up. Past Legend, every 1000 RP earns a star.

const TIERS := [
	# [name, min RP, colour]
	["Rookie", 0, Color(0.62, 0.65, 0.7)],
	["Bronze III", 100, Color(0.80, 0.50, 0.24)],
	["Bronze II", 220, Color(0.80, 0.50, 0.24)],
	["Bronze I", 360, Color(0.80, 0.50, 0.24)],
	["Silver III", 520, Color(0.78, 0.82, 0.88)],
	["Silver II", 700, Color(0.78, 0.82, 0.88)],
	["Silver I", 900, Color(0.78, 0.82, 0.88)],
	["Gold III", 1150, Color(1.0, 0.78, 0.2)],
	["Gold II", 1420, Color(1.0, 0.78, 0.2)],
	["Gold I", 1720, Color(1.0, 0.78, 0.2)],
	["Platinum III", 2050, Color(0.35, 0.86, 0.8)],
	["Platinum II", 2420, Color(0.35, 0.86, 0.8)],
	["Platinum I", 2830, Color(0.35, 0.86, 0.8)],
	["Diamond III", 3300, Color(0.55, 0.75, 1.0)],
	["Diamond II", 3800, Color(0.55, 0.75, 1.0)],
	["Diamond I", 4350, Color(0.55, 0.75, 1.0)],
	["Champion", 5000, Color(0.85, 0.35, 1.0)],
	["Legend", 6000, Color(1.0, 0.42, 0.1)],
]
const LEGEND_STAR := 1000

const DIFFICULTY := {"easy": 0.6, "medium": 1.0, "hard": 1.4}
const LAPS := {1: 0.5, 3: 1.0, 5: 1.3, 10: 1.8}


## Index into TIERS for a points total.
static func tier_index(rp: int) -> int:
	var k := 0
	for i in TIERS.size():
		if rp >= int(TIERS[i][1]):
			k = i
	return k


static func tier_name(rp: int) -> String:
	var k := tier_index(rp)
	var n: String = TIERS[k][0]
	if k == TIERS.size() - 1:
		var stars := stars_of(rp)
		if stars > 0:
			n += ", %d star%s" % [stars, "" if stars == 1 else "s"]
	return n


static func tier_color(rp: int) -> Color:
	return TIERS[tier_index(rp)][2]


## Legend stars: one per LEGEND_STAR points past Legend.
static func stars_of(rp: int) -> int:
	var legend: int = TIERS[TIERS.size() - 1][1]
	return maxi(0, (rp - legend) / LEGEND_STAR)


## [points into this step, points the step needs] towards the next tier (or
## the next Legend star).
static func progress(rp: int) -> Vector2i:
	var k := tier_index(rp)
	var lo: int = TIERS[k][1]
	var hi: int
	if k < TIERS.size() - 1:
		hi = TIERS[k + 1][1]
	else:
		lo += stars_of(rp) * LEGEND_STAR
		hi = lo + LEGEND_STAR
	return Vector2i(rp - lo, hi - lo)


## What the next step is called ("Silver III", or "Legend ★2").
static func next_name(rp: int) -> String:
	var k := tier_index(rp)
	if k < TIERS.size() - 1:
		return TIERS[k + 1][0]
	return tier_name(rp + LEGEND_STAR - progress(rp).x)


## Points for one race finish, with the breakdown shown on the results
## screen: {"total": int, "lines": [[text, value_text], ...]}.
static func race_points(pos: int, field: int, difficulty: String, laps: int,
		fastest_lap: bool, with_friends: bool) -> Dictionary:
	var lines: Array = []
	var f := 1.0 if field <= 1 else float(field - pos) / float(field - 1)
	var base := 6.0 + 54.0 * pow(f, 1.6)
	lines.append(["Finished P%d of %d" % [pos, field], "+%d" % int(round(base))])
	var bonus := 0.0
	if pos == 1:
		bonus = 15.0
	elif pos == 2:
		bonus = 8.0
	elif pos == 3:
		bonus = 4.0
	if bonus > 0.0:
		lines.append(["Win bonus" if pos == 1 else "Podium bonus", "+%d" % int(bonus)])
	if fastest_lap:
		bonus += 5.0
		lines.append(["Fastest lap", "+5"])
	var mult := 1.0
	var dm: float = DIFFICULTY.get(difficulty, 1.0)
	if dm != 1.0:
		lines.append(["%s bots" % difficulty.capitalize(), "×%.1f" % dm])
	mult *= dm
	var lm: float = LAPS.get(laps, clampf(0.5 + laps * 0.15, 0.5, 2.0))
	if lm != 1.0:
		lines.append(["%d lap%s" % [laps, "" if laps == 1 else "s"], "×%.1f" % lm])
	mult *= lm
	var fm := 1.0 if field >= 20 else (0.85 if field >= 12 else 0.65)
	if fm != 1.0:
		lines.append(["%d-car grid" % field, "×%.2f" % fm])
	mult *= fm
	if with_friends:
		lines.append(["Racing friends", "×1.2"])
		mult *= 1.2
	var total := maxi(1, int(round((base + bonus) * mult)))
	return {"total": total, "lines": lines}
