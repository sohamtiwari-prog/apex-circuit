class_name CarSpecs
extends RefCounted
## Every car in the game is a spec: physics, gearing, sound and body style.
## Units are SI (kg, W, N, m, rad). Car forward is +Z.

const CATALOG := ["gp26", "vanta_gt"]


static func get_spec(id: String) -> Dictionary:
	match id:
		"vanta_gt":
			return vanta_gt()
		_:
			return gp26()


static func display_name(id: String) -> String:
	return get_spec(id)["name"]


## Open-wheel Grand Prix car, modelled on a current-era F1 car:
## ~800 kg with driver, ~1000 hp hybrid V6, ~2x its weight in downforce
## at 250 km/h, 8-speed seamless gearbox.
static func gp26() -> Dictionary:
	return {
		"id": "gp26",
		"name": "Apex GP-26",
		"series": "GP1",
		"desc": "Grand Prix car. 1000 hp, 800 kg, 8-speed seamless shift.",
		"body": "gp",
		"color": Color(0.95, 0.38, 0.05),
		"accent": Color(0.06, 0.07, 0.09),

		"mass": 800.0,
		"com": Vector3(0, 0.12, -0.15),
		"power": 745000.0,
		"max_drive_force": 9600.0,    # traction-limited launch (~1.2 g)
		"drag": 0.9,
		"downforce": 3.4,
		"downforce_balance": -0.25,     # z of the aero centre of pressure
		"brake_base": 15.0,             # m/s^2 at low speed
		"brake_aero": 0.0042,           # extra m/s^2 per (m/s)^2 (carbon brakes + downforce)
		"brake_max": 48.0,
		"steer_low": 0.42,
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
		"grip_front": 3.3,
		"grip_rear": 3.5,
		"roll_influence": 0.03,
		"collision": [
			[Vector3(0.9, 0.4, 4.3), Vector3(0, 0.25, 0.0)],
			[Vector3(1.9, 0.12, 0.5), Vector3(0, 0.08, 2.55)],
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
			{"name": "Cockpit", "pos": Vector3(0, 0.66, 0.3), "pitch": -3.0, "cockpit": true},
			{"name": "T-cam", "pos": Vector3(0, 1.06, 0.0), "pitch": -5.0},
			{"name": "Nose", "pos": Vector3(0, 0.42, 2.2), "pitch": -2.0},
		],
		"chase_dist": 7.0,
		"chase_height": 2.0,

		"ai_grip": 13.0,
		"ai_grip_aero": 0.0026,
		"ai_brake": 22.0,
	}


## Mid-engined GT road car.
static func vanta_gt() -> Dictionary:
	return {
		"id": "vanta_gt",
		"name": "Apex Vanta GT",
		"series": "GT",
		"desc": "Mid-engined coupe. 560 hp, 1250 kg, 7-speed dual-clutch.",
		"body": "gt",
		"color": Color(1.0, 0.42, 0.1),
		"accent": Color(0.05, 0.05, 0.06),

		"mass": 1250.0,
		"com": Vector3(0, -0.22, 0.05),
		"power": 420000.0,
		"max_drive_force": 9000.0,
		"drag": 0.58,
		"downforce": 1.1,
		"downforce_balance": -0.1,
		"brake_base": 12.0,
		"brake_aero": 0.0,
		"brake_max": 13.0,
		"steer_low": 0.55,
		"steer_high": 0.085,
		"steer_full_speed": 56.0,
		"steer_rate": 2.4,

		"wheel_front_z": 1.33,
		"wheel_rear_z": -1.28,
		"track_front": 0.82,
		"track_rear": 0.84,
		"wheel_y": 0.1,
		"radius_front": 0.34,
		"radius_rear": 0.34,
		"tyre_width_front": 0.26,
		"tyre_width_rear": 0.3,
		"rest_length": 0.25,
		"travel": 0.2,
		"stiffness": 45.0,
		"damp_comp": 2.6,
		"damp_relax": 3.6,
		"max_susp_force": 30000.0,
		"grip_front": 2.9,
		"grip_rear": 3.1,
		"roll_influence": 0.06,
		"collision": [
			[Vector3(1.86, 0.62, 4.36), Vector3(0, 0.02, 0)],
			[Vector3(1.4, 0.42, 1.9), Vector3(0, 0.5, -0.3)],
		],

		"gears": [12.8, 10.38, 8.42, 6.83, 5.54, 4.49, 3.65],
		"idle_rpm": 900.0,
		"redline": 8500.0,
		"upshift_rpm": 8200.0,
		"downshift_rpm": 6800.0,
		"peak_rpm": 7200.0,
		"shift_time": 0.12,
		"cylinders": 8,
		"engine_base_hz": 200.0,
		"engine_tone": "v8",

		"cams": [
			{"name": "Hood", "pos": Vector3(0, 1.0, 0.95), "pitch": -3.0},
			{"name": "Bumper", "pos": Vector3(0, 0.12, 2.3), "pitch": 0.0},
		],
		"chase_dist": 6.2,
		"chase_height": 2.0,

		"ai_grip": 10.5,
		"ai_grip_aero": 0.0004,
		"ai_brake": 10.0,
	}
