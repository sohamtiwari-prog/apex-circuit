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

## Footprints of every large scenery object placed: [{"xf": Transform3D, "size": Vector3}]
## (unscaled transform, box size). Used to keep scenery off the road.
var scenery_boxes: Array = []
var trackside: Trackside


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
	_derive_runoff()
	_derive_drs()
	_build_grid()
	_build_ground()
	_build_road()
	_build_walls()
	trackside = Trackside.new()
	add_child(trackside)
	trackside.build(self)
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


## Centreline of a catalog track without building anything (menu maps).
static func outline(id: String) -> PackedVector3Array:
	var t := Track.new()
	if id == "kestrel_park":
		t._sample_control(KESTREL_LAYOUT)
	else:
		t._load_file("res://tracks/%s.json" % id)
	var pts := t.points
	t.free()
	return pts


## Track length in metres from its outline.
static func outline_length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(pts.size()):
		total += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return total


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
			return Color(0.13, 0.28, 0.09)
	return Color(0.16, 0.33, 0.1)


func _build_ground() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	var base := _ground_color()
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("noise_tex", _noise_texture(0.02, Color(0, 0, 0), Color(1, 1, 1)))
	match style:
		"desert":
			mat.set_shader_parameter("alt_color", base.lightened(0.04))
			mat.set_shader_parameter("stripe_strength", 0.0)
			mat.set_shader_parameter("far_color", Color(0.82, 0.7, 0.52))
		"city":
			mat.set_shader_parameter("alt_color", base)
			mat.set_shader_parameter("stripe_strength", 0.0)
			mat.set_shader_parameter("far_color", base)
		_:
			mat.set_shader_parameter("alt_color", base.lightened(0.09))
			mat.set_shader_parameter("far_color", base.lerp(Color(0.45, 0.55, 0.5), 0.35))
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


func _pt(i: int, j: int, t: float, off: float, dy := 0.0) -> Vector3:
	var a: Vector3 = points[i] + rights[i] * off
	var b: Vector3 = points[j] + rights[j] * off
	return a.lerp(b, t) + Vector3(0, dy, 0)


func _band(st: SurfaceTool, faces: PackedVector3Array, i: int, j: int,
		off0: float, off1: float, col: Color, t0: float = 0.0, t1: float = 1.0,
		dy0 := 0.0, dy1 := 0.0) -> void:
	var seg: float = points[i].distance_to(points[j])
	var v0: float = (cum[i] + t0 * seg) / 8.0
	var v1: float = (cum[i] + t1 * seg) / 8.0
	var p00 := _pt(i, j, t0, off0, dy0)
	var p01 := _pt(i, j, t0, off1, dy1)
	var p10 := _pt(i, j, t1, off0, dy0)
	var p11 := _pt(i, j, t1, off1, dy1)
	var l0: float = lerpf(line_offset[i], line_offset[j], t0) if line_offset.size() == points.size() else 0.0
	var l1: float = lerpf(line_offset[i], line_offset[j], t1) if line_offset.size() == points.size() else 0.0
	var verts := [p00, p10, p01, p01, p10, p11]
	var uvs := [Vector2(off0 / 8.0, v0), Vector2(off0 / 8.0, v1), Vector2(off1 / 8.0, v0),
		Vector2(off1 / 8.0, v0), Vector2(off0 / 8.0, v1), Vector2(off1 / 8.0, v1)]
	var uv2s := [Vector2(off0, l0), Vector2(off0, l1), Vector2(off1, l0),
		Vector2(off1, l0), Vector2(off0, l1), Vector2(off1, l1)]
	for k in range(6):
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.set_uv2(uv2s[k])
		st.add_vertex(verts[k])
		faces.append(verts[k])


# ------------------------------------------------------------ run-off

const RUNOFF_NONE := 0
const RUNOFF_GRAVEL := 1
const RUNOFF_ASPHALT := 2

## Per sample, for the left (index 0) and right (index 1) side: what lies
## beyond the kerb (grass, gravel trap or asphalt run-off) and how wide.
var runoff_type: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray()]
var runoff_width := 0.0


