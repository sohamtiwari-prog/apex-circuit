class_name Trackside
extends Node3D
## Everything built beside a circuit: barriers (concrete, armco, tyre walls),
## catch fencing, advertising boards, the start gantry with working lights,
## pit lane and pit building, grandstands with crowds, bridges and distant
## hills. All static geometry is merged into a few meshes per material so a
## phone draws it in a handful of calls.

const BRANDS := [
	["APEX", Color(0.95, 0.4, 0.05), Color(1, 1, 1)],
	["VOLTRA", Color(0.08, 0.1, 0.14), Color(0.3, 0.9, 1.0)],
	["NORTHWIND AIR", Color(0.1, 0.25, 0.6), Color(1, 1, 1)],
	["KESTREL OIL", Color(0.9, 0.82, 0.1), Color(0.1, 0.1, 0.1)],
	["AURUM WATCHES", Color(0.06, 0.06, 0.06), Color(0.95, 0.78, 0.35)],
	["FALCO TYRES", Color(0.85, 0.1, 0.1), Color(1, 1, 1)],
	["BLUEPEAK", Color(1, 1, 1), Color(0.1, 0.35, 0.8)],
	["ORBIS TELECOM", Color(0.45, 0.1, 0.6), Color(1, 1, 1)],
]
const AD_ROWS := 8

var track: Track
var _geo := {}                 # material key -> SurfaceTool
var _lamps: Array[MeshInstance3D] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _ad_viewport: SubViewport
var _board_viewport: SubViewport
var board_spots: Array = []          # sample index of each 300 m board (tests, previews)


func build(t: Track) -> void:
	track = t
	_make_ad_atlas()
	_barriers()
	_gantry()
	_pits_and_stands()
	_bridges()
	if track.track_id == "riviera":
		_tunnel(1460.0, 1900.0)
		_yachts()
	_hills()
	_brake_boards()
	_marshal_posts()
	_tv_towers()
	_flagpoles()
	if track.night:
		_floodlights()
	_commit()


## Night races: lighting towers all the way round, both sides, with banks
## of bright lamps angled down at the track.
func _floodlights() -> void:
	var n := track.size()
	var step := int(48.0 / Track.SPACING)
	var k := 0
	for i in range(0, n, step):
		var side := 1.0 if k % 2 == 0 else -1.0
		k += 1
		var out: Vector3 = track.rights[i] * side
		var lat := track.wall_at(i, side) + 2.2
		var p: Vector3 = track.points[i] + out * lat
		if track.has_method("ground_height") and not track.terrain_h.is_empty():
			p.y = track.ground_height(p.x, p.z)
		var basis := Basis.looking_at(out, Vector3.UP)
		var h := 13.0 if track.style != "city" else 9.0
		if _reserved_near(p):
			continue
		_box("metal", Transform3D(basis, p + Vector3(0, h * 0.5, 0)), Vector3(0.3, h, 0.3), Color(0.3, 0.31, 0.34))
		# Arm reaching over the barrier, and the lamp bank facing the road.
		_box("metal", Transform3D(basis, p + Vector3(0, h, 0) - out * 1.2), Vector3(0.2, 0.2, 2.6), Color(0.3, 0.31, 0.34))
		var head := Transform3D(basis.rotated(basis.x, 0.6), p + Vector3(0, h - 0.3, 0) - out * 2.3)
		_box("metal", head, Vector3(2.2, 0.9, 0.35), Color(0.12, 0.12, 0.13))
		_box("flood", head.translated_local(Vector3(0, 0, 0.19)), Vector3(2.0, 0.75, 0.04), Color(1.0, 0.97, 0.9))


func _reserved_near(p: Vector3) -> bool:
	for box in track.scenery_boxes:
		var xf: Transform3D = box["xf"]
		var size: Vector3 = box["size"]
		var local := xf.affine_inverse() * p
		if absf(local.x) < size.x * 0.5 + 0.5 and absf(local.z) < size.z * 0.5 + 0.5:
			return true
	return false


## Start lights on the gantry: `lit` columns red (0..5).
func set_lights(lit: int) -> void:
	for k in range(_lamps.size()):
		_lamps[k].material_override = _lamp_on if k < lit else _lamp_off


# ------------------------------------------------------------ geometry helpers

func _st(key: String) -> SurfaceTool:
	if not _geo.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_geo[key] = st
	return _geo[key]


## Quad a-b-c-d (counter-clockwise seen from the front), flat normal.
func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color,
		uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]) -> void:
	var st := _st(key)
	var n := (b - a).cross(c - a).normalized()
	var vs := [a, b, c, a, c, d]
	var us := [uv[0], uv[1], uv[2], uv[0], uv[2], uv[3]]
	for k in range(6):
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(us[k])
		st.add_vertex(vs[k])


