class_name AIDriver
extends RefCounted
## Drives a RaceCar around a Track: pure-pursuit steering plus a
## look-ahead speed planner based on the curvature of the road ahead.

var idx := -1
var lateral_grip := 10.5     # m/s^2 the AI is willing to use in corners
var brake_decel := 10.0      # m/s^2 it plans braking with
var lane_offset := 0.0       # metres right of centerline
var target_speed := 0.0


func update(car: RaceCar, track: Track) -> void:
	var n := track.size()
	var pos := car.global_position
	idx = track.nearest_index(pos, idx)
	var v := car.forward_speed()

	# --- steering: aim at a point ahead on the line
	var look := 7.0 + absf(v) * 0.5
	var ahead := int(look / Track.SPACING)
	var ti := (idx + ahead) % n
	var tgt: Vector3 = track.points[ti] + track.rights[ti] * lane_offset
	var fwd := car.global_basis.z
	fwd.y = 0.0
	var to := tgt - pos
	to.y = 0.0
	var ang := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	# Positive angle = target to the left; steer_input + is right.
	car.steer_input = clampf(-ang / 0.3, -1.0, 1.0)

	# --- speed: slowest speed the curves ahead allow, given braking distance
	var horizon := v * v / (2.0 * brake_decel) + 30.0
	var steps := int(horizon / Track.SPACING) + 1
	var best := 90.0
	var k := 0
	while k <= steps:
		var si := (idx + k) % n
		var c := maxf(absf(track.curv[si]), 0.0001)
		var vmax := sqrt(lateral_grip / c)
		var dist := k * Track.SPACING
		var allowed := sqrt(vmax * vmax + 2.0 * brake_decel * dist)
		best = minf(best, allowed)
		k += 2
	target_speed = best

	if v < target_speed - 0.5:
		car.throttle = 1.0
		car.brake_input = 0.0
	elif v > target_speed + 1.0:
		car.throttle = 0.0
		car.brake_input = clampf((v - target_speed) / 4.0, 0.2, 1.0)
	else:
		car.throttle = 0.35
		car.brake_input = 0.0
