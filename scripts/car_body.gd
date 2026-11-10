class_name CarBody
extends Node3D
## Builds a car's 3D model procedurally (see MeshKit). The body is merged
## into one mesh with a surface per material; each wheel is one more mesh.
## Far from the camera the whole car (body, driver and wheels) is swapped
## for a single merged mesh with one material: one draw call instead of
## ~30, which is most of the cost of a full grid. Car forward is +Z.

const FENDER_LIFT := 0.13      # extra height of the upper body over the station data
const CABIN_LIFT := 0.13

var helmet: MeshInstance3D
var spec: Dictionary
var _tools := {}
static var _mats := {}
static var _wheel_cache := {}
var _tail_mat: StandardMaterial3D
var _brake_level := -1.0
var _blob: MeshInstance3D
var _far: MeshInstance3D
var _fine: MeshInstance3D
var _lod_wait := 0.0

## Beyond this distance (m) the car is drawn as one merged mesh.
const LOD_DISTANCE := 50.0
const LOD_MARGIN := 3.0


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
	# Small parts (louvres, fences, strakes, suspension): only drawn close up,
	# and left out of the far version.
	if _tools.has("fine"):
		var fm := MeshKit.finish(_tools["fine"])
		fm.surface_set_material(0, _material("matte"))
		_fine = MeshInstance3D.new()
		_fine.mesh = fm
		_fine.visibility_range_end = LOD_DISTANCE
		_fine.visibility_range_end_margin = LOD_MARGIN
		add_child(_fine)
		_tools.erase("fine")
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
	# The far version is merged once the car has settled on its suspension.
	_lod_wait = 0.8
	set_process(true)


func _process(delta: float) -> void:
	if _lod_wait <= 0.0:
		set_process(false)
		return
	_lod_wait -= delta
	if _lod_wait <= 0.0 and is_inside_tree():
		build_far_lod()
		set_process(false)


## Merges the body, driver and wheels (as they sit now) into one mesh with a
## single vertex-coloured material, shown beyond LOD_DISTANCE; the detailed
## parts are hidden there.
func build_far_lod() -> void:
	if _far != null:
		return
	var st := SurfaceTool.new()
	var inv := global_transform.affine_inverse()
	var parts: Array[MeshInstance3D] = []
	for n in find_children("*", "MeshInstance3D", true, false):
		if n != _blob and n != _fine:
			parts.append(n as MeshInstance3D)
	for mi in _wheel_mis:
		if is_instance_valid(mi):
			parts.append(mi as MeshInstance3D)
	var any := false
	for mi in parts:
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			st.append_from(mi.mesh, s, xf)
			any = true
	if not any:
		return
	_far = MeshInstance3D.new()
	_far.mesh = st.commit()
	_far.material_override = _far_material()
	_far.visibility_range_begin = LOD_DISTANCE
	_far.visibility_range_begin_margin = LOD_MARGIN
	add_child(_far)
	# Match the detailed car (the time-trial ghost is see-through, no shadow).
	var ref: GeometryInstance3D = parts[0]
	_far.transparency = ref.transparency
	_far.cast_shadow = ref.cast_shadow
	for mi in parts:
		mi.visibility_range_end = LOD_DISTANCE
		mi.visibility_range_end_margin = LOD_MARGIN


static var _far_mat: StandardMaterial3D