## Box with flat faces; xf positions its centre (basis may rotate it).
func _box(key: String, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := []
	for i in range(8):
		c.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		_quad(key, c[f[0]], c[f[1]], c[f[2]], c[f[3]], col)


func _material(key: String) -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	# Double-sided: thin walls, fences and boards are seen from both sides.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match key:
		"metal":
			m.metallic = 0.75
			m.roughness = 0.38
		"glass":
			m.metallic = 0.6
			m.roughness = 0.08
		"fence":
			m.albedo_texture = _fence_texture()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic = 0.5
			m.roughness = 0.5
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"ads":
			m.albedo_texture = _ad_viewport.get_texture()
			m.vertex_color_use_as_albedo = false
			m.roughness = 0.6
		"boards":
			m.albedo_texture = _board_viewport.get_texture()
			m.vertex_color_use_as_albedo = false
			m.roughness = 0.7
		"crowd":
			m.albedo_texture = _crowd_texture()
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			m.roughness = 1.0
		"hills":
			m.roughness = 1.0
		"lamp":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"flood":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(1.0, 0.97, 0.9)
			m.emission_energy_multiplier = 5.0
		"tunnel":
			m.roughness = 0.95
	return m


func _commit() -> void:
	for key in _geo:
		var st: SurfaceTool = _geo[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _material(key)
		if key == "hills" or key == "fence":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_geo.clear()


# ------------------------------------------------------------ textures

func _fence_texture() -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(64):
		for x in range(64):
			# Diamond chain-link: two diagonal wire families.
			var a := posmod(x + y, 32)
			var b := posmod(x - y, 32)
			if a < 3 or b < 3:
				img.set_pixel(x, y, Color(0.75, 0.77, 0.8, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _crowd_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var img := Image.create(128, 32, true, Image.FORMAT_RGB8)
	var shirts := [Color(0.9, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.1, 0.2, 0.6), Color(0.95, 0.5, 0.05),
		Color(0.1, 0.5, 0.2), Color(0.95, 0.85, 0.1), Color(0.15, 0.15, 0.15), Color(0.5, 0.75, 0.95)]
	for y in range(32):
		for x in range(128):
			var row := y % 4
			var col: Color
			if row == 3:
				col = Color(0.25, 0.25, 0.27)                 # seat back / gap
			elif rng.randf() < 0.12:
				col = Color(0.55, 0.55, 0.58)                 # empty seat
			elif row == 0:
				col = Color(0.85, 0.66, 0.5).darkened(rng.randf() * 0.5)   # heads
			else:
				col = shirts[rng.randi() % shirts.size()].darkened(rng.randf() * 0.25)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Advertising boards for fictional brands, drawn once into a texture atlas
## (one 8:1 board per row).
func _make_ad_atlas() -> void:
	_ad_viewport = SubViewport.new()
	_ad_viewport.size = Vector2i(1024, 128 * AD_ROWS)
	_ad_viewport.transparent_bg = false
	_ad_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ad_viewport.disable_3d = true
	add_child(_ad_viewport)
	for k in range(AD_ROWS):
		var brand: Array = BRANDS[k % BRANDS.size()]
		var bg := ColorRect.new()
		bg.color = brand[1]
		bg.position = Vector2(0, k * 128)
		bg.size = Vector2(1024, 128)
		_ad_viewport.add_child(bg)
		var stripe := ColorRect.new()
		stripe.color = Color(brand[2]).lerp(brand[1], 0.6)
		stripe.position = Vector2(0, k * 128 + 112)
		stripe.size = Vector2(1024, 16)
		_ad_viewport.add_child(stripe)
		var label := Label.new()
		label.text = brand[0]
		label.position = Vector2(0, k * 128)
		label.size = Vector2(1024, 116)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 84)
		label.add_theme_color_override("font_color", brand[2])
		_ad_viewport.add_child(label)


## UVs of ad row k, repeated `reps` times along a board.
func _ad_uv(k: int, reps: float) -> Array:
	var v0 := float(posmod(k, AD_ROWS)) / AD_ROWS
	var v1 := v0 + 1.0 / AD_ROWS
	return [Vector2(0, v1), Vector2(reps, v1), Vector2(reps, v0), Vector2(0, v0)]


# ------------------------------------------------------------ barriers

func _barrier_kind(i: int, side: int) -> String:
	if track.style == "city":
		return "concrete"
	var s: float = track.cum[i]
	if s < 380.0 or s > track.total_length - 420.0:
		return "concrete"
	if track.runoff_type[0].size() == track.size() and track.runoff_type[side][i] != Track.RUNOFF_NONE:
		return "tecpro"
	return "armco"


## Along the pit lane, the barrier drawn on the pit side is the pit wall
## (the garages stand where the outer barrier would be).
func _in_pit_straight(i: int, side: float) -> bool:
	if not track.has_pit_lane or side != track.pit_side:
		return false
	var ps := track.pit_ps(i)
	return ps >= track.PIT_ENTRY_LEN and ps <= track.PIT_ENTRY_LEN + track.PIT_STRAIGHT_LEN


func _barrier_lat(i: int, side: float) -> float:
	return track.pit_off if _in_pit_straight(i, side) else track.wall_at(i, side)


func _barriers() -> void:
	var n := track.size()
	var step := 3
	var off := track.wall_offset
	var concrete := Color(0.8, 0.8, 0.78)
	var ad_index := 0
	for side_i in range(2):
		var side := -1.0 if side_i == 0 else 1.0
		var run := 0
		for i in range(0, n, step):
			var j := (i + step) % n
			# No barrier across the ends of the pit lane.
			if _in_pit_straight(i, side) != _in_pit_straight(j, side):
				continue
			var a: Vector3 = track.points[i] + track.rights[i] * _barrier_lat(i, side) * side
			var b: Vector3 = track.points[j] + track.rights[j] * _barrier_lat(j, side) * side
			var mid := (a + b) * 0.5
			var y0 := Track.GROUND_Y
			var inward: Vector3 = -track.rights[i] * side        # towards the track
			var kind := "concrete" if _in_pit_straight(i, side) else _barrier_kind(i, side_i)
			var top := 1.05
			match kind:
				"concrete":
					# Wall face (towards the track), top, and an ad board on top.
					var f := inward * 0.36
					if side > 0:
						_quad("concrete", a + f + Vector3(0, y0, 0), b + f + Vector3(0, y0, 0), b + f + Vector3(0, y0 + top, 0), a + f + Vector3(0, y0 + top, 0), concrete)
					else:
						_quad("concrete", b + f + Vector3(0, y0, 0), a + f + Vector3(0, y0, 0), a + f + Vector3(0, y0 + top, 0), b + f + Vector3(0, y0 + top, 0), concrete)
					if side < 0:
						_quad("concrete", a + f + Vector3(0, y0 + top, 0), b + f + Vector3(0, y0 + top, 0), b - f + Vector3(0, y0 + top, 0), a - f + Vector3(0, y0 + top, 0), concrete.darkened(0.1))
					else:
						_quad("concrete", b + f + Vector3(0, y0 + top, 0), a + f + Vector3(0, y0 + top, 0), a - f + Vector3(0, y0 + top, 0), b - f + Vector3(0, y0 + top, 0), concrete.darkened(0.1))
					if run % 4 == 0:
						ad_index += 1
					var ad := _ad_uv(ad_index, 1.0)
					ad = [ad[1], ad[0], ad[3], ad[2]]          # read correctly from the track
					var lo := Vector3(0, y0 + 0.12, 0) + f * 1.02
					var hi := Vector3(0, y0 + 0.92, 0) + f * 1.02
					if side > 0:
						_quad("ads", a + lo, b + lo, b + hi, a + hi, Color.WHITE, ad)
					else:
						_quad("ads", b + lo, a + lo, a + hi, b + hi, Color.WHITE, ad)
				"tecpro":
					# Block barrier: alternating red and white blocks.
					var col := Color(0.85, 0.12, 0.1) if run % 2 == 0 else Color(0.92, 0.92, 0.92)
					var dir := (b - a)
					var basis := Basis.looking_at(-dir.normalized(), Vector3.UP)
					_box("concrete", Transform3D(basis, mid + inward * 0.5 + Vector3(0, y0 + 0.5, 0)), Vector3(1.2, 1.0, dir.length() - 0.08), col)
					_box("concrete", Transform3D(basis, mid + inward * 0.5 + Vector3(0, y0 + 1.02, 0)), Vector3(1.22, 0.06, dir.length() - 0.08), Color(0.12, 0.2, 0.55))
				"armco":
					# Two steel rails on posts.
					for rail_y in [0.45, 0.8]:
						var lo := Vector3(0, y0 + rail_y - 0.14, 0) + inward * 0.25
						var hi := Vector3(0, y0 + rail_y + 0.14, 0) + inward * 0.25
						if side > 0:
							_quad("metal", a + lo, b + lo, b + hi, a + hi, Color(0.74, 0.76, 0.78))
						else:
							_quad("metal", b + lo, a + lo, a + hi, b + hi, Color(0.74, 0.76, 0.78))
					_box("metal", Transform3D(Basis.looking_at(-(b - a).normalized(), Vector3.UP), a + inward * 0.05 + Vector3(0, y0 + 0.5, 0)), Vector3(0.12, 1.0, 0.12), Color(0.5, 0.52, 0.55))
					top = 0.95
			# Catch fence above every barrier.
			var fb := Vector3(0, y0 + top, 0)
			var ft := Vector3(0, y0 + top + 3.2, 0)
			var flen := a.distance_to(b)
			_quad("fence", a + fb, b + fb, b + ft, a + ft, Color.WHITE, [Vector2(0, 6.4), Vector2(flen * 2.0, 6.4), Vector2(flen * 2.0, 0), Vector2(0, 0)])
			if run % 2 == 0:
				_box("metal", Transform3D(Basis(), a + Vector3(0, y0 + top + 1.7, 0) - inward * 0.1), Vector3(0.1, 3.4, 0.1), Color(0.45, 0.47, 0.5))
			run += 1


# ------------------------------------------------------------ start gantry

func _gantry() -> void:
	var n := track.size()
	var i := 3 % n
	var p: Vector3 = track.points[i]
	var r: Vector3 = track.rights[i]
	var basis := Basis.looking_at(-track.htangents[i], Vector3.UP)
	var span := track.wall_offset + 0.8
	var y := 7.2
	var steel := Color(0.24, 0.25, 0.28)
	# Legs behind the barriers (on the pit wall, on the pit side).
	var legs := {}
	for side in [-1.0, 1.0]:
		legs[side] = track.pit_off if _in_pit_straight(i, side) else span
		_box("metal", Transform3D(basis, p + r * float(legs[side]) * side + Vector3(0, y * 0.5, 0)), Vector3(0.6, y, 0.6), steel)
	var width: float = float(legs[-1.0]) + float(legs[1.0])
	var centre := p + r * (float(legs[1.0]) - float(legs[-1.0])) * 0.5
	_box("metal", Transform3D(basis, centre + Vector3(0, y, 0)), Vector3(width + 0.6, 0.7, 0.7), steel)
	_box("metal", Transform3D(basis, centre + Vector3(0, y - 1.1, 0)), Vector3(width + 0.6, 0.15, 0.4), steel)
	# Light panel facing the grid (the cars approach from -tangent... the grid
	# is behind the line, so the panel faces backwards along the track).
	var panel_c := p + Vector3(0, y - 1.0, 0) - track.htangents[i] * 0.45
	_box("metal", Transform3D(basis, panel_c), Vector3(5.6, 1.5, 0.35), Color(0.04, 0.04, 0.05))
	_lamp_off = StandardMaterial3D.new()
	_lamp_off.albedo_color = Color(0.12, 0.02, 0.02)
	_lamp_off.roughness = 0.3
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.albedo_color = Color(1.0, 0.1, 0.05)
	_lamp_on.emission_enabled = true
	_lamp_on.emission = Color(1.0, 0.08, 0.04)
	_lamp_on.emission_energy_multiplier = 5.0
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.24
	lamp_mesh.height = 0.3
	lamp_mesh.radial_segments = 12
	lamp_mesh.rings = 4
	for col in range(5):
		var mi := MeshInstance3D.new()
		mi.mesh = lamp_mesh
		var x := (col - 2.0) * 1.05
		mi.transform = Transform3D(basis.rotated(basis.x, PI * 0.5), panel_c + basis.x * x - track.htangents[i] * 0.2 + Vector3(0, 0.3, 0))
		mi.material_override = _lamp_off
		add_child(mi)
		var mi2 := MeshInstance3D.new()
		mi2.mesh = lamp_mesh
		mi2.transform = mi.transform.translated(Vector3(0, -0.62, 0))
		mi2.material_override = _lamp_off
		add_child(mi2)
		_lamps.append(mi)
		_lamp_pairs.append(mi2)
	# Ad banner on the beam.
	var ad := _ad_uv(0, 3.0)
	var fwd: Vector3 = -track.htangents[i]
	var b0 := p - r * span + Vector3(0, y - 0.35, 0) + fwd * 0.36
	var b1 := p + r * span + Vector3(0, y - 0.35, 0) + fwd * 0.36
	_quad("ads", b0, b1, b1 + Vector3(0, 0.7, 0), b0 + Vector3(0, 0.7, 0), Color.WHITE, ad)
	_quad("ads", b1 - fwd * 0.72, b0 - fwd * 0.72, b0 - fwd * 0.72 + Vector3(0, 0.7, 0), b1 - fwd * 0.72 + Vector3(0, 0.7, 0), Color.WHITE, ad)


var _lamp_pairs: Array[MeshInstance3D] = []


func set_lights_out() -> void:
	set_lights(0)


func _process(_d: float) -> void:
	# Keep the lower lamp of each column in step with the upper one.
	for k in range(_lamp_pairs.size()):
		_lamp_pairs[k].material_override = _lamps[k].material_override


# ------------------------------------------------------------ pits and stands

func _pits_and_stands() -> void:
	var n := track.size()
	var L := track.total_length
	# Pit lane and garages beside the main straight (Track plans where), a
	# grandstand facing them.
	if track.has_pit_lane:
		_pit_complex()
		var lane_s := track.pit_s0 + track.PIT_ENTRY_LEN
		_grandstand_run(lane_s + 60.0, minf(160.0, track.PIT_STRAIGHT_LEN - 100.0), -track.pit_side)
	else:
		_grandstand_run(L - 150.0, 90.0, 1.0)
	# Grandstands at the three sharpest corners, on the outside.
	var corners: Array = []
	var i := 0
	while i < n:
		if absf(track.curv[i]) > 1.0 / 90.0:
			var best := i
			while i < n and absf(track.curv[i]) > 1.0 / 90.0:
				if absf(track.curv[i]) > absf(track.curv[best]):
					best = i
				i += 1
			corners.append(best)
		i += 1
	corners.sort_custom(func(x, y): return absf(track.curv[x]) > absf(track.curv[y]))
	var placed := 0
	for c in corners:
		if placed >= 3:
			break
		var outside := 1.0 if track.curv[c] > 0.0 else -1.0
		if _grandstand_run(track.cum[c] - 35.0, 70.0, outside):
			placed += 1


## The pit lane: entry road, the lane behind the pit wall (fast lane, box
## lane with each team's box marked), exit road, and the garages.
func _pit_complex() -> void:
	var side := track.pit_side
	var total := track.pit_total()
	var e0 := track.PIT_ENTRY_LEN
	var e1 := track.PIT_ENTRY_LEN + track.PIT_STRAIGHT_LEN
	var off := track.pit_off
	var samples := _samples_between(track.pit_s0, total)
	if samples.size() < 10:
		return
	var tarmac := Color(0.3, 0.3, 0.31)
	var white := Color(0.92, 0.92, 0.92)
	var lift := Vector3(0, Track.GROUND_Y + 0.03, 0)
	var edge_min := track.road_half + Track.KERB_W + 0.4
	for k in range(samples.size() - 1):
		var i: int = samples[k]
		var j: int = samples[k + 1]
		var psi := track.pit_ps(i)
		var psj := track.pit_ps(j)
		var ti := track.pit_tarmac(psi)
		var tj := track.pit_tarmac(psj)
		var straight := psi >= e0 and psj <= e1
		var in_i := ti.x if straight else maxf(ti.x, edge_min)
		var in_j := tj.x if straight else maxf(tj.x, edge_min)
		if tj.y <= in_j + 0.2:
			continue
		_strip(i, j, in_i, in_j, ti.y, tj.y, lift, tarmac)
		if straight:
			# Fast lane | box lane.
			_strip(i, j, off + 6.5, off + 6.5, off + 6.65, off + 6.65, lift + Vector3(0, 0.004, 0), white)
		else:
			# Edge lines along the entry and exit roads.
			_strip(i, j, ti.y - 0.35, tj.y - 0.35, ti.y - 0.2, tj.y - 0.2, lift + Vector3(0, 0.004, 0), white)
			if ti.x >= edge_min and tj.x >= edge_min:
				_strip(i, j, ti.x + 0.2, tj.x + 0.2, ti.x + 0.35, tj.x + 0.35, lift + Vector3(0, 0.004, 0), white)
	# Speed limit lines across the lane where the limiter goes on and off.
	for ps in [e0, e1]:
		var i := _sample_at_ps(samples, ps)
		var t := track.pit_tarmac(ps)
		var fwd: Vector3 = track.htangents[i]
		var r: Vector3 = track.rights[i] * side
		var p0: Vector3 = track.points[i] + r * t.x + lift + Vector3(0, 0.005, 0)
		var p1: Vector3 = track.points[i] + r * t.y + lift + Vector3(0, 0.005, 0)
		var d := fwd * 0.25
		if side > 0:
			_quad("concrete", p0 - d, p0 + d, p1 + d, p1 - d, white)
		else:
			_quad("concrete", p0 + d, p0 - d, p1 - d, p1 + d, white)
	# Team boxes: an outline in the team's colour with a stop bar at the front.
	var teams: Array = CarSpecs.TEAMS
	for team in track.pit_boxes:
		var ps: float = track.pit_boxes[team]
		var col: Color = teams[int(team) % teams.size()]["base"]
		var i0 := _sample_at_ps(samples, ps - 3.6)
		var i1 := _sample_at_ps(samples, ps + 3.6)
		var y := lift + Vector3(0, 0.006, 0)
		_strip(i0, i1, off + 7.0, off + 7.0, off + 7.2, off + 7.2, y, col)
		_strip(i0, i1, off + 10.8, off + 10.8, off + 11.0, off + 11.0, y, col)
		for ib in [i0, i1]:
			var r: Vector3 = track.rights[ib] * side
			var fwd: Vector3 = track.htangents[ib]
			var q0: Vector3 = track.points[ib] + r * (off + 7.0) + y
			var q1: Vector3 = track.points[ib] + r * (off + 11.0) + y
			var d: Vector3 = fwd * (0.12 if ib == i0 else 0.3)
			if side > 0:
				_quad("concrete", q0 - d, q0 + d, q1 + d, q1 - d, col if ib == i0 else white)
			else:
				_quad("concrete", q0 + d, q0 - d, q1 - d, q1 + d, col if ib == i0 else white)
	# The building: garages at ground level, glass hospitality floor, roof.
	var lane: Array = []
	for i in samples:
		var ps := track.pit_ps(i)
		if ps >= e0 and ps <= e1:
			lane.append(i)
	var bld0 := off + 12.0
	var depth := Track.GARAGE_DEPTH
	var per := int(Track.GARAGE_LEN / Track.SPACING)
	var garage := 0
	for k in range(0, lane.size() - per, per):
		var i: int = lane[k]
		var j: int = lane[mini(k + per, lane.size() - 1)]
		var a: Vector3 = track.points[i] + track.rights[i] * side * bld0
		var b: Vector3 = track.points[j] + track.rights[j] * side * bld0
		var mid := (a + b) * 0.5
		var dir := b - a
		var basis := Basis.looking_at(-dir.normalized(), Vector3.UP)
		var out: Vector3 = track.rights[i] * side
		var seg_len := dir.length() + 0.05
		var team: Dictionary = teams[garage % teams.size()]
		# Ground floor block with a dark garage opening and team-colour fascia.
		_box("concrete", Transform3D(basis, mid + out * (depth * 0.5) + Vector3(0, 2.5, 0)), Vector3(depth, 5.0, seg_len), Color(0.86, 0.86, 0.88))
		_box("concrete", Transform3D(basis, mid + out * 0.25 + Vector3(0, 1.8, 0)), Vector3(0.6, 3.6, seg_len * 0.82), Color(0.08, 0.08, 0.09))
		_box("concrete", Transform3D(basis, mid - out * 0.05 + Vector3(0, 4.2, 0)), Vector3(0.3, 0.7, seg_len * 0.9), team["base"])
		# Glass floor and roof.
		_box("glass", Transform3D(basis, mid + out * (depth * 0.5 + 1.0) + Vector3(0, 7.0, 0)), Vector3(depth - 2.0, 4.0, seg_len), Color(0.2, 0.32, 0.42))
		_box("concrete", Transform3D(basis, mid + out * (depth * 0.5 - 1.0) + Vector3(0, 9.2, 0)), Vector3(depth + 2.0, 0.4, seg_len), Color(0.93, 0.93, 0.95))
		_reserve(Transform3D(basis, mid + out * (depth * 0.5)), Vector3(depth + 2.0, 10.0, seg_len), false, true)
		garage += 1


## A strip between two laterals (unsigned, on the pit side) from sample i to j.
func _strip(i: int, j: int, in_i: float, in_j: float, out_i: float, out_j: float, lift: Vector3, col: Color) -> void:
	var side := track.pit_side
	var ri: Vector3 = track.rights[i] * side
	var rj: Vector3 = track.rights[j] * side
	var q := [track.points[i] + ri * in_i + lift, track.points[j] + rj * in_j + lift,
		track.points[j] + rj * out_j + lift, track.points[i] + ri * out_i + lift]
	if side > 0:
		_quad("concrete", q[0], q[3], q[2], q[1], col)
	else:
		_quad("concrete", q[0], q[1], q[2], q[3], col)


func _sample_at_ps(samples: Array, ps: float) -> int:
	var best: int = samples[0]
	var bd := INF
	for i in samples:
		var d := absf(track.pit_ps(i) - ps)
		if d < bd:
			bd = d
			best = i
	return best


func _samples_between(start_s: float, length: float) -> Array:
	var n := track.size()
	var L := track.total_length
	var out: Array = []
	for i in range(n):
		var s := fposmod(track.cum[i] - start_s, L)
		if s <= length:
			out.append(i)
	out.sort_custom(func(x, y): return fposmod(track.cum[x] - start_s, L) < fposmod(track.cum[y] - start_s, L))
	return out


## A run of grandstand behind the barrier, following the track.
func _grandstand_run(start_s: float, length: float, side: float) -> bool:
	var samples := _samples_between(start_s, length)
	if samples.size() < 6:
		return false
	var off := track.wall_offset + 3.0
	var rows := 9
	var depth := rows * 0.9 + 2.0
	var step := 3
	# Check exactly the space each segment will take.
	for k in range(0, samples.size() - step, step):
		var i: int = samples[k]
		var j: int = samples[k + step]
		var seg := track.points[i].distance_to(track.points[j])
		var xf := Transform3D(Basis.looking_at(-track.htangents[i], Vector3.UP), (track.points[i] + track.points[j]) * 0.5 + (track.rights[i] + track.rights[j]) * 0.5 * side * (off + depth * 0.5))
		if not track.footprint_clear(xf, Vector3(depth + 2.0, 10.0, seg + 1.0), 1.5):
			return false
	for k in range(0, samples.size() - step, step):
		var i: int = samples[k]
		var j: int = samples[k + step]
		var ri: Vector3 = track.rights[i] * side
		var rj: Vector3 = track.rights[j] * side
		var seg := track.points[i].distance_to(track.points[j])
		for r in range(rows):
			var d0 := off + r * 0.9
			var d1 := d0 + 0.9
			var h0 := 0.6 + r * 0.5
			var a0: Vector3 = track.points[i] + ri * d0 + Vector3(0, h0, 0)
			var b0: Vector3 = track.points[j] + rj * d0 + Vector3(0, h0, 0)
			var a1: Vector3 = track.points[i] + ri * d1 + Vector3(0, h0, 0)
			var b1: Vector3 = track.points[j] + rj * d1 + Vector3(0, h0, 0)
			# Riser (concrete) then the seated tier (crowd).
			var dn := Vector3(0, -0.5, 0)
			if side > 0:
				_quad("concrete", a0 + dn, b0 + dn, b0, a0, Color(0.6, 0.6, 0.62))
			else:
				_quad("concrete", b0 + dn, a0 + dn, a0, b0, Color(0.6, 0.6, 0.62))
			var uv := [Vector2(0, (r % 8 + 1) / 8.0), Vector2(seg / 8.0, (r % 8 + 1) / 8.0), Vector2(seg / 8.0, (r % 8) / 8.0), Vector2(0, (r % 8) / 8.0)]
			# Seen from the track, the tier should face up and towards the cars.
			var lift := Vector3(0, 0.45, 0)
			if side > 0:
				_quad("crowd", a0, b0, b1 + lift, a1 + lift, Color.WHITE, uv)
			else:
				_quad("crowd", b0, a0, a1 + lift, b1 + lift, Color.WHITE, uv)
		# Back wall, roof and roof posts.
		var back := off + rows * 0.9 + 0.3
		var topy := 0.6 + rows * 0.5 + 3.4
		var pa: Vector3 = track.points[i] + ri * back
		var pb: Vector3 = track.points[j] + rj * back
		if side > 0:
			_quad("concrete", pb, pa, pa + Vector3(0, topy, 0), pb + Vector3(0, topy, 0), Color(0.72, 0.72, 0.74))
		else:
			_quad("concrete", pa, pb, pb + Vector3(0, topy, 0), pa + Vector3(0, topy, 0), Color(0.72, 0.72, 0.74))
		var fa: Vector3 = track.points[i] + ri * (off - 1.0) + Vector3(0, topy + 0.6, 0)
		var fb2: Vector3 = track.points[j] + rj * (off - 1.0) + Vector3(0, topy + 0.6, 0)
		var roof_col := Color(0.92, 0.92, 0.94)
		if side > 0:
			_quad("concrete", fa, pa + Vector3(0, topy, 0), pb + Vector3(0, topy, 0), fb2, roof_col)
			_quad("concrete", fb2, pb + Vector3(0, topy, 0), pa + Vector3(0, topy, 0), fa, roof_col.darkened(0.3))
		else:
			_quad("concrete", fb2, pb + Vector3(0, topy, 0), pa + Vector3(0, topy, 0), fa, roof_col)
			_quad("concrete", fa, pa + Vector3(0, topy, 0), pb + Vector3(0, topy, 0), fb2, roof_col.darkened(0.3))
		if k % (step * 3) == 0:
			_box("metal", Transform3D(Basis(), pa + Vector3(0, topy * 0.5, 0) - ri * 0.4), Vector3(0.35, topy, 0.35), Color(0.55, 0.56, 0.6))
		_reserve(Transform3D(Basis.looking_at(-track.htangents[i], Vector3.UP), (track.points[i] + track.points[j]) * 0.5 + (ri + rj) * 0.5 * (off + depth * 0.5)), Vector3(depth + 2.0, 10.0, seg + 1.0))
	return true


## Keeps trees and buildings out of this box later.
## overhead: a structure that spans the road above car height (the hotel
## over the tunnel): other scenery keeps clear, but it's meant to be there.
func _reserve(xf: Transform3D, size: Vector3, overhead := false, pit := false) -> void:
	track.scenery_boxes.append({"xf": xf, "size": size, "overhead": overhead, "pit": pit})


# ------------------------------------------------------------ bridges

func _bridges() -> void:
	var n := track.size()
	for frac in [0.3, 0.62]:
		var i := int(n * frac)
		# Only over a straight-ish bit.
		var ok := true
		for k in range(-15, 16):
			if absf(track.curv[posmod(i + k, n)]) > 1.0 / 400.0:
				ok = false
				break
		if not ok:
			continue
		var p: Vector3 = track.points[i]
		var r: Vector3 = track.rights[i]
		var basis := Basis.looking_at(-track.htangents[i], Vector3.UP)
		var span := track.wall_offset + 2.0
		var y := 7.5
		var col := Color(0.86, 0.86, 0.88)
		for side in [-1.0, 1.0]:
			_box("concrete", Transform3D(basis, p + r * span * side + Vector3(0, y * 0.5, 0)), Vector3(3.0, y, 3.0), col)
		_box("concrete", Transform3D(basis, p + Vector3(0, y + 0.6, 0)), Vector3(span * 2.0 + 3.0, 1.2, 3.2), col)
		var fwd: Vector3 = track.htangents[i]
		var ad := _ad_uv(i, 4.0)
		var l0 := p - r * (span + 1.5) + Vector3(0, y + 1.2, 0)
		var l1 := p + r * (span + 1.5) + Vector3(0, y + 1.2, 0)
		var h := Vector3(0, 1.6, 0)
		_quad("ads", l1 - fwd * 1.62, l0 - fwd * 1.62, l0 - fwd * 1.62 + h, l1 - fwd * 1.62 + h, Color.WHITE, ad)
		_quad("ads", l0 + fwd * 1.62, l1 + fwd * 1.62, l1 + fwd * 1.62 + h, l0 + fwd * 1.62 + h, Color.WHITE, ad)


# ------------------------------------------------------------ distant hills

func _hills() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in track.points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var centre := (lo + hi) * 0.5
	var radius := (hi - lo).length() * 0.5 + 450.0
	var seg := 96
	var noise := FastNoiseLite.new()
	noise.seed = track.size()
	noise.frequency = 0.9
	var near_col: Color
	var far_col: Color
	var height := 70.0
	match track.style:
		"desert":
			near_col = Color(0.8, 0.66, 0.46)
			far_col = Color(0.86, 0.76, 0.62)
			height = 35.0
		"city":
			near_col = Color(0.3, 0.38, 0.26)
			far_col = Color(0.5, 0.58, 0.62)
			height = 160.0
		"forest":
			near_col = Color(0.1, 0.22, 0.09)
			far_col = Color(0.32, 0.42, 0.42)
			height = 110.0
		_:
			near_col = Color(0.16, 0.3, 0.12)
			far_col = Color(0.4, 0.5, 0.48)
	for k in range(seg):
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var h0 := height * (0.35 + 0.65 * (noise.get_noise_1d(float(k) / seg * 12.0) * 0.5 + 0.5))
		var h1 := height * (0.35 + 0.65 * (noise.get_noise_1d(float(k + 1) / seg * 12.0) * 0.5 + 0.5))
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var c3 := Vector3(centre.x, (track.terrain_base if not track.terrain_h.is_empty() else Track.GROUND_Y) - 0.5, centre.y)
		var in0 := c3 + d0 * radius
		var in1 := c3 + d1 * radius
		var top0 := c3 + d0 * (radius + 500.0) + Vector3(0, h0, 0)
		var top1 := c3 + d1 * (radius + 500.0) + Vector3(0, h1, 0)
		var back0 := c3 + d0 * (radius + 1100.0) + Vector3(0, h0 * 0.6, 0)
		var back1 := c3 + d1 * (radius + 1100.0) + Vector3(0, h1 * 0.6, 0)
		_hill_quad(in0, in1, top1, top0, near_col)
		_hill_quad(top0, top1, back1, back0, far_col)


func _hill_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	# Faces the centre of the circuit.
	var n := (b - a).cross(c - a)
	if n.y < 0.0:
		_quad("hills", a, d, c, b, col)
	else:
		_quad("hills", a, b, c, d, col)


# ------------------------------------------------------------ street-circuit landmarks

## The harbour-side tunnel under the grand hotel: walls, ceiling with lamp
## strips, portals, and the hotel block on top.
func _tunnel(from_m: float, to_m: float) -> void:
	var n := track.size()
	var i0 := int(from_m / Track.SPACING)
	var i1 := int(to_m / Track.SPACING)
	var height := Track.TUNNEL_H
	track.add_tunnel(i0, i1)
	var concrete := Color(0.62, 0.6, 0.56)
	var ceiling := Color(0.32, 0.31, 0.3)
	var step := 2
	for k in range(i0, i1, step):
		var i := k % n
		var j := (k + step) % n
		var pi: Vector3 = track.points[i]
		var pj: Vector3 = track.points[j]
		var li := track.wall_at(i, -1.0) + 0.5
		var lj := track.wall_at(j, -1.0) + 0.5
		var ri := track.wall_at(i, 1.0) + 0.5
		var rj := track.wall_at(j, 1.0) + 0.5
		var al: Vector3 = pi - track.rights[i] * li
		var bl: Vector3 = pj - track.rights[j] * lj
		var ar: Vector3 = pi + track.rights[i] * ri
		var br: Vector3 = pj + track.rights[j] * rj
		var up := Vector3(0, height, 0)
		var down := Vector3(0, -0.3, 0)
		_quad("tunnel", al + down, bl + down, bl + up, al + up, concrete)
		_quad("tunnel", br + down, ar + down, ar + up, br + up, concrete)
		_quad("tunnel", al + up, bl + up, br + up, ar + up, ceiling)
		var thick := Vector3(0, height + 1.6, 0)
		_quad("tunnel", ar + thick, br + thick, bl + thick, al + thick, concrete.darkened(0.2))
		if k % 4 == 0:
			for o in [-1.6, 1.6]:
				var c: Vector3 = (pi + pj) * 0.5 + track.rights[i] * o + Vector3(0, height - 0.08, 0)
				_box("lamp", Transform3D(Basis.looking_at(-track.htangents[i], Vector3.UP), c), Vector3(0.35, 0.08, 2.6), Color(1.0, 0.93, 0.75))
	# Portal faces above each opening, and the hotel over the tunnel.
	for e in [i0 % n, i1 % n]:
		var p: Vector3 = track.points[e]
		var r: Vector3 = track.rights[e]
		var w := track.wall_at(e, 1.0) + track.wall_at(e, -1.0) + 1.0
		var xf := Transform3D(Basis.looking_at(-track.htangents[e], Vector3.UP), p + r * (track.wall_at(e, 1.0) - track.wall_at(e, -1.0)) * 0.5 + Vector3(0, height + 3.0, 0))
		_box("tunnel", xf, Vector3(w + 6.0, 6.0, 1.2), concrete.darkened(0.1))
	var cream := Color(0.93, 0.89, 0.8)
	for k in range(i0 + 10, i1 - 10, 22):
		var i := k % n
		var p: Vector3 = track.points[i]
		var b := Basis.looking_at(-track.htangents[i], Vector3.UP)
		var size := Vector3(track.wall_offset * 2.0 + 26.0, 22.0, 46.0)
		var xf := Transform3D(b, p + Vector3(0, height + 1.6 + size.y * 0.5, 0))
		_box("concrete", xf, size, cream)
		for f in range(1, 6):
			var band := Transform3D(b, p + Vector3(0, height + 1.6 + f * 3.8, 0))
			_box("glass", band, Vector3(size.x + 0.1, 1.3, size.z + 0.1), Color(0.18, 0.24, 0.3))
		_reserve(Transform3D(b, p), Vector3(size.x, 30.0, size.z), true)


## Motor yachts moored in the harbour.
func _yachts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1929
	var placed := 0
	var spots: Array = []
	for attempt in range(1500):
		if placed >= 34:
			break
		var i := rng.randi() % track.size()
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p: Vector3 = track.points[i] + track.rights[i] * side * rng.randf_range(42.0, 190.0)
		if track.ground_height(p.x, p.z) > track.sea_level - 2.5:
			continue
		var length := rng.randf_range(14.0, 34.0)
		var clash := false
		for q in spots:
			if Vector2(q.x - p.x, q.z - p.z).length() < length * 0.8 + 10.0:
				clash = true
				break
		if clash:
			continue
		spots.append(p)
		placed += 1
		var b := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3) + (PI * 0.5 if rng.randf() < 0.5 else 0.0))
		var beam := length * rng.randf_range(0.2, 0.25)
		var base := Vector3(p.x, track.sea_level, p.z)
		_box("concrete", Transform3D(b, base + Vector3(0, 0.6, 0)), Vector3(beam, 2.0, length), Color(0.96, 0.96, 0.95))
		_box("concrete", Transform3D(b, base + b.z * (length * 0.08) + Vector3(0, 2.3, 0)), Vector3(beam * 0.8, 1.6, length * 0.55), Color(0.98, 0.98, 0.97))
		_box("glass", Transform3D(b, base + b.z * (length * 0.08) + Vector3(0, 2.4, 0)), Vector3(beam * 0.82, 0.6, length * 0.5), Color(0.1, 0.14, 0.2))
		if length > 24.0:
			_box("concrete", Transform3D(b, base + b.z * (length * 0.12) + Vector3(0, 3.7, 0)), Vector3(beam * 0.6, 1.2, length * 0.32), Color(0.98, 0.98, 0.97))


# ------------------------------------------------------------ braking boards

## 300 / 200 / 100 m boards before every big braking zone (where the GP
## car loses more than ~90 km/h), on the side away from the racing line.
func _brake_boards() -> void:
	_board_viewport = SubViewport.new()
	_board_viewport.size = Vector2i(384, 160)
	_board_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_board_viewport.disable_3d = true
	add_child(_board_viewport)
	for k in range(3):
		var bg := ColorRect.new()
		bg.color = Color(0.96, 0.96, 0.96)
		bg.position = Vector2(k * 128 + 4, 4)
		bg.size = Vector2(120, 152)
		_board_viewport.add_child(bg)
		var bar := ColorRect.new()
		bar.color = Color(0.85, 0.1, 0.08)
		bar.position = Vector2(k * 128 + 4, 4)
		bar.size = Vector2(120, 22)
		_board_viewport.add_child(bar)
		var l := Label.new()
		l.text = str(300 - k * 100)
		l.position = Vector2(k * 128, 28)
		l.size = Vector2(128, 120)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UIStyle.font("extrabold"))
		l.add_theme_font_size_override("font_size", 70)
		l.add_theme_color_override("font_color", Color(0.06, 0.06, 0.07))
		_board_viewport.add_child(l)
	var n := track.size()
	var prof := track.speed_profile(CarSpecs.get_spec("gp26"))
	var i := 0
	var placed := 0
	while i < n and placed < 12:
		# A corner: local minimum of the speed profile.
		var a: float = prof[posmod(i - 1, n)]
		var b: float = prof[i]
		var c: float = prof[(i + 1) % n]
		if b < a and b <= c:
			# Peak speed in the 400 m before it.
			var peak := b
			for k in range(1, int(400.0 / Track.SPACING)):
				peak = maxf(peak, prof[posmod(i - k, n)])
			if peak - b > 25.0:
				_board_set(i)
				placed += 1
				i += int(150.0 / Track.SPACING)
				continue
		i += 1


