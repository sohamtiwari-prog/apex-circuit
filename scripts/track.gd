class_name Track
extends Node3D
## A race circuit built procedurally from a centreline.
##
## Tracks come from data files (tracks/<id>.json, imported from real circuit
## outlines by tools/import_circuit.py) or from a list of control points.
## The centreline is sampled every SPACING metres; every other system (road
## mesh, walls, lap timing, AI) works off those samples.

const KERB_W := 1.3
const LINE_W := 0.3
const SPACING := 2.0
const ROAD_Y := 0.0
const GROUND_Y := -0.08
const GRID := 24.0

## Tracks available in the game, in menu order.
const CATALOG := [
	{"id": "silvermoor", "name": "Silvermoor Circuit", "desc": "Britain · 5.86 km · fast and flowing", "style": "park"},
	{"id": "brianza", "name": "Autodromo di Brianza", "desc": "Italy · 5.77 km · temple of speed", "style": "park"},
	{"id": "ardennes", "name": "Circuit des Ardennes", "desc": "Belgium · 6.96 km · long and legendary", "style": "forest"},
	{"id": "riviera", "name": "Riviera Street Circuit", "desc": "Monaco · 3.30 km · tight streets, no room for error", "style": "city"},
	{"id": "styria", "name": "Styria Ring", "desc": "Austria · 4.29 km · short, fast, heavy braking", "style": "park"},
	{"id": "entrelagos", "name": "Autodromo Entrelagos", "desc": "Brazil · 4.28 km · anticlockwise classic", "style": "park"},
	{"id": "desert", "name": "Desert Sun International Circuit", "desc": "Bahrain · 5.39 km · stop-and-go in the sand", "style": "desert"},
	{"id": "kestrel_park", "name": "Kestrel Park", "desc": "Original club circuit · 2.06 km", "style": "park"},
]

# Original club circuit, defined by control points (x, z) in metres.
const KESTREL_LAYOUT := [
	Vector2(0, 0), Vector2(150, 0), Vector2(300, 0), Vector2(380, 20),
	Vector2(420, 80), Vector2(410, 160), Vector2(360, 210), Vector2(300, 220),
	Vector2(260, 260), Vector2(270, 330), Vector2(320, 380), Vector2(330, 440),
	Vector2(290, 480), Vector2(230, 470), Vector2(180, 420), Vector2(120, 400),
	Vector2(40, 420), Vector2(-40, 440), Vector2(-120, 420), Vector2(-170, 360),
	Vector2(-160, 290), Vector2(-110, 250), Vector2(-120, 180), Vector2(-170, 130),
	Vector2(-160, 60), Vector2(-100, 10), Vector2(-50, 0),
]

var track_id := "kestrel_park"
var track_name := "Kestrel Park"
var road_half := 6.5          # half the asphalt width
var wall_offset := 19.0
var style := "park"             # park, forest, city, desert

var points := PackedVector3Array()
var tangents := PackedVector3Array()
var rights := PackedVector3Array()
var cum := PackedFloat32Array()
var curv := PackedFloat32Array()     # signed, 1/radius; negative = right-hander
var total_length := 0.0
var _grid := {}

# Racing line (see tools/racing_line.py): lateral offset per sample.
var line_offset := PackedFloat32Array()
var line_points := PackedVector3Array()
var line_curv := PackedFloat32Array()      # signed, 1/radius of the racing line
var line_curv_safe := PackedFloat32Array() # |curvature|, max over the surrounding 30 m (for speed planning)
var line_margin := 1.35
var _profiles := {}


static func catalog_entry(id: String) -> Dictionary:
	for t in CATALOG:
		if t["id"] == id:
			return t
	return CATALOG[0]


static func catalog_name(id: String) -> String:
	for t in CATALOG:
		if t["id"] == id:
			return t["name"]
	return id


func build(id: String = "kestrel_park") -> void:
	track_id = id
	track_name = catalog_name(id)
	style = catalog_entry(id)["style"]
	if id == "kestrel_park":
		road_half = 6.5
		wall_offset = 19.0
		_sample_control(KESTREL_LAYOUT)
	else:
		_load_file("res://tracks/%s.json" % id)
	_derive()
	_derive_line()
	_build_grid()
	_build_ground()
	_build_road()
	_build_walls()
	_build_scenery()


# ------------------------------------------------------------ queries

func size() -> int:
	return points.size()


