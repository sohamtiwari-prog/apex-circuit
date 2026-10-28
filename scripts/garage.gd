class_name Garage
extends RefCounted
## Car prices, upgrades and performance ratings.
##
## Upgrades are quick and cheap on purpose: five parts, three levels each,
## installed in 30 s / 1 min / 2 min (real time, even with the app closed),
## or straight away for a small fee. Each level changes the car's physics:
##   Engine  +4% power        Aero    +5% downforce, -1.5% drag
##   Brakes  +4% braking      Tyres   +2.5% grip      Weight  -2.5% mass
## The Performance Rating (PR) sums up what the car can do, so you can see
## whether it's ready for an event.

const PARTS := ["engine", "aero", "brakes", "tyres", "weight"]
const PART_NAMES := {"engine": "Engine", "aero": "Aero", "brakes": "Brakes", "tyres": "Tyres", "weight": "Weight"}
const PART_EFFECT := {
	"engine": "+4% power",
	"aero": "+5% downforce, less drag",
	"brakes": "+4% stopping power",
	"tyres": "+2.5% grip",
	"weight": "-2.5% weight",
}
const MAX_LEVEL := 3
const SECONDS := [0, 30, 60, 120]          # install time for levels 1..3

## Purchase price (credits). The Marauder is your first car.
const PRICES := {
	"marauder": 0, "stuttgart9": 18000, "vanta_gt": 30000,
	"toro_furia": 45000, "veloce": 70000, "gp26": 120000,
}
## What upgrades are priced against (the starter car isn't free to tune).
const VALUE := {
	"marauder": 12000, "stuttgart9": 18000, "vanta_gt": 30000,
	"toro_furia": 45000, "veloce": 70000, "gp26": 120000,
}
const STARTER := "marauder"
const START_CREDITS := 10000


static func price(car_id: String) -> int:
	return int(PRICES.get(car_id, 50000))


## Cost of upgrading `part` to `level` (1..3).
static func upgrade_cost(car_id: String, level: int) -> int:
	var v := float(VALUE.get(car_id, 30000))
	return int(round((300.0 + v * 0.012) * level / 50.0)) * 50


static func upgrade_seconds(level: int) -> int:
	return SECONDS[clampi(level, 0, MAX_LEVEL)]


## Fee to finish an upgrade now: a tenth of its price for the time left.
static func rush_cost(car_id: String, level: int, seconds_left: float) -> int:
	if seconds_left <= 0.0:
		return 0
	var full := float(upgrade_seconds(level))
	var c := float(upgrade_cost(car_id, level)) * 0.1 * clampf(seconds_left / full, 0.0, 1.0)
	return maxi(int(round(c / 10.0)) * 10, 10)


## Applies upgrade levels {part: level} to a raw spec (before CarSpecs
## derives gearing, tyre and AI values from it).
static func apply(s: Dictionary, levels: Dictionary) -> void:
	if levels.is_empty():
		return
	var sig := ""
	for p in PARTS:
		var l := clampi(int(levels.get(p, 0)), 0, MAX_LEVEL)
		sig += str(l)
		if l == 0:
			continue
		match p:
			"engine":
				s["power"] = float(s["power"]) * (1.0 + 0.04 * l)
				s["max_drive_force"] = float(s["max_drive_force"]) * (1.0 + 0.025 * l)
			"aero":
				s["downforce"] = float(s["downforce"]) * (1.0 + 0.05 * l)
				s["drag"] = float(s["drag"]) * (1.0 - 0.015 * l)
			"brakes":
				for k in ["brake_base", "brake_max", "brake_aero"]:
					s[k] = float(s[k]) * (1.0 + 0.04 * l)
			"tyres":
				for k in ["grip_front", "grip_rear"]:
					s[k] = float(s[k]) * (1.0 + 0.025 * l)
				if s.has("mu_front"):
					s["mu_front"] = float(s["mu_front"]) * (1.0 + 0.025 * l)
					s["mu_rear"] = float(s["mu_rear"]) * (1.0 + 0.025 * l)
			"weight":
				s["mass"] = float(s["mass"]) * (1.0 - 0.025 * l)
	if sig != "00000":
		s["variant"] = "|u" + sig
		# More power on the same gearing: let the top speed rise with it.
		if s.has("top_kmh") and not s.has("gears"):
			var e := clampi(int(levels.get("engine", 0)), 0, MAX_LEVEL)
			var a := clampi(int(levels.get("aero", 0)), 0, MAX_LEVEL)
			s["top_kmh"] = float(s["top_kmh"]) * pow((1.0 + 0.04 * e) / (1.0 - 0.015 * a), 1.0 / 3.0)


## Performance Rating, roughly 40 (Marauder) to 95 (fully upgraded GP car).
static func pr(spec: Dictionary) -> float:
	var pw := float(spec["power"]) / float(spec["mass"])
	var v := 55.6
	var grip := float(spec["mu_front"]) * (1.0 + float(spec["downforce"]) * v * v / float(spec["mass"]) / 9.81)
	var top := top_speed_kmh(spec)
	var brake := float(spec["brake_base"]) + float(spec["brake_aero"]) * v * v * 0.5
	return 20.0 + 25.0 * pw / 950.0 + 15.0 * (top - 250.0) / 160.0 + 30.0 * grip / 4.5 + 10.0 * clampf(brake / 25.0, 0.0, 1.0)


static func top_speed_kmh(spec: Dictionary) -> float:
	if spec.has("top_kmh"):
		return float(spec["top_kmh"])
	# GP car: where power meets drag (gearing is long enough).
	var p := float(spec["power"])
	var d := float(spec["drag"])
	return pow(p / d, 1.0 / 3.0) * 3.6 * 0.98


## Credits for a race: by finishing place, field size and length.
static func race_reward(base: int, position: int, field: int) -> int:
	var f := 0.0
	match position:
		1:
			f = 1.0
		2:
			f = 0.7
		3:
			f = 0.55
		_:
			f = 0.4 * clampf(1.0 - float(position - 4) / maxf(field - 3, 1), 0.1, 1.0)
	return int(round(base * f / 10.0)) * 10
