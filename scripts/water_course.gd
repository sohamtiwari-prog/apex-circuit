class_name WaterCourse
extends Node3D
## A powerboat course: open water (scripts/water.gd) with the course marked
## by lines of buoys, big inflatable buoys at the turns, a floating start
## gantry, and the shore round it: a lake in the hills, or a harbour with
## quays and the city behind. The track (scripts/track.gd) still supplies
## the course's centreline, racing line and lap timing; this builds what
## you see (and the shore the boats can run into).

var track: Track
var kind := "lake"
var water: Water
## Shore distance field: metres from the course's centreline, on a grid.
var _d := PackedFloat32Array()
var _x0 := 0.0
var _z0 := 0.0
var _nx := 0
var _nz := 0
const CELL := 8.0
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _marks: Array = []                  # turn buoys: [node, base position] (they ride the swell)
var _lamps: Array[MeshInstance3D] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _buoy_mat: ShaderMaterial
var shore_at := 90.0                    # typical distance of the shore from the course


func build(t: Track, water_kind: String) -> void:
	track = t
	kind = water_kind
	_rng.seed = hash(t.track_id)
	_noise.seed = _rng.randi()
	_noise.frequency = 0.004
	_noise.fractal_octaves = 3
	shore_at = t.road_half + (70.0 if kind == "lake" else 38.0)
	water = Water.create(self, "lake" if kind == "lake" else "harbour", 0.0, 0.7 if kind == "lake" else 0.5)
	_distance_field()
	_shore()
	_buoys()
	_turn_marks()
	_start_gantry()
	_sponsor_barges()
	_moored_boats()
	_grandstand()
	if kind == "lake":
		_trees()
	else:
		_city()


func _process(_delta: float) -> void:
	# The turn buoys bob on the swell.
	for m in _marks:
		var node: Node3D = m[0]
		var p: Vector3 = m[1]
		node.position.y = Water.height(p.x, p.z) - 0.15
	if _buoy_mat != null:
		_buoy_mat.set_shader_parameter("wave_time", Water.time)


## The start lights on the gantry (0 = all off).
func set_lights(n: int) -> void:
	for k in _lamps.size():
		_lamps[k].material_override = _lamp_on if k / 2 < n else _lamp_off


# ------------------------------------------------------------ the shore

## Distance from the course's centreline over a grid round it (a chamfer
## distance transform: exact near the course, close enough further out).
func _distance_field() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in track.points:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var margin := 900.0
	_x0 = floorf((lo.x - margin) / CELL) * CELL
	_z0 = floorf((lo.y - margin) / CELL) * CELL
	_nx = int(ceil((hi.x - lo.x + margin * 2.0) / CELL)) + 1
	_nz = int(ceil((hi.y - lo.y + margin * 2.0) / CELL)) + 1
	_d.resize(_nx * _nz)
	_d.fill(1e6)
	for p in track.points:
		var cx := int(round((p.x - _x0) / CELL))
		var cz := int(round((p.z - _z0) / CELL))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var ix := cx + dx
				var iz := cz + dz
				if ix < 0 or iz < 0 or ix >= _nx or iz >= _nz:
					continue
				var d := Vector2(_x0 + ix * CELL - p.x, _z0 + iz * CELL - p.z).length()
				var k := iz * _nx + ix
				if d < _d[k]:
					_d[k] = d
	var a := CELL
	var b := CELL * 1.4142
	for iz in _nz:
		for ix in _nx:
			var k := iz * _nx + ix
			var v := _d[k]
			if ix > 0:
				v = minf(v, _d[k - 1] + a)
			if iz > 0:
				v = minf(v, _d[k - _nx] + a)
				if ix > 0:
					v = minf(v, _d[k - _nx - 1] + b)
				if ix < _nx - 1:
					v = minf(v, _d[k - _nx + 1] + b)
			_d[k] = v
	for iz in range(_nz - 1, -1, -1):
		for ix in range(_nx - 1, -1, -1):
			var k := iz * _nx + ix
			var v := _d[k]
			if ix < _nx - 1:
				v = minf(v, _d[k + 1] + a)
			if iz < _nz - 1:
				v = minf(v, _d[k + _nx] + a)
				if ix < _nx - 1:
					v = minf(v, _d[k + _nx + 1] + b)
				if ix > 0:
					v = minf(v, _d[k + _nx - 1] + b)
			_d[k] = v


