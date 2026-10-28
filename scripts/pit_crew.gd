class_name PitCrew
extends Node3D
## A team's pit crew at work on a stopped car: a gunner and two tyre men at
## each wheel, front and rear jack men, and the lollipop man in front.
## `progress` (0..1, set by the race weekend) drives the stop: the car goes
## up on the jacks, the old wheels come off and are carried out, the new
## ones go on, the car drops, and release() turns the lollipop green. The
## crew steps away and is removed once the car has gone.

var progress := 0.0:
	set(v):
		progress = v
		_animate()

var car: RaceCar
var _crew: MeshInstance3D
var _old: Array[MeshInstance3D] = []
var _new: Array[MeshInstance3D] = []
var _wheel_local: Array[Vector3] = []
var _outward: Array[float] = []
var _sign: MeshInstance3D
var _sign_mat: StandardMaterial3D
var _released := false
var _gone := 0.0
var _new_colour := Color.WHITE
var _swapped := false

const LIFT := 0.03


func setup(c: RaceCar, track: Track, team: int, compound_colour: Color) -> void:
	car = c
	_new_colour = compound_colour
	# Work in the car's frame as it sits in the box (level).
	var b := car.global_basis
	var fwd := Vector3(b.z.x, 0.0, b.z.z).normalized()
	global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), car.global_position - Vector3(0, 0.25, 0))
	var spec := car.spec
	var t: Dictionary = CarSpecs.TEAMS[posmod(team, CarSpecs.TEAMS.size())]
	var suit: Color = t["base"]
	var trim: Color = t.get("accent", Color(0.95, 0.95, 0.95))
	var st := MeshKit.new_tool()
	var inv := global_transform.affine_inverse()
	for w in car.wheels:
		var p: Vector3 = inv * w.global_position
		_wheel_local.append(p)
		_outward.append(signf(p.x) if absf(p.x) > 0.05 else 1.0)
	var front_z := 0.0
	var rear_z := 0.0
	for p in _wheel_local:
		front_z = maxf(front_z, p.z)
		rear_z = minf(rear_z, p.z)
	var ground := 0.0
	for k in _wheel_local.size():
		var p := _wheel_local[k]
		var o := _outward[k]
		ground = p.y - float(car.wheels[k].wheel_radius)
		# Gunner kneeling at the wheel; tyre-off man behind, tyre-on man in front.
		_person(st, Vector3(p.x + o * 0.75, ground, p.z), PI / 2 * -o, true, suit, trim)
		_person(st, Vector3(p.x + o * 1.05, ground, p.z - 0.95), PI / 2 * -o, false, suit, trim)
		_person(st, Vector3(p.x + o * 1.05, ground, p.z + 0.95), PI / 2 * -o, false, suit, trim)
	_person(st, Vector3(0, ground, front_z + 1.55), PI, false, suit, trim)
	_person(st, Vector3(-0.95, ground, rear_z - 1.0), PI * 0.2, false, suit, trim)
	# Jacks: low trolleys at nose and tail.
	MeshKit.box(st, Vector3(0.5, 0.18, 1.0), Vector3(0, ground + 0.12, front_z + 0.95), Color(0.2, 0.2, 0.22))
	MeshKit.box(st, Vector3(0.5, 0.18, 0.8), Vector3(0, ground + 0.12, rear_z - 0.75), Color(0.2, 0.2, 0.22))
	MeshKit.box(st, Vector3(0.06, 0.06, 0.9), Vector3(-0.45, ground + 0.55, rear_z - 0.85), Color(0.2, 0.2, 0.22), Vector3(-30, -30, 0))
	# Lollipop man, front left, with his pole.
	var lp := Vector3(-1.4, ground, front_z + 2.6)
	_person(st, lp, PI * 0.85, false, suit, trim)
	MeshKit.box(st, Vector3(0.04, 1.7, 0.04), lp + Vector3(0.35, 1.25, -0.25), Color(0.85, 0.85, 0.85), Vector3(0, 0, -12))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.7
	_crew = MeshInstance3D.new()
	_crew.mesh = MeshKit.finish(st)
	_crew.material_override = mat
	add_child(_crew)
	# The sign on the lollipop: red until release.
	var sst := MeshKit.new_tool()
	MeshKit.lathe(sst, [Vector2(-0.02, 0.0), Vector2(-0.02, 0.24), Vector2(0.02, 0.24), Vector2(0.02, 0.0)], 18, Color.WHITE)
	_sign_mat = StandardMaterial3D.new()
	_sign_mat.albedo_color = Color(0.85, 0.1, 0.08)
	_sign_mat.emission_enabled = true
	_sign_mat.emission = Color(0.6, 0.05, 0.03)
	_sign = MeshInstance3D.new()
	_sign.mesh = MeshKit.finish(sst)
	_sign.material_override = _sign_mat
	_sign.position = lp + Vector3(0.53, 2.1, -0.25)
	_sign.rotation.y = PI / 2
	add_child(_sign)
	# Old wheels (taken off) and new ones (going on).
	var r := float(car.wheels[0].wheel_radius)
	var width := float(spec.get("tyre_width_front", 0.3))
	for k in _wheel_local.size():
		var old := _tyre(float(car.wheels[k].wheel_radius), width, Tyres.COLOR.get("medium", Color.WHITE), true)
		var nw := _tyre(float(car.wheels[k].wheel_radius), width, compound_colour, false)
		old.visible = false
		nw.visible = false
		add_child(old)
		add_child(nw)
		_old.append(old)
		_new.append(nw)
	_animate()


