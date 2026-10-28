class_name ReplayCamera
extends Camera3D
## Cameras for replays.
##
##  TV:         camera towers round the track (on the outside of each corner,
##              on grandstand and building roofs where there's no room), zoomed
##              like a broadcast lens; the next one ahead takes over as the car
##              passes, skipping any whose view is blocked by hills, trees or
##              buildings.
##  Helicopter: high and to the side, tracking the car.
##  Blimp:      nearly straight down from 120 m.
##  Drone:      a slow orbit close to the car.
##  Chase:      behind, a bit further back than when racing.
##  Onboards:   the car's own cameras (cockpit, T-cam, nose...), plus one
##              looking backwards.
##  Auto:       a director cutting between them every few seconds.

const BASE_MODES := ["Auto", "TV", "Helicopter", "Blimp", "Drone", "Chase"]

var track: Track
var replay: Replay
var target: RaceCar
var modes: Array[String] = []
var mode := 0
var shot := "TV"                       # what Auto is showing now
var _shot_left := 0.0
var _rng := RandomNumberGenerator.new()

var _towers: Array = []                # [{s, pos}] sorted by s
var _tower := -1
var _blocked := 0.0
var _tower_left := 0                   # Auto: TV towers to show before cutting
var _idx := 0                          # target's track index
var _dir := Vector3.ZERO               # smoothed heading
var _look := Vector3.ZERO              # smoothed aim point
var _orbit := 0.0
var _side := 1.0
var _cockpit_on := false


func _ready() -> void:
	near = 0.1
	far = 3000.0
	fov = 50.0
	_rng.seed = 11


func setup(t: Track, r: Replay) -> void:
	track = t
	replay = r
	_build_towers()


func set_focus(car: RaceCar) -> void:
	_set_cockpit(false)
	target = car
	var name := modes[mode] if mode < modes.size() else "Auto"
	modes.clear()
	for m in BASE_MODES:
		modes.append(m)
	for c in car.spec["cams"]:
		modes.append(String(c["name"]))
	modes.append("Rear-facing")
	mode = maxi(modes.find(name), 0)
	_idx = track.nearest_index(car.global_position, -1)
	_tower = -1
	cut()


func cycle_mode() -> void:
	mode = (mode + 1) % modes.size()
	_tower = -1
	cut()


func mode_name() -> String:
	return modes[mode]


## What's on screen now ("Auto: Helicopter" in Auto).
func shot_name() -> String:
	return ("Auto: " + shot) if mode == 0 else modes[mode]


## Next frame jumps straight to the shot (no smoothing from the last one).
func cut() -> void:
	_dir = Vector3.ZERO
	_look = Vector3.ZERO
	_shot_left = 0.0
	_blocked = 0.0


func release() -> void:
	_set_cockpit(false)


func _set_cockpit(on: bool) -> void:
	if on == _cockpit_on or target == null:
		return
	_cockpit_on = on
	for child in target.get_children():
		if child is CarBody:
			(child as CarBody).set_cockpit_view(on)


# ------------------------------------------------------------ TV towers

func _build_towers() -> void:
	_towers.clear()
	var n := track.size()
	var block := 50 if track.style == "city" else 80   # one tower per 100-160 m of track
	var count := maxi(n / block, 4)
	var alt := 1.0
	for b in count:
		var i0 := b * n / count
		var i1 := (b + 1) * n / count
		# At the tightest point of this stretch, on the outside of the bend.
		var best := i0
		for i in range(i0, i1):
			if absf(track.curv[i]) > absf(track.curv[best]):
				best = i
		var side := signf(track.curv[best]) if absf(track.curv[best]) > 1.0 / 900.0 else alt
		alt = -alt
		# Towers stand by the track, a little before the apex so the car
		# comes towards them and sweeps past.
		var i := posmod(best - 8, n)
		var h := 6.0 + float((b * 7) % 5)
		# Clear ground by the track first, either side; else up on a roof.
		var pos := Vector3.INF
		for roof in [false, true]:
			for sd in [side, -side]:
				for extra in [5.0, 1.5]:
					if pos == Vector3.INF:
						pos = _tower_spot(i, sd, h, extra, roof)
		if pos == Vector3.INF:
			continue
		_towers.append({"s": track.cum[i], "pos": pos})


