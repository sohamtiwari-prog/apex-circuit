class_name RaceCamera
extends Camera3D
## Chase cameras plus the car's own onboard cameras (cockpit, T-cam, etc.
## from its spec).

var target: RaceCar
var mode := 0
var _modes: Array = []          # [{name, pos?, pitch?, cockpit?}]
var _dir := Vector3.ZERO
var _up := Vector3.ZERO           # onboard cameras: smoothed chassis up
var _sy := 0.0                    # onboard cameras: smoothed height
var _prev_spd := 0.0
var _accel := 0.0                 # smoothed forward acceleration (m/s²)
var _lag := 0.0                   # chase: how far the car has pulled away / closed in (m)
var _blur: MeshInstance3D         # speed blur over the picture
var _blur_mat: ShaderMaterial
var speed_fx := true              # speed blur (graphics: off in battery saver)
var warm_blur := 0                 # frames to draw the blur (with nothing to blur) so its shader is ready


func _ready() -> void:
	near = 0.1          # (0.05 cost depth precision: distant surfaces flickered on phones)
	far = 2400.0
	fov = 70.0
	# Cars passing (or being passed) change pitch, like they do trackside.
	doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	# Run after the car each physics tick.
	process_physics_priority = 10
	# Speed blur: a quad over the whole picture (shaders/speed_blur.gdshader).
	_blur = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_blur.mesh = q
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = load("res://shaders/speed_blur.gdshader")
	_blur_mat.render_priority = 100
	_blur.material_override = _blur_mat
	_blur.extra_cull_margin = 16384.0
	_blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blur.visible = false
	add_child(_blur)
	_blur.position = Vector3(0, 0, -1)


func set_target(car: RaceCar) -> void:
	target = car
	_modes = [{"name": "Chase", "chase": 1.0}, {"name": "Far chase", "chase": 1.45}]
	for c in car.spec["cams"]:
		_modes.append(c)


## The speed blur off while something else is on screen (the replay).
var _blur_on := true

func set_blur_enabled(on: bool) -> void:
	_blur_on = on
	if not on:
		_blur.visible = false


func set_mode(m: int) -> void:
	mode = posmod(m, maxi(_modes.size(), 1))
	_dir = Vector3.ZERO
	_up = Vector3.ZERO
	_update_cockpit()


func cycle() -> int:
	set_mode(mode + 1)
	return mode


func mode_name() -> String:
	return _modes[mode]["name"]


func snap() -> void:
	_dir = Vector3.ZERO
	_up = Vector3.ZERO


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
	# Speed: the view widens as you go faster (most past 150 km/h), so the
	# road and the trackside rush past at the edges.
	var rush := clampf((spd - 25.0) / 65.0, 0.0, 1.0)
	rush = rush * rush * (3.0 - 2.0 * rush)
	var base_fov := 68.0 if m.has("chase") else 76.0
	var wide := 17.0 if m.has("chase") else 12.0
	fov = lerpf(fov, base_fov + wide * rush, 1.0 - exp(-2.5 * delta))
	# Forward acceleration, smoothed: the car pulls away from the camera as
	# it accelerates and the camera closes in under braking.
	if delta > 0.0:
		_accel = lerpf(_accel, (spd - _prev_spd) / delta, 1.0 - exp(-4.0 * delta))
	_prev_spd = spd
	_lag = lerpf(_lag, clampf(_accel * 0.045, -0.9, 0.75), 1.0 - exp(-3.0 * delta))
	_update_blur(spd, m.has("chase"))

	if m.has("chase"):
		# Smooth only the viewing direction, never the distance, so the
		# camera doesn't lag behind at speed.
		if _dir == Vector3.ZERO:
			_dir = fwd
		_dir = _dir.lerp(fwd, 1.0 - exp(-6.0 * delta)).normalized()
		var k: float = m["chase"]
		var dist: float = float(target.spec["chase_dist"]) * k + _lag
		# A touch lower at speed: the road closer, rushing under you.
		var height: float = float(target.spec["chase_height"]) * k * (1.0 - 0.1 * rush)
		global_position = t.origin - _dir * dist + Vector3.UP * height + _shake(spd, delta)
		look_at(t.origin + _dir * float(target.spec.get("chase_look", 4.0)) + Vector3.UP * 0.6, Vector3.UP)
	else:
		# Onboard: like a driver's head, not bolted to the chassis. Heading
		# follows the car exactly; the chassis' pitch and roll come through
		# smoothed (and at two thirds), and the suspension's bounce is
		# filtered out, so the view doesn't buzz with every ripple.
		var pitch := deg_to_rad(float(m.get("pitch", 0.0)))
		var local_basis := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, pitch)
		if _up == Vector3.ZERO:
			_up = t.basis.y
			_sy = t.origin.y
		_up = _up.lerp(t.basis.y, 1.0 - exp(-7.0 * delta)).normalized()
		var up := Vector3.UP.lerp(_up, 0.65).normalized()
		var f := t.basis.z
		f = (f - up * f.dot(up)).normalized()
		var body := Basis(up.cross(f), up, f)
		# Height: follows the road (and hills) but not the bounce.
		_sy = lerpf(_sy + target.linear_velocity.y * delta, t.origin.y, 1.0 - exp(-9.0 * delta))
		var origin := Vector3(t.origin.x, _sy, t.origin.z)
		global_transform = Transform3D(body * local_basis, origin + body * Vector3(m["pos"]))
		if target.wheels_on_grass > 0:
			global_position += _shake(spd, delta) * 0.35


