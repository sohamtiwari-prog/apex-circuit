class_name NetRace
extends Node
## Multiplayer side of a race (see Net for the connection).
##
##  - Every phone simulates its own car and sends its state 20 times a second.
##  - The host also runs the bots, the start lights, lap counting and
##    positions, and sends everyone a snapshot of every car (20 Hz) and the
##    standings (4 Hz).
##  - Other cars are drawn by interpolating ~0.12 s behind the newest
##    snapshot, so they move smoothly despite network jitter. They are solid
##    (kinematic), so you can bump wheels with your friends.
##  - A friend who drops out is taken over by a bot; if the host leaves,
##    everyone is told and returned to the menu.

const SEND_HZ := 20.0
const DELAY_MIN := 0.12        # seconds of interpolation delay (adapts to jitter)
const DELAY_MAX := 0.6         # online through a public server can be jumpy
const START_WAIT := 15.0       # max seconds to wait for everyone to load

var race: Node
var Net: Node                  # the Net autoload, looked up at runtime
var _send_t := 0.0
var _std_t := 0.0
var _buffers := {}             # slot -> Array of [local time, PackedFloat32Array]
var _slot_of_peer := {}        # host: peer id -> slot
var _ready_peers := {}
var _wait := 0.0
var _host_time := 0.0
var _host_time_at := 0.0
var _host_state := 0
var ended := false
# Session clock, in *simulation* time (sum of physics steps): a car's state
# always matches its stamp, even when a slow frame runs several physics steps
# at once. Clients estimate the host's clock (offset from the fastest packets
# seen), and every car state is stamped with it, so arrival jitter doesn't matter.
var _sim := 0.0
var _offset := -INF
var _offsets: Array[float] = []     # recent (host time - local time) samples
var _jitter := 0.03                 # how late packets arrive vs the fastest (s)
var _peer_offsets := {}             # host: peer -> recent (client stamp - local time)
var delay := 0.12


func setup(r: Node) -> void:
	race = r
	Net = get_node("/root/Net")
	Net.message.connect(_on_message)
	Net.peer_left.connect(_on_peer_left)
	Net.peer_joined.connect(_on_peer_joined)
	Net.closed.connect(_on_closed)
	for e in race.entrants:
		if e.net_id > 0:
			_slot_of_peer[e.net_id] = e.slot
	if not Net.is_host():
		Net.send(1, {"t": "ready"})


## Estimated host session time, on any phone.
func net_time() -> float:
	if Net.is_host():
		return _sim
	return _sim + (_offset if _offset > -INF else 0.0)


static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Host: start the lights once everyone has loaded (or after a timeout).
func all_ready(delta: float) -> bool:
	_wait += delta
	var humans := 0
	for e in race.entrants:
		if e.net_id > 1 and e.remote:
			humans += 1
	return _ready_peers.size() >= humans or _wait > START_WAIT


# ------------------------------------------------------------ state vectors

## position, rotation, velocity, steering, rpm, gear, brake, DRS, throttle
static func car_state(c: RaceCar) -> PackedFloat32Array:
	var xf := c.global_transform
	var q := xf.basis.get_rotation_quaternion()
	var v := c.remote_vel if c.remote else c.linear_velocity
	return PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w,
		v.x, v.y, v.z, c.steering, c.rpm, float(c.gear), c.brake_input, 1.0 if c.drs_open else 0.0, c.throttle])


## Turns a car into a network-driven one: no physics of its own, moved to
## the interpolated position each tick, still solid for other cars.
static func make_remote(c: RaceCar) -> void:
	c.remote = true
	c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	c.freeze = true
	c.set_physics_process(false)
	# No rigid collisions: contact with network cars is soft (see _contacts),
	# so a car that's only drawn here never acts like an immovable wall.
	c.collision_layer = 0
	c.collision_mask = 0


## A bot takes over (the friend driving it left).
static func make_local_bot(c: RaceCar) -> void:
	c.remote = false
	c.freeze = false
	c.set_physics_process(true)
	c.collision_layer = 2
	c.collision_mask = 1
	c.linear_velocity = c.remote_vel
	c.controls_enabled = true


# ------------------------------------------------------------ tick

