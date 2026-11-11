class_name CarSpecs
extends RefCounted
## Every car in the game is a spec: physics, gearing, sound, cameras and
## body design. Units are SI (kg, W, N, m). Car forward is +Z.
## Names are fictional; designs are modelled on real car types.
##
## For now the game is Grand Prix only: one car you can drive, the GP car,
## in ten teams' liveries. (The junior single-seaters, F2, F3, F4 and
## karts, come in a later update as series of their own.) The safety car
## (scripts/safety_car.gd) is the one other car, a road car.

const CATALOG := ["gp26"]
const SAFETY_CAR := "vanta_gt"

## Grand Prix teams (fictional) and their liveries: base, accent, stripe, helmet.
const TEAMS := [
	{"id": "apex", "name": "Apex Racing", "base": Color(1.0, 0.45, 0.05), "accent": Color(0.08, 0.1, 0.14), "stripe": Color(0.15, 0.6, 1.0), "helmet": Color(1.0, 0.85, 0.1)},
	{"id": "rosso", "name": "Rosso Corsa GP", "base": Color(0.86, 0.05, 0.05), "accent": Color(0.95, 0.95, 0.95), "stripe": Color(1.0, 0.85, 0.0), "helmet": Color(0.95, 0.1, 0.1)},
	{"id": "argento", "name": "Argento Motorsport", "base": Color(0.75, 0.77, 0.8), "accent": Color(0.05, 0.06, 0.07), "stripe": Color(0.0, 0.8, 0.7), "helmet": Color(0.92, 0.92, 0.95)},
	{"id": "navy", "name": "Navy Storm Racing", "base": Color(0.07, 0.1, 0.3), "accent": Color(0.9, 0.12, 0.15), "stripe": Color(1.0, 0.8, 0.0), "helmet": Color(0.1, 0.25, 0.8)},
	{"id": "emerald", "name": "Emerald Racing", "base": Color(0.0, 0.33, 0.25), "accent": Color(0.75, 1.0, 0.2), "stripe": Color(0.9, 0.9, 0.9), "helmet": Color(0.1, 0.5, 0.3)},
	{"id": "bleu", "name": "Bleu Alpin", "base": Color(0.05, 0.3, 0.75), "accent": Color(1.0, 0.4, 0.75), "stripe": Color(0.95, 0.95, 0.95), "helmet": Color(0.2, 0.45, 0.95)},
	{"id": "eagle", "name": "Steel Eagle Racing", "base": Color(0.93, 0.93, 0.94), "accent": Color(0.08, 0.08, 0.09), "stripe": Color(0.85, 0.05, 0.1), "helmet": Color(0.15, 0.15, 0.17)},
	{"id": "atlas", "name": "Atlas Racing", "base": Color(0.05, 0.2, 0.55), "accent": Color(0.95, 0.95, 0.97), "stripe": Color(0.2, 0.7, 1.0), "helmet": Color(0.95, 0.95, 0.97)},
	{"id": "nero", "name": "Nero Verde", "base": Color(0.06, 0.06, 0.07), "accent": Color(0.25, 0.95, 0.25), "stripe": Color(0.9, 0.9, 0.9), "helmet": Color(0.3, 0.95, 0.35)},
	{"id": "azur", "name": "Azur Racing", "base": Color(0.92, 0.94, 0.98), "accent": Color(0.1, 0.25, 0.75), "stripe": Color(0.9, 0.1, 0.25), "helmet": Color(0.15, 0.3, 0.85)},
]

static func team(index: int) -> Dictionary:
	return TEAMS[posmod(index, TEAMS.size())]


## Returns a full spec. `team_index` picks the GP car's team livery. Any
## id that isn't a car here (an older save's road car, a friend on an older
## version) is the GP car.
static func get_spec(id: String, team_index := 0) -> Dictionary:
	var s: Dictionary
	match id:
		SAFETY_CAR:
			s = vanta_gt()
		_:
			s = gp26()
	if s["body"] == "gp":
		var t := team(team_index)
		s["livery"] = t
		s["team_name"] = t["name"]
		s["color"] = t["base"]
	_derive(s)
	return s