## Distance from the course at (x, z) (bilinear on the grid).
func course_distance(x: float, z: float) -> float:
	var fx := clampf((x - _x0) / CELL, 0.0, _nx - 1.001)
	var fz := clampf((z - _z0) / CELL, 0.0, _nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _nx + ix
	return lerpf(lerpf(_d[k], _d[k + 1], tx), lerpf(_d[k + _nx], _d[k + _nx + 1], tx), tz)


## How far out the shore is here: varies along the shoreline.
func _shore_dist(x: float, z: float) -> float:
	return shore_at + _noise.get_noise_2d(x, z) * (60.0 if kind == "lake" else 18.0)


## Height of the land (or lake bed) at (x, z).
func ground_height(x: float, z: float) -> float:
	var d := course_distance(x, z)
	var s := _shore_dist(x, z)
	var e := d - s
	if kind == "harbour":
		# Quays: a steep stone edge, then the flat waterfront and the city.
		if e < 0.0:
			return -5.0
		return lerpf(-5.0, 1.6, clampf(e / 3.0, 0.0, 1.0)) + maxf(e - 120.0, 0.0) * 0.02
	if e < 0.0:
		return -1.2 + e * 0.06                          # the lake bed shelving away
	# A beach, then the hills rising behind it.
	var hills := 0.5 + 0.5 * _noise.get_noise_2d(x * 2.3 + 500.0, z * 2.3)
	return -1.2 + minf(e, 22.0) * 0.12 + maxf(e - 22.0, 0.0) * (0.06 + 0.22 * hills) + maxf(e - 250.0, 0.0) * 0.15 * hills


func _shore() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2                                   # every other cell: 16 m
	var nx := (_nx - 1) / step
	var nz := (_nz - 1) / step
	var h := PackedFloat32Array()
	h.resize((nx + 1) * (nz + 1))
	for iz in nz + 1:
		for ix in nx + 1:
			var x := _x0 + ix * step * CELL
			var z := _z0 + iz * step * CELL
			h[iz * (nx + 1) + ix] = ground_height(x, z)
	var sand := Color(0.78, 0.7, 0.53) if kind == "lake" else Color(0.55, 0.54, 0.52)
	var grass := Color(0.28, 0.42, 0.18) if kind == "lake" else Color(0.5, 0.49, 0.47)
	var rock := Color(0.42, 0.4, 0.37)
	var bed := Color(0.28, 0.3, 0.22)
	for iz in nz:
		for ix in nx:
			var q: Array = []
			var cols: Array = []
			for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var gx: int = ix + c.x
				var gz: int = iz + c.y
				var y := h[gz * (nx + 1) + gx]
				var p := Vector3(_x0 + gx * step * CELL, y, _z0 + gz * step * CELL)
				q.append(p)
				var col := grass
				if y < -0.6:
					col = bed
				elif y < 0.9:
					col = sand
				var n := _noise.get_noise_2d(p.x * 7.0, p.z * 7.0)
				col = col.lerp(rock, clampf((y - 30.0) / 40.0, 0.0, 0.6)) * (0.9 + 0.2 * n)
				cols.append(col)
			# (Skip cells that are all far under the water.)
			if q[0].y < -2.0 and q[1].y < -2.0 and q[2].y < -2.0 and q[3].y < -2.0:
				continue
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					st.set_color(cols[k])
					st.add_vertex(q[k])
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	var tex := NoiseTexture2D.new()
	var nn := FastNoiseLite.new()
	nn.frequency = 0.08
	tex.noise = nn
	tex.seamless = true
	tex.width = 128
	tex.height = 128
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	# The shore stops boats that run aground.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("barrier", true)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------ buoys

## The course's edges: small buoys all the way round both sides, closer
## together in the turns (they bob on the swell: a shader does it).
func _buoys() -> void:
	var n := track.size()
	var xforms: Array = []
	var cols: Array = []
	for side in [-1.0, 1.0]:
		var i := 0
		while i < n:
			var tight := absf(track.curv[i]) > 0.008
			var p: Vector3 = track.points[i] + track.rights[i] * side * (track.road_half + 0.5)
			xforms.append(Transform3D(Basis(), Vector3(p.x, -0.12, p.z)))
			cols.append(Color(1.0, 0.55, 0.05) if side < 0.0 else Color(1.0, 0.85, 0.05))
			i += 6 if tight else 16
	var mesh := SphereMesh.new()
	mesh.radius = 0.45
	mesh.height = 0.8
	mesh.radial_segments = 12
	mesh.rings = 6
	_buoy_mat = ShaderMaterial.new()
	_buoy_mat.shader = _bob_shader()
	var waves: Array = []
	for k in Water.MAX_WAVES:
		if k * 5 + 4 < Water._k.size():
			waves.append(Vector4(Water._k[k * 5], Water._k[k * 5 + 1], Water._k[k * 5 + 2], Water._k[k * 5 + 3]))
		else:
			waves.append(Vector4.ZERO)
	_buoy_mat.set_shader_parameter("waves", waves)
	var phases := Vector4.ZERO
	for k in Water.MAX_WAVES:
		if k * 5 + 4 < Water._k.size():
			phases[k] = Water._k[k * 5 + 4]
	_buoy_mat.set_shader_parameter("phases", phases)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _buoy_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


static func _bob_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
// Floating things ride the swell: the same waves as scripts/water.gd.
uniform vec4 waves[4];
uniform vec4 phases;
uniform float wave_time;
varying vec3 col;
void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 w = waves[i];
		h += w.z * sin(w.x * at.x + w.y * at.z - w.w * wave_time + phases[i]);
	}
	VERTEX.y += h;
	col = COLOR.rgb;
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
"""
	return sh


## At every turn, big inflatable buoys round the inside of the bend, wrapped
## in sponsors' colours (the boats turn round these).
func _turn_marks() -> void:
	var n := track.size()
	var k := 0
	for c in track.corners():
		var i0: int = c[0]
		var i1: int = c[1]
		var mid := (i0 + i1) / 2
		var inside := signf(track.curv[mid])          # + : a left-hander, inside on the left
		var side := -inside                            # (rights point right)
		for j in [i0, mid, i1]:
			if j != mid and (i1 - i0) < 12:
				continue
			var p: Vector3 = track.points[j % n] + track.rights[j % n] * side * (track.road_half + 1.4)
			_inflatable(p, Sponsors.SERIES[k % 3] if j == mid else _partner(k + j), k)
			k += 1


func _partner(k: int) -> String:
	var b: Array = Sponsors.brands()
	return String(b[posmod(k * 7 + 3, b.size())]["id"])


## A tall inflatable buoy: a cylinder printed with a sponsor's board, a
## dome on top.
func _inflatable(p: Vector3, brand: String, k: int) -> void:
	var node := Node3D.new()
	node.position = Vector3(p.x, 0.0, p.z)
	add_child(node)
	var r := 1.0
	var hgt := 2.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv := Sponsors.board_uv(Sponsors.board_of(brand, k % 2 == 1))
	var seg := 20
	for s in seg:
		var a0 := TAU * s / seg
		var a1 := TAU * (s + 1) / seg
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		# The board wraps twice round.
		var u0 := uv.position.x + uv.size.x * fmod(float(s) / seg * 2.0, 1.0)
		var u1 := u0 + uv.size.x * 2.0 / seg
		var up := Vector3(0, hgt, 0)
		var n0 := p0.normalized()
		var n1 := p1.normalized()
		for v in [[p0, n0, Vector2(u0, uv.end.y)], [p1 + up, n1, Vector2(u1, uv.position.y)], [p1, n1, Vector2(u1, uv.end.y)],
				[p0, n0, Vector2(u0, uv.end.y)], [p0 + up, n0, Vector2(u0, uv.position.y)], [p1 + up, n1, Vector2(u1, uv.position.y)]]:
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = Sponsors.boards()
	m.roughness = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	node.add_child(mi)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.2
	dome.mesh = sm
	dome.position.y = hgt
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Sponsors.color(brand)
	dm.roughness = 0.45
	dome.material_override = dm
	node.add_child(dome)
	_marks.append([node, Vector3(p.x, 0.0, p.z)])


# ------------------------------------------------------------ start

## A floating gantry across the course at the line: pontoons outside the
## buoys, an arch with the series' banner and the start lights.
func _start_gantry() -> void:
	var p: Vector3 = track.points[0]
	var r: Vector3 = track.rights[0]
	var fwd: Vector3 = track.htangents[0]
	var span := track.road_half + 4.0
	var basis := Basis.looking_at(-fwd, Vector3.UP)
	var white := Color(0.92, 0.93, 0.95)
	var st := MeshKit.new_tool()
	for side in [-1.0, 1.0]:
		var foot: Vector3 = p + r * side * span
		MeshKit.box(st, Vector3(3.0, 0.6, 6.0), Vector3.ZERO, Color(0.15, 0.16, 0.18), Vector3.ZERO, Transform3D(basis, foot + Vector3(0, 0.1, 0)))
		track.scenery_boxes.append({"xf": Transform3D(basis, foot + r * side * 0.5), "size": Vector3(2.0, 9.0, 6.0)})
		MeshKit.box(st, Vector3(0.6, 9.0, 0.6), Vector3.ZERO, white, Vector3.ZERO, Transform3D(basis, foot + Vector3(0, 4.9, 0)))
	MeshKit.box(st, Vector3(span * 2.0 + 0.6, 1.4, 0.8), Vector3.ZERO, Color(0.1, 0.1, 0.12), Vector3.ZERO, Transform3D(basis, p + Vector3(0, 9.1, 0)))
	var mesh := MeshKit.finish(st)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	# Banners on both faces.
	_board_run(p - r * span + Vector3(0, 8.45, 0) - fwd * 0.42, p + r * span + Vector3(0, 8.45, 0) - fwd * 0.42, 1.3, Sponsors.board_of("apex"), -fwd, 3)
	_board_run(p - r * span + Vector3(0, 8.45, 0) + fwd * 0.42, p + r * span + Vector3(0, 8.45, 0) + fwd * 0.42, 1.3, Sponsors.board_of("aurum", true), fwd, 3)
	# Five pairs of lamps facing the boats coming to the line.
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.emission_enabled = true
	_lamp_on.albedo_color = Color(1, 0.1, 0.05)
	_lamp_on.emission = Color(1, 0.05, 0.02)
	_lamp_on.emission_energy_multiplier = 6.0
	_lamp_off = StandardMaterial3D.new()
	_lamp_off.albedo_color = Color(0.12, 0.03, 0.03)
	var lamp := SphereMesh.new()
	lamp.radius = 0.22
	lamp.height = 0.44
	for k in 5:
		for row in 2:
			var l := MeshInstance3D.new()
			l.mesh = lamp
			l.material_override = _lamp_off
			l.position = p + r * (float(k) - 2.0) * 0.8 + Vector3(0, 9.35 - row * 0.5, 0) - fwd * 0.45
			add_child(l)
			_lamps.append(l)


func _board_run(l: Vector3, r: Vector3, h: float, board: int, face: Vector3, reps: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in reps:
		_board_quad(st, l.lerp(r, float(k) / reps), l.lerp(r, float(k + 1) / reps), h, board, face)
	_add_boards(st)


func _board_quad(st: SurfaceTool, l: Vector3, r: Vector3, h: float, board: int, face: Vector3) -> void:
	var rv := (-face).cross(Vector3.UP)
	if (r - l).dot(rv) < 0.0:
		var t := l
		l = r
		r = t
	var uv := Sponsors.board_uv(board)
	var up := Vector3(0, h, 0)
	var q := [l, r, r + up, l + up]
	var uvs := [Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y), uv.position]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(face)
		st.set_uv(uvs[k])
		st.add_vertex(q[k])


func _add_boards(st: SurfaceTool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = Sponsors.boards()
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	add_child(mi)


# ------------------------------------------------------------ round the course

## Sponsors' boards on floating pontoons outside the buoys along the
## straights, facing the course.
func _sponsor_barges() -> void:
	var n := track.size()
	var boards := SurfaceTool.new()
	boards.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st := MeshKit.new_tool()
	var k := 0
	var i := 40
	while i < n - 10:
		if absf(track.curv[i]) < 0.004:
			for side in [-1.0, 1.0]:
				var out: Vector3 = track.rights[i] * side
				var p: Vector3 = track.points[i] + out * (track.road_half + 9.0)
				var fwd: Vector3 = track.htangents[i]
				var basis := Basis.looking_at(-fwd, Vector3.UP)
				MeshKit.box(st, Vector3(1.6, 0.5, 14.0), Vector3.ZERO, Color(0.13, 0.14, 0.16), Vector3.ZERO, Transform3D(basis, p + Vector3(0, 0.05, 0)))
				track.scenery_boxes.append({"xf": Transform3D(basis, p), "size": Vector3(1.6, 2.0, 14.0)})
				var l := p - fwd * 6.5 - out * 0.3 + Vector3(0, 0.3, 0)
				var r := p + fwd * 6.5 - out * 0.3 + Vector3(0, 0.3, 0)
				_board_quad(boards, l, r, 1.6, _board_for(k), -out)
				_board_quad(boards, l + out * 0.6, r + out * 0.6, 1.6, _board_for(k + 5), out)
				k += 1
		i += 55
	_add_boards(boards)
	var mesh := MeshKit.finish(st)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _board_for(k: int) -> int:
	match k % 4:
		0:
			return Sponsors.board_of(Sponsors.SERIES[(k / 4) % 3])
		2:
			return Sponsors.board_of("mareo")
	return posmod(k * 5 + 1, Sponsors.board_count())


## Spectators' boats and yachts moored round the course.
func _moored_boats() -> void:
	var xforms: Array = []
	var cols: Array = []
	var n := track.size()
	for t in 90:
		var i := _rng.randi_range(0, n - 1)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		# Moored along the shore, clear of the course.
		var p: Vector3 = track.points[i]
		var out: Vector3 = track.rights[i] * side
		var lat := track.road_half + 20.0
		while lat < 500.0 and ground_height(p.x + out.x * lat, p.z + out.z * lat) < -0.9:
			lat += 3.0
		p = p + out * (lat - _rng.randf_range(6.0, 22.0))
		if course_distance(p.x, p.z) < track.road_half + 20.0 or ground_height(p.x, p.z) > -0.8:
			continue
		var s := _rng.randf_range(0.8, 1.8)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
		xforms.append(Transform3D(b, Vector3(p.x, 0.0, p.z)))
		cols.append([Color(0.95, 0.95, 0.96), Color(0.9, 0.9, 0.92), Color(0.15, 0.2, 0.35), Color(0.75, 0.1, 0.1)][_rng.randi() % 4])
	if xforms.is_empty():
		return
	var st := MeshKit.new_tool()
	# A small motor yacht: a pointed hull, a cabin, a dark windscreen.
	MeshKit.loft(st, [MeshKit.station(-3.0, 0.25, 1.1, 0.5, 4.0), MeshKit.station(0.5, 0.3, 1.2, 0.55, 4.0),
		MeshKit.station(2.6, 0.45, 0.6, 0.4, 3.0), MeshKit.station(3.4, 0.6, 0.05, 0.1, 2.0)], 10,
		func(p: Vector3, th: float) -> Color: return Color(1, 1, 1) if p.y > 0.2 else Color(0.55, 0.55, 0.58))
	MeshKit.box(st, Vector3(1.6, 0.7, 2.6), Vector3(0, 1.05, -0.6), Color(1, 1, 1))
	MeshKit.box(st, Vector3(1.5, 0.35, 0.1), Vector3(0, 1.2, 0.72), Color(0.1, 0.12, 0.15), Vector3(-25, 0, 0))
	var mesh := MeshKit.finish(st)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.3
	mmi.material_override = m
	add_child(mmi)


## A grandstand on the shore opposite the start, facing the water.
func _grandstand() -> void:
	var i0 := 0
	for side in [-1.0, 1.0]:
		var out: Vector3 = track.rights[i0] * side
		var p: Vector3 = track.points[i0]
		var lat := track.road_half + 10.0
		while lat < 400.0 and ground_height(p.x + out.x * lat, p.z + out.z * lat) < 1.2:
			lat += 4.0
		if lat >= 400.0:
			continue
		var at := p + out * (lat + 6.0)
		at.y = ground_height(at.x, at.z)
		var basis := Basis.looking_at(-out, Vector3.UP)
		var st := MeshKit.new_tool()
		var rows := 10
		for r in rows:
			var c := Color(0.65, 0.66, 0.7) if r % 2 == 0 else Color(0.6, 0.61, 0.65)
			MeshKit.box(st, Vector3(60.0, 0.5 + r * 0.5, 1.0), Vector3(0, (0.5 + r * 0.5) * 0.5, r * 1.0), c, Vector3.ZERO, Transform3D(basis, at))
			# The crowd: a band of colours along each row.
			var crowd := Color.from_hsv(_rng.randf(), 0.5, 0.75)
			MeshKit.box(st, Vector3(59.0, 0.45, 0.4), Vector3(0, 0.5 + r * 0.5 + 0.22, r * 1.0 - 0.2), crowd, Vector3.ZERO, Transform3D(basis, at))
		MeshKit.box(st, Vector3(62.0, 0.3, 12.0), Vector3(0, 9.0, 4.5), Color(0.9, 0.9, 0.92), Vector3.ZERO, Transform3D(basis, at))
		for sx in [-29.0, 29.0]:
			MeshKit.box(st, Vector3(0.5, 9.0, 0.5), Vector3(sx, 4.5, 10.0), Color(0.8, 0.8, 0.82), Vector3.ZERO, Transform3D(basis, at))
		var mesh := MeshKit.finish(st)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.8
		mesh.surface_set_material(0, m)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		track.scenery_boxes.append({"xf": Transform3D(basis, at + basis * Vector3(0, 0, 5.0)), "size": Vector3(62.0, 9.0, 12.0)})
		# Sponsors along the roof's front edge.
		var boards := SurfaceTool.new()
		boards.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 5:
			_board_quad(boards, at + basis * Vector3(-31.0 + k * 12.4, 8.1, -1.55), at + basis * Vector3(-31.0 + (k + 1) * 12.4, 8.1, -1.55), 1.5, _board_for(k + 2), -out)
		_add_boards(boards)
		return


func _trees() -> void:
	var xforms: Array[Transform3D] = []
	var cols: Array = []
	var tries := 2600
	var span_x := (_nx - 1) * CELL
	var span_z := (_nz - 1) * CELL
	for t in tries:
		var x := _x0 + _rng.randf() * span_x
		var z := _z0 + _rng.randf() * span_z
		var y := ground_height(x, z)
		if y < 2.0 or y > 90.0:
			continue
		var s := _rng.randf_range(0.8, 1.5)
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, y - 0.3, z)))
		cols.append(Color(0.75, 0.9, 0.7).lerp(Color(0.5, 0.6, 0.4), _rng.randf()))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Track._tree_mesh("conifer" if kind == "lake" else "broadleaf")
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 1600.0
	add_child(mmi)


## The harbour's city: blocks along the waterfront, taller further back.
func _city() -> void:
	var xforms: Array = []
	var cols: Array = []
	var palette := [Color(0.93, 0.88, 0.78), Color(0.95, 0.8, 0.62), Color(0.86, 0.72, 0.6),
		Color(0.9, 0.9, 0.88), Color(0.98, 0.86, 0.7), Color(0.8, 0.74, 0.7)]
	var span_x := (_nx - 1) * CELL
	var span_z := (_nz - 1) * CELL
	var placed: Array = []
	for t in 2400:
		var x := _x0 + _rng.randf() * span_x
		var z := _z0 + _rng.randf() * span_z
		var d := course_distance(x, z)
		var e := d - _shore_dist(x, z)
		if e < 22.0 or e > 520.0:
			continue
		var p := Vector2(x, z)
		var clear := true
		for q in placed:
			if p.distance_to(q) < 30.0:
				clear = false
				break
		if not clear:
			continue
		placed.append(p)
		var w := _rng.randf_range(16.0, 30.0)
		var dd := _rng.randf_range(16.0, 28.0)
		var h := _rng.randf_range(10.0, 26.0) + clampf((e - 22.0) / 6.0, 0.0, 70.0) * _rng.randf_range(0.3, 1.0)
		var y := ground_height(x, z)
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		xforms.append(Transform3D(Basis(b.x * w, b.y * h, b.z * dd), Vector3(x, y - 0.5 + h * 0.5, z)))
		track.scenery_boxes.append({"xf": Transform3D(b, Vector3(x, y, z)), "size": Vector3(w, h, dd)})
		cols.append(palette[_rng.randi() % palette.size()])
	if xforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var facade := ShaderMaterial.new()
	facade.shader = load("res://shaders/building.gdshader")
	facade.set_shader_parameter("night", 1.0 if track.night else 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = facade
	add_child(mmi)
