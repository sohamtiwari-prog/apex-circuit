class_name CarBody
extends Node3D
## Builds a car's visual model from primitives. Car forward is +Z.

var helmet: MeshInstance3D
var _paint: StandardMaterial3D
var _accent: StandardMaterial3D
var _carbon: StandardMaterial3D
var _mats := {}


func build(spec: Dictionary, car: RaceCar) -> void:
	_paint = _mat(spec["color"], 0.55, 0.3)
	_accent = _mat(spec["accent"], 0.4, 0.4)
	_carbon = _mat(Color(0.05, 0.05, 0.06), 0.3, 0.55)
	if spec["body"] == "gp":
		_build_gp()
	else:
		_build_gt()
	for w in car.wheels:
		_build_wheel(w, spec, spec["body"] == "gp")


## Hide the driver's own helmet when the camera sits inside it.
func set_cockpit_view(on: bool) -> void:
	if helmet != null:
		helmet.visible = not on


func _mat(color: Color, metallic := 0.0, rough := 0.5, emission := Color.BLACK) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color, metallic, rough, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 2.0
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	(parent if parent != null else self).add_child(mi)
	return mi


func _prism(size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var pm := PrismMesh.new()
	pm.size = size
	pm.left_to_right = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO, top := -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top < 0.0 else top
	cm.height = height
	cm.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi


# ------------------------------------------------------------ GP car

func _build_gp() -> void:
	var white := _mat(Color(0.92, 0.92, 0.93), 0.3, 0.35)
	var dark := _carbon
	var halo_mat := _mat(Color(0.12, 0.12, 0.13), 0.7, 0.3)
	var red_light := _mat(Color(0.5, 0.0, 0.0), 0.0, 0.3, Color(1, 0.05, 0.02))
	var visor := _mat(Color(0.02, 0.02, 0.03), 0.9, 0.05)

	# Floor and plank.
	_box(Vector3(1.55, 0.04, 3.1), Vector3(0, -0.1, -0.25), dark)
	_box(Vector3(0.3, 0.03, 3.4), Vector3(0, -0.125, -0.1), _mat(Color(0.45, 0.35, 0.2), 0.0, 0.8))
	# Survival cell / cockpit tub.
	_box(Vector3(0.78, 0.46, 1.7), Vector3(0, 0.15, 0.5), _paint)
	_box(Vector3(0.5, 0.06, 0.62), Vector3(0, 0.39, 0.3), dark)               # cockpit opening rim
	# Nose: tapering down to the front wing.
	_box(Vector3(0.42, 0.26, 0.9), Vector3(0, 0.17, 1.65), _paint, Vector3(-6, 0, 0))
	_box(Vector3(0.3, 0.18, 0.7), Vector3(0, 0.06, 2.3), _paint, Vector3(-10, 0, 0))
	_box(Vector3(0.22, 0.12, 0.25), Vector3(0, -0.02, 2.72), white)
	# Front wing: main plane, flaps, endplates.
	_box(Vector3(1.96, 0.03, 0.44), Vector3(0, -0.1, 2.6), dark)
	_box(Vector3(1.86, 0.03, 0.22), Vector3(0, -0.05, 2.5), _paint, Vector3(-14, 0, 0))
	_box(Vector3(1.7, 0.03, 0.18), Vector3(0, 0.0, 2.43), white, Vector3(-22, 0, 0))
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.03, 0.24, 0.55), Vector3(0.98 * sx, -0.02, 2.55), _paint)
	# Sidepods with inlets and an undercut.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.42, 0.38, 1.9), Vector3(0.6 * sx, 0.08, -0.35), _paint)
		_box(Vector3(0.36, 0.22, 0.06), Vector3(0.6 * sx, 0.14, 0.62), dark)         # inlet
		_box(Vector3(0.3, 0.1, 1.3), Vector3(0.62 * sx, -0.12, -0.2), dark)           # undercut
		_box(Vector3(0.12, 0.05, 0.08), Vector3(0.48 * sx, 0.42, 0.78), dark)         # mirror
		_box(Vector3(0.03, 0.12, 0.03), Vector3(0.44 * sx, 0.36, 0.78), dark)         # mirror stalk
	# Engine cover tapering to the rear, shark fin.
	_box(Vector3(0.66, 0.46, 1.7), Vector3(0, 0.36, -0.75), _paint)
	_box(Vector3(0.4, 0.34, 0.9), Vector3(0, 0.22, -1.85), _paint)
	_box(Vector3(0.03, 0.3, 1.0), Vector3(0, 0.72, -1.4), _paint)
	# Airbox / roll hoop above the driver.
	_box(Vector3(0.34, 0.36, 0.45), Vector3(0, 0.78, -0.12), _paint)
	_box(Vector3(0.22, 0.16, 0.06), Vector3(0, 0.8, 0.12), dark)                  # intake
	# Halo: centre pillar plus a hoop around the cockpit.
	_box(Vector3(0.05, 0.34, 0.05), Vector3(0, 0.57, 0.92), halo_mat, Vector3(-18, 0, 0))
	_box(Vector3(0.05, 0.05, 0.42), Vector3(0, 0.74, 0.7), halo_mat, Vector3(-8, 0, 0))
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.05, 0.62), Vector3(0.2 * sx, 0.72, 0.3), halo_mat, Vector3(0, 18 * sx, 0))
	# Driver.
	helmet = MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.14
	hs.height = 0.28
	helmet.mesh = hs
	helmet.material_override = _mat(Color(1.0, 0.85, 0.1), 0.2, 0.3)
	helmet.position = Vector3(0, 0.56, 0.22)
	add_child(helmet)
	_box(Vector3(0.2, 0.06, 0.04), Vector3(0, 0.58, 0.35), visor, Vector3.ZERO, helmet)
	helmet.get_child(0).position = Vector3(0, 0.02, 0.13)
	# Steering wheel, visible from the cockpit camera.
	_box(Vector3(0.28, 0.13, 0.03), Vector3(0, 0.5, 0.6), dark, Vector3(-20, 0, 0))
	_box(Vector3(0.12, 0.05, 0.02), Vector3(0, 0.52, 0.585), _mat(Color(0.1, 0.6, 0.2), 0.0, 0.3, Color(0.1, 1.0, 0.3)), Vector3(-20, 0, 0))
	# Rear wing: beam wing, main plane, DRS flap, endplates, swan neck.
	_box(Vector3(0.9, 0.03, 0.22), Vector3(0, 0.33, -2.32), dark)
	_box(Vector3(1.0, 0.04, 0.34), Vector3(0, 0.8, -2.35), dark, Vector3(8, 0, 0))
	_box(Vector3(1.0, 0.04, 0.24), Vector3(0, 0.93, -2.43), _paint, Vector3(28, 0, 0))
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.03, 0.5, 0.62), Vector3(0.51 * sx, 0.72, -2.33), _paint)
	_box(Vector3(0.05, 0.42, 0.08), Vector3(0, 0.6, -2.2), dark)
	# Diffuser and rain light.
	_box(Vector3(1.0, 0.18, 0.4), Vector3(0, -0.02, -2.2), dark, Vector3(-12, 0, 0))
	_box(Vector3(0.12, 0.08, 0.03), Vector3(0, 0.24, -2.5), red_light)