func _tower_spot(i: int, side: float, h: float, extra: float, roof: bool) -> Vector3:
	if track.in_tunnel(i):
		# Up in the tunnel's ceiling corner.
		return track.points[i] + track.rights[i] * side * (track.wall_at(i, side) - 1.0) + Vector3.UP * (Track.TUNNEL_H - 1.2)
	var lat := track.wall_at(i, side) + extra
	var p: Vector3 = track.points[i] + track.rights[i] * side * lat
	if track.is_water(p.x, p.z):
		return Vector3.INF               # (moored yachts would fill the view)
	p.y = track.ground_height(p.x, p.z) + h
	# Always well above the catch fence (about 4.2 m over the road), so it
	# films over it rather than through it.
	p.y = maxf(p.y, track.points[i].y + maxf(h, 6.5))
	# On a building or grandstand: up on its roof.
	for box in track.scenery_boxes:
		var xf: Transform3D = box["xf"]
		var size: Vector3 = box["size"]
		var local := xf.affine_inverse() * p
		if absf(local.x) < size.x * 0.5 + 1.0 and absf(local.z) < size.z * 0.5 + 1.0:
			if bool(box.get("overhead", false)) or not roof:
				return Vector3.INF
			p.y = maxf(p.y, xf.origin.y + size.y + 3.0)
	return p


