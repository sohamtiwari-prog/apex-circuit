class_name Showroom
extends Node3D
## The team garage behind the menus, in daylight: a pale epoxy floor with
## the pit-lane line painted on it, white wall panels over grey cabinets,
## strip lights overhead, and the car on a turntable set
## flush in the floor with its grid box painted round it (the box turns
## with the car). `cam_pos` / `look` frame the car to one side of the
## screen, leaving room for the menu boards.

var showcase: Node3D
var car: RaceCar
var cam: Camera3D
var spin := 0.22

const FLOOR := Color(0.4, 0.42, 0.44)
const PLATE := Color(0.33, 0.345, 0.36)
const WALL := Color(0.9, 0.91, 0.92)
const CABINET := Color(0.28, 0.3, 0.33)
const PAINT_WHITE := Color(0.95, 0.95, 0.93)
const PAINT_YELLOW := Color(1.0, 0.8, 0.0)


func build(cam_pos := Vector3(5.6, 1.9, 6.4), look := Vector3(0.9, 0.15, -1.6), fov := 36.0) -> void:
	var sun := Look.build(self, "garage")
	sun.shadow_blur = 2.5
	sun.directional_shadow_max_distance = 30.0
	for n in find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (n as WorldEnvironment).environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.86, 0.88, 0.92)
		env.ambient_light_energy = 0.75
		env.glow_intensity = 0.15
		env.adjustment_contrast = 1.04
	# Daylight from the open door (behind the camera), soft.
	var door := DirectionalLight3D.new()
	door.rotation_degrees = Vector3(-12, 40, 0)
	door.light_energy = 0.45
	door.light_color = Color(0.95, 0.97, 1.0)
	add_child(door)

	# Floor, the pit-lane line, the turntable.
	_box(Vector3(0, -0.05, 0), Vector3(40, 0.1, 40), FLOOR, 0.32)
	_box(Vector3(0, 0.002, 4.3), Vector3(40, 0.004, 0.16), PAINT_YELLOW, 0.5)
	var seam := _disc(3.08, Color(0.2, 0.21, 0.23))
	seam.position.y = 0.001
	add_child(seam)
	showcase = Node3D.new()
	add_child(showcase)
	var plate := _disc(3.0, PLATE)
	plate.position.y = 0.003
	showcase.add_child(plate)
	# The grid box: a line across in front of the car, short lines down
	# its sides.
	for b in [[Vector3(0, 0, 2.75), Vector3(2.7, 0.004, 0.14)],
			[Vector3(-1.28, 0, 2.15), Vector3(0.14, 0.004, 1.34)],
			[Vector3(1.28, 0, 2.15), Vector3(0.14, 0.004, 1.34)]]:
		var m := _box(b[0] + Vector3(0, 0.006, 0), b[1], PAINT_WHITE, 0.5, showcase)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Walls: behind (z = -7) and to the left (x = -8).
	_wall(Vector3(0, 0, -7.0), Vector3.RIGHT, 30.0, true)
	_wall(Vector3(-8.0, 0, 0), Vector3.BACK, 30.0, false)
	# Ceiling with the strip lights.
	_box(Vector3(0, 6.1, 0), Vector3(40, 0.2, 40), Color(0.75, 0.77, 0.8), 0.9)
	for z in [-4.5, -1.0, 2.5]:
		var strip := _box(Vector3(-1.0, 5.95, z), Vector3(9.0, 0.08, 0.28), Color.WHITE, 1.0)
		var mat := strip.material_override as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = 2.2
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
		_box(c + Vector3.UP * 3.6, Vector3(1.47, 4.8, 0.1) * Vector3(1, 1, 1), WALL, 0.7, self, basis)
		_box(c + Vector3.UP * 0.6 + out * 0.3, Vector3(1.46, 1.2, 0.6), CABINET, 0.45, self, basis)
		_box(c + Vector3.UP * 1.17 + out * 0.32, Vector3(1.48, 0.06, 0.66), Color(0.72, 0.74, 0.76), 0.3, self, basis)
	_box(origin - out * 0.06 + Vector3.UP * 3.0, Vector3(length, 6.0, 0.05), Color(0.62, 0.64, 0.67), 0.9, self, basis)
	if board:
		# The pit-lane yellow carried up the wall at cabinet height.
		var line := _box(origin + out * 0.62 + Vector3.UP * 1.21, Vector3(length, 0.03, 0.04), PAINT_YELLOW, 0.5, self, basis)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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


func _process(delta: float) -> void:
	if showcase != null:
		showcase.rotate_y(delta * spin)
