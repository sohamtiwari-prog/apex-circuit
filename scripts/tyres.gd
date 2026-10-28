class_name Tyres
extends RefCounted
## Tyre compounds, wear and weather grip.
##
##   Soft    +3.5% grip, about 16 km before it's worn out
##   Medium  baseline, about 30 km
##   Hard    -3% grip, about 52 km
##   Wet     the only tyre that works in the rain; slow and fragile when dry
##
## Grip fades slowly with wear (5% by 75% worn), then falls off a cliff
## (27% down when completely worn). Sliding wears tyres faster. On a wet
## track slicks lose up to 30% of their grip; wets lose almost nothing.

const COMPOUNDS := ["soft", "medium", "hard", "wet"]
const NAMES := {"soft": "Soft", "medium": "Medium", "hard": "Hard", "wet": "Wet"}
const LETTER := {"soft": "S", "medium": "M", "hard": "H", "wet": "W"}
const COLOR := {"soft": Color("ff4438"), "medium": Color("ffc93c"), "hard": Color("f1f3f6"), "wet": Color("3a8dff")}
const GRIP := {"soft": 1.035, "medium": 1.0, "hard": 0.97, "wet": 0.9}
const LIFE_M := {"soft": 16000.0, "medium": 30000.0, "hard": 52000.0, "wet": 26000.0}


## Grip multiplier for a compound at a wear level (0 new .. 1 gone) on a
## track that is `wet` (0 dry .. 1 soaked).
static func grip(compound: String, wear: float, wet: float) -> float:
	var g := float(GRIP.get(compound, 1.0))
	if compound == "wet":
		g = lerpf(0.9, 0.97, wet)
	else:
		g *= lerpf(1.0, 0.7, wet)
	var w := clampf(wear, 0.0, 1.0)
	var cliff := maxf(w - 0.75, 0.0) / 0.25
	return g * (1.0 - 0.05 * minf(w / 0.75, 1.0) - 0.22 * cliff * cliff)


## Wear added over `metres` of driving with `slip` (0..1, sliding).
static func wear(compound: String, metres: float, slip: float, wet: float) -> float:
	var life := float(LIFE_M.get(compound, 30000.0))
	if compound == "wet":
		life *= lerpf(0.33, 1.0, wet)          # wets overheat on a dry track
	return metres / life * (1.0 + 1.5 * clampf(slip, 0.0, 1.0))


## The tyre to be on for this much water.
static func best_for(wet: float, laps_left: float, lap_m: float) -> String:
	if wet > 0.45:
		return "wet"
	var dist := laps_left * lap_m
	if dist < float(LIFE_M["soft"]) * 0.85:
		return "soft"
	if dist < float(LIFE_M["medium"]) * 0.85:
		return "medium"
	return "hard"
