class_name SafetyCar
extends Node
## The Safety Car (race control, scripts/race_control.gd).
##
##  1 DEPLOYED   until the car is out, everyone keeps to the VSC speed limit.
##               It comes out of the pit exit just ahead of the leader (or,
##               with no pit lane, onto the track ahead of it) and the field
##               closes up behind it in single file. No overtaking anyone,
##               nor the Safety Car (a penalty).
##  2 IN THIS LAP  once it has led the bunched field for about a lap: the
##               lights go out and at the end of the lap it peels into the
##               pit lane.
##  3 RESTART    the leader sets the pace to the line; racing resumes there.
## Pitting behind the Safety Car is the cheapest stop of the race.
## Multiplayer: the host drives it and sends where it is with the cars.

const LEAD_GAP := 14.0            # leader to Safety Car, bunched up
const PACE := 0.9                 # of the Safety Car's own racing pace (a GT car)

var rc: Node
var race: Node
var track: Track
var phase := 0                    # 0 in, 1 deployed, 2 in this lap, 3 restart
var out := false                  # on the track
var count := 0
var car: RaceCar
var drv: AIDriver
var _dist := 0.0                  # metres led with the field bunched
var _t := 0.0                     # seconds since deployed
var _lights: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D
var _restart_at := 0.0            # leader progress where racing resumes
var _proxy: SCEntrant             # multiplayer: the host's Safety Car, drawn here


class SCEntrant:
	var slot := 99
	var car: RaceCar


func setup(control: Node) -> void:
	rc = control
	race = control.race
	track = control.track


func reset() -> void:
	phase = 0
	out = false
	count = 0
	_hide()


func active() -> bool:
	return phase > 0


## Waiting for the car to come out: the VSC speed limit applies.
func limit_active() -> bool:
	return phase == 1 and not out


func deploy(why: String) -> void:
	if phase > 0:
		return
	count += 1
	phase = 1
	out = false
	_t = 0.0
	_dist = 0.0
	rc.announce("SAFETY CAR DEPLOYED: %s." % why)
	if race.engineer != null:
		race.engineer.say("Safety car, safety car. No overtaking, close up behind it.", 4.0)


func state() -> int:
	return phase


## The host's word (multiplayer clients).
func set_remote(p: int, on_track: bool) -> void:
	var was := phase
	phase = p
	if p == 1 and was == 0:
		rc._vsc_on_t = 0.0
		rc._over.clear()
		rc._vsc_pen.clear()
		if race.engineer != null:
			race.engineer.say("Safety car, safety car. No overtaking, close up behind it.", 4.0)
	if p == 0 and was > 0 and race.engineer != null:
		race.engineer.say("Green, green, green! Go!", 3.0)
	if on_track and not out:
		_hint = -1                           # (just appeared: find it afresh)
	out = on_track
	if not on_track and car != null:
		car.visible = false
	_set_lights(p == 1)


## Distance along the track (m) and speed of the Safety Car, if out.
func s_pos() -> float:
	return track.cum[_idx()] if out and car != null else -1.0


func speed() -> float:
	if car == null:
		return 0.0
	return car.remote_vel.length() if car.remote else car.forward_speed()


var _hint := 0

func _idx() -> int:
	if car == null:
		return 0
	if drv != null and not car.remote:
		return drv.idx
	# (Another phone's Safety Car: where it's drawn here.)
	_hint = track.nearest_index(car.global_position, -1) if _hint < 0 else track.track_index(car.global_position, _hint)
	return _hint


# ------------------------------------------------------------ host / single player

func physics(dt: float) -> void:
	if phase == 0 or not rc.authority:
		return
	_t += dt
	var leader = _leader()
	if leader == null:
		return
	var L := track.total_length
	match phase:
		1, 2:
			if not out:
				_try_come_out(leader)
				return
			_drive(dt, leader)
			var gap := fposmod(s_pos() - float(track.cum[leader.idx]), L)
			# (Counts once the queue has caught it, or after a minute and a
			# half regardless: it never stays out for the rest of the race.)
			if gap < 60.0 or _t > 90.0:
				_dist += speed() * dt
			if phase == 1 and _dist > minf(L * 0.6, 3200.0) and _t > 35.0:
				phase = 2
				_set_lights(false)
				rc.announce("SAFETY CAR IN THIS LAP.")
			elif phase == 2:
				_go_in(leader)
		3:
			if float(leader.progress) >= _restart_at:
				phase = 0
				rc.announce("RACING RESUMES. Green flag.")
				if race.engineer != null:
					race.engineer.say("Green, green, green! Go!", 3.0)


func _leader():
	var best = null
	for e in race.entrants:
		if e.finished or e.eliminated or e.dnf:
			continue
		if best == null or float(e.progress) > float(best.progress):
			best = e
	return best


