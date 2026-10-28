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
var _tail_mat: StandardMaterial3D
var _brake_level := -1.0


## Brake lights: brighter while braking. The GP car's rear light flashes
## (as it does on a real car when the hybrid system is harvesting).
func set_brake_lights(braking: bool, t: float) -> void:
	if _tail_mat == null:
		return
	var level := 2.0
	if braking:
		level = 9.0
		if spec["body"] == "gp" and fmod(t, 0.25) < 0.12:
			level = 1.0
	if level != _brake_level:
		_brake_level = level
		_tail_mat.emission_energy_multiplier = level


func build(car_spec: Dictionary, car: RaceCar) -> void:
	spec = car_spec
	if spec["body"] == "gp":
		_build_gp()
	else:
		_build_road()
	var mesh := ArrayMesh.new()
	var tail_surface := -1
	for key in _tools:
		MeshKit.finish(_tools[key], mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key))
		if key == "tail":
			tail_surface = mesh.get_surface_count() - 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	# This car's own tail-light material, so its brake lights are its own.
	if tail_surface >= 0:
		_tail_mat = (_material("tail") as StandardMaterial3D).duplicate()
		mi.set_surface_override_material(tail_surface, _tail_mat)
	for w in car.wheels:
		_attach_wheel(w)
	_blob_shadow()
	if spec["body"] == "gp":
		_gp_decals()
		set_number(int(spec.get("number", 26)))


## A soft dark patch under the car: grounds it at any distance (sun shadows
## only reach so far) and under cloud.
func _blob_shadow() -> void:
	var q := QuadMesh.new()
	var w := maxf(float(spec["track_front"]), float(spec["track_rear"])) * 2.0 + 0.7
	var l := float(spec["wheel_front_z"]) - float(spec["wheel_rear_z"]) + 1.9
	q.size = Vector2(w, l)
	q.material = _shadow_mat()
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.rotation.x = -PI / 2
	mi.position = Vector3(0, float(spec["wheel_y"]) - float(spec["rest_length"]) - float(spec["radius_rear"]) + 0.035, (float(spec["wheel_front_z"]) + float(spec["wheel_rear_z"])) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static var _shadow_m: StandardMaterial3D

static func _shadow_mat() -> StandardMaterial3D:
	if _shadow_m != null:
		return _shadow_m
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0.55)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	g.width = 64
	g.height = 64
	m.albedo_texture = g
	_shadow_m = m
	return m


const SPONSORS := ["KESTREL OIL", "VOLTRA", "ORBIS TELECOM", "AURUM", "NORTHWIND", "FALCO", "MERIDIAN", "HALCYON", "TRIDENT BANK", "SOLACE"]

var _numbers: Array = []

## Sponsor names on the sidepods, engine cover and rear wing (GP liveries).
func _gp_decals() -> void:
	var lv: Dictionary = spec["livery"]
	var ti := CarSpecs.TEAMS.find(lv)
	var main: String = SPONSORS[posmod(ti, SPONSORS.size())]
	var second: String = SPONSORS[posmod(ti + 3, SPONSORS.size())]
	var ink: Color = lv["accent"] if Color(lv["base"]).get_luminance() > 0.45 else Color(0.97, 0.97, 0.98)
	for sx in [-1.0, 1.0]:
		_decal(main, Vector3(0.765 * sx, 0.13, 0.05), Vector3(0, PI / 2 * sx, 0), 0.0022, ink, 52)
		_decal(second, Vector3(0.255 * sx, 0.36, -0.78), Vector3(0, PI / 2 * sx, 0), 0.0017, ink, 40)
	_decal(main, Vector3(0, 0.86, -2.47), Vector3(0, PI, 0), 0.0024, ink, 48)
	_decal(second, Vector3(0, 0.255, 1.7), Vector3(-PI / 2 + 0.28, 0, 0), 0.0014, ink, 40)


