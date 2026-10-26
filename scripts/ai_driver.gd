class_name AIDriver
extends RefCounted
## Drives a RaceCar along the track's racing line.
##   Steering: pure pursuit on the racing line (bicycle-model geometry).
##   Speed:    the car's precomputed speed profile (Track.speed_profile),
##             scaled by skill, so braking points and corner speeds are
##             planned ahead without per-frame searching.
## lane_offset moves the car off the line, e.g. to overtake.

var idx := -1
var lane_offset := 0.0        # metres right of the racing line
var skill := 1.0              # 1.0 = the profile's full pace
var speed_cap := 999.0        # m/s, set by race logic when blocked
var target_speed := 0.0
var _profile := PackedFloat32Array()


func update(car: RaceCar, track: Track) -> void:
	var n := track.size()
	if _profile.size() != n:
		_profile = track.speed_profile(car.spec)
	var pos := car.global_position
	idx = track.track_index(pos, idx)
	var v := car.forward_speed()

	# --- steering
	var look := clampf(5.0 + absf(v) * 0.32, 6.0, 34.0)
	var ti := (idx + int(look / Track.SPACING)) % n
	var w := maxf(0.0, track.road_half - 1.1)
	var off := clampf(track.line_offset[ti] + lane_offset, -w, w)
	var tgt: Vector3 = track.points[ti] + track.rights[ti] * off
	var fwd := car.global_basis.z
	fwd.y = 0.0
	var to := tgt - pos
	to.y = 0.0
	var ld := maxf(to.length(), 1.0)
	var alpha := fwd.normalized().signed_angle_to(to / ld, Vector3.UP)   # + = target to the left
	var wheelbase: float = float(car.spec["wheel_front_z"]) - float(car.spec["wheel_rear_z"])
	var delta := atan2(2.0 * wheelbase * sin(alpha), ld)
	var max_steer := lerpf(car.spec["steer_low"], car.spec["steer_high"],
		clampf(absf(v) / float(car.spec["steer_full_speed"]), 0.0, 1.0))
	car.steer_input = clampf(-delta / max_steer, -1.0, 1.0)

	# --- speed: look slightly ahead in the profile to allow for response lag
	var ahead := idx + 3 + int(absf(v) * 0.04)
	target_speed = minf(_profile[ahead % n] * skill, speed_cap)
	var err := target_speed - v
	if err > 0.3:
		car.throttle = clampf(err / 2.0, 0.35, 1.0)
		car.brake_input = 0.0
	elif err < -0.8:
		car.throttle = 0.0
		car.brake_input = clampf(-err / 3.0, 0.15, 1.0)
	else:
		car.throttle = 0.3
		car.brake_input = 0.0