func _board_set(corner: int) -> void:
	var n := track.size()
	# Count back from where the braking ends to where the turn-in starts.
	var side := -signf(track.line_offset[posmod(corner - 60, n)])
	if side == 0.0:
		side = 1.0
	board_spots.append(posmod(corner - int(340.0 / Track.SPACING), n))
	for k in range(3):
		var dist := 300.0 - k * 100.0
		var i := posmod(corner - int((dist + 40.0) / Track.SPACING), n)
		var lat := track.road_half + Track.KERB_W + 3.5
		var base: Vector3 = track.points[i] + track.rights[i] * lat * side
		var fwd: Vector3 = track.htangents[i]
		# Text reads left to right for a driver looking down the track.
		var right: Vector3 = track.rights[i]
		var w := 1.0
		var h := 1.3
		var bottom := base + Vector3(0, 1.0, 0) - fwd * 0.02
		var l0 := bottom - right * w * 0.5
		var r0 := bottom + right * w * 0.5
		var u0 := float(k) / 3.0
		var u1 := float(k + 1) / 3.0
		_quad("boards", l0, r0, r0 + Vector3(0, h, 0), l0 + Vector3(0, h, 0), Color.WHITE,
			[Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)])
		# Plain back, so the number isn't seen mirrored from behind.
		var back := fwd * 0.03
		_quad("concrete", r0 + back, l0 + back, l0 + back + Vector3(0, h, 0), r0 + back + Vector3(0, h, 0), Color(0.55, 0.56, 0.58))
		_box("metal", Transform3D(Basis(), base + Vector3(0, 0.5, 0) + fwd * 0.06), Vector3(0.12, 1.0, 0.12), Color(0.5, 0.52, 0.55))


