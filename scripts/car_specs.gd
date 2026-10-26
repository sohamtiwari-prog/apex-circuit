class_name CarSpecs
extends RefCounted
## Every car in the game is a spec: physics, gearing, sound, cameras and
## body design. Units are SI (kg, W, N, m). Car forward is +Z.
## Names are fictional; designs are modelled on real car types.

const CATALOG := ["gp26", "vanta_gt", "stuttgart9", "marauder", "toro_furia", "veloce"]

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

## Paint colours for road-car opponents.
const ROAD_PAINTS := [Color(0.85, 0.05, 0.05), Color(0.92, 0.92, 0.93), Color(0.05, 0.05, 0.06),
	Color(1.0, 0.75, 0.0), Color(0.1, 0.3, 0.85), Color(0.0, 0.45, 0.3), Color(0.55, 0.57, 0.6),
	Color(1.0, 0.45, 0.05), Color(0.45, 0.1, 0.55), Color(0.55, 0.85, 0.1)]


static func team(index: int) -> Dictionary:
	return TEAMS[posmod(index, TEAMS.size())]


## Returns a full spec. `team_index` picks the livery for GP cars and the
## paint for road cars (-1 keeps a road car's own colour).
static func get_spec(id: String, team_index := 0) -> Dictionary:
	var s: Dictionary
	match id:
		"vanta_gt":
			s = vanta_gt()
		"stuttgart9":
			s = stuttgart9()
		"marauder":
			s = marauder()
		"toro_furia":
			s = toro_furia()
		"veloce":
			s = veloce()
		_:
			s = gp26()
	if s["body"] == "gp":
		var t := team(team_index)
		s["livery"] = t
		s["team_name"] = t["name"]
		s["color"] = t["base"]
	elif team_index > 0:
		s["color"] = ROAD_PAINTS[posmod(team_index, ROAD_PAINTS.size())]
	_derive(s)
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
	if not s.has("ai_grip"):
		var mu: float = minf(s["grip_front"], s["grip_rear"])
		s["ai_grip"] = 8.3 * mu
		s["ai_grip_aero"] = 0.85 * mu * float(s["downforce"]) / float(s["mass"])
		s["ai_brake"] = minf(float(s["brake_base"]) * 0.85, 9.81 * mu * 0.62)
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
		"gear_count": 7, "shift_time": 0.12, "chase_dist": 6.2, "chase_height": 2.0,
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
		"cylinders": 6,
		"engine_base_hz": 250.0,
		"engine_tone": "gp",

		"cams": [
			{"name": "Cockpit", "pos": Vector3(0, 0.6, 0.3), "pitch": -2.0, "cockpit": true},
			{"name": "T-cam", "pos": Vector3(0, 0.98, -0.05), "pitch": -5.0},
			{"name": "Nose", "pos": Vector3(0, 0.3, 2.25), "pitch": -2.0},
		],
		"chase_dist": 7.0,
		"chase_height": 2.0,

		# Measured limit at full lock (tests/diag_steer.gd, tests/grip_test.gd):
		# ~2.6 g at 72 km/h -> ~5.8 g at 216 km/h; the AI plans with ~92% of it.
		"ai_grip": 17.5,
		"ai_grip_aero": 0.0095,
		"ai_brake": 15.0,
	}


# ------------------------------------------------------------ road cars
# Body "shape": "body" and "cabin" are loft stations [z, y, half_width,
# half_height, superellipse_n]; the cabin is glass with a painted roof.

