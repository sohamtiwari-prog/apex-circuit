class_name CarBody
extends Node3D
## Builds a car's 3D model procedurally (see MeshKit). The body is merged
## into one mesh with a surface per material, so each car costs only a few
## draw calls; each wheel is one more mesh. Car forward is +Z.

const FENDER_LIFT := 0.13      # extra height of the upper body over the station data
const CABIN_LIFT := 0.13

var helmet: MeshInstance3D
var spec: Dictionary
var _tools := {}
static var _mats := {}
static var _wheel_cache := {}


func build(car_spec: Dictionary, car: RaceCar) -> void:
	spec = car_spec
	if spec["body"] == "gp":
		_build_gp()
	else:
		_build_road()
	var mesh := ArrayMesh.new()
	for key in _tools:
		MeshKit.finish(_tools[key], mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	for w in car.wheels:
		_attach_wheel(w)


## Hide the driver's own helmet when the camera sits inside it.
func set_cockpit_view(on: bool) -> void:
	if helmet != null:
		helmet.visible = not on


func _st(key: String) -> SurfaceTool:
	if not _tools.has(key):
		_tools[key] = MeshKit.new_tool()
	return _tools[key]


static func _material(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match key:
		"paint":
			m.metallic = 0.45
			m.roughness = 0.22
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
		"matte":
			m.metallic = 0.25
			m.roughness = 0.55
		"glass":
			m.metallic = 0.6
			m.roughness = 0.05
		"rubber":
			m.roughness = 0.85
		"metal":
			m.metallic = 0.9
			m.roughness = 0.25
		"head":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.96, 0.88)
			m.emission_energy_multiplier = 1.6
		"tail":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.05, 0.03)
			m.emission_energy_multiplier = 2.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func _stations(rows: Array, bottom_half_width := -1.0) -> Array:
	var out: Array = []
	for r in rows:
		var s := MeshKit.station(r[0], r[1], r[2], r[3], r[4])
		if bottom_half_width > 0.0:
			s["a_bot"] = minf(r[2], bottom_half_width)
		out.append(s)
	return out


# ------------------------------------------------------------ GP car