## Nearest centerline sample. Pass the previous result as `hint` for a
## fast local search; -1 searches the whole track.
func nearest_index(pos: Vector3, hint: int = -1) -> int:
	var n := points.size()
	var best := 0
	var best_d := INF
	if hint < 0:
		for i in range(n):
			var p: Vector3 = points[i]
			var d := (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
			if d < best_d:
				best_d = d
				best = i
	else:
		for k in range(-60, 61):
			var i := (hint + k + n) % n
			var p: Vector3 = points[i]
			var d := (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
			if d < best_d:
				best_d = d
				best = i
	return best


## Cheap per-frame tracking: walks from `hint` towards the nearest sample.
## Cars move well under a sample per tick, so this takes a few steps.
func track_index(pos: Vector3, hint: int) -> int:
	if hint < 0:
		return nearest_index(pos, -1)
	var n := points.size()
	var best := hint
	var p: Vector3 = points[best]
	var best_d := (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
	for dir in [1, -1]:
		var i: int = best
		for step in range(40):
			var j: int = (i + dir + n) % n
			var q: Vector3 = points[j]
			var d := (q.x - pos.x) * (q.x - pos.x) + (q.z - pos.z) * (q.z - pos.z)
			if d >= best_d:
				break
			best_d = d
			best = j
			i = j
	return best


## Signed lateral offset from the centerline (+ = right of travel).
func lateral(pos: Vector3, idx: int) -> float:
	var p: Vector3 = points[idx]
	var r: Vector3 = rights[idx]
	return (pos - p).dot(r)


## Transform for a car sitting on the centerline at `idx`, facing along
## the track (+Z of the car = direction of travel).
func pose_at(idx: int, height: float, lateral_offset := 0.0) -> Transform3D:
	var n := points.size()
	idx = (idx + n) % n
	var t: Vector3 = tangents[idx]
	var b := Basis.looking_at(-t, Vector3.UP)
	var p: Vector3 = points[idx] + rights[idx] * lateral_offset + Vector3.UP * height
	return Transform3D(b, p)


func dist_to_centerline(pos: Vector3, radius: float = 30.0) -> float:
	var cx := int(floor(pos.x / GRID))
	var cz := int(floor(pos.z / GRID))
	var r := int(ceil(radius / GRID))
	var best := INF
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if _grid.has(key):
				for i in _grid[key]:
					var q: Vector3 = points[i]
					var d := Vector2(q.x - pos.x, q.z - pos.z).length()
					if d < best:
						best = d
	return best


# ------------------------------------------------------------ sampling

func _load_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	track_name = data.get("name", track_name)
	road_half = float(data.get("half_width", 7.0))
	wall_offset = float(data.get("wall_offset", 24.0))
	points = PackedVector3Array()
	for p in data["points"]:
		points.append(Vector3(float(p[0]), ROAD_Y, float(p[1])))
	line_offset = PackedFloat32Array()
	if data.has("line"):
		for o in data["line"]:
			line_offset.append(float(o))
		line_margin = float(data.get("line_margin", 1.35))


func _sample_control(layout: Array) -> void:
	var curve := Curve3D.new()
	curve.bake_interval = SPACING
	var n := layout.size()
	for i in range(n + 1):
		var p: Vector2 = layout[i % n]
		var pv: Vector2 = layout[(i - 1 + n) % n]
		var nx: Vector2 = layout[(i + 1) % n]
		var h: Vector2 = (nx - pv) * 0.2
		curve.add_point(Vector3(p.x, ROAD_Y, p.y), Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, h.y))
	# Resample at exactly SPACING metres so distances and curvature are uniform.
	var length := curve.get_baked_length()
	var count_target := int(round(length / SPACING))
	var step := length / count_target
	points = PackedVector3Array()
	for k in range(count_target):
		var b: Vector3 = curve.sample_baked(k * step, true)
		points.append(Vector3(b.x, ROAD_Y, b.z))


func _derive() -> void:
	var count := points.size()
	tangents.resize(count)
	rights.resize(count)
	cum.resize(count)
	curv.resize(count)
	var d := 0.0
	for i in range(count):
		var t: Vector3 = (points[(i + 1) % count] - points[(i - 1 + count) % count]).normalized()
		tangents[i] = t
		rights[i] = t.cross(Vector3.UP).normalized()
		cum[i] = d
		d += points[i].distance_to(points[(i + 1) % count])
	total_length = d
	for i in range(count):
		var a: Vector3 = tangents[(i - 4 + count) % count]
		var b: Vector3 = tangents[(i + 4) % count]
		curv[i] = a.cross(b).y / (8.0 * SPACING)


func _build_grid() -> void:
	_grid.clear()
	for i in range(points.size()):
		var p: Vector3 = points[i]
		var key := Vector2i(int(floor(p.x / GRID)), int(floor(p.z / GRID)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


# ------------------------------------------------------------ materials

func _noise_texture(freq: float, dark: Color, light: Color) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq
	var grad := Gradient.new()
	grad.set_color(0, dark)
	grad.set_color(1, light)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	return tex


# ------------------------------------------------------------ ground

func _ground_color() -> Color:
	match style:
		"desert":
			return Color(0.78, 0.62, 0.42)
		"city":
			return Color(0.36, 0.36, 0.38)
		"forest":
			return Color(0.17, 0.36, 0.11)
	return Color(0.2, 0.42, 0.13)


func _build_ground() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _ground_color()
	mat.albedo_texture = _noise_texture(0.05, Color(0.7, 0.72, 0.6), Color(1, 1, 1))
	mat.uv1_scale = Vector3(500, 500, 1)
	mat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = GROUND_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var body := StaticBody3D.new()
	body.position.y = GROUND_Y
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------ road

func _kerb_mask() -> Array[bool]:
	var n := points.size()
	var raw: Array[bool] = []
	raw.resize(n)
	for i in range(n):
		raw[i] = absf(curv[i]) > 1.0 / 110.0
	var out: Array[bool] = []
	out.resize(n)
	for i in range(n):
		var on := false
		for k in range(-5, 6):
			if raw[(i + k + n) % n]:
				on = true
				break
		out[i] = on
	return out


func _pt(i: int, j: int, t: float, off: float) -> Vector3:
	var a: Vector3 = points[i] + rights[i] * off
	var b: Vector3 = points[j] + rights[j] * off
	return a.lerp(b, t)


func _band(st: SurfaceTool, faces: PackedVector3Array, i: int, j: int,
		off0: float, off1: float, col: Color, t0: float = 0.0, t1: float = 1.0) -> void:
	var seg: float = points[i].distance_to(points[j])
	var v0: float = (cum[i] + t0 * seg) / 8.0
	var v1: float = (cum[i] + t1 * seg) / 8.0
	var p00 := _pt(i, j, t0, off0)
	var p01 := _pt(i, j, t0, off1)
	var p10 := _pt(i, j, t1, off0)
	var p11 := _pt(i, j, t1, off1)
	var verts := [p00, p10, p01, p01, p10, p11]
	var uvs := [Vector2(off0 / 8.0, v0), Vector2(off0 / 8.0, v1), Vector2(off1 / 8.0, v0),
		Vector2(off1 / 8.0, v0), Vector2(off0 / 8.0, v1), Vector2(off1 / 8.0, v1)]
	for k in range(6):
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])
		faces.append(verts[k])


func _build_road() -> void:
	var n := points.size()
	var kerb := _kerb_mask()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()

	var asphalt := Color(0.2, 0.2, 0.19)
	var white := Color(0.93, 0.93, 0.93)
	var red := Color(0.82, 0.12, 0.09)
	var verge := _ground_color().lightened(0.06)
	if style == "city":
		verge = Color(0.42, 0.42, 0.44)
	var black := Color(0.06, 0.06, 0.06)
	var h := road_half

	for i in range(n):
		var j := (i + 1) % n
		var kc: Color = verge
		if kerb[i]:
			kc = red if int(cum[i] / 3.0) % 2 == 0 else white
		_band(st, faces, i, j, -h - KERB_W, -h, kc)
		_band(st, faces, i, j, -h, -h + LINE_W, white)
		_band(st, faces, i, j, h - LINE_W, h, white)
		_band(st, faces, i, j, h, h + KERB_W, kc)
		if i == 0:
			# Chequered start/finish line: 2 rows x 20 cells.
			var cells := 20
			var w := (2.0 * (h - LINE_W)) / cells
			for row in range(2):
				for c in range(cells):
					var o0 := -h + LINE_W + c * w
					var col: Color = white if (c + row) % 2 == 0 else black
					_band(st, faces, i, j, o0, o0 + w, col, row * 0.5, row * 0.5 + 0.5)
		else:
			_band(st, faces, i, j, -h + LINE_W, h - LINE_W, asphalt)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = _noise_texture(0.35, Color(0.78, 0.78, 0.78), Color(1, 1, 1))
	mat.roughness = 0.92
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------ walls

func _build_walls() -> void:
	var n := points.size()
	var step := 3
	var body := StaticBody3D.new()
	add_child(body)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box

	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for side in [-1.0, 1.0]:
		var count := 0
		for i in range(0, n, step):
			var j := (i + step) % n
			var a: Vector3 = points[i] + rights[i] * wall_offset * side
			var b: Vector3 = points[j] + rights[j] * wall_offset * side
			var mid := (a + b) * 0.5
			# Skip segments that fold into the track on tight inside corners.
			if dist_to_centerline(mid, wall_offset + 2.0) < wall_offset - 2.5:
				continue
			var dir := b - a
			dir.y = 0
			var length := dir.length()
			if length < 0.1:
				continue
			var fwd := dir / length
			var basis := Basis.looking_at(-fwd, Vector3.UP)
			var height := 1.1
			var thick := 0.7
			var center := mid + Vector3.UP * (GROUND_Y + height * 0.5)
			var scaled := Basis(basis.x * thick, basis.y * height, basis.z * (length + 0.35))
			xforms.append(Transform3D(scaled, center))
			colors.append(Color(0.13, 0.35, 0.8) if count % 2 == 0 else Color(0.92, 0.92, 0.92))
			count += 1

			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(thick, height + 0.6, length + 0.35)
			cs.shape = shape
			cs.transform = Transform3D(basis, center + Vector3.UP * 0.3)
			body.add_child(cs)

	mm.instance_count = xforms.size()
	for k in range(xforms.size()):
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, colors[k])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# ------------------------------------------------------------ scenery

func _build_scenery() -> void:
	if style == "city":
		_build_city()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(points.size()):
		var p: Vector3 = points[i]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(160, 160)
	hi += Vector2(160, 160)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.25
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 6
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 2.4
	crown_mesh.height = 6.5
	crown_mesh.radial_segments = 8

	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var crown_cols: Array[Color] = []
	var attempts := 1400
	if style == "forest":
		attempts = 3200
	elif style == "desert":
		attempts = 220
	for k in range(attempts):
		var pos := Vector3(rng.randf_range(lo.x, hi.x), GROUND_Y, rng.randf_range(lo.y, hi.y))
		if dist_to_centerline(pos, wall_offset + 12.0) < wall_offset + 9.0:
			continue
		var s := rng.randf_range(0.8, 1.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		trunks.append(Transform3D(b, pos + Vector3.UP * 1.2 * s))
		crowns.append(Transform3D(b, pos + Vector3.UP * (2.4 + 3.25) * s))
		var g := rng.randf_range(0.0, 1.0)
		if style == "desert":
			crown_cols.append(Color(0.35 + 0.1 * g, 0.42 + 0.1 * g, 0.18))
		else:
			crown_cols.append(Color(0.12 + 0.08 * g, 0.32 + 0.12 * g, 0.12 + 0.05 * g))

	_multimesh(trunk_mesh, trunks, [], Color(0.36, 0.25, 0.16))
	_multimesh(crown_mesh, crowns, crown_cols, Color.WHITE)
	_build_grandstands()


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], cols: Array, base: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in range(xforms.size()):
		mm.set_instance_transform(k, xforms[k])
		if mm.use_colors:
			mm.set_instance_color(k, cols[k])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.vertex_color_use_as_albedo = mm.use_colors
	mat.roughness = 0.95
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _build_grandstands() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.62, 0.62, 0.64)
	var seats := StandardMaterial3D.new()
	seats.albedo_color = Color(0.85, 0.32, 0.08)
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.9, 0.9, 0.92)
	# Two stands along the left of the main straight, plus one on the right.
	for spec in [[25, -1.0], [55, -1.0], [40, 1.0]]:
		var idx: int = spec[0]
		var side: float = spec[1]
		var base: Transform3D = pose_at(idx, GROUND_Y)
		var out: Vector3 = rights[idx] * side
		var origin: Vector3 = base.origin + out * (wall_offset + 9.0)
		var basis: Basis = base.basis
		for tier in range(5):
			var bm := BoxMesh.new()
			bm.size = Vector3(4.0, 1.0 + tier * 1.0, 50.0)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = seats if tier % 2 == 0 else concrete
			mi.transform = Transform3D(basis, origin + out * (tier * 3.2) + Vector3.UP * (0.5 + tier * 0.5))
			add_child(mi)
		var rm := BoxMesh.new()
		rm.size = Vector3(18.0, 0.4, 52.0)
		var r := MeshInstance3D.new()
		r.mesh = rm
		r.material_override = roof
		r.transform = Transform3D(basis, origin + out * 7.0 + Vector3.UP * 8.5)
		add_child(r)