## Your own paint (scripts/paint_shop.gd) over a car's spec: colours,
## pattern and race number. p: {"on", "base", "accent", "stripe", "helmet",
## "pattern", "number"} (colours as html strings, so they go through the
## save file and the network as they are).
static func apply_paint(s: Dictionary, p: Dictionary) -> Dictionary:
	if p.is_empty() or not bool(p.get("on", false)):
		return s
	var base := Color.html(String(p.get("base", "#ff7310")))
	var accent := Color.html(String(p.get("accent", "#14181f")))
	var stripe := Color.html(String(p.get("stripe", "#2699ff")))
	var helmet := Color.html(String(p.get("helmet", "#ffd919")))
	var pattern := String(p.get("pattern", "classic"))
	if pattern == "carbon":
		# Bare carbon, your colours as the trim.
		stripe = base
		accent = base.darkened(0.25)
		base = Color(0.05, 0.05, 0.06)
	if s["body"] == "gp":
		var lv: Dictionary = (s["livery"] as Dictionary).duplicate()
		lv["base"] = base
		lv["accent"] = accent
		lv["stripe"] = stripe
		lv["helmet"] = helmet
		s["livery"] = lv
		s["color"] = base
	else:
		s["color"] = base
		s["accent"] = accent
		var shape: Dictionary = (s["shape"] as Dictionary).duplicate()
		shape["stripes"] = pattern == "stripes" or pattern == "chequer" or pattern == "carbon"
		shape["two_tone"] = pattern == "split"
		s["shape"] = shape
	s["pattern"] = pattern
	s["number"] = clampi(int(p.get("number", 26)), 1, 99)
	s["paint"] = p
	return s


## Car setup (scripts/setup_screen.gd), each a step either side of the
## car's own (0): wing -5..5 (downforce and drag), gearing -3..3 (longer:
## more top speed, less pick-up), brake balance 50..70 % front, handling
## balance -3..3 (anti-roll bars: + steadier, - more rotation), tyre
## pressure -3..3 (lower: more grip, more wear).
const SETUP_RANGE := {"wing": [-5, 5], "gearing": [-3, 3], "bias": [50, 70], "balance": [-3, 3], "pressure": [-3, 3]}

static func apply_setup(s: Dictionary, st: Dictionary) -> Dictionary:
	if st.is_empty():
		return s
	var wing := clampi(int(st.get("wing", 0)), -5, 5)
	var gearing := clampi(int(st.get("gearing", 0)), -3, 3)
	var balance := clampi(int(st.get("balance", 0)), -3, 3)
	var pressure := clampi(int(st.get("pressure", 0)), -3, 3)
	s["downforce"] = float(s["downforce"]) * (1.0 + 0.05 * wing)
	s["drag"] = float(s["drag"]) * (1.0 + 0.04 * wing)
	var g: Array = []
	for r in s["gears"]:
		g.append(float(r) * (1.0 - 0.03 * gearing))
	s["gears"] = g
	if st.has("bias"):
		s["brake_bias"] = clampf(float(st["bias"]) / 100.0, 0.5, 0.7)
	s["arb_front"] = float(s["arb_front"]) * (1.0 + 0.1 * balance)
	s["arb_rear"] = float(s["arb_rear"]) * (1.0 - 0.1 * balance)
	s["mu_front"] = float(s["mu_front"]) * (1.0 - 0.012 * pressure)
	s["mu_rear"] = float(s["mu_rear"]) * (1.0 - 0.012 * pressure)
	s["wear_mul"] = 1.0 - 0.07 * pressure
	if s.has("top_kmh"):
		# (Road cars quote a top speed; with more or less wing and gearing it moves.)
		s["top_kmh"] = float(s["top_kmh"]) * pow(1.0 / (1.0 + 0.04 * wing), 1.0 / 3.0) * (1.0 + 0.02 * gearing)
	s["setup"] = st
	return s


static func display_name(id: String) -> String:
	return get_spec(id)["name"]