func _build_gp() -> void:
	var lv: Dictionary = spec["livery"]
	var base: Color = lv["base"]
	var accent: Color = lv["accent"]
	var stripe: Color = lv["stripe"]
	var carbon := Color(0.05, 0.05, 0.06)
	var paint := _st("paint")
	var matte := _st("matte")

	# Nose cone flowing into the survival cell, airbox and engine cover.
	var spine := _stations([
		[2.78, -0.02, 0.07, 0.045, 2.3], [2.55, 0.02, 0.11, 0.07, 2.4], [2.25, 0.07, 0.15, 0.1, 2.5],
		[1.9, 0.12, 0.18, 0.13, 2.6], [1.55, 0.17, 0.22, 0.16, 2.7], [1.2, 0.21, 0.28, 0.19, 2.8],
		[0.9, 0.22, 0.33, 0.21, 3.0], [0.6, 0.2, 0.36, 0.19, 3.0], [0.25, 0.21, 0.37, 0.2, 3.0],
		[0.0, 0.27, 0.34, 0.27, 3.0], [-0.25, 0.38, 0.24, 0.36, 2.6], [-0.55, 0.36, 0.25, 0.31, 2.6],
		[-0.95, 0.3, 0.24, 0.24, 2.6], [-1.35, 0.24, 0.2, 0.18, 2.6], [-1.75, 0.19, 0.15, 0.13, 2.5],
		[-2.15, 0.16, 0.11, 0.1, 2.4], [-2.4, 0.15, 0.07, 0.07, 2.3]])
	MeshKit.loft(paint, spine, 24, func(p: Vector3, th: float) -> Color:
		if absf(p.x) < 0.035 and th > 0.3 and p.z > -0.1:
			return stripe                      # centre stripe along the nose
		if th < -0.4:
			return accent                      # darker underside
		if p.z < -0.6 and th > 0.2 and absf(p.x) < 0.12:
			return accent                      # engine-cover spine
		return base)
	# Airbox intake above the driver's head.
	MeshKit.ellipsoid(matte, Vector3(0, 0.67, -0.04), Vector3(0.11, 0.08, 0.05), 12, carbon)
	# Shark fin.
	MeshKit.box(paint, Vector3(0.02, 0.26, 1.0), Vector3(0, 0.66, -1.35), base, Vector3(-8, 0, 0))

	# Sidepods with a coke-bottle taper.
	for sx in [-1.0, 1.0]:
		var pod := []
		for r in [[0.85, 0.12, 0.17, 0.17, 0.56], [0.55, 0.12, 0.21, 0.19, 0.56], [0.1, 0.11, 0.22, 0.18, 0.54],
				[-0.4, 0.08, 0.2, 0.15, 0.5], [-0.9, 0.05, 0.15, 0.11, 0.45], [-1.4, 0.03, 0.09, 0.07, 0.38], [-1.75, 0.02, 0.05, 0.05, 0.32]]:
			pod.append(MeshKit.station(r[0], r[1], r[2], r[3], 3.0, r[4] * sx))
		MeshKit.loft(paint, pod, 16, func(p: Vector3, th: float) -> Color:
			if p.z > 0.8:
				return carbon                  # inlet
			if absf(th) < 0.5 and p.y > 0.05 and p.y < 0.12:
				return stripe                  # side stripe
			return accent if th < -0.3 else base)
		# Mirror on a stalk.
		MeshKit.ellipsoid(paint, Vector3(0.48 * sx, 0.47, 0.72), Vector3(0.07, 0.035, 0.04), 10, base)
		MeshKit.tube(matte, [Vector3(0.3 * sx, 0.34, 0.74), Vector3(0.44 * sx, 0.46, 0.73)], 0.012, 6, carbon)

	# Floor, plank and diffuser.
	MeshKit.box(matte, Vector3(1.5, 0.025, 3.0), Vector3(0, -0.11, -0.4), carbon)
	MeshKit.box(matte, Vector3(0.3, 0.025, 3.4), Vector3(0, -0.125, -0.2), Color(0.45, 0.35, 0.2))
	for sx in [-1.0, 1.0]:
		MeshKit.box(matte, Vector3(0.02, 0.08, 0.8), Vector3(0.75 * sx, -0.08, 0.7), carbon)
	MeshKit.box(matte, Vector3(1.0, 0.2, 0.42), Vector3(0, -0.03, -2.2), carbon, Vector3(-14, 0, 0))

	# Front wing: main plane and two flaps, endplates.
	MeshKit.airfoil(matte, -0.98, 0.98, -0.1, 2.82, 0.34, 0.1, 0.05, 4.0, carbon)
	MeshKit.airfoil(paint, -0.95, 0.95, -0.06, 2.55, 0.22, 0.1, 0.06, 14.0, accent)
	MeshKit.airfoil(paint, -0.9, 0.9, -0.01, 2.38, 0.17, 0.1, 0.06, 26.0, base)
	for sx in [-1.0, 1.0]:
		MeshKit.box(paint, Vector3(0.025, 0.24, 0.6), Vector3(0.985 * sx, -0.02, 2.55), base)
	# Nose pylons to the wing.
	for sx in [-1.0, 1.0]:
		MeshKit.box(matte, Vector3(0.02, 0.1, 0.25), Vector3(0.07 * sx, -0.03, 2.62), carbon)

	# Rear wing: beam wing, main plane, DRS flap, endplates, swan-neck pylon.
	MeshKit.airfoil(matte, -0.45, 0.45, 0.32, -2.15, 0.2, 0.12, 0.05, 8.0, carbon)
	MeshKit.airfoil(matte, -0.5, 0.5, 0.78, -2.12, 0.3, 0.12, 0.06, 8.0, carbon)
	MeshKit.airfoil(paint, -0.5, 0.5, 0.88, -2.36, 0.22, 0.1, 0.06, 28.0, base)
	for sx in [-1.0, 1.0]:
		MeshKit.box(paint, Vector3(0.025, 0.5, 0.62), Vector3(0.515 * sx, 0.7, -2.32), base)
		MeshKit.box(paint, Vector3(0.026, 0.1, 0.62), Vector3(0.516 * sx, 0.9, -2.32), stripe)
	MeshKit.tube(matte, [Vector3(0, 0.2, -2.05), Vector3(0, 0.55, -2.15), Vector3(0, 0.8, -2.25)], 0.025, 6, carbon)
	MeshKit.box(_st("tail"), Vector3(0.12, 0.08, 0.03), Vector3(0, 0.22, -2.48), Color.WHITE)

	# Halo: hoop from behind the shoulders converging on a centre pillar.
	var halo := []
	for t in range(9):
		var u := float(t) / 8.0
		var ang := lerpf(-PI * 0.5, PI * 0.5, u)
		halo.append(Vector3(sin(ang) * 0.33, 0.7 + cos(ang) * 0.06, -0.02 + cos(ang) * 0.84))
	MeshKit.tube(matte, halo, 0.025, 8, carbon)
	MeshKit.tube(matte, [Vector3(0, 0.76, 0.82), Vector3(0, 0.6, 0.92), Vector3(0, 0.42, 0.96)], 0.025, 8, carbon)

	# Steering wheel with a lit display.
	MeshKit.box(matte, Vector3(0.28, 0.13, 0.03), Vector3(0, 0.45, 0.62), carbon, Vector3(-20, 0, 0))
	MeshKit.box(_st("head"), Vector3(0.1, 0.04, 0.01), Vector3(0, 0.47, 0.603), Color.WHITE, Vector3(-20, 0, 0))

	# Suspension: wishbones and push-rods to each upright.
	for front in [true, false]:
		var z: float = spec["wheel_front_z"] if front else spec["wheel_rear_z"]
		var tw: float = spec["track_front"] if front else spec["track_rear"]
		for sx in [-1.0, 1.0]:
			var outer := Vector3((tw - 0.13) * sx, 0.0, z)
			for yy in [0.3, 0.1]:
				MeshKit.tube(matte, [Vector3(0.28 * sx, yy, z + 0.22), outer + Vector3(0, yy, 0)], 0.016, 5, carbon)
				MeshKit.tube(matte, [Vector3(0.28 * sx, yy, z - 0.22), outer + Vector3(0, yy, 0)], 0.016, 5, carbon)

	# Driver's helmet (separate so the cockpit camera can hide it).
	var hst := MeshKit.new_tool()
	var hcol: Color = lv["helmet"]
	MeshKit.ellipsoid(hst, Vector3(0, 0.53, 0.24), Vector3(0.125, 0.13, 0.14), 16, hcol)
	MeshKit.box(hst, Vector3(0.2, 0.05, 0.05), Vector3(0, 0.55, 0.36), Color(0.02, 0.02, 0.03))
	var hmesh := MeshKit.finish(hst)
	hmesh.surface_set_material(0, _material("paint"))
	helmet = MeshInstance3D.new()
	helmet.mesh = hmesh
	add_child(helmet)