func physics_tick(delta: float) -> void:
	if ended:
		return
	_sim += delta
	if not _offsets.is_empty():
		var target: float = _offsets.max()
		# Never jump: at most 5% faster or slower than real time while syncing.
		_offset = move_toward(_offset, target, 0.05 * delta)
	# Interpolation delay: one send interval plus room for the usual lateness.
	_jitter = maxf(_jitter * (1.0 - 0.3 * delta), 0.0)
	var want := clampf(1.0 / SEND_HZ + 0.05 + _jitter * 2.0, DELAY_MIN, DELAY_MAX)
	# Change slowly (<= 8% of real time) so cars never visibly speed up or slow down.
	delay = move_toward(delay, want, 0.08 * delta)
	var t := now()
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_HZ
		if Net.is_host():
			var cars := {}
			for e in race.entrants:
				cars[e.slot] = car_state(e.car)
			Net.send(0, {"t": "s", "nt": net_time(), "time": race.race_time, "st": race.state, "lt": race.lights_time, "cars": cars}, false)
		else:
			Net.send(1, {"t": "c", "nt": net_time(), "s": car_state(race.player.car)}, false)
	if Net.is_host():
		_std_t -= delta
		if _std_t <= 0.0:
			_std_t = 0.25
			var rows: Array = []
			for e in race.entrants:
				rows.append([e.slot, e.lap, e.progress, 1 if e.finished else 0, e.finish_time, e.best_lap, e.last_lap, e.position])
			Net.send(0, {"t": "std", "rows": rows})
	else:
		# Follow the host's clock and start lights.
		if _host_time_at > 0.0 and race.state != 0:
			race.race_time = _host_time + (t - _host_time_at)
	var at := net_time() - delay
	for e in race.entrants:
		if e.remote:
			_drive_remote(e, at)
	_contacts()


## Soft contact between cars simulated here and cars driven by other phones:
## each car is three overlapping circles (nose, middle, tail); overlapping
## circles push this phone's car away with a spring and a damper. Every phone
## does this for its own cars, so contact feels the same from both sides.
func _contacts() -> void:
	var remote_cars: Array = []
	var local_cars: Array = []
	for e in race.entrants:
		if e.remote:
			remote_cars.append(e.car)
		elif not e.car.freeze:
			local_cars.append(e.car)
	if remote_cars.is_empty():
		return
	for lc in local_cars:
		var c: RaceCar = lc
		var cp := c.global_position
		for rc in remote_cars:
			var o: RaceCar = rc
			if cp.distance_squared_to(o.global_position) > 64.0:
				continue
			var hit := false
			for a in _circles(c):
				for b in _circles(o):
					var d: Vector3 = a - b
					d.y = 0.0
					var dist := d.length()
					var pen := 2.1 - dist
					if pen <= 0.0:
						continue
					var n := d / maxf(dist, 0.01)
					var rel := (c.linear_velocity - o.remote_vel).dot(n)
					var f := n * (c.mass * (55.0 * pen - 5.0 * minf(rel, 0.0)))
					c.apply_force(f, a - cp)
					hit = true
			if hit:
				c.angular_damp = 0.15


static func _circles(c: RaceCar) -> Array:
	var b := c.global_basis
	var p := c.global_position
	var half := (float(c.spec["wheel_front_z"]) - float(c.spec["wheel_rear_z"])) * 0.5 + 0.55
	return [p + b.z * half * 0.72, p, p - b.z * half * 0.72]


## Also every drawn frame, so other cars glide even when the frame rate and
## the physics rate don't line up.
func _process(_delta: float) -> void:
	if ended or race == null:
		return
	# Between physics steps: the fraction of the next step already elapsed.
	var at := net_time() + Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second) - delay
	for e in race.entrants:
		if e.remote:
			_drive_remote(e, at)


func _drive_remote(e, at: float) -> void:
	var buf: Array = _buffers.get(e.slot, [])
	if buf.is_empty():
		return
	var a: Array = buf[0]
	var b: Array = buf[0]
	for k in range(buf.size()):
		if buf[k][0] <= at:
			a = buf[k]
			b = buf[mini(k + 1, buf.size() - 1)]
	var sa: PackedFloat32Array = a[1]
	var sb: PackedFloat32Array = b[1]
	var f := 0.0
	var pos: Vector3
	if b[0] > a[0]:
		f = clampf((at - a[0]) / (b[0] - a[0]), 0.0, 1.0)
		pos = Vector3(sa[0], sa[1], sa[2]).lerp(Vector3(sb[0], sb[1], sb[2]), f)
	else:
		# Newer than anything we have: extrapolate a little on velocity.
		var ahead := clampf(at - a[0], 0.0, 0.25)
		pos = Vector3(sa[0], sa[1], sa[2]) + Vector3(sa[7], sa[8], sa[9]) * ahead
	var qa := Quaternion(sa[3], sa[4], sa[5], sa[6]).normalized()
	var qb := Quaternion(sb[3], sb[4], sb[5], sb[6]).normalized()
	var c: RaceCar = e.car
	c.global_transform = Transform3D(Basis(qa.slerp(qb, f)), pos)
	c.remote_vel = Vector3(sa[7], sa[8], sa[9]).lerp(Vector3(sb[7], sb[8], sb[9]), f)
	c.steering = lerpf(sa[10], sb[10], f)
	c.rpm = lerpf(sa[11], sb[11], f)
	c.gear = int(sb[12])
	c.brake_input = sb[13]
	c.drs_open = sb[14] > 0.5
	c.throttle = sb[15]
	c.engine_load = sb[15]
	var v := c.forward_speed()
	for w in c.wheels:
		w.steer_angle = c.steering if w.use_as_steering else 0.0
		w.spin_rate = v / w.wheel_radius