## Out of the pit exit as the leader comes by (no pit lane: onto the
## track 250 m ahead of it).
func _try_come_out(leader) -> void:
	var L := track.total_length
	var lead_s: float = track.cum[leader.idx]
	var pose: Transform3D
	if track.has_pit_lane:
		var ps := track.pit_total() + 6.0
		var exit_s := fposmod(track.pit_s0 + ps, L)
		var d := fposmod(exit_s - lead_s, L)
		if d < 40.0 or d > 260.0:
			return
		if car == null:
			_make_car()
		pose = race.weekend.lane_pose(ps, track.pit_lane_lat(ps), car.spawn_height()) if race.weekend != null else _track_pose(exit_s)
	else:
		if car == null:
			_make_car()
		pose = _track_pose(lead_s + 250.0)
	car.global_transform = pose
	car.linear_velocity = pose.basis.z * 22.0
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	car.controls_enabled = true
	car.freeze = false
	car.visible = true
	drv.idx = track.nearest_index(car.global_position, -1)
	drv.path_lat = Callable()
	out = true
	_set_lights(true)


func _track_pose(s: float) -> Transform3D:
	var L := track.total_length
	var i := clampi(track.cum.bsearch(fposmod(s, L)), 0, track.size() - 1)
	return track.pose_at(i, car.spawn_height() if car != null else 0.6, track.line_offset[i])


## At a pace the field can catch: under the speed the bots are held to
## behind it (80% of their car's), whatever they race. (It drove at its own
## car's pace: in a field of road cars no faster than it, the leader never
## got within reach, and it stayed out for the rest of the race.)
func _drive(_dt: float, leader = null) -> void:
	var cap := 999.0
	if leader != null:
		var prof := track.speed_profile(leader.car.spec)
		if prof.size() > 0:
			cap = prof[posmod(drv.idx, prof.size())] * 0.65
	drv.speed_cap = cap
	drv.update(car, track)


## In this lap: into the pit lane at the end of it, then gone; the leader
## takes it to the line.
func _go_in(leader) -> void:
	if track.has_pit_lane:
		var ps := track.pit_ps(drv.idx)
		if drv.path_lat.is_null() and ps > -220.0 and ps < 0.0:
			drv.path_lat = func(i: int) -> float: return track.pit_side * track.pit_lane_lat(track.pit_ps(i))
		if not drv.path_lat.is_null():
			drv.speed_cap = 22.0 if ps > 0.0 else 999.0
		if ps > track.PIT_ENTRY_LEN + 25.0 and ps < track.pit_total():
			_finish_in(leader)
	else:
		var to_line := fposmod(-track.cum[drv.idx], track.total_length)
		if to_line < 250.0:
			_finish_in(leader)


func _finish_in(leader) -> void:
	_hide()
	out = false
	phase = 3
	var L := track.total_length
	# (Racing resumes at the line: the pit entry's usually just before it.)
	_restart_at = (floor(float(leader.progress) / L) + 1.0) * L
	rc.announce("SAFETY CAR IN. Restart at the line.")


func _hide() -> void:
	if car != null:
		car.visible = false
		car.freeze = true
		car.controls_enabled = false
		car.global_position = Vector3(0, -500, 0)
	_set_lights(false)


func _make_car() -> void:
	var spec := CarSpecs.get_spec("vanta_gt", 0)
	spec["color"] = Color(0.9, 0.9, 0.92)
	spec["name"] = "Safety Car"
	car = RaceCar.new()
	car.setup(spec)
	race.add_child(car)
	car.set_ghost(true)                      # nobody can crash into it
	drv = AIDriver.new()
	drv.skill = 0.86
	_add_lights()


func _add_lights() -> void:
	_light_mat = StandardMaterial3D.new()
	_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light_mat.albedo_color = Color(1.0, 0.6, 0.05)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.05, 0.08, 0.22)
	bar.mesh = bm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	bar.material_override = dark
	bar.position = Vector3(0, 1.17, -0.35)
	car.add_child(bar)
	for side in [-1.0, 1.0]:
		var l := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.36, 0.1, 0.2)
		l.mesh = lm
		l.material_override = _light_mat
		l.position = Vector3(side * 0.32, 1.22, -0.35)
		car.add_child(l)
		_lights.append(l)


func _set_lights(on: bool) -> void:
	for l in _lights:
		l.visible = on


func flash(t: float) -> void:
	if _lights.size() == 2 and _lights[0].visible:
		var a := fmod(t * 2.5, 1.0) < 0.5
		_light_mat.albedo_color = Color(1.0, 0.6, 0.05) if a else Color(0.35, 0.18, 0.02)


# ------------------------------------------------------------ multiplayer

## Host: [phase, on track, the car's state...] for the snapshot.
func net_state() -> Array:
	var a: Array = [phase, 1 if out else 0]
	if out and car != null:
		a.append(NetRace.car_state(car))
	return a


## Client: the host's Safety Car.
func net_update(a: Array, nt: float, net: Node) -> void:
	var p := int(a[0])
	var on := int(a[1]) == 1
	if p != phase or on != out:
		set_remote(p, on)
	if on and a.size() > 2:
		if car == null:
			_make_car()
			NetRace.make_remote(car)
			_proxy = SCEntrant.new()
			_proxy.car = car
		car.visible = true
		net._push(99, a[2], nt)


func net_draw(net: Node, at: float) -> void:
	if _proxy != null and out:
		net._drive_remote(_proxy, at)