# ------------------------------------------------------------ GT car

func _build_gt() -> void:
	var dark := _accent
	var glass := _mat(Color(0.08, 0.1, 0.14), 0.5, 0.08)
	var head := _mat(Color(0.9, 0.9, 0.85), 0.0, 0.2, Color(1, 0.95, 0.85))
	var tail := _mat(Color(0.6, 0.02, 0.02), 0.0, 0.3, Color(1, 0.05, 0.03))
	_box(Vector3(1.88, 0.36, 4.3), Vector3(0, -0.08, 0), _paint)
	_box(Vector3(1.94, 0.14, 3.0), Vector3(0, -0.22, 0.0), dark)
	_box(Vector3(1.84, 0.2, 1.3), Vector3(0, 0.15, 1.45), _paint, Vector3(-7, 0, 0))
	_box(Vector3(1.9, 0.16, 0.4), Vector3(0, -0.2, 2.15), dark)
	_box(Vector3(1.5, 0.38, 1.8), Vector3(0, 0.32, -0.25), glass)
	_box(Vector3(1.42, 0.08, 1.4), Vector3(0, 0.53, -0.3), _paint)
	_box(Vector3(1.6, 0.3, 1.3), Vector3(0, 0.2, -1.55), _paint, Vector3(6, 0, 0))
	_box(Vector3(0.06, 0.18, 0.7), Vector3(-0.95, 0.02, -0.75), dark)
	_box(Vector3(0.06, 0.18, 0.7), Vector3(0.95, 0.02, -0.75), dark)
	_box(Vector3(0.08, 0.3, 0.12), Vector3(-0.6, 0.45, -2.0), dark)
	_box(Vector3(0.08, 0.3, 0.12), Vector3(0.6, 0.45, -2.0), dark)
	_box(Vector3(1.9, 0.05, 0.38), Vector3(0, 0.62, -2.03), dark, Vector3(-8, 0, 0))
	_box(Vector3(1.7, 0.16, 0.3), Vector3(0, -0.2, -2.12), dark)
	_box(Vector3(0.42, 0.07, 0.06), Vector3(-0.62, 0.1, 2.12), head)
	_box(Vector3(0.42, 0.07, 0.06), Vector3(0.62, 0.1, 2.12), head)
	_box(Vector3(1.6, 0.06, 0.05), Vector3(0, 0.08, -2.16), tail)