# ------------------------------------------------------------ marshal posts

func _marshal_posts() -> void:
	if track.style == "city":
		return
	var n := track.size()
	var every := int(480.0 / Track.SPACING)
	for i in range(every / 2, n, every):
		var side := 1.0 if (i / every) % 2 == 0 else -1.0
		var out: Vector3 = track.rights[i] * side
		var p: Vector3 = track.points[i] + out * (track.wall_offset + 3.0)
		var basis := Basis.looking_at(-track.htangents[i], Vector3.UP)
		var xf := Transform3D(basis, p + Vector3(0, 1.3, 0))
		if not track.footprint_clear(Transform3D(basis, p), Vector3(3.0, 3.0, 3.0), 1.0):
			continue
		_box("concrete", xf, Vector3(2.4, 2.6, 2.6), Color(0.93, 0.93, 0.92))
		_box("concrete", Transform3D(basis, p + Vector3(0, 2.7, 0)), Vector3(2.8, 0.2, 3.0), Color(0.95, 0.45, 0.08))
		_box("glass", Transform3D(basis, p + Vector3(0, 1.7, 0) - out * 1.22), Vector3(0.05, 0.8, 1.8), Color(0.2, 0.3, 0.38))
		# Flag pole with a yellow flag.
		var pole := p - out * 1.6 + basis.z * 1.2
		_box("metal", Transform3D(Basis(), pole + Vector3(0, 1.6, 0)), Vector3(0.06, 3.2, 0.06), Color(0.7, 0.7, 0.72))
		_box("concrete", Transform3D(basis, pole + Vector3(0, 2.8, 0) - basis.z * 0.45), Vector3(0.02, 0.6, 0.85), Color(1.0, 0.85, 0.1))
		_reserve(Transform3D(basis, p), Vector3(4.0, 4.0, 4.0))