func _tyre(r: float, width: float, band: Color, used: bool) -> MeshInstance3D:
	var st := MeshKit.new_tool()
	var hw := width * 0.5
	var rubber := Color(0.05, 0.05, 0.055) if not used else Color(0.09, 0.085, 0.08)
	MeshKit.lathe(st, [Vector2(hw, r * 0.6), Vector2(hw, r), Vector2(-hw, r), Vector2(-hw, r * 0.6)], 20, rubber)
	MeshKit.lathe(st, [Vector2(hw + 0.005, r * 0.72), Vector2(hw + 0.005, r * 0.82)], 20, band)
	MeshKit.lathe(st, [Vector2(-hw - 0.005, r * 0.82), Vector2(-hw - 0.005, r * 0.72)], 20, band)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.finish(st)
	mi.material_override = mat
	return mi


## A crew member in overalls and helmet; kneeling for the wheel guns.
func _person(st: SurfaceTool, at: Vector3, yaw: float, kneel: bool, suit: Color, trim: Color) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	if kneel:
		MeshKit.box(st, Vector3(0.34, 0.42, 0.55), Vector3(0, 0.21, -0.05), suit.darkened(0.25), Vector3.ZERO, xf)
		MeshKit.box(st, Vector3(0.44, 0.55, 0.28), Vector3(0, 0.7, 0.05), suit, Vector3(18, 0, 0), xf)
		MeshKit.box(st, Vector3(0.1, 0.1, 0.42), Vector3(0, 0.75, 0.38), Color(0.12, 0.12, 0.13), Vector3.ZERO, xf)   # wheel gun
		MeshKit.ellipsoid(st, Vector3(0, 1.1, 0.14), Vector3(0.14, 0.15, 0.15), 8, trim, xf)
	else:
		MeshKit.box(st, Vector3(0.34, 0.86, 0.24), Vector3(0, 0.43, 0), suit.darkened(0.25), Vector3.ZERO, xf)
		MeshKit.box(st, Vector3(0.46, 0.62, 0.28), Vector3(0, 1.17, 0), suit, Vector3.ZERO, xf)
		MeshKit.box(st, Vector3(0.12, 0.5, 0.12), Vector3(0.29, 1.1, 0.08), suit, Vector3(-30, 0, 0), xf)
		MeshKit.box(st, Vector3(0.12, 0.5, 0.12), Vector3(-0.29, 1.1, 0.08), suit, Vector3(-30, 0, 0), xf)
		MeshKit.ellipsoid(st, Vector3(0, 1.64, 0), Vector3(0.15, 0.16, 0.16), 8, trim, xf)


func _wheel_meshes() -> Array:
	if car == null or not is_instance_valid(car) or car.body == null:
		return []
	return car.body._wheel_mis


## Up on the jacks, wheels off and carried out, new ones in, back down.
func _animate() -> void:
	if car == null or not is_instance_valid(car) or _released:
		return
	var p := progress
	var lift := LIFT * clampf(p / 0.08, 0.0, 1.0) * clampf((1.0 - p) / 0.1, 0.0, 1.0)
	if car.body != null:
		car.body.position.y = lift
	var meshes := _wheel_meshes()
	for k in _wheel_local.size():
		var home := _wheel_local[k] + Vector3(0, lift, 0)
		var o := _outward[k]
		var off_t := clampf((p - 0.12) / 0.2, 0.0, 1.0)         # old wheel out
		var on_t := clampf((p - 0.4) / 0.2, 0.0, 1.0)          # new wheel in
		var out_pos := home + Vector3(o * 1.1, -0.05, -0.85)
		var in_from := home + Vector3(o * 1.1, -0.05, 0.85)
		var old := _old[k]
		var nw := _new[k]
		var car_wheel_on := p < 0.12 or p >= 0.6
		if k < meshes.size() and is_instance_valid(meshes[k]):
			(meshes[k] as MeshInstance3D).visible = car_wheel_on
		old.visible = p >= 0.12
		old.position = home.lerp(out_pos, off_t)
		old.rotation = Vector3(0, PI if o < 0.0 else 0.0, 0)
		nw.visible = p >= 0.3 and p < 0.6
		nw.position = in_from.lerp(home, on_t)
		nw.rotation = Vector3(0, PI if o < 0.0 else 0.0, 0)
	if p >= 0.6 and not _swapped and car.body != null:
		_swapped = true
		car.body.set_compound_color(_new_colour)


## The car goes: lollipop up (green), crew steps back and leaves.
func release() -> void:
	progress = 1.0
	_released = true
	if car != null and is_instance_valid(car) and car.body != null:
		car.body.position.y = 0.0
		for m in _wheel_meshes():
			if is_instance_valid(m):
				(m as MeshInstance3D).visible = true
		if not _swapped:
			car.body.set_compound_color(_new_colour)
	for nw in _new:
		nw.visible = false
	_sign_mat.albedo_color = Color(0.1, 0.8, 0.25)
	_sign_mat.emission = Color(0.05, 0.6, 0.15)
	_gone = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if not _released:
		return
	_gone += delta
	# Old tyres wheeled into the garage, crew back inside.
	for k in _old.size():
		_old[k].position += Vector3(_outward[k] * delta * 1.5, 0, 0)
	# Crew back to the garage: gone soon after the car (they'd be in the way
	# of the cameras following it out).
	if _gone > 1.0:
		_crew.visible = false
		_sign.visible = false
	if _gone > 2.5:
		queue_free()