## Fills in values computed from the physics: gear ratios from top speed,
## and AI grip/brake limits from tyres and downforce (unless measured ones
## are given, as for the GP car).
static func _derive(s: Dictionary) -> void:
	if not s.has("gears"):
		var r: float = s["radius_rear"]
		var redline: float = s["redline"]
		var top: float = float(s["top_kmh"]) / 3.6
		var first: float = float(s["first_kmh"]) / 3.6
		var n: int = s["gear_count"]
		var r_top := redline / 60.0 * TAU * r / top
		var r_first := redline / 60.0 * TAU * r / first
		var gears: Array = []
		for g in range(n):
			gears.append(r_first * pow(r_top / r_first, float(g) / (n - 1)))
		s["gears"] = gears
	# Tyre/suspension model (car.gd). Peak friction comes from the old grip
	# figures; the rear has a little more, so every car settles into gentle
	# understeer at the limit instead of spinning.
	var gp: bool = s["body"] == "gp"
	if not s.has("mu_front"):
		var k := 0.71 if gp else 0.69
		s["mu_front"] = float(s["grip_front"]) * k
		s["mu_rear"] = maxf(float(s["grip_rear"]) * k, float(s["mu_front"]) * 1.15)
	if not s.has("slip_peak_front"):
		s["slip_peak_front"] = 5.5 if gp else 7.0
		s["slip_peak_rear"] = float(s["slip_peak_front"]) * 0.8
	if not s.has("susp_hz"):
		s["susp_hz"] = 4.0 if gp else 2.2
		s["susp_damping"] = 0.7 if gp else 0.6
		s["arb_front"] = 0.8 if gp else 0.7
		s["arb_rear"] = 0.6 if gp else 0.45
		s["brake_bias"] = 0.57 if gp else 0.62
	# The AI plans with 92% of the front tyres' grip (the limiting axle).
	var mu_f: float = s["mu_front"]
	s["ai_grip"] = 0.92 * mu_f * 9.81
	s["ai_grip_aero"] = 0.92 * mu_f * float(s["downforce"]) / float(s["mass"])
	s["ai_brake"] = 0.85 * minf(float(s["brake_base"]), 9.81 * mu_f)
	if not s.has("downshift_rpm"):
		s["upshift_rpm"] = float(s["redline"]) * 0.965
		s["downshift_rpm"] = float(s["redline"]) * 0.8


static func _road_defaults(s: Dictionary) -> Dictionary:
	var d := {
		"series": "Road", "body": "road", "accent": Color(0.05, 0.05, 0.06),
		"com": Vector3(0, -0.2, 0.0), "downforce_balance": -0.1,
		"brake_aero": 0.0, "steer_low": 0.55, "steer_high": 0.085, "steer_full_speed": 56.0, "steer_rate": 2.4,
		"wheel_y": 0.1, "rest_length": 0.25, "travel": 0.2, "stiffness": 45.0,
		"damp_comp": 2.6, "damp_relax": 3.6, "max_susp_force": 40000.0, "roll_influence": 0.06,
		"radius_front": 0.34, "radius_rear": 0.35, "tyre_width_front": 0.26, "tyre_width_rear": 0.32,
		"gear_count": 7, "shift_time": 0.12, "chase_dist": 5.8, "chase_height": 1.75, "chase_look": 7.0,
		"cams": [
			{"name": "Hood", "pos": Vector3(0, 0.62, 0.9), "pitch": -3.0},
			{"name": "Bumper", "pos": Vector3(0, -0.02, 2.25), "pitch": 0.0},
		],
	}
	for k in s:
		d[k] = s[k]
	return d


# ------------------------------------------------------------ GP car

## Open-wheel Grand Prix car, modelled on a current-era F1 car:
## ~800 kg with driver, ~1000 hp hybrid V6, ~2x its weight in downforce
## at 250 km/h, 8-speed seamless gearbox.
static func gp26() -> Dictionary:
	return {
		"id": "gp26",
		"name": "Apex GP-26",
		"series": "GP1",
		"desc": "Grand Prix car · 1000 hp · 800 kg · 340 km/h",
		"body": "gp",
		"color": Color(0.95, 0.38, 0.05),
		"accent": Color(0.06, 0.07, 0.09),

		"mass": 800.0,
		"com": Vector3(0, 0.12, -0.15),
		"power": 745000.0,
		"max_drive_force": 9600.0,      # traction-limited launch (~1.2 g)
		"drag": 0.9,
		"downforce": 3.4,
		"downforce_balance": -0.25,     # z of the aero centre of pressure
		"brake_base": 15.0,             # m/s^2 at low speed
		"brake_aero": 0.0042,           # extra m/s^2 per (m/s)^2 (carbon brakes + downforce)
		"brake_max": 48.0,
		"steer_low": 0.52,              # enough lock for the tightest street hairpins
		"steer_high": 0.07,
		"steer_full_speed": 70.0,
		"steer_rate": 2.6,

		"wheel_front_z": 1.75,
		"wheel_rear_z": -1.75,
		"track_front": 0.80,
		"track_rear": 0.78,
		"wheel_y": 0.3,
		"radius_front": 0.36,
		"radius_rear": 0.36,
		"tyre_width_front": 0.30,
		"tyre_width_rear": 0.40,
		"rest_length": 0.12,
		"travel": 0.1,
		"stiffness": 140.0,
		"damp_comp": 5.0,
		"damp_relax": 7.0,
		"max_susp_force": 60000.0,
		"grip_front": 2.6,              # grippy, RR3-style; downforce adds more with speed
		"grip_rear": 2.8,
		"roll_influence": 0.03,
		"collision": [
			[Vector3(0.9, 0.4, 4.3), Vector3(0, 0.25, 0.0)],
			[Vector3(1.9, 0.12, 0.5), Vector3(0, 0.0, 2.55)],
			[Vector3(1.0, 0.3, 0.4), Vector3(0, 0.78, -2.3)],
		],

		"gears": [16.0, 13.46, 11.32, 9.52, 8.0, 6.73, 5.66, 4.78],
		"idle_rpm": 4000.0,
		"redline": 12000.0,
		"upshift_rpm": 11700.0,
		"downshift_rpm": 10200.0,
		"peak_rpm": 10800.0,
		"shift_time": 0.04,
		"cylinders": 12,
		"engine_base_hz": 250.0,
		"engine_tone": "v12gp",          # recorded V12 (scripts/car_audio.gd)

		"cams": [
			{"name": "Cockpit", "pos": Vector3(0, 0.6, 0.3), "pitch": -2.0, "cockpit": true},
			{"name": "T-cam", "pos": Vector3(0, 0.98, -0.05), "pitch": -5.0},
			{"name": "Nose", "pos": Vector3(0, 0.3, 2.25), "pitch": -2.0},
		],
		# Low and close behind (the TV / game chase view of a single-seater):
		# the road fills the picture and rushes under you.
		"chase_dist": 5.4,
		"chase_height": 1.5,
		"chase_look": 5.0,

	}