# ------------------------------------------------------------ TV towers

func _tv_towers() -> void:
	var n := track.size()
	var placed := 0
	for frac in [0.18, 0.45, 0.72]:
		var i := int(n * frac)
		var side := 1.0 if track.curv[i] > 0.0 else -1.0
		var out: Vector3 = track.rights[i] * side
		var p: Vector3 = track.points[i] + out * (track.wall_offset + 7.0)
		var basis := Basis.looking_at(-out, Vector3.UP)
		if not track.footprint_clear(Transform3D(basis, p), Vector3(4.0, 10.0, 4.0), 2.0):
			continue
		var steel := Color(0.62, 0.64, 0.68)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				_box("metal", Transform3D(basis, p + basis.x * cx * 1.1 + basis.z * cz * 1.1 + Vector3(0, 4.0, 0)), Vector3(0.12, 8.0, 0.12), steel)
		for y in [2.0, 4.0, 6.0]:
			_box("metal", Transform3D(basis, p + Vector3(0, y, 0)), Vector3(2.4, 0.08, 2.4), steel)
		_box("concrete", Transform3D(basis, p + Vector3(0, 8.1, 0)), Vector3(2.8, 0.2, 2.8), Color(0.35, 0.36, 0.4))
		# The camera and operator's umbrella.
		_box("metal", Transform3D(basis, p + Vector3(0, 8.6, 0) - out * 0.6), Vector3(0.5, 0.5, 1.0), Color(0.1, 0.1, 0.12))
		_box("concrete", Transform3D(basis, p + Vector3(0, 10.0, 0)), Vector3(2.0, 0.1, 2.0), UIStyle.APEX)
		_reserve(Transform3D(basis, p), Vector3(5.0, 10.0, 5.0))
		placed += 1