# ------------------------------------------------------------ road cars

func _build_road() -> void:
	var shape: Dictionary = spec["shape"]
	var col: Color = spec["color"]
	var accent: Color = spec["accent"]
	var paint := _st("paint")
	var matte := _st("matte")
	var glass := _st("glass")
	var dark := Color(0.04, 0.04, 0.05)
	# The lower body tucks in under the fenders so the wheels show.
	var inner: float = minf(float(spec["track_front"]), float(spec["track_rear"])) - 0.16
	var body := _stations(shape["body"], inner)
	var two_tone: bool = shape.get("two_tone", false)
	var stripes: bool = shape.get("stripes", false)
	_loft_road(paint, body, 28, func(p: Vector3, th: float) -> Color:
		if th < -0.9:
			return dark                        # underbody
		if stripes and absf(p.x) > 0.1 and absf(p.x) < 0.22 and th > 0.6:
			return Color(0.95, 0.95, 0.95)
		if two_tone and (p.z < 0.6 and p.z > -1.3 and absf(th) < 0.7):
			return accent                      # signature side sweep
		return col)
	var cabin_rows: Array = []
	for r in shape["cabin"]:
		cabin_rows.append([r[0], r[1] + CABIN_LIFT, r[2], r[3], r[4]])
	var cabin := _stations(cabin_rows)
	var glass_col := func(_p: Vector3, _th: float) -> Color:
		return Color(0.06, 0.08, 0.11)
	MeshKit.loft(glass, cabin, 20, glass_col, Transform3D.IDENTITY, false)
	# Painted roof panel over the glass.
	var roof: Array = []
	for r in cabin_rows:
		if r[3] > 0.08:
			roof.append(MeshKit.station(r[0], r[1] + r[3] * 0.92, r[2] * 0.82, 0.03, 2.2))
	if roof.size() >= 2:
		var roof_col := func(_p: Vector3, _th: float) -> Color:
			return col
		MeshKit.loft(paint, roof, 16, roof_col)

	# Lights.
	var ls: Vector3 = shape.get("light_size", Vector3(0.2, 0.06, 0.08))
	for hp in shape.get("headlights", []):
		for sx in [-1.0, 1.0]:
			MeshKit.box(_st("head"), ls, Vector3(hp.x * sx, hp.y + FENDER_LIFT * 0.5, hp.z), Color.WHITE)
	for hp in shape.get("round_lights", []):
		for sx in [-1.0, 1.0]:
			MeshKit.ellipsoid(_st("head"), Vector3(hp.x * sx, hp.y + FENDER_LIFT, hp.z), Vector3(0.11, 0.09, 0.07), 12, Color.WHITE)
	var rows: Array = shape["body"]
	var tail_z: float = rows[rows.size() - 1][0]
	if shape.get("tail_bar", false):
		MeshKit.box(_st("tail"), Vector3(1.4, 0.05, 0.04), Vector3(0, 0.08 + FENDER_LIFT * 0.6, tail_z - 0.01), Color.WHITE)
	for tp in shape.get("tails", []):
		for sx in [-1.0, 1.0]:
			MeshKit.box(_st("tail"), Vector3(0.3, 0.07, 0.04), Vector3(tp.x * sx, tp.y + FENDER_LIFT * 0.6, tp.z), Color.WHITE)
	if shape.get("grille", false):
		MeshKit.ellipsoid(matte, Vector3(0, -0.06, 2.22), Vector3(0.18, 0.14, 0.05), 14, Color(0.2, 0.2, 0.22))
	# Side intakes behind the doors.
	if shape.get("intakes", false):
		for sx in [-1.0, 1.0]:
			MeshKit.ellipsoid(matte, Vector3(0.9 * sx, 0.02, -0.65), Vector3(0.06, 0.12, 0.35), 10, dark)
	# Diffuser / exhausts.
	MeshKit.box(matte, Vector3(1.4, 0.12, 0.3), Vector3(0, -0.26, tail_z + 0.1), dark)
	for sx in [-0.25, 0.25]:
		MeshKit.lathe(_st("metal"), [Vector2(-0.12, 0.05), Vector2(0.12, 0.05)], 10, Color(0.6, 0.6, 0.62),
			Transform3D(Basis(Vector3.UP, PI / 2), Vector3(sx, -0.2, tail_z - 0.02)))
	# Rear wing.
	if shape.has("wing"):
		var w: Dictionary = shape["wing"]
		var wy: float = float(w["y"]) + FENDER_LIFT
		MeshKit.airfoil(matte, -w["span"], w["span"], wy, w["z"], w["chord"], 0.12, 0.05, w["aoa"], dark)
		for sx in [-1.0, 1.0]:
			MeshKit.box(matte, Vector3(0.04, 0.2, 0.14), Vector3(w["span"] * 0.6 * sx, wy - 0.1, w["z"] - 0.1), dark)


