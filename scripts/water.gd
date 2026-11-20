class_name Water
extends Node3D
## Open water: a lake, a harbour or the sea, with real waves.
##
## The swell is six trochoidal (Gerstner) waves: the water moves in circles
## as each passes, so crests come up sharp and troughs stay broad and flat,
## the way real waves look. The same six waves give the height the boats
## float on (Water.height, used by scripts/boat_hull.gd) and the surface you
## see (shaders/open_water.gdshader), so a boat rides exactly the swell
## drawn under it. Fine ripples on top are only drawn.
##
## Boats' wakes are felt as well as seen: every boat leaves a trail of wake
## points (scripts/boat_fx.gd); another boat crossing them rides over the
## two ridges of the V and the churned trail between (Water.wake_height).
##
## Shallows: where the course has a shore, the lake bed's height is handed
## to the shader, which turns the water clearer and greener as it shoals and
## breaks it into foam along the water's edge.
##
## The mesh is a disc of rings round the camera, fine in the middle and
## coarse at the horizon, that follows the camera; the waves are worked out
## in world space, so the water doesn't move with it.

const G := 9.81
const WAVES := 6
## The swell: [direction (deg), wavelength (m), height (m, crest above mean), phase].
const CALM := [
	[20.0, 28.0, 0.1, 0.0],
	[-35.0, 15.0, 0.07, 1.7],
	[75.0, 9.0, 0.045, 4.1],
	[140.0, 5.5, 0.028, 2.6],
	[-110.0, 3.6, 0.016, 5.3],
	[50.0, 2.4, 0.01, 0.8],
]
## How peaked the crests are (0 rounded sine waves .. 1 cusps).
const STEEP := 0.75
## The boats feel the first four (the two shortest are ripples only drawn:
## too small to move a boat, and it saves the phone the sums).
const FELT := 4

static var time := 0.0                 # seconds of wave motion (the physics clock)
static var level := 0.0                # mean water height
static var roughness_now := 1.0        # wave height: 1 calm, more when it's rough
## Per wave: dir x, dir z, k, amplitude, omega, phase, q (7 each).
static var _w := PackedFloat32Array()
## Wake points from all boats: [x, z, dir x, dir z, age, strength, owner].
static var wakes: Array = []
const WAKE_LIFE := 2.1

var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var camera: Camera3D                   # the water centres on this (or the active camera)


## (Re)sets the waves: their heights scaled by `roughness` (1 = calm water).
static func set_waves(roughness := 1.0, base_level := 0.0) -> void:
	level = base_level
	roughness_now = roughness
	_w = PackedFloat32Array()
	var n := CALM.size()
	for w in CALM:
		var a := deg_to_rad(float(w[0]))
		var k := TAU / float(w[1])
		var amp := float(w[2]) * roughness
		var omega := sqrt(G * k)                 # deep-water waves: long ones run faster
		# Each wave's share of the peaking, kept short of folding over.
		var q := clampf(STEEP / maxf(k * amp * n, 0.0001), 0.0, 1.0)
		_w.append_array([cos(a), sin(a), k, amp, omega, float(w[3]), q])
	wakes.clear()


## Where the water at rest at (x, z) is now: its sideways shift, and height.
static func _at(x: float, z: float) -> Vector3:
	var dx := 0.0
	var dz := 0.0
	var h := 0.0
	for i in range(0, mini(_w.size(), FELT * 7), 7):
		var th := _w[i + 2] * (_w[i] * x + _w[i + 1] * z) - _w[i + 4] * time + _w[i + 5]
		var s := sin(th)
		var qa := _w[i + 6] * _w[i + 3]
		dx -= qa * _w[i] * s
		dz -= qa * _w[i + 1] * s
		h += _w[i + 3] * cos(th)
	return Vector3(dx, h, dz)


## Height of the water surface at (x, z), now (without wakes).
static func height(x: float, z: float) -> float:
	if _w.is_empty():
		set_waves()
	# Find the bit of water that's been carried to (x, z): its rest position
	# plus its shift lands here (one step of fixed-point iteration: the
	# shifts are a few centimetres).
	var d := _at(x, z)
	return level + _at(x - d.x, z - d.z).y