# ------------------------------------------------------------ flags

## Flagpoles behind the barrier along the main straight.
func _flagpoles() -> void:
	var n := track.size()
	var colours := [Color(0.85, 0.1, 0.1), Color(0.1, 0.25, 0.65), Color(0.95, 0.95, 0.95), Color(0.1, 0.55, 0.25),
		Color(0.95, 0.75, 0.1), UIStyle.APEX]
	var side := 1.0
	if track.style == "city":
		return
	var k := 0
	for back in range(-60, 0, 6):
		var i := posmod(back, n)
		var out: Vector3 = track.rights[i] * side
		var p: Vector3 = track.points[i] + out * (track.wall_offset + 1.4)
		if not track.footprint_clear(Transform3D(Basis(), p), Vector3(1, 1, 1), 1.0):
			continue
		_box("metal", Transform3D(Basis(), p + Vector3(0, 4.5, 0)), Vector3(0.08, 9.0, 0.08), Color(0.8, 0.8, 0.82))
		var fwd: Vector3 = track.htangents[i]
		var col: Color = colours[k % colours.size()]
		var top := p + Vector3(0, 8.6, 0)
		# Two-panel flag with a slight wave.
		_quad("concrete", top, top + fwd * 0.9 + Vector3(0, 0.08, 0), top + fwd * 0.9 + Vector3(0, -0.9, 0), top + Vector3(0, -1.0, 0), col)
		_quad("concrete", top + fwd * 0.9 + Vector3(0, 0.08, 0), top + fwd * 1.8 + out * 0.15, top + fwd * 1.8 + out * 0.15 + Vector3(0, -1.0, 0), top + fwd * 0.9 + Vector3(0, -0.9, 0), col.darkened(0.15))
		k += 1