func _decal(text: String, pos: Vector3, rot: Vector3, px: float, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UIStyle.font("extrabold", true)
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation = rot
	l.double_sided = false
	l.visibility_range_end = 55.0
	add_child(l)
	return l


## Race number on the nose and the engine cover.
func set_number(n: int) -> void:
	if spec["body"] != "gp":
		return
	for l in _numbers:
		l.queue_free()
	_numbers.clear()
	var lv: Dictionary = spec["livery"]
	var ink: Color = Color(0.97, 0.97, 0.98) if Color(lv["base"]).get_luminance() < 0.6 else Color(0.06, 0.06, 0.08)
	_numbers.append(_decal(str(n), Vector3(0, 0.2, 2.15), Vector3(-PI / 2 + 0.22, 0, 0), 0.0026, ink, 64))
	for sx in [-1.0, 1.0]:
		_numbers.append(_decal(str(n), Vector3(0.025 * sx, 0.66, -1.35), Vector3(0, PI / 2 * sx, 0), 0.003, ink, 64))


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
			# Carbon fibre: a fine twill weave, mapped without UVs.
			m.metallic = 0.3
			m.roughness = 0.42
			m.albedo_texture = _weave()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(14, 14, 14)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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


static var _weave_tex: ImageTexture

## 2x2 twill carbon weave, light enough to keep the vertex colour.
static func _weave() -> ImageTexture:
	if _weave_tex != null:
		return _weave_tex
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var band := ((x / 2 + y / 2) % 4) < 2
			var along := float((x if band else y) % 4) / 3.0
			var v := 0.78 + 0.22 * (0.5 + 0.5 * sin(along * PI)) * (1.0 if band else 0.85)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_weave_tex = ImageTexture.create_from_image(img)
	return _weave_tex


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
	# Airbox intake above the driver's head, and the T-cam on top.
	MeshKit.ellipsoid(matte, Vector3(0, 0.67, -0.04), Vector3(0.11, 0.08, 0.05), 12, carbon)
	MeshKit.box(matte, Vector3(0.09, 0.035, 0.07), Vector3(0, 0.765, -0.06), Color(0.95, 0.8, 0.05) if CarSpecs.TEAMS.find(lv) % 2 == 1 else Color(0.06, 0.06, 0.07))
	# Exhaust under the rear wing.
	MeshKit.lathe(_st("metal"), [Vector2(-0.1, 0.045), Vector2(0.1, 0.045)], 10, Color(0.55, 0.5, 0.45),
		Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0.2, -2.32)))
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
	var dark := Color(0.035, 0.035, 0.04)
	var two_tone: bool = shape.get("two_tone", false)
	var stripes: bool = shape.get("stripes", false)
	var color_fn := func(p: Vector3, th: float) -> Color:
		if stripes and absf(p.x) > 0.1 and absf(p.x) < 0.22 and th > 0.6:
			return Color(0.95, 0.95, 0.95)
		if two_tone and (p.z < 0.6 and p.z > -1.3 and absf(th) < 0.7):
			return accent                      # signature side sweep
		return col
	_road_shell(paint, matte, shape["body"], color_fn, dark)
	_greenhouse(shape["cabin"], col)
	_road_details(shape, col, dark)

