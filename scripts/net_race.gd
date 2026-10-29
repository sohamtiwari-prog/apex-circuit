class_name NetRace
extends Node
## Multiplayer side of a race (see Net for the connection).
##
##  - Every phone simulates its own car and sends its state 20 times a second.
##  - The host also runs the bots, the start lights, lap counting and
##    positions, and sends everyone a snapshot of every car (20 Hz) and the
##    standings (4 Hz).
##  - Other cars are interpolated ~0.12 s behind the newest snapshot (smooth
##    despite network jitter), then carried forward along their path by that
##    delay, so they're drawn, and touched, where they are now rather than
##    where they were. Contact is the same soft contact as single player:
##    each phone pushes its own car by its share (CarContacts.step_against).
##  - A friend who drops out is taken over by a bot; if the host leaves,
##    everyone is told and returned to the menu.

const SEND_HZ := 20.0
const DELAY_MIN := 0.12        # seconds of interpolation delay (adapts to jitter)
const DELAY_MAX := 0.6         # online through a public server can be jumpy
const START_WAIT := 15.0       # max seconds to wait for everyone to load
const LEAD_MAX := 0.3          # carry other cars forward at most this far (s)

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
var _touching := {}
var _kicks := {}                    # slot -> [[net time, velocity change]] from contact here
var _yaw_rate := {}                 # slot -> smoothed yaw rate (rad/s) of a network car
var _ahead := {}                    # slot -> [smoothed forward offset, its time]


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

## A car's state plus its tyres and pit stop: compound, wear, pit phase,
## the compound it's boxing for.
static func entrant_state(e) -> PackedFloat32Array:
	var s := car_state(e.car)
	s.append_array(PackedFloat32Array([float(Tyres.COMPOUNDS.find(e.compound)), e.wear, float(e.pit_phase), float(Tyres.COMPOUNDS.find(e.next_compound))]))
	return s


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
				cars[e.slot] = entrant_state(e)
			Net.send(0, {"t": "s", "nt": net_time(), "time": race.race_time, "st": race.state, "lt": race.lights_time, "cars": cars}, false)
		else:
			Net.send(1, {"t": "c", "nt": net_time(), "s": entrant_state(race.player)}, false)
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


## Contact between cars simulated here and cars driven by other phones (or
## the host's bots): this phone's cars take their share of each contact.
## Cars in the pit lane, and cars just put back on track, pass through.
func _contacts() -> void:
	var remote_cars: Array = []
	var local_cars: Array = []
	for e in race.entrants:
		if e.remote:
			if e.pit_phase == 0 and not e.eliminated:
				remote_cars.append(e.car)
		elif not e.car.freeze and not e.car.is_ghost:
			local_cars.append(e.car)
	if remote_cars.is_empty() or local_cars.is_empty():
		_touching.clear()
		return
	var kicks := {}
	for hit in CarContacts.step_against(local_cars, remote_cars, 1.0 / Engine.physics_ticks_per_second, _touching, kicks):
		race.car_contact.emit(hit[0], hit[1], hit[2])
	for e in race.entrants:
		if kicks.has(e.car):
			add_kick(e.slot, kicks[e.car])


## Contact here pushed another phone's car: move its copy accordingly until
## its own states (which will include that push) catch up.
func add_kick(slot: int, dv: Vector3) -> void:
	if not _kicks.has(slot):
		_kicks[slot] = []
	(_kicks[slot] as Array).append([net_time(), dv])


## Also every drawn frame, so other cars glide even when the frame rate and
## the physics rate don't line up.
func _process(_delta: float) -> void:
	if ended or race == null or race.replay.playing:
		return
	# Between physics steps: the fraction of the next step already elapsed.
	var at := net_time() + Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second) - delay
	for e in race.entrants:
		if e.remote:
			_drive_remote(e, at)


func _drive_remote(e, at: float) -> void:
	_drive_remote_lead(e, at, LEAD_MAX)