## Street circuit: apartment blocks and hotels right behind the barriers.
func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var n := points.size()
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var palette := [Color(0.93, 0.88, 0.78), Color(0.95, 0.8, 0.62), Color(0.86, 0.72, 0.6),
		Color(0.9, 0.9, 0.88), Color(0.98, 0.86, 0.7), Color(0.8, 0.74, 0.7)]
	for side in [-1.0, 1.0]:
		var i := 0
		while i < n:
			var w := rng.randf_range(14.0, 30.0)
			var depth := rng.randf_range(14.0, 26.0)
			var h := rng.randf_range(12.0, 48.0)
			var p: Vector3 = points[i] + rights[i] * side * (wall_offset + 2.5 + depth * 0.5)
			if dist_to_centerline(p, depth + wall_offset) > wall_offset + 1.5 + depth * 0.45:
				var b := Basis.looking_at(-tangents[i], Vector3.UP)
				xforms.append(Transform3D(Basis(b.x * depth, b.y * h, b.z * w), p + Vector3.UP * (GROUND_Y + h * 0.5)))
				cols.append(palette[rng.randi() % palette.size()])
			i += int(w / SPACING) + 1
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_multimesh(box, xforms, cols, Color.WHITE)
	_build_grandstands()


# ------------------------------------------------------------ racing line