## Lights, grille, intakes, diffuser, exhausts, wing.
func _road_lights(shape: Dictionary, matte: SurfaceTool, dark: Color) -> void:
	var ls: Vector3 = shape.get("light_size", Vector3(0.2, 0.06, 0.08))
	var rows: Array = shape["body"]
	# Headlights sit in the nose surface: a dark housing with the lamp in it.
	for hp in shape.get("headlights", []):
		for sx in [-1.0, 1.0]:
			var y := _surface_y(rows, hp.z, hp.x) - ls.y * 0.25
			MeshKit.box(matte, ls + Vector3(0.04, 0.03, 0.02), Vector3(hp.x * sx, y - 0.005, hp.z - 0.01), dark, Vector3(-12, 0, 0))
			MeshKit.box(_st("head"), ls, Vector3(hp.x * sx, y, hp.z), Color.WHITE, Vector3(-12, 0, 0))
	for hp in shape.get("round_lights", []):
		for sx in [-1.0, 1.0]:
			var y := _surface_y(rows, hp.z, hp.x) - 0.03
			MeshKit.ellipsoid(_st("head"), Vector3(hp.x * sx, y, hp.z), Vector3(0.11, 0.09, 0.07), 12, Color.WHITE)
	var tail_z: float = rows[rows.size() - 1][0]
	var tail := _shell_ring(rows, tail_z + 0.02)
	var tail_y: float = float(tail["shoulder"]) - 0.03
	if shape.get("tail_bar", false):
		MeshKit.box(_st("tail"), Vector3(float(tail["width"]) * 1.7, 0.05, 0.04), Vector3(0, tail_y, tail_z + 0.005), Color.WHITE)
	for tp in shape.get("tails", []):
		for sx in [-1.0, 1.0]:
			MeshKit.box(_st("tail"), Vector3(0.3, 0.07, 0.04), Vector3(minf(tp.x, float(tail["width"]) - 0.18) * sx, tail_y, tail_z + 0.005), Color.WHITE)
	if shape.get("grille", false):
		MeshKit.ellipsoid(matte, Vector3(0, -0.06, 2.22), Vector3(0.18, 0.14, 0.05), 14, Color(0.2, 0.2, 0.22))
	# Side intakes behind the doors.
	if shape.get("intakes", false):
		for sx in [-1.0, 1.0]:
			MeshKit.ellipsoid(matte, Vector3(0.9 * sx, 0.02, -0.65), Vector3(0.06, 0.12, 0.35), 10, dark)
	# Diffuser / exhausts.
	var tb: float = tail["bottom"]
	MeshKit.box(matte, Vector3(1.4, 0.12, 0.3), Vector3(0, tb + 0.04, tail_z + 0.12), dark)
	for sx in [-0.25, 0.25]:
		MeshKit.lathe(_st("metal"), [Vector2(-0.12, 0.05), Vector2(0.12, 0.05)], 10, Color(0.6, 0.6, 0.62),
			Transform3D(Basis(Vector3.UP, PI / 2), Vector3(sx, tb + 0.1, tail_z - 0.02)))
	# Rear wing.
	if shape.has("wing"):
		var w: Dictionary = shape["wing"]
		var wy: float = float(w["y"]) + FENDER_LIFT
		MeshKit.airfoil(matte, -w["span"], w["span"], wy, w["z"], w["chord"], 0.12, 0.05, w["aoa"], dark)
		for sx in [-1.0, 1.0]:
			MeshKit.box(matte, Vector3(0.04, 0.2, 0.14), Vector3(w["span"] * 0.6 * sx, wy - 0.1, w["z"] - 0.1), dark)



## Interpolates the spec's body stations at depth z: [y, half_width, half_height, n].
static func _row_at(rows: Array, z: float) -> Array:
	if z >= float(rows[0][0]):
		return [rows[0][1], rows[0][2], rows[0][3], rows[0][4]]
	for i in range(rows.size() - 1):
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		if z <= float(a[0]) and z >= float(b[0]):
			var t := (float(a[0]) - z) / maxf(float(a[0]) - float(b[0]), 0.001)
			return [lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t), lerpf(a[4], b[4], t)]
	var l: Array = rows[rows.size() - 1]
	return [l[1], l[2], l[3], l[4]]


const SHELL_UPPER := 9