## (lead_max 0: drawn where it was `delay` ago, as before prediction.)
func _drive_remote_lead(e, at: float, lead_max: float) -> void:
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
	var vel := Vector3(sa[7], sa[8], sa[9]).lerp(Vector3(sb[7], sb[8], sb[9]), f)
	var basis := Basis(qa.slerp(qb, f))
	# Carry it forward to now along its path: on its velocity, turning at
	# its yaw rate (so it follows a bend rather than running wide of it).
	var newest: float = buf[buf.size() - 1][0]
	var lead := clampf(net_time() - at, 0.0, lead_max)
	lead = minf(lead, maxf(newest + lead_max - at, 0.0))
	var yr := 0.0
	if b[0] > a[0]:
		var ha := Vector3(sa[7], 0.0, sa[9])
		var hb := Vector3(sb[7], 0.0, sb[9])
		if ha.length() > 3.0 and hb.length() > 3.0:
			yr = ha.signed_angle_to(hb, Vector3.UP) / (b[0] - a[0])
	var ws: float = lerpf(float(_yaw_rate.get(e.slot, yr)), yr, 0.15)
	_yaw_rate[e.slot] = ws
	if lead > 0.0 and vel.length() > 1.0:
		var turn := ws * lead
		# The step forward, smoothed over ~0.05 s: packets arriving early or
		# late would otherwise make it (and the car) twitch.
		var step := vel.rotated(Vector3.UP, turn * 0.5) * lead
		var now_s := at                    # the game's clock (also in tests)
		var prev: Array = _ahead.get(e.slot, [step, now_s])
		var k := 1.0 - exp(-maxf(now_s - float(prev[1]), 0.0) / 0.05)
		var sm: Vector3 = (prev[0] as Vector3).lerp(step, k)
		_ahead[e.slot] = [sm, now_s]
		pos += sm
		basis = Basis(Vector3.UP, turn) * basis
		vel = vel.rotated(Vector3.UP, turn)
	# Pushes from contact on this phone that its states don't show yet.
	var ks: Array = _kicks.get(e.slot, [])
	if not ks.is_empty():
		var now_t := net_time()
		var k := 0
		while k < ks.size():
			var kt: float = ks[k][0]
			if kt < at:
				ks.remove_at(k)             # its states include this push by now
				continue
			pos += (ks[k][1] as Vector3) * maxf(now_t - kt, 0.0)
			vel += ks[k][1]
			k += 1
	c.global_transform = Transform3D(basis, pos)
	c.remote_vel = vel
	c.steering = lerpf(sa[10], sb[10], f)
	c.rpm = lerpf(sa[11], sb[11], f)
	c.gear = int(sb[12])
	c.brake_input = sb[13]
	c.drs_open = sb[14] > 0.5
	c.throttle = sb[15]
	c.engine_load = sb[15]
	if sb.size() >= 20:
		# Tyres and pit stop (for the tower, tyre colours and the crew).
		var ci := int(sb[16])
		if ci >= 0 and ci < Tyres.COMPOUNDS.size():
			e.compound = Tyres.COMPOUNDS[ci]
		var ni := int(sb[19])
		if ni >= 0 and ni < Tyres.COMPOUNDS.size():
			e.next_compound = Tyres.COMPOUNDS[ni]
		e.wear = sb[17]
		var phase := int(sb[18])
		if phase != e.pit_phase:
			var was: int = e.pit_phase
			e.pit_phase = phase
			if e.pit_box < 0.0 and race.track.has_pit_lane:
				e.pit_box = float(race.track.pit_boxes.get(posmod(e.team_idx, 10), -1.0))
			if phase == 0:
				e.pit_box = -1.0
			if race.weekend != null:
				race.weekend.remote_pit(e, was, phase)
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
			if race.weekend != null:
				race.weekend.remote_pit(e, e.pit_phase, 0)
			e.pit_phase = 0
			e.pit_req = false
			e.pit_box = -1.0
			e.ghost = 1.5
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