var _shake_t := 0.0


## The speed blur: none below about 140 km/h, full flat out; gentler
## onboard (you're looking past the car, not at it).
func _update_blur(spd: float, chase: bool) -> void:
	var on := speed_fx and target != null and _blur_on
	var amt := clampf((spd - 38.0) / 52.0, 0.0, 1.0)
	amt = amt * amt * (1.0 if chase else 0.7)
	_blur.visible = on and amt > 0.01
	if warm_blur > 0 and speed_fx:
		warm_blur -= 1
		_blur.visible = true
		_blur_mat.set_shader_parameter("amount", 0.0)
		return
	if not _blur.visible:
		return
	_blur_mat.set_shader_parameter("amount", amt)
	var vsize := get_viewport().get_visible_rect().size
	if chase:
		# Your car stays sharp: the box it covers on screen.
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var b := target.global_basis
		for sx in [-1.15, 1.15]:
			for sy in [-0.1, 1.15]:
				for sz in [-2.8, 2.8]:
					var p: Vector3 = target.global_position + b.x * sx + b.y * sy + b.z * sz
					if is_position_behind(p):
						continue
					var s := unproject_position(p) / vsize
					lo = lo.min(s)
					hi = hi.max(s)
		if hi.x > lo.x:
			_blur_mat.set_shader_parameter("car_c", (lo + hi) * 0.5)
			_blur_mat.set_shader_parameter("car_r", (hi - lo) * 0.62)
		_blur_mat.set_shader_parameter("keep_band", Vector2(-1.0, 2.0))
	else:
		# Onboard: only the band at the horizon streaks, not the cockpit
		# below or the halo above.
		_blur_mat.set_shader_parameter("car_r", Vector2.ZERO)
		_blur_mat.set_shader_parameter("keep_band", Vector2(0.3, 0.6))
	# Streak towards where the road ahead is on screen.
	var ahead: Vector3 = target.global_position + target.global_basis.z * 80.0 + Vector3.UP * 1.0
	var vp := get_viewport()
	if vp != null and not is_position_behind(ahead):
		var s := unproject_position(ahead) / vp.get_visible_rect().size
		_blur_mat.set_shader_parameter("focus", Vector2(clampf(s.x, 0.25, 0.75), clampf(s.y, 0.25, 0.7)))

## Road vibration: a little at high speed, more over kerbs, grass and gravel.
func _shake(spd: float, delta: float) -> Vector3:
	_shake_t += delta
	# Grows with speed: barely there at 180 km/h, a fine buzz flat out.
	var amp := clampf((spd - 45.0) * 0.0007, 0.0, 0.03)
	if target.wheels_on_grass > 0:
		amp += 0.03 * clampf(spd / 30.0, 0.0, 1.0)
	if amp <= 0.0:
		return Vector3.ZERO
	# A fine buzz plus a slower float over the road's undulations.
	var bob := sin(_shake_t * 7.3) * 0.6 + sin(_shake_t * 11.9 + 2.0) * 0.4
	return Vector3(sin(_shake_t * 61.0) * 0.6, sin(_shake_t * 83.0 + 1.3) + bob * 0.8, sin(_shake_t * 47.0 + 0.4) * 0.4) * amp