## One cross-section of the road-car shell at depth z (right half, roof
## centre first): {ring, shoulder, width, top, bottom}.
func _shell_ring(rows: Array, z: float) -> Dictionary:
	var wy := float(spec["wheel_y"]) - float(spec["rest_length"]) * 0.75
	var arches := [[float(spec["wheel_front_z"]), float(spec["radius_front"]) + 0.07, float(spec["track_front"])],
		[float(spec["wheel_rear_z"]), float(spec["radius_rear"]) + 0.07, float(spec["track_rear"])]]
	var upper := SHELL_UPPER
	var r := _row_at(rows, z)
	var yc: float = r[0]
	var w: float = r[1]
	var top_c: float = yc + float(r[2]) + FENDER_LIFT        # hood / roof centre line
	var bot: float = yc - float(r[2])
	var nn: float = r[3]
	var shoulder: float = yc + (float(r[2]) + FENDER_LIFT) * 0.45
	var edge := bot + 0.07
	var arch_w := 0.0
	var inner := w * 0.85
	for a in arches:
		var dz := absf(z - float(a[0]))
		if dz < float(a[1]):
			var ay := wy + sqrt(float(a[1]) * float(a[1]) - dz * dz)
			# Fenders rise over the tyres (above the hood on low cars).
			shoulder = maxf(shoulder, ay + 0.05)
			if ay > edge:
				arch_w = maxf(arch_w, clampf((ay - edge) / 0.06, 0.0, 1.0))
				edge = ay
				inner = minf(inner, float(a[2]) - float(spec["tyre_width_rear"]) * 0.5 - 0.05)
	edge = minf(edge, shoulder - 0.04)
	var flare := 0.03 * arch_w
	var ring := PackedVector3Array()
	# Upper: from the shoulder (widest) across to the hood/roof centre;
	# where the fenders stand above the hood it dips between them.
	for k in upper + 1:
		var th := PI * 0.5 * float(k) / upper
		var c := cos(th)
		var sn := sin(th)
		ring.append(Vector3((w + flare) * pow(c, 2.0 / nn), shoulder + (top_c - shoulder) * pow(sn, 2.0 / nn), z))
	ring.reverse()                         # roof centre first, down to the side
	# Lower: the slab side down to the sill (or the arch), then under.
	ring.append(Vector3((w + flare) * 0.995, lerpf(shoulder, edge, 0.5), z))
	ring.append(Vector3((w + flare) * 0.975, edge, z))
	ring.append(Vector3(lerpf(w * 0.93, inner, arch_w), edge - 0.01 * (1.0 - arch_w), z))
	ring.append(Vector3(lerpf(w * 0.85, inner, arch_w), bot, z))
	ring.append(Vector3(0.0, bot, z))
	return {"ring": ring, "shoulder": shoulder, "width": w + flare, "top": top_c, "bottom": bot}


## Height of the shell's upper surface at (x, z).
func _surface_y(rows: Array, z: float, x: float) -> float:
	var ring: PackedVector3Array = _shell_ring(rows, z)["ring"]
	x = absf(x)
	for k in SHELL_UPPER:
		var a := ring[k]
		var b := ring[k + 1]
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.0001))
	return ring[SHELL_UPPER].y


## The body shell, sampled finely along the car: rounded shoulders, slab
## sides, and real wheel arches (the sides rise over each tyre, with a dark
## wheel well behind), slightly flared round the wheels.
func _road_shell(paint: SurfaceTool, matte: SurfaceTool, rows: Array, color_fn: Callable, dark: Color) -> void:
	var z0 := float(rows[0][0])
	var z1 := float(rows[rows.size() - 1][0])
	var wy := float(spec["wheel_y"]) - float(spec["rest_length"]) * 0.75
	var arches := [[float(spec["wheel_front_z"]), float(spec["radius_front"]) + 0.07, float(spec["track_front"])],
		[float(spec["wheel_rear_z"]), float(spec["radius_rear"]) + 0.07, float(spec["track_rear"])]]
	var n_st := 64
	var upper := SHELL_UPPER
	var rings: Array = []
	for i in n_st + 1:
		rings.append(_shell_ring(rows, lerpf(z0, z1, float(i) / n_st))["ring"])
	var m := (rings[0] as PackedVector3Array).size()
	for side in [1.0, -1.0]:
		for i in range(rings.size() - 1):
			var r0: PackedVector3Array = rings[i]
			var r1: PackedVector3Array = rings[i + 1]
			for k in range(m - 1):
				var a := r0[k] * Vector3(side, 1, 1)
				var b := r0[k + 1] * Vector3(side, 1, 1)
				var c := r1[k + 1] * Vector3(side, 1, 1)
				var d := r1[k] * Vector3(side, 1, 1)
				var mid := (a + c) * 0.5
				var under := k >= upper + 2
				var th := PI * 0.5 * (1.0 - float(mini(k, upper)) / upper) if k <= upper else -0.3
				var colr: Color = dark if under else color_fn.call(mid, th)
				var st := matte if under else paint
				if side > 0.0:
					MeshKit._quad(st, a, d, c, b, colr)
				else:
					MeshKit._quad(st, a, b, c, d, colr)
		# Nose and tail: close the ends.
		for end in [0, rings.size() - 1]:
			var ring: PackedVector3Array = rings[end]
			var centre := Vector3(0, (ring[0].y + ring[m - 1].y) * 0.5, ring[0].z)
			for k in range(m - 1):
				var a := ring[k] * Vector3(side, 1, 1)
				var b := ring[k + 1] * Vector3(side, 1, 1)
				var colr: Color = dark if k >= upper + 2 else color_fn.call(centre, 0.5)
				if (end == 0) == (side > 0.0):
					MeshKit._tri(paint, centre, a, b, colr)
				else:
					MeshKit._tri(paint, centre, b, a, colr)


