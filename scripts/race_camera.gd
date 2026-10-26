class_name RaceCamera
extends Camera3D
## Chase / far chase / hood / bumper cameras.

enum Mode { CHASE, CHASE_FAR, HOOD, BUMPER }
const MODE_NAMES := ["Chase", "Far chase", "Hood", "Bumper"]

var target: RaceCar
var mode: int = Mode.CHASE
var _dir := Vector3.ZERO


func _ready() -> void:
	near = 0.1
	far = 1800.0
	fov = 70.0
	# Run after the car each physics tick.
	process_physics_priority = 10


func cycle() -> int:
	mode = (mode + 1) % MODE_NAMES.size()
	_dir = Vector3.ZERO
	return mode


func snap() -> void:
	_dir = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var t := target.global_transform
	var fwd := t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var spd := absf(target.forward_speed())
	fov = lerpf(fov, 68.0 + clampf(spd * 0.22, 0.0, 16.0), 1.0 - exp(-3.0 * delta))

	match mode:
		Mode.CHASE, Mode.CHASE_FAR:
			# Smooth only the viewing direction, never the distance, so the
			# camera doesn't lag behind at speed.
			if _dir == Vector3.ZERO:
				_dir = fwd
			_dir = _dir.lerp(fwd, 1.0 - exp(-6.0 * delta)).normalized()
			var dist := 6.2 if mode == Mode.CHASE else 9.5
			var height := 2.0 if mode == Mode.CHASE else 3.0
			global_position = t.origin - _dir * dist + Vector3.UP * height
			look_at(t.origin + _dir * 4.0 + Vector3.UP * 0.7, Vector3.UP)
		Mode.HOOD:
			global_transform = t * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.0, 0.95))
		Mode.BUMPER:
			global_transform = t * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.12, 2.3))