static func _far_material() -> StandardMaterial3D:
	if _far_mat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.metallic = 0.35
		m.roughness = 0.35
		_far_mat = m
	return _far_mat


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
	mi.visibility_range_end = 260.0
	add_child(mi)
	_blob = mi


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
	l.visibility_range_end = 32.0
	add_child(l)
	# (Not in the browser: with a grid of cars' worth of these 3D labels,
	# WebGL stopped drawing the whole 3D world. The livery stays; the
	# lettering goes.)
	l.visible = not OS.has_feature("web")
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
			# Glossy paint under a clear lacquer: the colour stays rich (low
			# metallic) and the lacquer carries sharp sky reflections.
			m.metallic = 0.2
			m.roughness = 0.24
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.06
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
	var pattern := String(spec.get("pattern", "classic"))
	MeshKit.loft(paint, spine, 24, func(p: Vector3, th: float) -> Color:
		match pattern:
			"stripes":
				# Twin stripes nose to tail.
				if absf(absf(p.x) - 0.06) < 0.022 and th > 0.25:
					return stripe
				return accent if th < -0.4 else base
			"split":
				# Two-tone: the lower half in the accent, a pinstripe between.
				if absf(th) < 0.12:
					return stripe
				return accent if th < 0.0 else base
			"chequer":
				# The chequered flag over the top, the accent underneath.
				if th < -0.4:
					return accent
				var cz := floori(p.z / 0.26)
				var ct := floori((th + PI) / (TAU / 14.0))
				return base if (cz + ct) % 2 == 0 else stripe
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
			if pattern == "split":
				return accent if th < 0.1 else base
			if absf(th) < 0.5 and p.y > 0.05 and p.y < 0.12:
				return stripe                  # side stripe
			return accent if th < -0.3 else base)
		# Mirror on a stalk.
		MeshKit.ellipsoid(paint, Vector3(0.48 * sx, 0.47, 0.72), Vector3(0.07, 0.035, 0.04), 10, base)
		MeshKit.tube(matte, [Vector3(0.3 * sx, 0.34, 0.74), Vector3(0.44 * sx, 0.46, 0.73)], 0.012, 6, carbon)

	var fine := _st("fine")
	_gp_floor(matte, fine, carbon)
	_gp_front_wing(paint, matte, fine, base, accent, stripe, carbon)
	_gp_rear_wing(paint, matte, fine, base, accent, stripe, carbon)
	# Cooling louvres on the top of the sidepods and the engine cover.
	for sx in [-1.0, 1.0]:
		for k in 5:
			MeshKit.box(fine, Vector3(0.16, 0.012, 0.035), Vector3(0.47 * sx, 0.305 - k * 0.012, -0.32 - k * 0.075), carbon, Vector3(-6, 0, 0))

	# Halo: hoop from behind the shoulders converging on a centre pillar.
	var halo := []
	for t in range(9):
		var u := float(t) / 8.0
		var ang := lerpf(-PI * 0.5, PI * 0.5, u)
		halo.append(Vector3(sin(ang) * 0.33, 0.7 + cos(ang) * 0.06, -0.02 + cos(ang) * 0.84))
	MeshKit.tube(matte, halo, 0.025, 8, carbon)
	MeshKit.tube(matte, [Vector3(0, 0.76, 0.82), Vector3(0, 0.6, 0.92), Vector3(0, 0.42, 0.96)], 0.025, 8, carbon)

	# Steering wheel with a lit display.
	MeshKit.box(_st("fine"), Vector3(0.28, 0.13, 0.03), Vector3(0, 0.45, 0.62), carbon, Vector3(-20, 0, 0))
	MeshKit.box(_st("head"), Vector3(0.1, 0.04, 0.01), Vector3(0, 0.47, 0.603), Color.WHITE, Vector3(-20, 0, 0))

	# Suspension: wishbones and push-rods to each upright.
	for front in [true, false]:
		var z: float = spec["wheel_front_z"] if front else spec["wheel_rear_z"]
		var tw: float = spec["track_front"] if front else spec["track_rear"]
		for sx in [-1.0, 1.0]:
			var outer := Vector3((tw - 0.13) * sx, 0.0, z)
			for yy in [0.3, 0.1]:
				MeshKit.tube(_st("fine"), [Vector3(0.28 * sx, yy, z + 0.22), outer + Vector3(0, yy, 0)], 0.016, 5, carbon)
				MeshKit.tube(_st("fine"), [Vector3(0.28 * sx, yy, z - 0.22), outer + Vector3(0, yy, 0)], 0.016, 5, carbon)

	# Driver's helmet (separate so the cockpit camera can hide it).
	var hst := MeshKit.new_tool()
	var hcol: Color = lv["helmet"]
	var hc := Vector3(0, 0.53, 0.24)
	MeshKit.ellipsoid(hst, hc, Vector3(0.125, 0.13, 0.14), 16, hcol)
	# The design: a band round it in the team's stripe colour, a stripe
	# over the top, and the visor, curved round the front.
	var ring: Array = []
	for k in 17:
		var a := TAU * k / 16.0
		ring.append(hc + Vector3(sin(a) * 0.124, 0.02, cos(a) * 0.139))
	MeshKit.tube(hst, ring, 0.011, 5, stripe)
	var crown: Array = []
	for k in 9:
		var a := lerpf(-1.2, 1.35, k / 8.0)
		crown.append(hc + Vector3(0, cos(a) * 0.131, sin(a) * 0.141))
	MeshKit.tube(hst, crown, 0.014, 5, accent)
	var visor: Array = []
	for k in 9:
		var a := lerpf(-1.05, 1.05, k / 8.0)
		visor.append(hc + Vector3(sin(a) * 0.118, 0.03, cos(a) * 0.132))
	MeshKit.tube(hst, visor, 0.026, 6, Color(0.02, 0.02, 0.03))
	var hmesh := MeshKit.finish(hst)
	hmesh.surface_set_material(0, _material("paint"))
	helmet = MeshInstance3D.new()
	helmet.mesh = hmesh
	add_child(helmet)