func _derive_runoff() -> void:
	var n := points.size()
	runoff_type = [PackedByteArray(), PackedByteArray()]
	for side in range(2):
		runoff_type[side].resize(n)
		runoff_type[side].fill(RUNOFF_NONE)
	runoff_width = clampf(wall_offset - road_half - KERB_W - 3.0, 0.0, 16.0)
	if style == "city" or runoff_width < 3.0:
		return
	var gravel_share := 0.3
	if style == "forest":
		gravel_share = 0.65
	elif style == "desert":
		gravel_share = 0.15
	# Corners: runs of samples tighter than ~350 m radius.
	var i := 0
	var corner := 0
	while i < n:
		if absf(curv[i]) < 1.0 / 350.0:
			i += 1
			continue
		var start := i
		var sum := 0.0
		while i < n and absf(curv[i]) >= 1.0 / 350.0:
			sum += curv[i]
			i += 1
		var outside := 1 if sum > 0.0 else 0          # left-hander -> outside is the right
		var h := fposmod(sin(float(corner) * 12.9898 + float(n) * 0.37) * 43758.5453, 1.0)
		var kind := RUNOFF_GRAVEL if h < gravel_share else RUNOFF_ASPHALT
		# From the braking zone to well past the exit, where cars run wide.
		for k in range(start - 20, i + 45):
			runoff_type[outside][posmod(k, n)] = kind
		for k in range(start - 5, i + 10):
			var inside := 1 - outside
			if runoff_type[inside][posmod(k, n)] == RUNOFF_NONE:
				runoff_type[inside][posmod(k, n)] = RUNOFF_ASPHALT if kind == RUNOFF_ASPHALT else RUNOFF_NONE
		corner += 1


## DRS zones on the long straights: [{"detect": idx, "start": idx, "end": idx}]
var drs_zones: Array = []


func _derive_drs() -> void:
	drs_zones.clear()
	var n := points.size()
	if n == 0:
		return
	# Find straight runs (|curvature| < 1/700 m, smoothed), longest first.
	var straight := PackedByteArray()
	straight.resize(n)
	for i in range(n):
		var worst := 0.0
		for k in range(-6, 7, 3):
			worst = maxf(worst, absf(curv[posmod(i + k, n)]))
		straight[i] = 1 if worst < 1.0 / 250.0 else 0
	# Start the scan in a corner so a straight across the line stays whole.
	var first := 0
	while first < n and straight[first] == 1:
		first += 1
	var runs: Array = []
	var i := 0
	while i < n:
		var a := (first + i) % n
		if straight[a] == 0:
			i += 1
			continue
		var run_len := 0
		while i < n and straight[(first + i) % n] == 1:
			run_len += 1
			i += 1
		runs.append([a, run_len])
	runs.sort_custom(func(x, y): return x[1] > y[1])
	for r in runs:
		var length_m: float = r[1] * SPACING
		if length_m < 420.0 or drs_zones.size() >= 3:
			continue
		var start: int = (int(r[0]) + int(70.0 / SPACING)) % n
		var end: int = (int(r[0]) + int(r[1]) - int(50.0 / SPACING)) % n
		var detect: int = posmod(start - int(140.0 / SPACING), n)
		drs_zones.append({"detect": detect, "start": start, "end": end})


## Index of the DRS zone that sample idx is inside, or -1.
func drs_zone_at(idx: int) -> int:
	var n := points.size()
	for z in range(drs_zones.size()):
		var a: int = drs_zones[z]["start"]
		var b: int = drs_zones[z]["end"]
		if posmod(idx - a, n) <= posmod(b - a, n):
			return z
	return -1


## Surface under a point: 0 track (asphalt/kerb/run-off asphalt), 1 grass,
## 2 gravel. Used by the car physics through race.gd.
func surface_at(idx: int, lat: float) -> int:
	var a := absf(lat)
	if a <= road_half + KERB_W + 1.0:
		return 0
	if runoff_type[0].size() == points.size():
		var kind := runoff_type[1 if lat > 0.0 else 0][idx]
		if kind != RUNOFF_NONE and a <= road_half + KERB_W + 1.0 + runoff_width:
			return 2 if kind == RUNOFF_GRAVEL else 0
	return 1


