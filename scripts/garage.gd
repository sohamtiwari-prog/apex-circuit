class_name Garage
extends RefCounted
## Car prices and performance ratings. Every car is raced exactly as it
## comes: no upgrades, so what decides a race is the driving. The
## Performance Rating (PR) sums up what each car can do.

## Purchase price (credits). The Marauder is your first car.
const PRICES := {
	"marauder": 0, "stuttgart9": 18000, "vanta_gt": 30000,
	"toro_furia": 45000, "veloce": 70000, "gp26": 120000,
}
const STARTER := "marauder"
const START_CREDITS := 10000

## What the old upgrades (removed in schema 5) cost, for the refund.
static func old_upgrade_cost(car_id: String, level: int) -> int:
	var value := {"marauder": 12000, "stuttgart9": 18000, "vanta_gt": 30000,
		"toro_furia": 45000, "veloce": 70000, "gp26": 120000}
	var v := float(value.get(car_id, 30000))
	return int(round((300.0 + v * 0.012) * level / 50.0)) * 50


static func price(car_id: String) -> int:
	return int(PRICES.get(car_id, 50000))


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