## Floor: the plank, the floor edges with their fences, and a diffuser
## with strakes under the rear.
func _gp_floor(matte: SurfaceTool, fine: SurfaceTool, carbon: Color) -> void:
	MeshKit.box(matte, Vector3(1.5, 0.025, 3.0), Vector3(0, -0.11, -0.4), carbon)
	MeshKit.box(matte, Vector3(0.3, 0.025, 3.4), Vector3(0, -0.125, -0.2), Color(0.45, 0.35, 0.2))
	var edge := carbon.lightened(0.04)
	for sx in [-1.0, 1.0]:
		# The edge of the floor curls up, with a slot cut in it.
		MeshKit.box(matte, Vector3(0.05, 0.025, 2.3), Vector3(0.775 * sx, -0.09, -0.55), edge, Vector3(0, 0, -18 * sx))
		MeshKit.box(matte, Vector3(0.015, 0.03, 0.5), Vector3(0.8 * sx, -0.07, -1.35), edge)
		# Fences at the front of the floor, ahead of the sidepods.
		for k in 3:
			MeshKit.plate(fine, [Vector2(1.18 - k * 0.05, -0.11), Vector2(1.0 - k * 0.05, 0.02), Vector2(0.72 - k * 0.05, 0.03), Vector2(0.7 - k * 0.05, -0.11)],
				(0.45 + k * 0.1) * sx, 0.012, carbon)
	# Diffuser: the ramp up under the gearbox, its walls and strakes.
	var ramp := [Vector2(-1.55, -0.12), Vector2(-2.42, 0.1), Vector2(-2.42, 0.14), Vector2(-1.55, -0.08)]
	MeshKit.box(matte, Vector3(1.0, 0.02, 0.9), Vector3(0, -0.005, -1.98), carbon, Vector3(-14, 0, 0))
	for x in [-0.5, -0.3, -0.12, 0.12, 0.3, 0.5]:
		MeshKit.plate(fine, ramp, x, 0.012, carbon)