func _build_road() -> void:
	var n := points.size()
	var kerb := _kerb_mask()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()

	# Alpha = material code for the road shader.
	var asphalt := Color(0.4, 0.4, 0.41, 1.0)
	var white := Color(0.93, 0.93, 0.93, 0.0)
	var red := Color(0.82, 0.12, 0.09, 0.0)
	var verge := _ground_color().lightened(0.2)
	verge.a = 0.0
	if style == "city":
		verge = Color(0.42, 0.42, 0.44, 0.0)
	var black := Color(0.1, 0.1, 0.1, 0.0)
	var gravel := Color(0.78, 0.69, 0.52, 0.66)
	if style == "desert":
		gravel = Color(0.86, 0.74, 0.55, 0.66)
	var runoff := Color(0.47, 0.48, 0.5, 0.33)
	var green_paint := Color(0.16, 0.5, 0.3, 0.0)
	var h := road_half
	var outer := h + KERB_W
	var low := GROUND_Y + 0.012

	for i in range(n):
		var j := (i + 1) % n
		var kc: Color = verge
		if kerb[i]:
			kc = red if int(cum[i] / 3.0) % 2 == 0 else white
		_band(st, faces, i, j, -outer, -h, kc)
		_band(st, faces, i, j, -h, -h + LINE_W, white)
		_band(st, faces, i, j, h - LINE_W, h, white)
		_band(st, faces, i, j, h, outer, kc)
		for side in [-1.0, 1.0]:
			var kind := RUNOFF_NONE
			if runoff_type[0].size() == n:
				kind = runoff_type[1 if side > 0.0 else 0][i]
			var ramp_col: Color = verge
			if kind == RUNOFF_ASPHALT:
				ramp_col = green_paint
			elif kind == RUNOFF_GRAVEL:
				ramp_col = runoff
			# Short ramp down to the surroundings, so rejoining never catches a step.
			if side < 0.0:
				_band(st, faces, i, j, -outer - 1.0, -outer, ramp_col, 0.0, 1.0, low, 0.0)
			else:
				_band(st, faces, i, j, outer, outer + 1.0, ramp_col, 0.0, 1.0, 0.0, low)
			if kind != RUNOFF_NONE:
				var a := outer + 1.0
				var b := outer + 1.0 + runoff_width
				var col: Color = gravel if kind == RUNOFF_GRAVEL else runoff
				if kind == RUNOFF_ASPHALT:
					# Painted strip next to the kerb, then plain run-off.
					var stripe := 1.8
					if side < 0.0:
						_band(st, faces, i, j, -a - stripe, -a, green_paint, 0.0, 1.0, low, low)
						_band(st, faces, i, j, -b, -a - stripe, col, 0.0, 1.0, low, low)
					else:
						_band(st, faces, i, j, a, a + stripe, green_paint, 0.0, 1.0, low, low)
						_band(st, faces, i, j, a + stripe, b, col, 0.0, 1.0, low, low)
				elif side < 0.0:
					_band(st, faces, i, j, -b, -a, col, 0.0, 1.0, low, low)
				else:
					_band(st, faces, i, j, a, b, col, 0.0, 1.0, low, low)
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
		# DRS detection and activation lines (white, across the road).
		for z in drs_zones:
			if i == z["detect"] or i == z["start"]:
				_band(st, faces, i, j, -h + LINE_W, h - LINE_W, Color(0.93, 0.93, 0.93, 0.0), 0.3, 0.45, 0.006, 0.006)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road.gdshader")
	mat.set_shader_parameter("grain", _noise_texture(0.06, Color(0, 0, 0), Color(1, 1, 1)))

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

