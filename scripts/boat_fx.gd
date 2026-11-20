class_name BoatFX
extends Node3D
## What a racing powerboat throws up: the white wake behind it (a churned
## trail from the propeller, and the two arms of the V spreading out from
## the hull), the propeller's rooster tail of spray, and sheets of spray
## off the outside sponson in a turn. Drawn in world space; follows its
## boat (scripts/boat_hull.gd says how much of it is in the water).

const SAMPLE_EVERY := 0.06         # s between wake points
const LIFE := 2.1                  # s a wake point lasts
const MAX_POINTS := 56

var car: RaceCar
var _pts: Array = []               # [position, right, age, strength]
var _since := 0.0
var _mesh := ImmediateMesh.new()
var _mi: MeshInstance3D
var _rooster: CPUParticles3D
var _side: CPUParticles3D
static var _foam_mat: StandardMaterial3D
static var _spray_mat: StandardMaterial3D


func attach(c: RaceCar) -> void:
	car = c
	top_level = true
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = _foam()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_rooster = _particles(32, 0.8)
	_rooster.direction = Vector3(0, 0.75, -1)
	_rooster.spread = 9.0
	_rooster.initial_velocity_min = 7.0
	_rooster.initial_velocity_max = 13.0
	_rooster.scale_amount_min = 0.3
	_rooster.scale_amount_max = 0.7
	_side = _particles(24, 0.5)
	_side.direction = Vector3(1, 0.6, -0.3)
	_side.spread = 14.0
	_side.initial_velocity_min = 4.0
	_side.initial_velocity_max = 8.0


func _particles(amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _spray()
	p.mesh = q
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.45))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	add_child(p)
	return p


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or car.hull == null:
		return
	var hull := car.hull
	var b := car.global_basis
	var v := car.forward_speed()
	var on := hull.contact > 0.15 and absf(v) > 2.0 and car.visible
	# Wake points from the stern, between the sponsons.
	_since += delta
	for p in _pts:
		p[2] += delta
	while not _pts.is_empty() and float(_pts[0][2]) > LIFE:
		_pts.pop_front()
	if on and _since >= SAMPLE_EVERY:
		_since = 0.0
		var stern := car.global_position + b * Vector3(0, 0, -3.0)
		var right := Vector3(b.x.x, 0, b.x.z).normalized()
		_pts.append([stern, right, 0.0, clampf(absf(v) / 30.0, 0.25, 1.0)])
		if _pts.size() > MAX_POINTS:
			_pts.pop_front()
	_draw_wake()
	# Spray: the rooster tail grows with speed while the propeller bites;
	# the outside sponson throws a sheet in a hard turn.
	var prop := car.global_position + b * Vector3(0, 0.0, -3.5)
	_rooster.global_position = prop
	_rooster.direction = (b * Vector3(0, 0.7, -1.0)).normalized()
	_rooster.emitting = on and hull.prop_bite > 0.3 and absf(v) > 8.0
	_rooster.initial_velocity_max = 6.0 + absf(v) * 0.2
	var turning := car.angular_velocity.y
	var outside := -signf(turning) if absf(turning) > 0.05 else 1.0
	_side.global_position = car.global_position + b * Vector3(0.95 * outside, 0.1, 0.4)
	_side.direction = (b * Vector3(outside, 0.6, -0.4)).normalized()
	_side.emitting = on and absf(turning) * absf(v) > 9.0


func _draw_wake() -> void:
	_mesh.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# The churned trail behind the propeller, widening and fading; then the
	# V's two arms, spreading sideways as they age.
	for arm in [0.0, -1.0, 1.0]:
		for k in n - 1:
			var a: Array = _pts[k]
			var c: Array = _pts[k + 1]
			var qa := _strip(a, arm)
			var qc := _strip(c, arm)
			_quad(qa[0], qa[1], qc[1], qc[0], qa[2], qc[2])
	_mesh.surface_end()


## The two edges of a wake strip at a point, and its opacity.
func _strip(p: Array, arm: float) -> Array:
	var pos: Vector3 = p[0]
	var right: Vector3 = p[1]
	var age: float = p[2]
	var s: float = p[3]
	var life := clampf(1.0 - age / LIFE, 0.0, 1.0)
	var centre := pos
	var half := 0.0
	var alpha := 0.0
	if arm == 0.0:
		half = 0.7 + age * 1.1
		alpha = life * life * 0.34 * s
	else:
		centre = pos + right * arm * (1.0 + age * 3.2 * s)
		half = 0.22 + age * 0.3
		alpha = life * life * 0.28 * s
	var y := Water.height(centre.x, centre.z) + 0.04
	var l := centre - right * half
	var r := centre + right * half
	l.y = y
	r.y = y
	return [l, r, alpha]


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, al0: float, al1: float) -> void:
	var c0 := Color(1, 1, 1, al0)
	var c1 := Color(1, 1, 1, al1)
	for v in [[a, c0, Vector2(0, 0)], [b, c0, Vector2(1, 0)], [c, c1, Vector2(1, 1)], [a, c0, Vector2(0, 0)], [c, c1, Vector2(1, 1)], [d, c1, Vector2(0, 1)]]:
		_mesh.surface_set_color(v[1])
		_mesh.surface_set_uv(Vector2(v[0].x, v[0].z) * 0.25)
		_mesh.surface_set_normal(Vector3.UP)
		_mesh.surface_add_vertex(v[0])


static func _foam() -> StandardMaterial3D:
	if _foam_mat != null:
		return _foam_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.6
	# Broken-up foam: bubbly noise, white.
	var t := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.08
	t.noise = n
	t.seamless = true
	t.width = 128
	t.height = 128
	# Lacy: white along the cells' edges, clear in their middles.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.25), Color(1, 1, 1, 1.0)])
	t.color_ramp = g
	m.albedo_texture = t
	m.texture_repeat = true
	_foam_mat = m
	return m


static func _spray() -> StandardMaterial3D:
	if _spray_mat != null:
		return _spray_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(1, 1, 1, 0.9))
	g.gradient.set_color(1, Color(1, 1, 1, 0.0))
	m.albedo_texture = g
	m.albedo_color = Color(0.95, 0.97, 1.0)
	_spray_mat = m
	return m