## Front wing: four elements, the flaps sweeping up towards the nose,
## carbon main plane with painted flaps, shaped endplates.
func _gp_front_wing(paint: SurfaceTool, matte: SurfaceTool, fine: SurfaceTool, base: Color, accent: Color, stripe: Color, carbon: Color) -> void:
	var elems := [
		# y at the nose, rise, z, chord, aoa, colour, surface
		[-0.105, 0.0, 2.86, 0.33, 3.0, carbon, matte],
		[-0.075, 0.05, 2.6, 0.2, 12.0, accent, paint],
		[-0.04, 0.1, 2.45, 0.16, 22.0, base, paint],
		[0.0, 0.15, 2.32, 0.13, 32.0, base, paint],
	]
	var first := true
	for e in elems:
		var col: Color = e[5]
		for sx in [-1.0, 1.0]:
			var secs: Array = []
			var x0 := 0.0 if first else 0.09
			for k in 6:
				var u := float(k) / 5.0
				var x: float = lerpf(x0, 0.97, u) * sx
				# The flaps rise towards the nose and fall to meet the endplate.
				var rise := float(e[1]) * (1.0 - smoothstep(0.15, 0.95, absf(x)))
				var sweep := 0.06 * u * u
				secs.append([x, float(e[0]) + rise, float(e[2]) - sweep, float(e[3]), float(e[4]) + 6.0 * (1.0 - u)])
			MeshKit.wing(e[6], secs, 0.1, 0.06, func(_x, upper): return col if upper else col.darkened(0.25))
		first = false
	# Endplates: low at the front, rising to the rear, carbon with the
	# livery colour along the top.
	var outline := [Vector2(2.98, -0.13), Vector2(2.96, -0.06), Vector2(2.82, 0.0), Vector2(2.6, 0.05), Vector2(2.38, 0.13),
		Vector2(2.24, 0.15), Vector2(2.2, 0.08), Vector2(2.22, -0.13)]
	for sx in [-1.0, 1.0]:
		MeshKit.plate(matte, outline, 0.985 * sx, 0.016, carbon)
		MeshKit.strip(paint, [Vector2(2.96, -0.06), Vector2(2.82, 0.0), Vector2(2.6, 0.05), Vector2(2.38, 0.13), Vector2(2.24, 0.15)], 0.05, 0.985 * sx, 0.02, base)
		MeshKit.box(fine, Vector3(0.09, 0.015, 0.7), Vector3(0.95 * sx, -0.135, 2.6), carbon)
	# Pylons from the nose to the wing.
	for sx in [-1.0, 1.0]:
		MeshKit.plate(fine, [Vector2(2.78, -0.09), Vector2(2.7, 0.0), Vector2(2.52, 0.02), Vector2(2.52, -0.09)], 0.06 * sx, 0.016, carbon)