## Invisible collision boxes along both barrier lines (the visible
## barriers are drawn by Trackside).
func _build_walls() -> void:
	var n := points.size()
	var step := 3
	var body := StaticBody3D.new()
	add_child(body)
	for side in [-1.0, 1.0]:
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
			var basis := Basis.looking_at(-dir / length, Vector3.UP)
			var height := 1.1
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.7, height + 0.6, length + 0.35)
			cs.shape = shape
			cs.transform = Transform3D(basis, mid + Vector3.UP * (GROUND_Y + height * 0.5 + 0.3))
			body.add_child(cs)


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
	lo -= Vector2(220, 220)
	hi += Vector2(220, 220)

	var kinds := {"broad": [], "conifer": [], "palm": []}
	var tints := {"broad": [], "conifer": [], "palm": []}
	var attempts := 1500
	if style == "forest":
		attempts = 3000
	elif style == "desert":
		attempts = 260
	for k in range(attempts):
		var pos := Vector3(rng.randf_range(lo.x, hi.x), GROUND_Y, rng.randf_range(lo.y, hi.y))
		if dist_to_centerline(pos, wall_offset + 14.0) < wall_offset + 7.0:
			continue
		if _reserved(pos, 4.0):
			continue
		var kind := "broad"
		match style:
			"forest":
				kind = "conifer" if rng.randf() < 0.75 else "broad"
			"desert":
				kind = "palm"
			_:
				kind = "broad" if rng.randf() < 0.7 else "conifer"
		var sc := rng.randf_range(0.8, 1.45)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
		kinds[kind].append(Transform3D(b, pos))
		var g := rng.randf()
		tints[kind].append(Color(0.85 + 0.25 * g, 0.9 + 0.15 * g, 0.8 + 0.2 * rng.randf()))
	for kind in kinds:
		if kinds[kind].is_empty():
			continue
		_chunked_multimesh(_tree_mesh(kind), kinds[kind], tints[kind])


## True if pos is inside (or within margin of) any reserved scenery box.
func _reserved(pos: Vector3, margin: float) -> bool:
	for box in scenery_boxes:
		var xf: Transform3D = box["xf"]
		var size: Vector3 = box["size"]
		var local := xf.affine_inverse() * pos
		if absf(local.x) < size.x * 0.5 + margin and absf(local.z) < size.z * 0.5 + margin:
			return true
	return false


static var _tree_cache := {}

## Low-poly tree models: broadleaf, conifer, palm (vertex-coloured, ~150 tris).
static func _tree_mesh(kind: String) -> ArrayMesh:
	if _tree_cache.has(kind):
		return _tree_cache[kind]
	var st := MeshKit.new_tool()
	var up := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO)   # lathe axis X -> Y
	var bark := Color(0.33, 0.24, 0.16)
	match kind:
		"broad":
			MeshKit.lathe(st, [Vector2(0.0, 0.32), Vector2(2.6, 0.22), Vector2(3.4, 0.12)], 6, bark, up)
			var leaf := Color(0.2, 0.42, 0.14)
			MeshKit.ellipsoid(st, Vector3(0, 4.6, 0), Vector3(2.6, 2.2, 2.6), 8, leaf)
			MeshKit.ellipsoid(st, Vector3(1.2, 3.8, 0.6), Vector3(1.8, 1.6, 1.8), 7, leaf.darkened(0.12))
			MeshKit.ellipsoid(st, Vector3(-1.0, 4.0, -0.9), Vector3(1.9, 1.7, 1.9), 7, leaf.lightened(0.06))
			MeshKit.ellipsoid(st, Vector3(-0.2, 6.0, 0.3), Vector3(1.6, 1.4, 1.6), 7, leaf.lightened(0.12))
		"conifer":
			MeshKit.lathe(st, [Vector2(0.0, 0.25), Vector2(1.6, 0.18)], 6, bark, up)
			var needle := Color(0.1, 0.26, 0.12)
			for tier in range(4):
				var y0 := 1.2 + tier * 2.0
				var r := 2.6 - tier * 0.55
				MeshKit.lathe(st, [Vector2(y0, r), Vector2(y0 + 0.3, r * 0.92), Vector2(y0 + 3.0, 0.05)], 8, needle.lightened(tier * 0.05), up)
		"palm":
			var path := []
			for k in range(8):
				var t := k / 7.0
				path.append(Vector3(sin(t * 1.4) * 0.9, t * 7.5, 0))
			MeshKit.tube(st, path, 0.22, 6, Color(0.45, 0.36, 0.24))
			var crown: Vector3 = path[path.size() - 1]
			var frond := Color(0.25, 0.42, 0.14)
			for k in range(8):
				var ang := TAU * k / 8.0
				var dir := Vector3(cos(ang), 0, sin(ang))
				var prev := crown
				for seg in range(4):
					var t := (seg + 1) / 4.0
					var p2: Vector3 = crown + dir * (t * 3.6) + Vector3(0, 0.6 * t - 1.8 * t * t, 0)
					var side := dir.cross(Vector3.UP) * (0.45 * (1.0 - t * 0.6))
					MeshKit._quad(st, prev - side, p2 - side, p2 + side, prev + side, frond)
					MeshKit._quad(st, prev + side, p2 + side, p2 - side, prev - side, frond.darkened(0.15))
					prev = p2
	var mesh := MeshKit.finish(st)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	_tree_cache[kind] = mesh
	return mesh