## Loft with a narrower bottom half (a_bot) for wheel arches.
func _loft_road(st: SurfaceTool, stations: Array, seg: int, color_fn: Callable) -> void:
	var tops: Array = []
	var bots: Array = []
	for s in stations:
		var t: Dictionary = s.duplicate()
		# Fenders and shoulders sit above the tyres, as on a real car.
		t["b"] = float(s["b"]) + FENDER_LIFT
		tops.append(t)
		var b: Dictionary = s.duplicate()
		b["a"] = s.get("a_bot", s["a"])
		bots.append(b)
	# Build the upper half at full width and the lower half tucked in; the
	# two halves meet at the station centre line.
	_half_loft(st, tops, seg, color_fn, true)
	_half_loft(st, bots, seg, color_fn, false)


func _half_loft(st: SurfaceTool, stations: Array, seg: int, color_fn: Callable, upper: bool) -> void:
	var half := seg / 2
	var rings: Array = []
	var thetas: Array = []
	for k in range(half + 1):
		var th := PI * k / half
		thetas.append(th if upper else -th)
	for s in stations:
		var ring := PackedVector3Array()
		for th in thetas:
			var c := cos(th)
			var sn := sin(th)
			var n: float = s["n"]
			var x: float = s["a"] * signf(c) * pow(absf(c), 2.0 / n)
			var y: float = s["b"] * signf(sn) * pow(absf(sn), 2.0 / n)
			ring.append(Vector3(x, s["y"] + y, s["z"]))
		rings.append(ring)
	for r in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[r]
		var r1: PackedVector3Array = rings[r + 1]
		for k in range(half):
			var th: float = (thetas[k] + thetas[k + 1]) * 0.5
			var c: Color = color_fn.call((r0[k] + r1[k + 1]) * 0.5, th)
			if upper:
				MeshKit._quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], c)
			else:
				MeshKit._quad(st, r0[k], r1[k], r1[k + 1], r0[k + 1], c)
	# The side gap between a wide top and a tucked-in bottom: a flat sill.
	if not upper:
		return
	for end in [0, rings.size() - 1]:
		var ring: PackedVector3Array = rings[end]
		var centre := Vector3(0, stations[end]["y"], stations[end]["z"])
		var c: Color = color_fn.call(centre, 0.5)
		for k in range(half):
			if end == 0:
				MeshKit._tri(st, centre, ring[k + 1], ring[k], c)
			else:
				MeshKit._tri(st, centre, ring[k], ring[k + 1], c)


