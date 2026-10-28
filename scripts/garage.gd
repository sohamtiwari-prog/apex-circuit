class_name Garage
extends RefCounted
## Performance ratings. Every car is open to drive from the start and races
## exactly as it comes (no upgrades, no money): what decides a race is the
## driving. The Performance Rating (PR) sums up what each car can do.

## The car on the home screen until you pick another.
const STARTER := "marauder"


## Performance Rating, roughly 43 (Marauder) to 90 (GP car).
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