## MultiMeshes grouped by 300 m cells, so distant groups can be culled.
func _chunked_multimesh(mesh: Mesh, xforms: Array, cols: Array) -> void:
	var cells := {}
	for k in range(xforms.size()):
		var p: Vector3 = xforms[k].origin
		var key := Vector2i(int(floor(p.x / 300.0)), int(floor(p.z / 300.0)))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(k)
	for key in cells:
		var idxs: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = idxs.size()
		for q in range(idxs.size()):
			mm.set_instance_transform(q, xforms[idxs[q]])
			mm.set_instance_color(q, cols[idxs[q]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 1100.0
		mmi.visibility_range_end_margin = 100.0
		add_child(mmi)


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], cols: Array, base: Color, material: Material = null) -> void:
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
	mmi.material_override = material if material != null else mat
	add_child(mmi)


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
			var b := Basis.looking_at(-tangents[i], Vector3.UP)
			var foot := Transform3D(b, p)
			if footprint_clear(foot, Vector3(depth, h, w), wall_offset - road_half - KERB_W + 1.5) and not _reserved(p, maxf(w, depth) * 0.5):
				xforms.append(Transform3D(Basis(b.x * depth, b.y * h, b.z * w), p + Vector3.UP * (GROUND_Y + h * 0.5)))
				cols.append(palette[rng.randi() % palette.size()])
				scenery_boxes.append({"xf": foot, "size": Vector3(depth, h, w)})
			i += int(w / SPACING) + 1
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var facade := ShaderMaterial.new()
	facade.shader = load("res://shaders/building.gdshader")
	_multimesh(box, xforms, cols, Color.WHITE, facade)


## True if a box (unscaled transform + size) stays clear of the road and
## kerbs everywhere on its footprint, by at least `margin` metres.
func footprint_clear(xf: Transform3D, size: Vector3, margin := 1.0) -> bool:
	var limit := road_half + KERB_W + margin
	var nx := maxi(2, int(size.x / 4.0))
	var nz := maxi(2, int(size.z / 4.0))
	for ix in range(nx + 1):
		for iz in range(nz + 1):
			var local := Vector3(size.x * (float(ix) / nx - 0.5), 0.0, size.z * (float(iz) / nz - 0.5))
			if dist_to_centerline(xf * local, limit + 2.0) < limit:
				return false
	return true


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
## centre = true: the same for a car driving the middle of the road
## (tighter than the racing line), used by brake assist when you're off-line.
func speed_profile(spec: Dictionary, centre := false) -> PackedFloat32Array:
	var key: String = String(spec["id"]) + ("|centre" if centre else "")
	if _profiles.has(key):
		return _profiles[key]
	var n := points.size()
	var a0: float = spec["ai_grip"]
	var a1: float = spec["ai_grip_aero"]
	var curv_used := line_curv_safe
	if centre:
		curv_used = PackedFloat32Array()
		curv_used.resize(n)
		for i in range(n):
			var m := 0.0
			for k in range(-8, 9):
				m = maxf(m, absf(curv[posmod(i + k, n)]))
			curv_used[i] = m
	var v := PackedFloat32Array()
	v.resize(n)
	for i in range(n):
		var kk := curv_used[i]
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