## Mid-engined supercar.
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
static func stuttgart9() -> Dictionary:
	return _road_defaults({
		"id": "stuttgart9", "name": "Stuttgart 9 Turbo",
		"desc": "Rear-engined icon · 650 hp · 1640 kg · 330 km/h",
		"color": Color(0.85, 0.86, 0.88),
		"mass": 1640.0, "com": Vector3(0, -0.22, -0.12), "power": 478000.0, "max_drive_force": 12500.0,
		"drag": 0.64, "downforce": 0.9,
		"brake_base": 12.5, "brake_max": 13.5,
		"wheel_front_z": 1.25, "wheel_rear_z": -1.2, "track_front": 0.8, "track_rear": 0.82,
		"grip_front": 1.95, "grip_rear": 2.3,       # wide rear tyres tame the rear-engined balance
		"collision": [[Vector3(1.85, 0.6, 4.5), Vector3(0, -0.04, 0)], [Vector3(1.2, 0.4, 1.8), Vector3(0, 0.42, -0.2)]],
		"redline": 7200.0, "idle_rpm": 850.0, "peak_rpm": 6500.0, "top_kmh": 330.0, "first_kmh": 85.0, "gear_count": 8,
		"cylinders": 6, "engine_base_hz": 180.0, "engine_tone": "flat6",
		"shape": {
			"body": [[2.25, -0.18, 0.62, 0.12, 2.4], [1.95, -0.1, 0.84, 0.2, 2.6], [1.55, -0.04, 0.92, 0.27, 2.8],
				[1.0, -0.06, 0.9, 0.25, 3.0], [0.4, -0.08, 0.88, 0.24, 3.2], [-0.3, -0.04, 0.93, 0.28, 3.0],
				[-1.0, 0.0, 0.96, 0.3, 2.8], [-1.6, -0.02, 0.92, 0.28, 2.6], [-2.1, -0.08, 0.8, 0.22, 2.4], [-2.3, -0.12, 0.6, 0.13, 2.4]],
			"cabin": [[0.95, 0.2, 0.52, 0.02, 2.2], [0.6, 0.34, 0.6, 0.17, 2.2], [0.0, 0.42, 0.6, 0.22, 2.2],
				[-0.6, 0.33, 0.58, 0.15, 2.2], [-1.3, 0.2, 0.52, 0.06, 2.2], [-1.8, 0.14, 0.45, 0.02, 2.2]],
			"round_lights": [Vector3(0.6, 0.13, 1.83)], "tail_bar": true,
			"wing": {"z": -2.05, "y": 0.25, "span": 0.7, "chord": 0.28, "aoa": 6.0},
		},
	})


## Front-engined American muscle car.
static func marauder() -> Dictionary:
	return _road_defaults({
		"id": "marauder", "name": "Marauder V8",
		"desc": "Muscle car · 480 hp · 1750 kg · 285 km/h",
		"color": Color(0.1, 0.32, 0.85),
		"mass": 1750.0, "com": Vector3(0, -0.15, 0.25), "power": 358000.0, "max_drive_force": 10500.0,
		"drag": 0.72, "downforce": 0.35,
		"brake_base": 11.0, "brake_max": 12.0,
		"wheel_front_z": 1.55, "wheel_rear_z": -1.3, "track_front": 0.82, "track_rear": 0.83,
		"grip_front": 1.7, "grip_rear": 1.8,
		"collision": [[Vector3(1.9, 0.65, 4.8), Vector3(0, -0.02, 0)], [Vector3(1.3, 0.42, 1.9), Vector3(0, 0.46, -0.45)]],
		"redline": 7500.0, "idle_rpm": 750.0, "peak_rpm": 6500.0, "top_kmh": 285.0, "first_kmh": 80.0, "gear_count": 6,
		"cylinders": 8, "engine_base_hz": 160.0, "engine_tone": "v8",
		"shape": {
			"body": [[2.4, -0.07, 0.78, 0.19, 4.0], [2.1, -0.04, 0.9, 0.26, 4.0], [1.3, -0.02, 0.94, 0.28, 4.0],
				[0.4, -0.04, 0.93, 0.27, 4.0], [-0.6, -0.02, 0.95, 0.29, 4.0], [-1.5, 0.0, 0.94, 0.3, 4.0],
				[-2.15, -0.02, 0.9, 0.27, 4.0], [-2.4, -0.04, 0.82, 0.24, 4.0]],
			"cabin": [[0.55, 0.27, 0.6, 0.02, 2.8], [0.25, 0.42, 0.66, 0.17, 2.8], [-0.35, 0.5, 0.66, 0.22, 2.8],
				[-0.95, 0.44, 0.62, 0.17, 2.8], [-1.55, 0.3, 0.55, 0.05, 2.8], [-1.85, 0.27, 0.5, 0.02, 2.8]],
			"headlights": [Vector3(0.62, 0.06, 2.38)], "light_size": Vector3(0.24, 0.08, 0.06),
			"tail_bar": false, "tails": [Vector3(0.62, 0.06, -2.42)],
			"stripes": true,
		},
	})