## Upward surface normal at (x, z), now.
static func normal(x: float, z: float) -> Vector3:
	var e := 0.4
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Vertical speed of the surface at (x, z) (a crest coming up under a boat
## pushes it up harder).
static func rise_rate(x: float, z: float) -> float:
	var r := 0.0
	for i in range(0, mini(_w.size(), FELT * 7), 7):
		var th := _w[i + 2] * (_w[i] * x + _w[i + 1] * z) - _w[i + 4] * time + _w[i + 5]
		r += _w[i + 3] * _w[i + 4] * sin(th)
	return r


# ------------------------------------------------------------ wakes

## A boat leaves a wake point behind it.
static func add_wake(pos: Vector3, dir: Vector3, strength: float, owner: int) -> void:
	wakes.append([pos.x, pos.z, dir.x, dir.z, 0.0, strength, owner])


static func age_wakes(delta: float) -> void:
	var keep: Array = []
	for w in wakes:
		w[4] += delta
		if float(w[4]) < WAKE_LIFE:
			keep.append(w)
	wakes = keep


## The wake points near `pos` that aren't `owner`'s own (a boat doesn't ride
## its own wake): worked out once per boat per step.
static func wakes_near(pos: Vector3, owner: int, radius := 26.0) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for w in wakes:
		if int(w[6]) == owner:
			continue
		var dx: float = float(w[0]) - pos.x
		var dz: float = float(w[1]) - pos.z
		if dx * dx + dz * dz < r2:
			out.append(w)
	return out


## Extra height from those wakes at (x, z): two ridges spreading out as the
## V widens, and the churned trail behind the propeller, all dying away.
static func wake_height(x: float, z: float, near: Array) -> float:
	var h := 0.0
	for w in near:
		var age: float = w[4]
		var s: float = w[5]
		var rx := x - float(w[0])
		var rz := z - float(w[1])
		if rx * rx + rz * rz > 160.0:
			continue
		var along := rx * float(w[2]) + rz * float(w[3])
		if absf(along) > 7.0:
			continue
		var lat := absf(rx * float(w[3]) - rz * float(w[2]))
		var life := 1.0 - age / WAKE_LIFE
		var arm := 1.0 + age * 3.2 * s
		var ridge := exp(-pow((lat - arm) / 1.0, 2.0)) * 0.24
		var trail := exp(-pow(lat / (0.8 + age), 2.0)) * 0.08
		h += (ridge + trail) * s * life * life * exp(-pow(along / 3.6, 2.0))
	return h


# ------------------------------------------------------------ the surface

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


## The swell's numbers, for a shader with the same waves (this water's, the
## floating buoys').
static func shader_waves(m: ShaderMaterial) -> void:
	var a: Array = []
	var b: Array = []
	for i in WAVES:
		var o := i * 7
		if o + 6 < _w.size():
			a.append(Vector4(_w[o], _w[o + 1], _w[o + 2], _w[o + 3]))
			b.append(Vector4(_w[o + 4], _w[o + 5], _w[o + 6], 0.0))
		else:
			a.append(Vector4.ZERO)
			b.append(Vector4.ZERO)
	m.set_shader_parameter("waves", a)
	m.set_shader_parameter("wave_params", b)


func _build(tint: String) -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/open_water.gdshader")
	var deep := Color(0.015, 0.11, 0.15)
	var shallow := Color(0.05, 0.3, 0.32)
	var sand := Color(0.42, 0.5, 0.36)
	var surround := Color(0.11, 0.16, 0.12)       # wooded hills mirrored at the far shore
	var cover := 0.9
	match tint:
		"harbour":
			deep = Color(0.015, 0.08, 0.14)
			shallow = Color(0.06, 0.22, 0.28)
			sand = Color(0.3, 0.36, 0.34)
			surround = Color(0.3, 0.28, 0.26)    # the town's walls
			cover = 0.75
		"sea":
			deep = Color(0.01, 0.08, 0.19)
			shallow = Color(0.03, 0.3, 0.42)
			sand = Color(0.3, 0.62, 0.62)
			surround = Color(0.3, 0.34, 0.38)
			cover = 0.25
	material.set_shader_parameter("deep", deep)
	material.set_shader_parameter("shallow", shallow)
	material.set_shader_parameter("shoal", sand)
	material.set_shader_parameter("surround", surround)
	material.set_shader_parameter("surround_cover", cover)
	material.set_shader_parameter("ripples", _ripple_texture())
	material.set_shader_parameter("foam_tex", _foam_texture())
	shader_waves(material)
	material.set_shader_parameter("level", level)
	material.set_shader_parameter("rough", roughness_now)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _disc_mesh()
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.extra_cull_margin = 4000.0
	add_child(mesh_instance)


## The bed under the water (heights on a grid from x0, z0, `step` metres
## apart): shallows and the foam at the water's edge.
func set_ground(heights: PackedFloat32Array, w: int, h: int, x0: float, z0: float, step: float) -> void:
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array())
	var tex := ImageTexture.create_from_image(img)
	material.set_shader_parameter("ground", tex)
	material.set_shader_parameter("ground_rect", Vector4(x0, z0, (w - 1) * step, (h - 1) * step))
	material.set_shader_parameter("ground_texel", Vector2(1.0 / w, 1.0 / h))
	material.set_shader_parameter("has_ground", 1.0)


func _physics_process(delta: float) -> void:
	time += delta
	age_wakes(delta)


var _sun: DirectionalLight3D


func _process(_delta: float) -> void:
	material.set_shader_parameter("wave_time", time)
	if _sun == null:
		var suns := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		if not suns.is_empty():
			_sun = suns[0]
			material.set_shader_parameter("sun_dir", _sun.global_basis.z)
	var cam := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam != null:
		# Follow the camera in whole metres (the fine middle stays under it).
		var p := cam.global_position
		mesh_instance.global_position = Vector3(roundf(p.x), level, roundf(p.z))


## Rings round the middle: fine within a few metres, a few hundred metres
## apart at the horizon (3 km out).
static func _disc_mesh() -> ArrayMesh:
	const RINGS := 84
	const SPOKES := 112
	const R := 3000.0
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	for r in range(1, RINGS + 1):
		var rad := R * pow(float(r) / RINGS, 2.8)
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
static var _foam_tex: Texture2D


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


## Foam: lacy cells (white along their edges).
static func _foam_texture() -> Texture2D:
	if _foam_tex != null:
		return _foam_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.06
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	_foam_tex = t
	return t
