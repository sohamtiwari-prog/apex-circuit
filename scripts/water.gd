class_name Water
extends Node3D
## Open water: a lake, a harbour or the sea, with real waves.
##
## The surface is a sum of travelling waves. The same sum gives the height
## the boats float on (Water.height, used by scripts/boat_hull.gd) and the
## surface you see (shaders/open_water.gdshader), so a boat rides exactly
## the swell drawn under it. Smaller ripples on top are only drawn (as the
## surface's shading), they don't move the boats.
##
## The mesh is a disc of rings round the camera, fine in the middle and
## coarse at the horizon, that follows the camera; the waves are worked out
## in world space, so the water doesn't move with it.

const G := 9.81
## The swell that moves boats: [direction (deg), wavelength (m), height (m, crest to mean), phase].
const CALM := [
	[20.0, 23.0, 0.11, 0.0],
	[-35.0, 13.0, 0.075, 1.7],
	[75.0, 7.5, 0.045, 4.1],
	[140.0, 4.2, 0.022, 2.6],
]
const MAX_WAVES := 4

static var time := 0.0                 # seconds of wave motion (the physics clock)
static var level := 0.0                # mean water height
static var roughness_now := 1.0               # wave height: 1 calm, more when it's rough
static var _k := PackedFloat32Array()  # per wave: kx, kz, amplitude, omega, phase (5 each)

var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var camera: Camera3D                   # the water centres on this (or the active camera)


## (Re)sets the waves: their heights scaled by `roughness` (1 = calm water).
static func set_waves(roughness := 1.0, base_level := 0.0) -> void:
	level = base_level
	roughness_now = roughness
	_k = PackedFloat32Array()
	for w in CALM:
		var a := deg_to_rad(float(w[0]))
		var lambda := float(w[1])
		var k := TAU / lambda
		var omega := sqrt(G * k)                 # deep-water waves: long ones run faster
		_k.append_array([cos(a) * k, sin(a) * k, float(w[2]) * roughness, omega, float(w[3])])


## Height of the water surface at (x, z), now.
static func height(x: float, z: float) -> float:
	if _k.is_empty():
		set_waves()
	var h := level
	for i in range(0, _k.size(), 5):
		h += _k[i + 2] * sin(_k[i] * x + _k[i + 1] * z - _k[i + 3] * time + _k[i + 4])
	return h


## Upward surface normal at (x, z), now.
static func normal(x: float, z: float) -> Vector3:
	if _k.is_empty():
		set_waves()
	var dx := 0.0
	var dz := 0.0
	for i in range(0, _k.size(), 5):
		var c := _k[i + 2] * cos(_k[i] * x + _k[i + 1] * z - _k[i + 3] * time + _k[i + 4])
		dx += c * _k[i]
		dz += c * _k[i + 1]
	return Vector3(-dx, 1.0, -dz).normalized()


## Vertical speed of the surface at (x, z) (a crest coming up under a boat
## pushes it up harder).
static func rise_rate(x: float, z: float) -> float:
	var r := 0.0
	for i in range(0, _k.size(), 5):
		r -= _k[i + 2] * _k[i + 3] * cos(_k[i] * x + _k[i + 1] * z - _k[i + 3] * time + _k[i + 4])
	return r


## Builds the water under `parent`: `tint` "lake" (green-blue), "harbour"
## (blue-grey) or "sea" (blue).
static func create(parent: Node, tint := "lake", water_level := 0.0, roughness := 1.0) -> Water:
	set_waves(roughness, water_level)
	time = 0.0
	var w := Water.new()
	w.name = "Water"
	parent.add_child(w)
	w._build(tint)
	return w


func _build(tint: String) -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/open_water.gdshader")
	var deep := Color(0.02, 0.13, 0.17)
	var shallow := Color(0.05, 0.3, 0.32)
	match tint:
		"harbour":
			deep = Color(0.02, 0.09, 0.16)
			shallow = Color(0.07, 0.22, 0.3)
		"sea":
			deep = Color(0.01, 0.09, 0.2)
			shallow = Color(0.03, 0.3, 0.42)
	material.set_shader_parameter("deep", deep)
	material.set_shader_parameter("shallow", shallow)
	material.set_shader_parameter("ripples", _ripple_texture())
	var waves: Array = []
	for i in MAX_WAVES:
		if i * 5 + 4 < _k.size():
			waves.append(Vector4(_k[i * 5], _k[i * 5 + 1], _k[i * 5 + 2], _k[i * 5 + 3]))
		else:
			waves.append(Vector4.ZERO)
	material.set_shader_parameter("waves", waves)
	var phases := Vector4.ZERO
	for i in MAX_WAVES:
		if i * 5 + 4 < _k.size():
			phases[i] = _k[i * 5 + 4]
	material.set_shader_parameter("phases", phases)
	material.set_shader_parameter("level", level)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _disc_mesh()
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.extra_cull_margin = 4000.0
	add_child(mesh_instance)


func _physics_process(delta: float) -> void:
	time += delta


func _process(_delta: float) -> void:
	material.set_shader_parameter("wave_time", time)
	var cam := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam != null:
		# Follow the camera in whole metres (the fine middle stays under it).
		var p := cam.global_position
		mesh_instance.global_position = Vector3(roundf(p.x), level, roundf(p.z))


## Rings round the middle: fine within a few metres, a few hundred metres
## apart at the horizon (3 km out).
static func _disc_mesh() -> ArrayMesh:
	const RINGS := 72
	const SPOKES := 96
	const R := 3000.0
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	for r in range(1, RINGS + 1):
		var rad := R * pow(float(r) / RINGS, 2.6)
		for s in SPOKES:
			var a := TAU * s / SPOKES + (0.5 * TAU / SPOKES if r % 2 == 1 else 0.0)
			verts.append(Vector3(cos(a) * rad, 0.0, sin(a) * rad))
	for s in SPOKES:
		idx.append_array([0, 1 + (s + 1) % SPOKES, 1 + s])
	for r in range(1, RINGS):
		var a0 := 1 + (r - 1) * SPOKES
		var b0 := 1 + r * SPOKES
		for s in SPOKES:
			var s1 := (s + 1) % SPOKES
			idx.append_array([a0 + s, a0 + s1, b0 + s, a0 + s1, b0 + s1, b0 + s])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static var _ripple_tex: Texture2D


## Fine ripples (only drawn): a tiling noise used as two drifting normal maps.
static func _ripple_texture() -> Texture2D:
	if _ripple_tex != null:
		return _ripple_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 3.0
	t.generate_mipmaps = true
	t.noise = n
	_ripple_tex = t
	return t