## Can a camera at `from` see the car at `to`? Hills, trees and buildings.
func _clear(from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var len := d.length()
	var steps := int(len / 4.0)
	for k in range(1, steps):
		var u := float(k) / steps
		if len * (1.0 - u) < 9.0:
			break                       # the last few metres are the car's own track
		var p := from + d * u
		if not track.tunnels.is_empty():
			var tun := track.tunnel_at(p)
			if tun < 0:
				return false
			if tun > 0:
				continue                # down the tunnel bore: nothing in the way
		if p.y < track.ground_height(p.x, p.z) + 1.2:
			return false
		var top: float = track.tree_tops.get(Vector2i(floori(p.x / Track.TREE_CELL), floori(p.z / Track.TREE_CELL)), -INF)
		if p.y < top:
			return false
		if len * u > 12.0:
			for box in track.scenery_boxes:
				var xf: Transform3D = box["xf"]
				if xf.origin.distance_squared_to(p) > 2500.0:
					continue
				var size: Vector3 = box["size"]
				var local := xf.affine_inverse() * p
				if absf(local.x) < size.x * 0.5 and absf(local.z) < size.z * 0.5 and local.y > -2.0 and local.y < size.y:
					var own := xf.affine_inverse() * from
					if absf(own.x) < size.x * 0.5 + 1.0 and absf(own.z) < size.z * 0.5 + 1.0:
						continue            # the roof the camera stands on
					return false
	return true


## Track distance from the car to tower k (negative: already passed).
func _ahead(k: int, s: float) -> float:
	var d: float = float(_towers[k]["s"]) - s
	var L := track.total_length
	if d > L * 0.5:
		d -= L
	elif d < -L * 0.5:
		d += L
	return d


## Pick the tower to film from; false if none can see the car.
func _pick_tower(s: float, aim: Vector3, delta: float) -> bool:
	if _towers.is_empty():
		return false
	if _tower >= 0:
		var d := _ahead(_tower, s)
		var ok := d > -55.0 and d < 330.0
		if ok and not _clear(_towers[_tower]["pos"], aim):
			_blocked += delta
			ok = _blocked < 0.5
		else:
			_blocked = 0.0
		if ok:
			return true
	# The nearest tower ahead (or just passed) that has a clear view.
	var cands: Array = []
	for k in _towers.size():
		var d := _ahead(k, s)
		if d > -25.0 and d < 300.0 and k != _tower:
			cands.append([d, k])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands:
		if _clear(_towers[c[1]]["pos"], aim):
			if _tower >= 0:
				_tower_left -= 1
			_tower = c[1]
			_blocked = 0.0
			_look = Vector3.ZERO
			return true
	_tower = -1
	return false


# ------------------------------------------------------------ per frame

func follow(delta: float) -> void:
	if target == null:
		return
	_idx = track.track_index(target.global_position, _idx)
	var t := target.global_transform
	var fwd := t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	if _dir == Vector3.ZERO:
		_dir = fwd
	var k := 1.0 - exp(-4.0 * delta) if delta > 0.0 else 1.0
	_dir = _dir.lerp(fwd, k).normalized()

	var m := modes[mode]
	if m == "Auto":
		_direct(delta)
		m = shot
	_set_cockpit(m == "Cockpit")
	match m:
		"TV":
			if not _tv(delta):
				_helicopter(delta)
				if mode == 0:
					_shot_left = 0.0       # nothing in view: cut to something else
		"Helicopter":
			_helicopter(delta)
		"Blimp":
			_blimp(delta)
		"Drone":
			_drone(delta)
		"Chase":
			_chase(delta)
		"Rear-facing":
			_rear()
		_:
			_onboard(m)


func _direct(delta: float) -> void:
	_shot_left -= delta
	if shot == "TV" and _shot_left <= 0.0 and _tower_left > 0 and _tower >= 0:
		return                          # let the TV shot run to its next tower
	if _shot_left > 0.0:
		return
	var onboard := "T-cam" if modes.has("T-cam") else modes[BASE_MODES.size()]
	var options := ["TV", "TV", "TV", "TV", "Helicopter", "Chase", "Drone", "Blimp", onboard, onboard, "Rear-facing"]
	var pick := shot
	for tries in 8:
		pick = options[_rng.randi() % options.size()]
		if pick == "Rear-facing" and not _car_behind():
			pick = "TV"
		if pick != shot:
			break
	shot = pick
	_tower_left = _rng.randi_range(2, 3)
	_tower = -1
	_side = -_side
	cut()
	_shot_left = 3.0 if shot == "TV" else _rng.randf_range(4.0, 7.0)


func _car_behind() -> bool:
	for c in replay.cars:
		if c == target:
			continue
		var d: Vector3 = (c as RaceCar).global_position - target.global_position
		var along := d.dot(target.global_basis.z)
		if along < -3.0 and along > -35.0 and absf(d.dot(target.global_basis.x)) < 6.0:
			return true
	return false


func _tv(delta: float) -> bool:
	var aim := target.global_position + Vector3.UP * 0.5 + target.remote_vel * 0.12
	if not _pick_tower(track.cum[_idx], aim, delta):
		return false
	var pos: Vector3 = _towers[_tower]["pos"]
	global_position = pos
	# A camera operator: aim catches up quickly but not instantly.
	var fresh := _look == Vector3.ZERO or delta <= 0.0
	if fresh:
		_look = aim
	_look = _look.lerp(aim, 1.0 - exp(-9.0 * delta) if delta > 0.0 else 1.0)
	_aim(_look, Vector3.UP)
	# Zoom so the car fills about a quarter of the screen width.
	var dist := pos.distance_to(_look)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var want := rad_to_deg(2.0 * atan(11.0 / (dist * maxf(aspect, 1.0))))
	want = clampf(want, 2.5, 55.0)
	fov = want if fresh else lerpf(fov, want, 1.0 - exp(-6.0 * delta))
	return true


## look_at that never fails (target on top of the camera, or straight
## along the up vector).
func _aim(at: Vector3, up: Vector3) -> void:
	var d := at - global_position
	if d.length_squared() < 1e-4:
		return
	if d.normalized().cross(up.normalized()).length_squared() < 1e-6:
		up = _dir if _dir != Vector3.ZERO else Vector3.FORWARD
		if d.normalized().cross(up).length_squared() < 1e-6:
			up = Vector3.RIGHT
	look_at(at, up)


func _keep_above_ground(p: Vector3, clearance: float) -> Vector3:
	var g := track.ground_height(p.x, p.z)
	if not is_nan(track.sea_level):
		g = maxf(g, track.sea_level)
	p.y = maxf(p.y, g + clearance)
	return p


func _helicopter(_delta: float) -> void:
	var right := Vector3.UP.cross(_dir).normalized()
	var p := target.global_position - _dir * 38.0 + right * _side * 30.0 + Vector3.UP * 42.0
	global_position = _keep_above_ground(p, 25.0)
	_aim(target.global_position + _dir * 10.0, Vector3.UP)
	fov = 38.0


func _blimp(_delta: float) -> void:
	global_position = target.global_position - _dir * 20.0 + Vector3.UP * 120.0
	_aim(target.global_position + _dir * 6.0, _dir)
	fov = 24.0


func _drone(delta: float) -> void:
	_orbit += delta * 0.32 * _side
	var off := Vector3(cos(_orbit), 0.0, sin(_orbit)) * 11.0 + Vector3.UP * 3.2
	global_position = _keep_above_ground(target.global_position + off, 1.5)
	_aim(target.global_position + Vector3.UP * 0.5, Vector3.UP)
	fov = 58.0


func _chase(_delta: float) -> void:
	var dist := float(target.spec["chase_dist"]) * 1.25
	var height := float(target.spec["chase_height"]) * 1.15
	global_position = _keep_above_ground(target.global_position - _dir * dist + Vector3.UP * height, 0.8)
	_aim(target.global_position + _dir * 5.0 + Vector3.UP * 0.6, Vector3.UP)
	fov = 66.0


func _onboard(name: String) -> void:
	for c in target.spec["cams"]:
		if String(c["name"]) == name:
			var pitch := deg_to_rad(float(c.get("pitch", 0.0)))
			global_transform = target.global_transform * Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, pitch), c["pos"])
			fov = 74.0
			return
	_chase(0.0)


func _rear() -> void:
	# Above and behind the driver's head, looking back over the rear wing.
	var h := float(target.spec["chase_height"]) * 0.62 + 0.15
	var p := Vector3(0.0, h, float(target.spec["wheel_rear_z"]) * 0.2)
	global_transform = target.global_transform * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), p)
	fov = 70.0