## Rear wing: shaped endplates (carbon, the livery colour at the top), a
## main plane and the DRS flap in the livery, a two-element beam wing low
## down, and twin swan-neck pylons; the rain light on the crash structure.
func _gp_rear_wing(paint: SurfaceTool, matte: SurfaceTool, fine: SurfaceTool, base: Color, accent: Color, stripe: Color, carbon: Color) -> void:
	var half := 0.5
	# Main plane: dips slightly in the middle (a "spoon").
	var main: Array = []
	var flap: Array = []
	for k in 7:
		var x := lerpf(-half, half, float(k) / 6.0)
		var dip := 0.025 * (1.0 - pow(absf(x) / half, 2.0))
		main.append([x, 0.8 - dip, -2.1, 0.3, 9.0])
		flap.append([x, 0.9 - dip * 0.6, -2.36, 0.22, 28.0])
	MeshKit.wing(paint, main, 0.12, 0.06, func(_x, upper): return base if upper else carbon)
	MeshKit.wing(paint, flap, 0.1, 0.06, func(_x, upper): return accent if upper else base.darkened(0.2))
	# Beam wing: two small elements below, between the endplates' feet.
	MeshKit.airfoil(fine, -0.42, 0.42, 0.36, -2.12, 0.16, 0.12, 0.05, 10.0, carbon)
	MeshKit.airfoil(fine, -0.42, 0.42, 0.42, -2.28, 0.13, 0.12, 0.05, 24.0, carbon)
	var outline := [Vector2(-1.98, 0.3), Vector2(-2.0, 0.62), Vector2(-2.04, 0.86), Vector2(-2.13, 1.0), Vector2(-2.3, 1.04),
		Vector2(-2.55, 1.02), Vector2(-2.62, 0.94), Vector2(-2.6, 0.55), Vector2(-2.48, 0.3)]
	for sx in [-1.0, 1.0]:
		var x: float = (half + 0.012) * sx
		MeshKit.plate(matte, outline, x, 0.018, carbon)
		var top := [Vector2(-2.02, 0.8), Vector2(-2.04, 0.86), Vector2(-2.13, 1.0), Vector2(-2.3, 1.04), Vector2(-2.55, 1.02), Vector2(-2.62, 0.94)]
		MeshKit.strip(paint, top, 0.1, x, 0.022, base)
		var under: Array = []
		for p in top:
			under.append(p - Vector2(0, 0.1))
		MeshKit.strip(paint, under, 0.035, x, 0.022, stripe)
		# The DRS actuator pod in the middle, and the pylons.
		MeshKit.plate(matte, [Vector2(-1.95, 0.22), Vector2(-2.05, 0.5), Vector2(-2.16, 0.8), Vector2(-2.26, 0.8), Vector2(-2.14, 0.22)], 0.07 * sx, 0.014, carbon)
	MeshKit.ellipsoid(fine, Vector3(0, 0.88, -2.25), Vector3(0.035, 0.05, 0.1), 8, carbon)
	# Crash structure with the rain light.
	MeshKit.box(matte, Vector3(0.16, 0.12, 0.3), Vector3(0, 0.2, -2.36), carbon)
	MeshKit.box(_st("tail"), Vector3(0.12, 0.07, 0.02), Vector3(0, 0.21, -2.515), Color.WHITE)


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
	l.visibility_range_end = 32.0
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
	cmi.visibility_range_end = 32.0           # small detail: skip it far away
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


static var _tyre_mats := {}

## Rubber with the maker's name round the sidewall (light lettering on the
## racing slicks, below the compound band; dark grey on road tyres).
static func _tyre_material(rim_r: float, r: float, gp: bool) -> ShaderMaterial:
	var key := "%.3f|%.3f|%s" % [rim_r, r, gp]
	if _tyre_mats.has(key):
		return _tyre_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tyre.gdshader")
	m.set_shader_parameter("letters", _letter_strip())
	m.set_shader_parameter("rim_r", rim_r)
	m.set_shader_parameter("tyre_r", r)
	if gp:
		m.set_shader_parameter("band_lo", 0.12)
		m.set_shader_parameter("band_hi", 0.5)
	else:
		m.set_shader_parameter("band_lo", 0.3)
		m.set_shader_parameter("band_hi", 0.72)
		m.set_shader_parameter("letter_color", Color(0.2, 0.2, 0.21))
	_tyre_mats[key] = m
	return m


const _GLYPHS := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}

static var _letters: ImageTexture

## "APEX  -  RACE SLICK" twice round the tyre, in blocky lettering drawn
## here (no font rendering needed).
static func _letter_strip() -> ImageTexture:
	if _letters != null:
		return _letters
	var w := 2048
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	var words := ["APEX", " - ", "RACE SLICK"]
	var x := 180
	for rep in 2:
		for wi in words.size():
			var big: bool = wi == 0
			var cell := 8 if big else 6            # pixels per glyph dot
			var y0 := (h - 7 * cell) / 2
			for ch in String(words[wi]):
				var g: Array = _GLYPHS.get(ch, _GLYPHS[" "])
				for gy in 7:
					for gx in 5:
						if String(g[gy])[gx] == "1":
							img.fill_rect(Rect2i(x + gx * cell, y0 + gy * cell, cell, cell), Color(1, 1, 1))
				x += cell * 6
		x = 180 + w / 2
	img.generate_mipmaps()
	_letters = ImageTexture.create_from_image(img)
	return _letters


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
	mesh.surface_set_material(0, _tyre_material(rim_r, r, gp))
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
