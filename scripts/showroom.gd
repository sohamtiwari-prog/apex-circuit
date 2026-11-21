class_name Showroom
extends Node3D
## The team garage behind the menus, by day or at night (the menus' look): a pale epoxy floor with
## the pit-lane line painted on it, white wall panels over grey cabinets,
## strip lights overhead, and the car on a turntable set
## flush in the floor with its grid box painted round it (the box turns
## with the car). `cam_pos` / `look` frame the car to one side of the
## screen, leaving room for the menu boards.

var showcase: Node3D
var car: RaceCar
var cam: Camera3D
var spin := 0.22

# Day and night: the same garage, lights on after dark (the menus' look).
const DAY := {"floor": Color(0.4, 0.42, 0.44), "plate": Color(0.33, 0.345, 0.36), "wall": Color(0.9, 0.91, 0.92),
	"cabinet": Color(0.28, 0.3, 0.33), "top": Color(0.72, 0.74, 0.76), "ceiling": Color(0.75, 0.77, 0.8),
	"backing": Color(0.62, 0.64, 0.67), "ambient": Color(0.86, 0.88, 0.92), "ambient_energy": 0.75,
	"sun": 0.9, "door": 0.45, "strip": 2.2, "floor_rough": 0.32}
## At night it's a studio more than a workshop: a black lacquered floor the
## car stands reflected in, one pool of light from above, cool rim lights
## picking out its shape from behind, the garage itself fading into the dark.
const NIGHT := {"floor": Color(0.018, 0.02, 0.024), "plate": Color(0.03, 0.032, 0.036), "wall": Color(0.07, 0.075, 0.085),
	"cabinet": Color(0.025, 0.027, 0.03), "top": Color(0.09, 0.095, 0.1), "ceiling": Color(0.02, 0.02, 0.024),
	"backing": Color(0.015, 0.015, 0.018), "ambient": Color(0.42, 0.48, 0.6), "ambient_energy": 0.22,
	"sun": 0.55, "door": 0.08, "strip": 1.6, "floor_rough": 0.07}
const PAINT_WHITE := Color(0.95, 0.95, 0.93)
const PAINT_YELLOW := Color(1.0, 0.8, 0.0)

var pal: Dictionary = DAY


func build(cam_pos := Vector3(5.6, 1.9, 6.4), look := Vector3(0.9, 0.15, -1.6), fov := 36.0) -> void:
	pal = NIGHT if UIStyle.theme == "garage_dark" else DAY
	var sun := Look.build(self, "garage")
	sun.shadow_blur = 2.5
	sun.directional_shadow_max_distance = 30.0
	sun.light_energy = pal["sun"]
	for n in find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (n as WorldEnvironment).environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = pal["ambient"]
		env.ambient_light_energy = pal["ambient_energy"]
		env.glow_intensity = 0.15 if pal == DAY else 0.5
		env.adjustment_contrast = 1.04
		if pal == NIGHT:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.02, 0.02, 0.025)
	# Daylight from the open door (behind the camera), soft.
	var door := DirectionalLight3D.new()
	door.rotation_degrees = Vector3(-12, 40, 0)
	door.light_energy = pal["door"]
	door.light_color = Color(0.95, 0.97, 1.0)
	add_child(door)

	# Floor, the pit-lane line, the turntable.
	_box(Vector3(0, -0.05, 0), Vector3(40, 0.1, 40), pal["floor"], pal["floor_rough"])
	if pal == DAY:
		_box(Vector3(0, 0.002, 4.3), Vector3(40, 0.004, 0.16), PAINT_YELLOW, 0.5)
	var seam := _disc(3.08, Color(0.2, 0.21, 0.23) if pal == DAY else Color(0.0, 0.0, 0.0))
	seam.position.y = 0.001
	add_child(seam)
	showcase = Node3D.new()
	add_child(showcase)
	var plate := _disc(3.0, pal["plate"])
	plate.position.y = 0.003
	showcase.add_child(plate)
	# The grid box: a line across in front of the car, short lines down
	# its sides.
	for b in [[Vector3(0, 0, 2.75), Vector3(2.7, 0.004, 0.14)],
			[Vector3(-1.28, 0, 2.15), Vector3(0.14, 0.004, 1.34)],
			[Vector3(1.28, 0, 2.15), Vector3(0.14, 0.004, 1.34)]]:
		var m := _box(b[0] + Vector3(0, 0.006, 0), b[1], PAINT_WHITE if pal == DAY else Color(0.32, 0.33, 0.35), 0.5, showcase)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Walls: behind (z = -7) and to the left (x = -8).
	_wall(Vector3(0, 0, -7.0), Vector3.RIGHT, 30.0, true)
	_wall(Vector3(-8.0, 0, 0), Vector3.BACK, 30.0, false)
	# Ceiling with the strip lights.
	_box(Vector3(0, 6.1, 0), Vector3(40, 0.2, 40), pal["ceiling"], 0.9)
	for z in [-4.5, -1.0, 2.5]:
		var strip := _box(Vector3(-1.0, 5.95, z), Vector3(9.0, 0.08, 0.28), Color.WHITE, 1.0)
		_glow(strip, Color.WHITE, pal["strip"])
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props()
	# A key light over the turntable (the paint's highlight runs along the
	# car), and the garage itself reflected in the paint, not a sky.
	var key := SpotLight3D.new()
	key.position = Vector3(0.6, 5.6, 0.8)
	key.rotation_degrees = Vector3(-90, 0, 0)
	key.spot_range = 9.0
	key.spot_angle = 34.0
	key.spot_angle_attenuation = 0.6
	key.light_energy = 2.4 if pal == DAY else 7.0
	key.light_color = Color(1.0, 0.98, 0.95)
	key.shadow_enabled = false
	add_child(key)
	if pal == NIGHT:
		key.spot_angle = 28.0
		key.spot_angle_attenuation = 1.4
		# Rim lights behind the car, cool, low: its outline against the dark.
		for r in [[Vector3(-4.5, 1.6, -4.0), Color(0.55, 0.7, 1.0), 9.0], [Vector3(4.8, 2.2, -3.6), Color(1.0, 0.86, 0.7), 6.0]]:
			var rim := OmniLight3D.new()
			rim.position = r[0]
			rim.light_color = r[1]
			rim.light_energy = r[2]
			rim.omni_range = 7.5
			rim.omni_attenuation = 1.6
			add_child(rim)
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(16, 6.4, 14)
	probe.position = Vector3(0, 3.0, 0)
	probe.origin_offset = Vector3(0, -2.2, 0)
	probe.box_projection = true
	probe.intensity = 0.9
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(probe)

	if pal == NIGHT:
		_vignette()
	cam = Camera3D.new()
	cam.fov = fov
	cam.position = cam_pos
	add_child(cam)
	cam.look_at(look, Vector3.UP)
	cam.current = true


