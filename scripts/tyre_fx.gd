class_name TyreFX
extends Node3D
## Skid marks and tyre smoke for every car near the camera.
## Skid marks are quads in one MultiMesh ring buffer (oldest reused first),
## so they stay on the track for the session at a fixed cost.

const MAX_MARKS := 1800
const MARK_STEP := 0.45          # metres between mark segments
const RANGE := 140.0             # only cars this close to the camera

var _mm: MultiMesh
var _next := 0
var _count := 0
var _last := {}                  # wheel -> last mark point (Vector3) or null
var _smoke := {}                 # car -> CPUParticles3D
var _cars: Array = []
var camera: Camera3D


func setup(cars: Array) -> void:
	_cars = cars
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	_mm.mesh = quad
	_mm.instance_count = MAX_MARKS
	_mm.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.02)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _physics_process(_delta: float) -> void:
	var cam_pos := camera.global_position if camera != null else Vector3.ZERO
	for car in _cars:
		var c: RaceCar = car
		if not is_instance_valid(c):
			continue
		var near := camera == null or c.global_position.distance_squared_to(cam_pos) < RANGE * RANGE
		var smoking := false
		for w in c.wheels:
			var s := w.skid()
			if near and w.in_contact and s > 0.35 and w.surface == 0:
				_mark(w, c, s)
				if not w.use_as_steering and s > 0.55 and c.linear_velocity.length() > 4.0:
					smoking = true
			else:
				_last[w] = null
		if near or _smoke.has(c):
			_set_smoke(c, smoking and near)


func _mark(w: CarWheel, c: RaceCar, strength: float) -> void:
	var p := w.contact_point + w.contact_normal * 0.014
	var prev = _last.get(w)
	if prev == null:
		_last[w] = p
		return
	var d: Vector3 = p - prev
	var seg := d.length()
	if seg < MARK_STEP:
		return
	if seg > 3.0:                           # teleported / reset
		_last[w] = p
		return
	var fwd := d / seg
	var up := w.contact_normal
	var side := up.cross(fwd).normalized()
	var width := 0.3 if w.use_as_steering else 0.38
	var basis := Basis(side * width, up, fwd * (seg + 0.04))
	_mm.set_instance_transform(_next, Transform3D(basis, (p + prev) * 0.5))
	_mm.set_instance_color(_next, Color(1, 1, 1, clampf(0.25 + strength * 0.45, 0.0, 0.7)))
	_next = (_next + 1) % MAX_MARKS
	_count = mini(_count + 1, MAX_MARKS)
	_mm.visible_instance_count = _count
	_last[w] = p


func _set_smoke(c: RaceCar, on: bool) -> void:
	if not _smoke.has(c):
		if not on:
			return
		_smoke[c] = _make_smoke(c)
	var p: CPUParticles3D = _smoke[c]
	p.emitting = on


func _make_smoke(c: RaceCar) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 28
	p.lifetime = 1.3
	p.local_coords = false
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _puff_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	q.material = mat
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.9, 0.1, 0.3)
	p.direction = Vector3(0, 1, -0.3)
	p.spread = 25.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.92, 0.94, 0.55))
	ramp.set_color(1, Color(0.85, 0.86, 0.9, 0.0))
	p.color_ramp = ramp
	p.position = Vector3(0, 0.25, float(c.spec["wheel_rear_z"]))
	c.add_child(p)
	return p


static var _puff: ImageTexture

static func _puff_texture() -> ImageTexture:
	if _puff != null:
		return _puff
	var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	img.generate_mipmaps()
	_puff = ImageTexture.create_from_image(img)
	return _puff