## Low, angular Italian V12 hypercar.
static func toro_furia() -> Dictionary:
	return _road_defaults({
		"id": "toro_furia", "name": "Toro Furia",
		"desc": "V12 wedge hypercar · 770 hp · 1550 kg · 350 km/h",
		"color": Color(0.55, 0.85, 0.1),
		"mass": 1550.0, "power": 566000.0, "max_drive_force": 11500.0,
		"drag": 0.6, "downforce": 1.6,
		"brake_base": 13.0, "brake_max": 14.0,
		"wheel_front_z": 1.4, "wheel_rear_z": -1.33, "track_front": 0.85, "track_rear": 0.87,
		"radius_rear": 0.36, "tyre_width_rear": 0.35,
		"grip_front": 2.05, "grip_rear": 2.2,
		"collision": [[Vector3(2.0, 0.5, 4.8), Vector3(0, -0.08, 0)], [Vector3(1.2, 0.3, 2.0), Vector3(0, 0.28, -0.3)]],
		"redline": 9500.0, "idle_rpm": 1000.0, "peak_rpm": 8500.0, "top_kmh": 350.0, "first_kmh": 100.0,
		"cylinders": 12, "engine_base_hz": 260.0, "engine_tone": "v12",
		"shape": {
			"body": [[2.4, -0.24, 0.8, 0.06, 4.0], [2.05, -0.18, 0.95, 0.12, 4.0], [1.5, -0.11, 1.0, 0.2, 4.0],
				[0.8, -0.11, 1.0, 0.22, 4.0], [0.0, -0.09, 1.0, 0.24, 4.0], [-0.8, -0.05, 1.02, 0.28, 4.0],
				[-1.6, -0.01, 1.0, 0.28, 4.0], [-2.2, -0.03, 0.95, 0.24, 4.0], [-2.42, -0.05, 0.85, 0.2, 4.0]],
			"cabin": [[1.25, 0.08, 0.55, 0.02, 3.2], [0.75, 0.2, 0.62, 0.12, 3.2], [0.0, 0.28, 0.6, 0.15, 3.2],
				[-0.6, 0.24, 0.56, 0.12, 3.2], [-1.3, 0.16, 0.5, 0.06, 3.2], [-1.8, 0.14, 0.45, 0.02, 3.2]],
			"headlights": [Vector3(0.72, -0.12, 2.0)], "light_size": Vector3(0.26, 0.04, 0.16),
			"tail_bar": false, "tails": [Vector3(0.7, 0.05, -2.42)],
			"wing": {"z": -2.05, "y": 0.42, "span": 0.85, "chord": 0.34, "aoa": 14.0},
			"intakes": true,
		},
	})


## Quad-turbo W16 hypercar built for 400+ km/h.
static func veloce() -> Dictionary:
	return _road_defaults({
		"id": "veloce", "name": "Veloce Hyper",
		"desc": "W16 hypercar · 1500 hp · 1995 kg · 410 km/h",
		"color": Color(0.1, 0.25, 0.65),
		"accent": Color(0.06, 0.07, 0.1),
		"mass": 1995.0, "power": 1100000.0, "max_drive_force": 15500.0,
		"drag": 0.74, "downforce": 1.4,
		"brake_base": 13.0, "brake_max": 14.0,
		"wheel_front_z": 1.4, "wheel_rear_z": -1.32, "track_front": 0.86, "track_rear": 0.86,
		"radius_rear": 0.36, "tyre_width_rear": 0.36,
		"grip_front": 2.0, "grip_rear": 2.2,
		"collision": [[Vector3(2.04, 0.62, 4.5), Vector3(0, -0.04, 0)], [Vector3(1.24, 0.4, 1.9), Vector3(0, 0.42, -0.25)]],
		"redline": 6800.0, "idle_rpm": 800.0, "peak_rpm": 6000.0, "top_kmh": 410.0, "first_kmh": 110.0,
		"cylinders": 16, "engine_base_hz": 220.0, "engine_tone": "w16",
		"shape": {
			"body": [[2.25, -0.14, 0.72, 0.15, 2.4], [1.92, -0.06, 0.92, 0.24, 2.8], [1.3, -0.02, 1.0, 0.28, 3.0],
				[0.5, -0.06, 0.96, 0.26, 3.0], [-0.3, -0.02, 1.0, 0.3, 3.0], [-1.1, 0.02, 1.02, 0.32, 3.0],
				[-1.8, 0.0, 0.98, 0.3, 3.0], [-2.25, -0.04, 0.88, 0.25, 2.8]],
			"cabin": [[1.0, 0.24, 0.55, 0.02, 2.3], [0.6, 0.38, 0.62, 0.17, 2.3], [0.0, 0.45, 0.62, 0.21, 2.3],
				[-0.6, 0.38, 0.6, 0.17, 2.3], [-1.2, 0.26, 0.52, 0.07, 2.3], [-1.6, 0.24, 0.45, 0.02, 2.3]],
			"headlights": [Vector3(0.6, 0.02, 1.98)], "light_size": Vector3(0.22, 0.05, 0.08),
			"tail_bar": true, "two_tone": true, "grille": true,
		},
	})