## Windscreen, side windows and rear glass with a painted roof and pillars,
## and a black seal along the bottom of the glass.
func _greenhouse(cabin: Array, col: Color) -> void:
	var glass := _st("glass")
	var paint := _st("paint")
	var matte := _st("matte")
	var stations: Array = []
	for r in cabin:
		stations.append([float(r[0]), float(r[1]) + CABIN_LIFT, float(r[2]), float(r[3]), float(r[4])])
	var seg := 10
	var rings: Array = []
	for s in stations:
		var ring := PackedVector3Array()
		for k in seg + 1:
			var th := PI * float(k) / seg           # 0 = right side .. PI = left side
			var c := cos(th)
			var sn := sin(th)
			var n: float = s[4]
			ring.append(Vector3(float(s[2]) * signf(c) * pow(absf(c), 2.0 / n), float(s[1]) + float(s[3]) * pow(sn, 2.0 / n), float(s[0])))
		rings.append(ring)
	var trim := Color(0.03, 0.03, 0.035)
	for i in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for k in seg:
			var th := PI * (float(k) + 0.5) / seg
			var side_ang := minf(th, PI - th)          # 0 at the beltline, PI/2 on the roof
			var a := r0[k]
			var b := r0[k + 1]
			var c := r1[k + 1]
			var d := r1[k]
			if side_ang > 1.12:
				MeshKit._quad(paint, a, b, c, d, col)          # roof
			elif side_ang < 0.2:
				MeshKit._quad(matte, a, b, c, d, trim)         # window seal
			elif (i == 0 or i == rings.size() - 2) and side_ang < 0.95 and side_ang > 0.2 and false:
				MeshKit._quad(paint, a, b, c, d, col)
			else:
				MeshKit._quad(glass, a, b, c, d, Color(0.05, 0.065, 0.085))
	# A pillars and a B pillar: thin painted strips over the glass edge.
	var r_front: PackedVector3Array = rings[0]
	var r_mid: PackedVector3Array = rings[int(rings.size() / 2)]
	for sx in [1, -1]:
		var k0 := 1 if sx > 0 else seg - 1
		var kmax := int(seg * 0.4) if sx > 0 else int(seg * 0.6)
		var pa: Array = []
		var pb: Array = []
		var step := 1 if sx > 0 else -1
		var k := k0
		while (sx > 0 and k <= kmax) or (sx < 0 and k >= kmax):
			pa.append(r_front[k] + Vector3(0, 0.004, -0.02))
			pb.append(r_mid[k] + Vector3(0, 0.004, 0.0))
			k += step
		MeshKit.tube(matte, pa, 0.028, 5, trim)
		MeshKit.tube(paint, pb, 0.022, 5, col)


