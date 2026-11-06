class_name LineGuide
extends MeshInstance3D
## Optional racing-line guide on the road ahead of the player: the ideal
## line, green where you can keep accelerating, yellow where you'll need to
## ease off, red where you must brake now for what's coming at your current
## speed. Boxing (driving your own stop): it leads into the pit lane instead,
## braking for the 80 km/h limit at the speed line.

const AHEAD := 130                # samples (~260 m)
const WIDTH := 0.8               # half width: easy to see from the chase camera

var _mesh := ImmediateMesh.new()
var _timer := 0.0


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat


## `route` / `route_speed` (optional): your own pit stop, the way in and the
## speeds along it (Weekend.route_lat / route_speed).
func update_guide(car: RaceCar, track: Track, profile: PackedFloat32Array, idx: int, delta: float, route: Callable = Callable(), route_speed: Callable = Callable()) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / 15.0
	_mesh.clear_surfaces()
	var n := track.size()
	if profile.size() != n or n == 0:
		return
	var v := maxf(car.forward_speed(), 0.0)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var start := 4
	for k in range(start, AHEAD, 2):
		var i := (idx + k) % n
		var j := (idx + k + 2) % n
		# How hard would you have to brake from here to make that point?
		var d := maxf(k * Track.SPACING, 1.0)
		var target: float = profile[i]
		# (Lifted along the road's own normal: the surface tilts with the camber.)
		var a: Vector3 = track.line_points[i] + track.ups[i] * 0.07
		var b: Vector3 = track.line_points[j] + track.ups[j] * 0.07
		if route.is_valid():
			# Into the pit lane, down it to your box, and out.
			var la: float = route.call(i)
			var lb: float = route.call(j)
			if not is_nan(la):
				a = track.points[i] + track.rights[i] * la + track.ups[i] * 0.07
				target = minf(target, float(route_speed.call(track.pit_ps(i))))
			if not is_nan(lb):
				b = track.points[j] + track.rights[j] * lb + track.ups[j] * 0.07
		var need := (v * v - target * target) / (2.0 * d)
		var cap: float = float(car.spec["ai_brake"]) + float(car.spec["brake_aero"]) * 0.8 * v * v
		var col := UIStyle.GREEN
		if need > cap * 0.7:
			col = UIStyle.RED
		elif need > cap * 0.25 or v > target * 1.02:
			col = UIStyle.YELLOW
		var fade := clampf(float(k - start) / 6.0, 0.0, 1.0) * clampf(float(AHEAD - k) / 20.0, 0.0, 1.0)
		col.a = 0.8 * fade
		var side: Vector3 = track.rights[i] * WIDTH
		# Long dashes with short gaps: reads as one line from low down.
		var mid := a.lerp(b, 0.85)
		for p in [a - side, a + side, mid + side, a - side, mid + side, mid - side]:
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(p)
	_mesh.surface_end()
