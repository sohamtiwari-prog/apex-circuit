class_name RaceCar
extends VehicleBody3D
## Player/AI car. Forward is +Z in local space.
##
## Inputs (set every physics frame by a controller):
##   throttle     0..1
##   brake_input  0..1   (also reverses when nearly stopped)
##   steer_input  -1..1  (+ = right)

# Signs verified by tests/sim_test.gd against Godot's VehicleBody3D.
const STEER_SIGN := -1.0
const ENGINE_SIGN := 1.0

@export var body_color := Color(1.0, 0.42, 0.1)

# Drivetrain / aero tuning (SI units).
var car_mass := 1250.0
var max_drive_force := 8200.0     # N at the rear axle, low speed
var power := 270000.0             # W, caps force at speed
var drag_coef := 0.5              # F = c * v^2
var downforce_coef := 1.1         # F = c * v^2
var brake_decel := 12.0           # m/s^2 at full brake (before grip limit)
var max_steer_low := 0.55         # rad at parking speed
var max_steer_high := 0.085       # rad at 200+ km/h
var steer_rate := 2.4             # rad/s

var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var controls_enabled := true
var surface_drag := 0.0           # extra drag when off the road (set by race logic)

var wheels: Array[VehicleWheel3D] = []
var _steer := 0.0


func _ready() -> void:
	mass = car_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.22, 0.05)
	can_sleep = false
	# Godot's default damping acts like a huge invisible parachute; we model
	# aero drag ourselves, so remove it.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.4
	_build_collision()
	_build_body()
	_add_wheel(Vector3(-0.82, 0.1, 1.33), true)
	_add_wheel(Vector3(0.82, 0.1, 1.33), true)
	_add_wheel(Vector3(-0.84, 0.1, -1.28), false)
	_add_wheel(Vector3(0.84, 0.1, -1.28), false)


func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


func speed_kmh() -> float:
	return absf(forward_speed()) * 3.6


func reset_controls() -> void:
	throttle = 0.0
	brake_input = 0.0
	steer_input = 0.0
	_steer = 0.0
	steering = 0.0


func _physics_process(delta: float) -> void:
	var v := forward_speed()
	var thr := throttle if controls_enabled else 0.0
	var brk := brake_input if controls_enabled else 1.0
	var str_in := steer_input if controls_enabled else 0.0

	# Speed-sensitive steering, rate limited so inputs feel smooth.
	var max_steer := lerpf(max_steer_low, max_steer_high, clampf(absf(v) / 56.0, 0.0, 1.0))
	_steer = move_toward(_steer, clampf(str_in, -1.0, 1.0) * max_steer, steer_rate * delta)
	steering = _steer * STEER_SIGN

	var drive := 0.0
	var braking := 0.0
	if not controls_enabled:
		braking = 1.0              # held on the brakes (grid, countdown)
	elif brk > 0.05:
		if v > 1.5:
			braking = brk
		else:
			drive = -brk * 0.4     # reverse
	elif thr > 0.01:
		drive = thr

	if drive != 0.0:
		var force := minf(max_drive_force, power / maxf(absf(v), 1.0))
		engine_force = drive * force * 0.5 * ENGINE_SIGN   # per rear wheel
		brake = 0.0
	else:
		engine_force = 0.0
		# VehicleBody3D brake is an impulse per wheel per physics tick.
		var per_wheel_force := mass * brake_decel * 0.25 * braking + 60.0
		brake = per_wheel_force / float(Engine.physics_ticks_per_second)

	var vel := linear_velocity
	var spd := vel.length()
	apply_central_force(-vel * spd * drag_coef)
	apply_central_force(-global_basis.y * downforce_coef * v * v)
	if surface_drag > 0.0:
		var flat := Vector3(vel.x, 0.0, vel.z)
		apply_central_force(-flat * mass * surface_drag)


# ------------------------------------------------------------ construction

func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.86, 0.62, 4.36)
	cs.shape = shape
	cs.position = Vector3(0, 0.02, 0)
	add_child(cs)
	var cabin := CollisionShape3D.new()
	var cshape := BoxShape3D.new()
	cshape.size = Vector3(1.4, 0.42, 1.9)
	cabin.shape = cshape
	cabin.position = Vector3(0, 0.5, -0.3)
	add_child(cabin)


