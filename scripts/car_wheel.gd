class_name CarWheel
extends Node3D
## One wheel of a RaceCar: suspension and tyre state. The car's physics
## (car.gd) fills these in every tick; the wheel only moves its own visuals.

var use_as_steering := false      # front wheel
var wheel_radius := 0.35
var mount := Vector3.ZERO         # suspension top, car space

# Suspension
var compression := 0.0            # m, 0 = fully extended
var prev_compression := 0.0
var in_contact := false
var contact_point := Vector3.ZERO
var contact_normal := Vector3.UP
var load := 0.0                   # N, tyre normal force
var on_grass := false

# Tyre
var slip_angle := 0.0             # rad
var utilisation := 0.0            # 0..1+, share of available grip in use
var locked := false
var spin_angle := 0.0
var spin_rate := 0.0              # rad/s, visual
var steer_angle := 0.0            # rad, + = left (car space yaw)


func update_visual(delta: float) -> void:
	spin_angle = fmod(spin_angle + spin_rate * delta, TAU)
	position = mount - Vector3(0, maxf(0.0, _rest() - compression), 0)
	transform.basis = Basis(Vector3.UP, steer_angle) * Basis(Vector3.RIGHT, spin_angle)


var rest_length := 0.2
func _rest() -> float:
	return rest_length


## Skid level for effects: 0 = full grip, 1 = sliding hard.
func skid() -> float:
	return clampf((utilisation - 0.92) / 0.25, 0.0, 1.0) if in_contact else 0.0
