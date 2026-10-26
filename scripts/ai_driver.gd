class_name AIDriver
extends RefCounted
## Drives a RaceCar around a Track: pure-pursuit steering plus a
## look-ahead speed planner based on the curvature of the road ahead.
## Grip limits come from the car spec, including extra grip from downforce.

var idx := -1
var lane_offset := 0.0       # metres right of centerline
var target_speed := 0.0
var skill := 1.0             # scales the grip the AI dares to use


func _corner_speed(k: float, a0: float, a1: float) -> float:
	# Lateral limit with downforce: v^2 * k = a0 + a1 * v^2
	if k <= a1 + 0.00001:
		return 99.0
	return minf(sqrt(a0 / (k - a1)), 99.0)


func update(car: RaceCar, track: Track) -> void:
	var n := track.size()
	var pos := car.global_position
	idx = track.nearest_index(pos, idx)
	var v := car.forward_speed()
	var a0: float = float(car.spec["ai_grip"]) * skill
	var a1: float = float(car.spec["ai_grip_aero"]) * skill
	var brake_decel: float = car.spec["ai_brake"]

	# --- steering: aim at a point ahead on the line
	var look := 8.0 + absf(v) * 0.45
	var ahead := int(look / Track.SPACING)
	var ti := (idx + ahead) % n
	var tgt: Vector3 = track.points[ti] + track.rights[ti] * lane_offset
	var fwd := car.global_basis.z
	fwd.y = 0.0
	var to := tgt - pos
	to.y = 0.0
	var ang := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	# Positive angle = target to the left; steer_input + is right.
	car.steer_input = clampf(-ang / 0.25, -1.0, 1.0)

	# --- speed: slowest speed the curves ahead allow, given braking distance
	var horizon := v * v / (2.0 * brake_decel) + 40.0
	var steps := int(horizon / Track.SPACING) + 1
	var best := 99.0
	var k := 0
	while k <= steps:
		var si := (idx + k) % n
		var vmax := _corner_speed(absf(track.curv[si]), a0, a1)
		var dist := k * Track.SPACING
		best = minf(best, sqrt(vmax * vmax + 2.0 * brake_decel * dist))
		k += 2
	target_speed = best

	if v < target_speed - 0.5:
		car.throttle = 1.0
		car.brake_input = 0.0
	elif v > target_speed + 1.0:
		car.throttle = 0.0
		car.brake_input = clampf((v - target_speed) / 4.0, 0.2, 1.0)
	else:
		car.throttle = 0.4
		car.brake_input = 0.0