## One wall: grey cabinets along the bottom, white panels above with dark
## seams between them.
func _wall(origin: Vector3, along: Vector3, length: float, board: bool) -> void:
	var out := Vector3.UP.cross(along).normalized()     # (faces into the garage)
	if out.dot(-origin) < 0.0:
		out = -out
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var n := int(length / 1.5)
	for k in n:
		var c := origin + along * (-length * 0.5 + 0.75 + k * 1.5)
		_box(c + Vector3.UP * 3.6, Vector3(1.47, 4.8, 0.1), pal["wall"], 0.7, self, basis)
		_box(c + Vector3.UP * 0.6 + out * 0.3, Vector3(1.46, 1.2, 0.6), pal["cabinet"], 0.45, self, basis)
		_box(c + Vector3.UP * 1.17 + out * 0.32, Vector3(1.48, 0.06, 0.66), pal["top"], 0.3, self, basis)
	_box(origin - out * 0.06 + Vector3.UP * 3.0, Vector3(length, 6.0, 0.05), pal["backing"], 0.9, self, basis)
	if board and pal == DAY:
		# The pit-lane yellow carried up the wall at cabinet height.
		var line := _box(origin + out * 0.62 + Vector3.UP * 1.21, Vector3(length, 0.03, 0.04), PAINT_YELLOW, 0.5, self, basis)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## What a working garage has lying about: stacks of tyres in the three