## Mirrors, splitter, side skirts, number plates, then lights and the rest.
func _road_details(shape: Dictionary, col: Color, dark: Color) -> void:
	var matte := _st("matte")
	var paint := _st("paint")
	var cabin: Array = shape["cabin"]
	var rows: Array = shape["body"]
	var front := float(rows[0][0])
	var rear := float(rows[rows.size() - 1][0])
	# Door mirrors at the base of the windscreen.
	var cz := float(cabin[0][0]) - 0.22
	var sh := _shell_ring(rows, cz)
	var belt: float = maxf(float(cabin[0][1]) + CABIN_LIFT, float(sh["shoulder"])) + 0.08
	for sx in [-1.0, 1.0]:
		var mx: float = float(cabin[0][2]) * sx
		MeshKit.ellipsoid(paint, Vector3(mx + 0.17 * sx, belt + 0.05, cz), Vector3(0.1, 0.055, 0.05), 10, col)
		MeshKit.box(matte, Vector3(0.14, 0.025, 0.05), Vector3(mx + 0.07 * sx, belt + 0.02, cz + 0.01), dark)
	# Front splitter and side skirts.
	var fr := _row_at(rows, front - 0.15)
	MeshKit.box(matte, Vector3(float(fr[1]) * 1.8, 0.025, 0.25), Vector3(0, float(fr[0]) - float(fr[2]) - 0.01, front - 0.18), dark)
	var mid_z := (float(spec["wheel_front_z"]) + float(spec["wheel_rear_z"])) * 0.5
	var span := (float(spec["wheel_front_z"]) - float(spec["wheel_rear_z"])) - float(spec["radius_front"]) * 2.4
	var mr := _row_at(rows, mid_z)
	for sx in [-1.0, 1.0]:
		MeshKit.box(matte, Vector3(0.05, 0.06, span), Vector3((float(mr[1]) * 0.96) * sx, float(mr[0]) - float(mr[2]) + 0.02, mid_z), dark)
	# Number plates: white panels with the car's registration.
	var plate := _st("matte")
	var fz := front + 0.005
	var rz := rear - 0.005
	var fy := float(fr[0]) - float(fr[2]) * 0.35
	var rr := _row_at(rows, rear + 0.1)
	var ry := float(rr[0]) - float(rr[2]) * 0.1 + FENDER_LIFT * 0.3
	MeshKit.box(plate, Vector3(0.5, 0.12, 0.02), Vector3(0, fy, fz), Color(0.92, 0.92, 0.9))
	MeshKit.box(plate, Vector3(0.5, 0.12, 0.02), Vector3(0, ry, rz), Color(0.92, 0.92, 0.9))
	_plate_text(Vector3(0, fy, fz + 0.012), false)
	_plate_text(Vector3(0, ry, rz - 0.012), true)
	_road_lights(shape, matte, dark)


func _plate_text(pos: Vector3, rear: bool) -> void:
	var l := Label3D.new()
	l.text = "AC " + String(spec["id"]).substr(0, 2).to_upper() + " 26"
	l.font = UIStyle.font("bold", false)
	l.font_size = 36
	l.pixel_size = 0.0022
	l.modulate = Color(0.08, 0.08, 0.1)
	l.outline_size = 0
	l.position = pos
	l.double_sided = false
	l.no_depth_test = false
	if rear:
		l.rotation.y = PI
	l.visibility_range_end = 40.0
	add_child(l)


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

var _wheel_mis: Array = []


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
	_wheel_mis.append(mi)
	# Brake caliper (painted, doesn't turn with the wheel).
	var cal := Node3D.new()
	w.add_child(cal)
	w.caliper = cal
	var cst := MeshKit.new_tool()
	var hw := width * 0.5
	var rim_r := r * (0.6 if gp else 0.66)
	var side := 1.0 if w.position.x >= 0.0 else -1.0
	var cal_col: Color = spec.get("caliper", Color(0.85, 0.08, 0.06) if not gp else Color(0.08, 0.08, 0.09))
	var cx := (hw - 0.09) * side
	MeshKit.box(cst, Vector3(0.06, rim_r * 0.42, rim_r * 0.3), Vector3(cx, rim_r * 0.55, -rim_r * 0.2), cal_col, Vector3(-25, 0, 0))
	var cm := MeshKit.finish(cst)
	cm.surface_set_material(0, _material("paint"))
	var cmi := MeshInstance3D.new()
	cmi.mesh = cm
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cal.add_child(cmi)


## Colours the tyres' sidewall band (GP cars: the compound's colour).
func set_compound_color(c: Color) -> void:
	if spec.get("body", "") != "gp":
		return
	var m := _band_mat(c)
	for mi in _wheel_mis:
		if is_instance_valid(mi) and (mi as MeshInstance3D).mesh.get_surface_count() > 2:
			(mi as MeshInstance3D).set_surface_override_material(2, m)


static var _band_mats := {}

static func _band_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _band_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_band_mats[key] = m
	return _band_mats[key]