# ------------------------------------------------------------ wheels

func _build_wheel(w: VehicleWheel3D, spec: Dictionary, open_wheel: bool) -> void:
	var front := w.use_as_steering
	var r: float = w.wheel_radius
	var width: float = spec["tyre_width_front"] if front else spec["tyre_width_rear"]
	var side := signf(w.position.x)

	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = r
	tire_mesh.bottom_radius = r
	tire_mesh.height = width
	tire_mesh.radial_segments = 24
	var tire := MeshInstance3D.new()
	tire.mesh = tire_mesh
	tire.material_override = _mat(Color(0.05, 0.05, 0.05), 0.0, 0.85)
	tire.rotation.z = PI / 2.0
	w.add_child(tire)

	var rim_r := r * (0.62 if open_wheel else 0.68)
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = rim_r
	rim_mesh.bottom_radius = rim_r
	rim_mesh.height = 0.02
	rim_mesh.radial_segments = 16
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = _mat(Color(0.12, 0.12, 0.13), 0.8, 0.3) if open_wheel else _mat(Color(0.75, 0.76, 0.78), 0.9, 0.25)
	rim.rotation.z = PI / 2.0
	rim.position.x = (width * 0.5 + 0.005) * side
	w.add_child(rim)
	if open_wheel:
		# Tyre-compound stripe, like a soft (red) Pirelli-style marking.
		var stripe_mesh := TorusMesh.new()
		stripe_mesh.inner_radius = r * 0.78
		stripe_mesh.outer_radius = r * 0.84
		var stripe := MeshInstance3D.new()
		stripe.mesh = stripe_mesh
		stripe.material_override = _mat(Color(0.9, 0.08, 0.08), 0.0, 0.5)
		stripe.rotation.z = PI / 2.0
		stripe.position.x = (width * 0.5 + 0.004) * side
		stripe.scale = Vector3(1, 0.2, 1)
		w.add_child(stripe)
	# A spoke so the wheel visibly turns.
	var sp := MeshInstance3D.new()
	var spoke := BoxMesh.new()
	spoke.size = Vector3(0.02, rim_r * 1.8, 0.05)
	sp.mesh = spoke
	sp.material_override = _mat(Color(0.3, 0.3, 0.32), 0.8, 0.3)
	sp.position.x = (width * 0.5 + 0.012) * side
	w.add_child(sp)

	if open_wheel:
		# Wishbones from the chassis to the upright (fixed to the body).
		var inner_x := 0.38 * side
		var outer_x: float = w.position.x - 0.12 * side
		var mid := Vector3((inner_x + outer_x) * 0.5, w.position.y - 0.05, w.position.z)
		var length := absf(outer_x - inner_x)
		_box(Vector3(length, 0.025, 0.05), mid + Vector3(0, 0.1, 0), _carbon)
		_box(Vector3(length, 0.025, 0.05), mid + Vector3(0, -0.06, 0), _carbon)