## compounds' colours, a red tool chest, and the timing screen on the wall.
func _props() -> void:
	# Wheels stood against the cabinets, sidewalls out: softs (red bands)
	# and mediums (yellow).
	var rubber := Color(0.045, 0.045, 0.05)
	for k in 5:
		var col: Color = Color(0.86, 0.1, 0.1) if k < 3 else Color(1.0, 0.8, 0.0)
		var wheel := Node3D.new()
		wheel.position = Vector3(-6.4 + k * 0.82, 0.36, -5.85)
		wheel.rotation_degrees = Vector3(90, 0, 0)
		add_child(wheel)
		wheel.add_child(_cyl(0.36, 0.38, rubber, 0.85))
		var band := TorusMesh.new()
		band.inner_radius = 0.27
		band.outer_radius = 0.305
		band.rings = 40
		var bm := MeshInstance3D.new()
		bm.mesh = band
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.6
		bm.material_override = mat
		bm.scale = Vector3(1, 0.2, 1)
		bm.position = Vector3(0, 0.19, 0)
		wheel.add_child(bm)
		var rim := _cyl(0.22, 0.385, Color(0.16, 0.16, 0.17), 0.35)
		wheel.add_child(rim)
		var nut := _cyl(0.06, 0.4, Color(0.75, 0.76, 0.78), 0.3)
		wheel.add_child(nut)
	# The tool chest: red, drawers, on castors.
	var chest := Node3D.new()
	chest.position = Vector3(3.2, 0, -5.7)
	chest.rotation_degrees.y = -8.0
	add_child(chest)
	_box(Vector3(0, 0.62, 0), Vector3(1.4, 1.0, 0.62), Color(0.78, 0.06, 0.1), 0.35, chest)
	_box(Vector3(0, 1.15, 0), Vector3(1.44, 0.06, 0.66), Color(0.12, 0.12, 0.13), 0.5, chest)
	for d in 6:
		_box(Vector3(0, 0.27 + d * 0.16, 0.315), Vector3(1.3, 0.012, 0.01), Color(0.25, 0.02, 0.04), 0.5, chest)
		_box(Vector3(0, 0.33 + d * 0.16, 0.325), Vector3(0.9, 0.025, 0.02), Color(0.75, 0.76, 0.78), 0.25, chest)
	for x in [-0.6, 0.6]:
		for z in [-0.24, 0.24]:
			var w := _cyl(0.06, 0.05, Color(0.05, 0.05, 0.05), 0.8)
			w.rotation_degrees.z = 90.0
			w.position = Vector3(x, 0.06, z)
			chest.add_child(w)
	if pal == NIGHT:
		return
	# The timing screen: the running order in coloured rows.
	var scr := Node3D.new()
	scr.position = Vector3(-4.6, 2.35, -6.88)
	add_child(scr)
	_box(Vector3.ZERO, Vector3(2.4, 1.4, 0.06), Color(0.02, 0.02, 0.02), 0.4, scr)
	var lit := _box(Vector3(0, 0, 0.032), Vector3(2.26, 1.26, 0.005), Color(0.03, 0.035, 0.045), 0.3, scr)
	_glow(lit, Color(0.03, 0.04, 0.06), 1.0)
	var widths := [1.7, 1.55, 1.62, 1.4, 1.48, 1.3, 1.36, 1.2]
	for r in widths.size():
		var c := Color(0.85, 0.87, 0.9)
		if r == 2:
			c = Color(1.0, 0.82, 0.0)
		elif r == 0:
			c = Color(0.7, 0.35, 1.0)
		var y := 0.5 - r * 0.142
		var bar := _box(Vector3(-0.9 + float(widths[r]) * 0.5, y, 0.038), Vector3(widths[r], 0.07, 0.004), c, 0.5, scr)
		_glow(bar, c, 1.6)
		var pos := _box(Vector3(-1.02, y, 0.038), Vector3(0.12, 0.07, 0.004), Color(0.95, 0.95, 0.95), 0.5, scr)
		_glow(pos, Color(0.95, 0.95, 0.95), 1.2)


func _glow(m: MeshInstance3D, c: Color, energy: float) -> void:
	var mat := m.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = energy


func _cyl(r: float, h: float, colour: Color, rough: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 28
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = rough
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	return m


func _box(pos: Vector3, size: Vector3, colour: Color, rough: float, parent: Node = null, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = rough
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.transform = Transform3D(basis, pos)
	(parent if parent != null else self).add_child(m)
	return m


func _disc(r: float, colour: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.004
	mesh.radial_segments = 96
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.35
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	return m


func show_spec(spec: Dictionary) -> void:
	if car != null:
		car.queue_free()
	car = RaceCar.new()
	car.setup(spec)
	car.freeze = true
	showcase.add_child(car)
	car.position.y = car.spawn_height() - 0.05
	on_stand(car)


## A boat on show stands on a cradle (its outboard's leg hangs below the hull).
static func on_stand(c: RaceCar) -> void:
	if c.hull == null:
		return
	c.position.y += 0.62
	var st := MeshKit.new_tool()
	var grey := Color(0.2, 0.21, 0.23)
	for sx in [-0.82, 0.82]:
		MeshKit.box(st, Vector3(0.22, 0.12, 4.6), Vector3(sx, -0.06, -0.2), Color(0.12, 0.12, 0.13))
		for z in [-1.9, 1.4]:
			MeshKit.box(st, Vector3(0.12, 0.6, 0.12), Vector3(sx, -0.38, z), grey)
	MeshKit.box(st, Vector3(1.9, 0.1, 0.14), Vector3(0, -0.62, -1.9), grey)
	MeshKit.box(st, Vector3(1.9, 0.1, 0.14), Vector3(0, -0.62, 1.4), grey)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.finish(st)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.5
	m.roughness = 0.4
	mi.material_override = m
	c.add_child(mi)


func _process(delta: float) -> void:
	if showcase != null:
		showcase.rotate_y(delta * spin)


## The edges of the picture fall away into the dark (under the menus).
func _vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.0, 0.0, 0.01, 0.78))
	g.add_point(0.55, Color(0, 0, 0, 0.12))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.42, 0.5)
	tex.fill_to = Vector2(1.08, 1.0)
	tex.width = 256
	tex.height = 144
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)