func _push(slot: int, st: PackedFloat32Array, at: float) -> void:
	if not _buffers.has(slot):
		_buffers[slot] = []
	var buf: Array = _buffers[slot]
	if not buf.is_empty() and at <= buf[buf.size() - 1][0]:
		return                     # late or duplicate packet
	buf.append([at, st])
	while buf.size() > 16:
		buf.pop_front()


# ------------------------------------------------------------ messages

func _on_message(from: int, m: Dictionary) -> void:
	match String(m.get("t", "")):
		"c":
			if Net.is_host() and _slot_of_peer.has(from):
				var nt := float(m.get("nt", net_time()))
				if not _peer_offsets.has(from):
					_peer_offsets[from] = []
				var offs: Array = _peer_offsets[from]
				offs.append(nt - _sim)
				if offs.size() > 40:
					offs.pop_front()
				_jitter = maxf(_jitter, float(offs.max()) - float(offs[offs.size() - 1]))
				_push(_slot_of_peer[from], m["s"], nt)
		"ready":
			_ready_peers[from] = true
		"s":
			if Net.is_host():
				return
			_host_time = float(m["time"])
			_host_time_at = now()
			# Clock offset: the fastest packet in the last ~2 s is the best
			# estimate (least delayed). The clock then glides towards it.
			_offsets.append(float(m["nt"]) - _sim)
			if _offsets.size() > 40:
				_offsets.pop_front()
			_jitter = maxf(_jitter, float(_offsets.max()) - float(_offsets[_offsets.size() - 1]))
			if _offset == -INF:
				_offset = _offsets[0]
			_host_state = int(m["st"])
			var me: int = race.player.slot
			var cars: Dictionary = m["cars"]
			for slot in cars:
				if int(slot) != me:
					_push(int(slot), cars[slot], float(m["nt"]))
			if race.state == 0:
				race.lights_time = float(m["lt"])
				if _host_state != 0:
					race.lights_out_at = 0.0           # lights out on the next tick
		"std":
			if Net.is_host():
				return
			_apply_standings(m["rows"])
		"to_lobby":
			ended = true
			race.go_to_lobby()


func _apply_standings(rows: Array) -> void:
	var by_slot := {}
	for e in race.entrants:
		by_slot[e.slot] = e
	for r in rows:
		var e = by_slot.get(int(r[0]))
		if e == null:
			continue
		e.position = int(r[7])
		if e.is_player:
			continue
		e.lap = int(r[1])
		e.progress = float(r[2])
		e.finished = int(r[3]) == 1
		e.finish_time = float(r[4])
		e.best_lap = float(r[5])
		e.last_lap = float(r[6])


func _on_peer_left(id: int) -> void:
	if not Net.is_host() or not _slot_of_peer.has(id):
		return
	var slot: int = _slot_of_peer[id]
	_slot_of_peer.erase(id)
	for e in race.entrants:
		if e.slot == slot and e.remote:
			make_local_bot(e.car)
			e.remote = false
			e.net_id = 0
			e.ai = AIDriver.new()
			e.ai.skill = 0.93
			e.ai.idx = e.idx
			race.hud.show_warning("%s left; a bot takes over" % e.name, 3.0)


## Nobody can join halfway through a race.
func _on_peer_joined(id: int) -> void:
	if Net.is_host():
		Net.send(id, {"t": "busy"})


func _on_closed(reason: String) -> void:
	ended = true
	race.hud.show_banner(reason, UIStyle.YELLOW, 4.0)
	get_tree().create_timer(2.5).timeout.connect(func(): race.leave_to_menu())


## Host: everyone back to the lobby for the next race.
func back_to_lobby() -> void:
	ended = true
	Net.send(0, {"t": "to_lobby"})
	race.go_to_lobby()