func _mat(color: Color, metallic := 0.0, rough := 0.5, emission := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 2.0
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


## Original design: the "Apex Vanta GT", a mid-engined coupe.
func _build_body() -> void:
	var paint := _mat(body_color, 0.6, 0.28)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.2, 0.6)
	var glass := _mat(Color(0.08, 0.1, 0.14), 0.5, 0.08)
	var head := _mat(Color(0.9, 0.9, 0.85), 0.0, 0.2, Color(1, 0.95, 0.85))
	var tail := _mat(Color(0.6, 0.02, 0.02), 0.0, 0.3, Color(1, 0.05, 0.03))

	# Main tub and sills.
	_box(Vector3(1.88, 0.36, 4.3), Vector3(0, -0.08, 0), paint)
	_box(Vector3(1.94, 0.14, 3.0), Vector3(0, -0.22, 0.0), dark)
	# Nose, sloping down towards the front.
	_box(Vector3(1.84, 0.2, 1.3), Vector3(0, 0.15, 1.45), paint, Vector3(deg_to_rad(-7), 0, 0))
	_box(Vector3(1.9, 0.16, 0.4), Vector3(0, -0.2, 2.15), dark)    # splitter
	# Cabin + glasshouse.
	_box(Vector3(1.5, 0.38, 1.8), Vector3(0, 0.32, -0.25), glass)
	_box(Vector3(1.42, 0.08, 1.4), Vector3(0, 0.53, -0.3), paint)   # roof
	_box(Vector3(1.6, 0.3, 1.3), Vector3(0, 0.2, -1.55), paint, Vector3(deg_to_rad(6), 0, 0))  # engine cover
	# Side intakes.
	_box(Vector3(0.06, 0.18, 0.7), Vector3(-0.95, 0.02, -0.75), dark)
	_box(Vector3(0.06, 0.18, 0.7), Vector3(0.95, 0.02, -0.75), dark)
	# Rear wing.
	_box(Vector3(0.08, 0.3, 0.12), Vector3(-0.6, 0.45, -2.0), dark)
	_box(Vector3(0.08, 0.3, 0.12), Vector3(0.6, 0.45, -2.0), dark)
	_box(Vector3(1.9, 0.05, 0.38), Vector3(0, 0.62, -2.03), dark, Vector3(deg_to_rad(-8), 0, 0))
	# Diffuser.
	_box(Vector3(1.7, 0.16, 0.3), Vector3(0, -0.2, -2.12), dark)
	# Lights.
	_box(Vector3(0.42, 0.07, 0.06), Vector3(-0.62, 0.1, 2.12), head)
	_box(Vector3(0.42, 0.07, 0.06), Vector3(0.62, 0.1, 2.12), head)
	_box(Vector3(1.6, 0.06, 0.05), Vector3(0, 0.08, -2.16), tail)


func _add_wheel(pos: Vector3, front: bool) -> void:
	var w := VehicleWheel3D.new()
	w.position = pos
	w.use_as_steering = front
	w.use_as_traction = not front
	w.wheel_radius = 0.34
	w.wheel_rest_length = 0.25
	w.suspension_travel = 0.2
	w.suspension_stiffness = 45.0
	w.suspension_max_force = 30000.0
	w.damping_compression = 2.6
	w.damping_relaxation = 3.6
	w.wheel_friction_slip = 2.9 if front else 3.1
	w.wheel_roll_influence = 0.06
	add_child(w)
	wheels.append(w)

	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = 0.34
	tire_mesh.bottom_radius = 0.34
	tire_mesh.height = 0.27
	tire_mesh.radial_segments = 20
	var tire := MeshInstance3D.new()
	tire.mesh = tire_mesh
	tire.material_override = _mat(Color(0.04, 0.04, 0.04), 0.0, 0.9)
	tire.rotation.z = PI / 2.0
	w.add_child(tire)

	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.23
	rim_mesh.bottom_radius = 0.23
	rim_mesh.height = 0.02
	rim_mesh.radial_segments = 10
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = _mat(Color(0.75, 0.76, 0.78), 0.9, 0.25)
	rim.rotation.z = PI / 2.0
	rim.position.x = 0.14 * signf(pos.x)
	w.add_child(rim)
	# A spoke so you can see the wheel turning.
	var spoke := BoxMesh.new()
	spoke.size = Vector3(0.025, 0.4, 0.06)
	var sp := MeshInstance3D.new()
	sp.mesh = spoke
	sp.material_override = _mat(Color(0.2, 0.2, 0.22), 0.8, 0.3)
	sp.position.x = 0.15 * signf(pos.x)
	w.add_child(sp)
