class_name RaceCamera
extends Camera3D
## Chase cameras plus the car's own onboard cameras (cockpit, T-cam, etc.
## from its spec).

var target: RaceCar
var mode := 0
var _modes: Array = []          # [{name, pos?, pitch?, cockpit?}]
var _dir := Vector3.ZERO


func _ready() -> void:
	near = 0.05
	far = 2400.0
	fov = 70.0
	# Run after the car each physics tick.
	process_physics_priority = 10


func set_target(car: RaceCar) -> void:
	target = car
	_modes = [{"name": "Chase", "chase": 1.0}, {"name": "Far chase", "chase": 1.45}]
	for c in car.spec["cams"]:
		_modes.append(c)


func set_mode(m: int) -> void:
	mode = posmod(m, maxi(_modes.size(), 1))
	_dir = Vector3.ZERO
	_update_cockpit()


func cycle() -> int:
	set_mode(mode + 1)
	return mode


func mode_name() -> String:
	return _modes[mode]["name"]


func snap() -> void:
	_dir = Vector3.ZERO


func _update_cockpit() -> void:
	if target == null:
		return
	for child in target.get_children():
		if child is CarBody:
			(child as CarBody).set_cockpit_view(bool(_modes[mode].get("cockpit", false)))


func _physics_process(delta: float) -> void:
	if target == null or _modes.is_empty():
		return
	var t := target.global_transform
	var fwd := t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var spd := absf(target.forward_speed())
	var m: Dictionary = _modes[mode]
	var base_fov := 72.0 if m.has("chase") else 78.0
	fov = lerpf(fov, base_fov + clampf(spd * 0.15, 0.0, 12.0), 1.0 - exp(-3.0 * delta))

	if m.has("chase"):
		# Smooth only the viewing direction, never the distance, so the
		# camera doesn't lag behind at speed.
		if _dir == Vector3.ZERO:
			_dir = fwd
		_dir = _dir.lerp(fwd, 1.0 - exp(-6.0 * delta)).normalized()
		var k: float = m["chase"]
		var dist: float = float(target.spec["chase_dist"]) * k
		var height: float = float(target.spec["chase_height"]) * k
		global_position = t.origin - _dir * dist + Vector3.UP * height + _shake(spd, delta)
		look_at(t.origin + _dir * 4.0 + Vector3.UP * 0.6, Vector3.UP)
	else:
		var pitch := deg_to_rad(float(m.get("pitch", 0.0)))
		var local_basis := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, pitch)
		global_transform = t * Transform3D(local_basis, m["pos"])
		global_position += _shake(spd, delta) * 0.5


var _shake_t := 0.0

## Road vibration: a little at high speed, more over kerbs, grass and gravel.
func _shake(spd: float, delta: float) -> Vector3:
	_shake_t += delta
	var amp := clampf((spd - 50.0) * 0.0006, 0.0, 0.018)
	if target.wheels_on_grass > 0:
		amp += 0.03 * clampf(spd / 30.0, 0.0, 1.0)
	if amp <= 0.0:
		return Vector3.ZERO
	return Vector3(sin(_shake_t * 61.0) * 0.6, sin(_shake_t * 83.0 + 1.3), sin(_shake_t * 47.0 + 0.4) * 0.4) * amp
