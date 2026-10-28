class_name Showroom
extends Node3D
## The studio turntable used behind the menus: lights, a dark disc with an
## orange ring, a slowly turning car and a camera. `cam_offset` frames the
## car on one side of the screen, leaving room for the menu panels.

var showcase: Node3D
var car: RaceCar
var cam: Camera3D
var spin := 0.3


func build(cam_pos := Vector3(5.6, 1.9, 6.4), look := Vector3(0.9, 0.15, -1.6), fov := 36.0) -> void:
	Look.build(self, "studio")
	var rim := OmniLight3D.new()
	rim.position = Vector3(-4, 2.5, -3.5)
	rim.light_color = Color(0.75, 0.85, 1.0)
	rim.light_energy = 1.6
	rim.omni_range = 9.0
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(3, 3.5, 4)
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 1.6
	fill.omni_range = 12.0
	add_child(fill)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 4.0
	floor_mesh.bottom_radius = 4.2
	floor_mesh.height = 0.1
	floor_mesh.radial_segments = 72
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.1, 0.11, 0.13)
	floor_mat.metallic = 0.4
	floor_mat.roughness = 0.45
	var stage := MeshInstance3D.new()
	stage.mesh = floor_mesh
	stage.material_override = floor_mat
	stage.position.y = -0.05
	add_child(stage)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 4.12
	ring_mesh.outer_radius = 4.2
	ring_mesh.rings = 72
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = UIStyle.APEX
	ring_mat.emission_enabled = true
	ring_mat.emission = UIStyle.APEX
	ring_mat.emission_energy_multiplier = 0.25
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_mat
	add_child(ring)

	showcase = Node3D.new()
	add_child(showcase)
	cam = Camera3D.new()
	cam.fov = fov
	cam.position = cam_pos
	add_child(cam)
	cam.look_at(look, Vector3.UP)
	cam.current = true


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