static func _wheel_mesh(r: float, width: float, gp: bool) -> ArrayMesh:
	var hw := width * 0.5
	var rim_r := r * (0.6 if gp else 0.68)
	var rubber := MeshKit.new_tool()
	var tyre := Color(0.045, 0.045, 0.048)
	# Tyre cross-section: bead, sidewall, rounded shoulder, tread.
	var prof := [Vector2(hw - 0.004, rim_r), Vector2(hw + 0.006, rim_r + (r - rim_r) * 0.45), Vector2(hw + 0.002, r - 0.03),
		Vector2(hw - 0.018, r - 0.007), Vector2(hw - 0.045, r), Vector2(-hw + 0.045, r),
		Vector2(-hw + 0.018, r - 0.007), Vector2(-hw - 0.002, r - 0.03), Vector2(-hw - 0.006, rim_r + (r - rim_r) * 0.45), Vector2(-hw + 0.004, rim_r)]
	MeshKit.lathe(rubber, prof, 32, tyre)
	var metal := MeshKit.new_tool()
	var rim_col := Color(0.1, 0.1, 0.11) if gp else Color(0.64, 0.65, 0.68)
	var lip := hw - 0.012
	# Rim lip, barrel, and the brake disc behind the spokes.
	MeshKit.lathe(metal, [Vector2(lip + 0.004, rim_r + 0.008), Vector2(lip, rim_r - 0.012)], 32, rim_col.lightened(0.15))
	MeshKit.lathe(metal, [Vector2(-hw + 0.01, rim_r - 0.005), Vector2(lip, rim_r - 0.012)], 24, rim_col.darkened(0.45))
	var disc := Color(0.33, 0.32, 0.31)
	MeshKit.lathe(metal, [Vector2(hw - 0.1, rim_r * 0.82), Vector2(hw - 0.1, rim_r * 0.35)], 24, disc)
	MeshKit.lathe(metal, [Vector2(hw - 0.08, rim_r * 0.35), Vector2(hw - 0.08, rim_r * 0.82)], 24, disc)
	if gp:
		# Wheel cover: a flat carbon disc with a ring and a centre nut.
		MeshKit.lathe(metal, [Vector2(lip - 0.01, rim_r - 0.01), Vector2(lip - 0.025, rim_r * 0.3), Vector2(lip - 0.02, 0.0)], 32, Color(0.07, 0.07, 0.08))
		MeshKit.lathe(metal, [Vector2(lip - 0.005, rim_r * 0.8), Vector2(lip - 0.005, rim_r * 0.72)], 32, Color(0.75, 0.75, 0.78))
		MeshKit.lathe(metal, [Vector2(lip, 0.05), Vector2(lip + 0.02, 0.0)], 12, Color(0.85, 0.65, 0.1))
	else:
		# Five double spokes from a dished centre to the lip.
		var face := lip - 0.02
		for k in 10:
			var ang := TAU * (k / 2) / 5.0 + (0.11 if k % 2 == 0 else -0.11)
			var b := Basis(Vector3.RIGHT, ang)
			var p0 := Vector3(face - 0.03, 0, 0) + b * Vector3(0, rim_r * 0.22, 0)
			var p1 := Vector3(face, 0, 0) + b * Vector3(0, rim_r * 0.97, 0)
			MeshKit.tube(metal, [p0, p1], 0.017, 5, rim_col)
		MeshKit.lathe(metal, [Vector2(face - 0.04, rim_r * 0.24), Vector2(face - 0.01, rim_r * 0.18), Vector2(face, 0.0)], 16, rim_col)
		MeshKit.lathe(metal, [Vector2(face + 0.004, 0.04), Vector2(face + 0.006, 0.0)], 10, Color(0.15, 0.15, 0.17))
	var mesh := MeshKit.finish(rubber)
	mesh.surface_set_material(0, _material("rubber"))
	MeshKit.finish(metal, mesh)
	mesh.surface_set_material(1, _material("metal"))
	if gp:
		# Compound band on both sidewalls (recoloured per car: set_compound_color).
		var band := MeshKit.new_tool()
		var b0 := rim_r + (r - rim_r) * 0.55
		var b1 := rim_r + (r - rim_r) * 0.68
		MeshKit.lathe(band, [Vector2(hw + 0.0065, b0), Vector2(hw + 0.0065, b1)], 32, Color.WHITE)
		MeshKit.lathe(band, [Vector2(-hw - 0.0065, b1), Vector2(-hw - 0.0065, b0)], 32, Color.WHITE)
		MeshKit.finish(band, mesh)
		mesh.surface_set_material(2, _band_mat(Tyres.COLOR["medium"]))
	return mesh