func _derive_line() -> void:
	var n := points.size()
	if line_offset.size() != n:
		_optimise_line()
	line_points.resize(n)
	for i in range(n):
		line_points[i] = points[i] + rights[i] * line_offset[i]
	line_curv.resize(n)
	var k := 6
	for i in range(n):
		var a: Vector3 = line_points[(i - k + n) % n]
		var b: Vector3 = line_points[i]
		var c: Vector3 = line_points[(i + k) % n]
		var t1 := (b - a).normalized()
		var t2 := (c - b).normalized()
		var ang := atan2(t1.cross(t2).y, t1.dot(t2))
		# The two chords' midpoints are k samples apart, so the heading
		# changes by `ang` over k * SPACING metres.
		line_curv[i] = ang / (k * SPACING)
	# Plan speeds for the tightest point nearby, so noise in the data can't
	# make a corner look briefly straight (and the AI accelerate mid-corner).
	line_curv_safe.resize(n)
	var span := 8
	for i in range(n):
		var m := 0.0
		for j in range(-span, span + 1):
			m = maxf(m, absf(line_curv[(i + j + n) % n]))
		line_curv_safe[i] = m


## Same algorithm as tools/racing_line.py, for tracks defined in code.
func _optimise_line() -> void:
	var n := points.size()
	var w := maxf(0.0, road_half - line_margin)
	var off := PackedFloat32Array()
	off.resize(n)
	off.fill(0.0)
	var line := PackedVector3Array()
	line.resize(n)
	var scales := [3, 6, 12, 24]
	for it in range(400):
		var k: int = scales[it % scales.size()]
		for i in range(n):
			line[i] = points[i] + rights[i] * off[i]
		var nxt := off.duplicate()
		for i in range(n):
			var m: Vector3 = (-line[(i - 2 * k + n * 2) % n] + 4.0 * line[(i - k + n) % n]
				+ 4.0 * line[(i + k) % n] - line[(i + 2 * k) % n]) / 6.0
			var target := (m - points[i]).dot(rights[i])
			nxt[i] = clampf(off[i] + 0.6 * (target - off[i]), -w, w)
		off = nxt
	for _pass in range(20):
		var sm := off.duplicate()
		for i in range(n):
			sm[i] = clampf((off[(i - 1 + n) % n] + 2.0 * off[i] + off[(i + 1) % n]) * 0.25, -w, w)
		off = sm
	line_offset = off


## Fastest speed (m/s) at every sample for a car following the racing line:
## corner limits from tyre grip plus downforce, then braking zones worked
## backwards from each corner. Cached per car.
func speed_profile(spec: Dictionary) -> PackedFloat32Array:
	var key: String = spec["id"]
	if _profiles.has(key):
		return _profiles[key]
	var n := points.size()
	var a0: float = spec["ai_grip"]
	var a1: float = spec["ai_grip_aero"]
	var v := PackedFloat32Array()
	v.resize(n)
	for i in range(n):
		var kk := line_curv_safe[i]
		v[i] = 99.0 if kk <= a1 + 0.00001 else minf(sqrt(a0 / (kk - a1)), 99.0)
	var base_dec: float = spec["ai_brake"]
	var aero_dec: float = float(spec["brake_aero"]) * 0.8
	var max_dec: float = float(spec["brake_max"]) * 0.8
	for _loop in range(2):
		for j in range(n - 1, -1, -1):
			var nx := v[(j + 1) % n]
			var dec := minf(base_dec + aero_dec * nx * nx, max_dec)
			v[j] = minf(v[j], sqrt(nx * nx + 2.0 * dec * SPACING))
	_profiles[key] = v
	return v