# ------------------------------------------------------------ wheels

func _attach_wheel(w: CarWheel) -> void:
	var front := w.use_as_steering
	var r: float = w.wheel_radius
	var width: float = spec["tyre_width_front"] if front else spec["tyre_width_rear"]
	var gp: bool = spec["body"] == "gp"
	var key := "%s|%.3f|%.3f|%s" % [spec["id"], r, width, gp]
	var mesh: ArrayMesh
	if _wheel_cache.has(key):
		mesh = _wheel_cache[key]
	else:
		mesh = _wheel_mesh(r, width, gp)
		_wheel_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# The rim face is built on +X; turn left-side wheels around so it faces out.
	if w.position.x < 0.0:
		mi.rotation.y = PI
	w.add_child(mi)


static func _wheel_mesh(r: float, width: float, gp: bool) -> ArrayMesh:
	var hw := width * 0.5
	var rim_r := r * (0.6 if gp else 0.66)
	var rubber := MeshKit.new_tool()
	var tyre := Color(0.05, 0.05, 0.05)
	# Tyre cross-section: bead, sidewall, rounded shoulder, tread.
	var prof := [Vector2(hw, rim_r), Vector2(hw + 0.005, r * 0.82), Vector2(hw, r - 0.035),
		Vector2(hw - 0.02, r - 0.008), Vector2(hw - 0.05, r), Vector2(-hw + 0.05, r),
		Vector2(-hw + 0.02, r - 0.008), Vector2(-hw, r - 0.035), Vector2(-hw - 0.005, r * 0.82), Vector2(-hw, rim_r)]
	MeshKit.lathe(rubber, prof, 28, tyre)
	var metal := MeshKit.new_tool()
	var rim_col := Color(0.12, 0.12, 0.13) if gp else Color(0.72, 0.73, 0.75)
	# Outer rim face (dished), barrel, inner face.
	MeshKit.lathe(metal, [Vector2(hw - 0.01, rim_r), Vector2(hw - 0.03, rim_r * 0.55), Vector2(hw - 0.06, 0.04), Vector2(hw - 0.06, 0.0)], 20, rim_col)
	MeshKit.lathe(metal, [Vector2(-hw + 0.01, rim_r), Vector2(hw - 0.01, rim_r)], 20, rim_col.darkened(0.3))
	# Spokes, so the wheel visibly turns.
	for k in range(5 if not gp else 10):
		var ang := TAU * k / (5 if not gp else 10)
		var b := Basis(Vector3.RIGHT, ang)
		MeshKit.box(metal, Vector3(0.02, rim_r * 0.9, 0.035), Vector3(hw - 0.035, 0, 0) + b * Vector3(0, rim_r * 0.5, 0), rim_col, Vector3(rad_to_deg(ang), 0, 0))
	MeshKit.lathe(metal, [Vector2(hw - 0.02, 0.06), Vector2(hw - 0.0, 0.0)], 10, Color(0.6, 0.6, 0.62))
	if gp:
		# Compound marking (red = soft) on the sidewall.
		MeshKit.lathe(rubber, [Vector2(hw + 0.007, r * 0.74), Vector2(hw + 0.007, r * 0.79)], 28, Color(0.9, 0.08, 0.08))
		MeshKit.lathe(rubber, [Vector2(-hw - 0.007, r * 0.79), Vector2(-hw - 0.007, r * 0.74)], 28, Color(0.9, 0.08, 0.08))
	var mesh := MeshKit.finish(rubber)
	mesh.surface_set_material(0, _material("rubber"))
	MeshKit.finish(metal, mesh)
	mesh.surface_set_material(1, _material("metal"))
	return mesh