# ------------------------------------------------------------ the safety car
# A road car. Body "shape": "body" and "cabin" are loft stations [z, y,
# half_width, half_height, superellipse_n]; the cabin is glass with a
# painted roof.

## The safety car: a mid-engined supercar (not one you drive).
static func vanta_gt() -> Dictionary:
	return _road_defaults({
		"id": "vanta_gt", "name": "Apex Vanta GT",
		"desc": "Mid-engined supercar · 720 hp · 1420 kg · 341 km/h",
		"color": Color(1.0, 0.42, 0.1),
		"mass": 1420.0, "power": 530000.0, "max_drive_force": 10500.0,
		"drag": 0.62, "downforce": 1.4,
		"brake_base": 12.5, "brake_max": 13.5,
		"wheel_front_z": 1.33, "wheel_rear_z": -1.32, "track_front": 0.82, "track_rear": 0.84,
		"grip_front": 2.0, "grip_rear": 2.15,
		"collision": [[Vector3(1.9, 0.55, 4.45), Vector3(0, -0.05, 0)], [Vector3(1.25, 0.35, 1.9), Vector3(0, 0.38, -0.25)]],
		"redline": 8500.0, "idle_rpm": 900.0, "peak_rpm": 7300.0, "top_kmh": 341.0, "first_kmh": 95.0,
		"cylinders": 8, "engine_base_hz": 200.0, "engine_tone": "v8flat",
		"shape": {
			"body": [[2.25, -0.2, 0.74, 0.1, 2.5], [2.0, -0.14, 0.88, 0.17, 3.0], [1.6, -0.08, 0.95, 0.23, 3.4],
				[1.2, -0.07, 0.96, 0.25, 3.4], [0.6, -0.09, 0.93, 0.24, 3.4], [0.0, -0.07, 0.95, 0.27, 3.4],
				[-0.7, -0.03, 0.98, 0.3, 3.4], [-1.4, -0.01, 0.97, 0.3, 3.4], [-1.9, -0.03, 0.9, 0.27, 3.2], [-2.22, -0.05, 0.78, 0.21, 3.0]],
			"cabin": [[1.05, 0.17, 0.52, 0.02, 2.4], [0.65, 0.3, 0.6, 0.15, 2.4], [0.1, 0.36, 0.6, 0.19, 2.4],
				[-0.5, 0.34, 0.58, 0.17, 2.4], [-1.1, 0.24, 0.52, 0.09, 2.4], [-1.5, 0.16, 0.48, 0.02, 2.4]],
			"headlights": [Vector3(0.62, -0.03, 2.02)], "light_size": Vector3(0.2, 0.05, 0.1),
			"tail_bar": true, "wing": {"z": -2.0, "y": 0.33, "span": 0.78, "chord": 0.3, "aoa": 10.0},
			"intakes": true,
		},
	})


## Rear-engined sports car with the classic round-headlight silhouette.
