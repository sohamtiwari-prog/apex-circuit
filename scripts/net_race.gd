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
## Other cars are drawn from their newest state, carried on to now, not
## from states `delay` old: the less that's guessed, the closer to where they
## really are (tests/mp_truth.py: online, half the distance off). The
## gliding (below) keeps them smooth through late and early packets instead.
const DRAW_DELAY := 0.03
const DELAY_MAX := 0.6         # online through a public server can be jumpy
const START_WAIT := 15.0       # max seconds to wait for everyone to load
const LEAD_MAX := 1.0          # carry other cars forward at most this far (s): all the delay
const PRED_MAX := 1.0          # and at most this far past the newest state (s): a hiccup
const SNAP := 25.0             # a correction bigger than this (m) is a reset: no gliding
const GLIDE := 0.07            # small corrections are blended in over about this long (s)

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
var _disp := {}                     # slot -> [position, rotation, velocity, yaw rate, time] as last drawn
var horizon := {}                   # slot -> how far ahead of its newest state it's drawn (s)


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


## Estimated host session time, on any phone. The offset from the fastest
## packets is the host's clock as it was when they left (one trip behind),
## so half the round trip is added: then every phone means the same moment
## by "now", draws the others where they are now, and contact between two
## phones' cars happens in the same place on both (instead of the host's
## cars being drawn ~0.15 s back online, where you'd hit them, or not).
func net_time() -> float:
	if Net.is_host():
		return _sim
	return _sim + (_offset if _offset > -INF else 0.0) + _half_trip


var _half_trip := 0.0
var _pings: Array[int] = []
var _last_ping := -1


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

## A car's state plus its tyres and pit stop (compound, wear, pit phase,
## the compound it's boxing for) and race control (penalty to serve,
## penalties in all, track limits strikes, stops).
static func entrant_state(e) -> PackedFloat32Array:
	var s := car_state(e.car)
	s.append_array(PackedFloat32Array([float(Tyres.COMPOUNDS.find(e.compound)), e.wear, float(e.pit_phase), float(Tyres.COMPOUNDS.find(e.next_compound)),
		e.pen_pending, e.pen_total, float(e.tl_strikes), float(e.stops)]))
	# How fast it's turning: carrying it on round a bend between updates.
	var c: RaceCar = e.car
	s.append(c.remote_yaw if c.remote else (0.0 if c.freeze else c.angular_velocity.dot(c.global_basis.y)))
	return s


## position, rotation, velocity, steering, rpm, gear, brake, DRS, throttle
static func car_state(c: RaceCar) -> PackedFloat32Array:
	var xf := c.global_transform
	var q := xf.basis.get_rotation_quaternion()
	var v := c.remote_vel if c.remote else c.linear_velocity
	if c.freeze and not c.remote:
		v = Vector3.ZERO                 # (a frozen body keeps its last velocity, but isn't moving)
	return PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w,
		v.x, v.y, v.z, c.steering, c.rpm, float(c.gear), c.brake_input, 1.0 if c.drs_open else 0.0, c.throttle])


## On the wire, a car's state is packed into 45 bytes (it was ~120 as
## floats in a dictionary): a 20-car snapshot is ~0.9 KB instead of 2.4 KB,
## so it fits in one network packet (nothing to reassemble, nothing lost
## when one fragment of a big packet goes missing) and online it's a third
## of the traffic through the servers. Position stays exact; rotation,
## speed and the rest are rounded far below anything you could see.
const PACKED := 45

static func _q16(x: float, scale: float) -> int:
	return clampi(roundi(x * scale), -32767, 32767)


static func pack_state(buf: StreamPeerBuffer, slot: int, s: PackedFloat32Array) -> void:
	var f := s.duplicate()
	if f.size() < 25:
		f.resize(25)
	buf.put_u8(slot)
	buf.put_float(f[0]); buf.put_float(f[1]); buf.put_float(f[2])
	var q := Quaternion(f[3], f[4], f[5], f[6]).normalized()
	if q.w < 0.0:
		q = -q                               # (same rotation: keeps w >= 0)
	buf.put_16(_q16(q.x, 32767.0)); buf.put_16(_q16(q.y, 32767.0)); buf.put_16(_q16(q.z, 32767.0))
	buf.put_16(_q16(f[7], 100.0)); buf.put_16(_q16(f[8], 100.0)); buf.put_16(_q16(f[9], 100.0))
	buf.put_8(clampi(roundi(f[10] * 127.0), -127, 127))
	buf.put_u16(clampi(roundi(f[11]), 0, 65535))
	buf.put_8(clampi(int(f[12]), -1, 12))
	buf.put_u8(clampi(roundi(f[13] * 255.0), 0, 255))
	buf.put_u8(1 if f[14] > 0.5 else 0)
	buf.put_u8(clampi(roundi(f[15] * 255.0), 0, 255))
	buf.put_8(int(f[16])); buf.put_u16(clampi(roundi(f[17] * 65535.0), 0, 65535)); buf.put_u8(int(f[18])); buf.put_8(int(f[19]))
	buf.put_u16(clampi(roundi(f[20] * 10.0), 0, 65535)); buf.put_u16(clampi(roundi(f[21] * 10.0), 0, 65535))
	buf.put_u8(clampi(int(f[22]), 0, 255)); buf.put_u8(clampi(int(f[23]), 0, 255))
	buf.put_16(_q16(f[24], 1000.0))


## [slot, state] from bytes written by pack_state.
static func unpack_state(buf: StreamPeerBuffer) -> Array:
	var slot := buf.get_u8()
	var f := PackedFloat32Array()
	f.resize(25)
	f[0] = buf.get_float(); f[1] = buf.get_float(); f[2] = buf.get_float()
	var qx := buf.get_16() / 32767.0
	var qy := buf.get_16() / 32767.0
	var qz := buf.get_16() / 32767.0
	f[3] = qx; f[4] = qy; f[5] = qz; f[6] = sqrt(maxf(1.0 - qx * qx - qy * qy - qz * qz, 0.0))
	f[7] = buf.get_16() / 100.0; f[8] = buf.get_16() / 100.0; f[9] = buf.get_16() / 100.0
	f[10] = buf.get_8() / 127.0
	f[11] = buf.get_u16()
	f[12] = buf.get_8()
	f[13] = buf.get_u8() / 255.0
	f[14] = buf.get_u8()
	f[15] = buf.get_u8() / 255.0
	f[16] = buf.get_8(); f[17] = buf.get_u16() / 65535.0; f[18] = buf.get_u8(); f[19] = buf.get_8()
	f[20] = buf.get_u16() / 10.0; f[21] = buf.get_u16() / 10.0
	f[22] = buf.get_u8(); f[23] = buf.get_u8()
	f[24] = buf.get_16() / 1000.0
	return [slot, f]


static func pack_states(states: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	for slot in states:
		pack_state(buf, int(slot), states[slot])
	return buf.data_array


static func unpack_states(bytes: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var out := {}
	while buf.get_available_bytes() >= PACKED:
		var r := unpack_state(buf)
		out[int(r[0])] = r[1]
	return out


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
		# Never jump while racing: at most 5% faster or slower than real time
		# while syncing (15% if it's well out). On the grid, before the
		# lights, it's set straight away: the start is where cars are
		# closest, so it has to be right by then (it was still catching up
		# from the first, possibly late, packet: cars ~10 m from where they
		# were for the first seconds of the race).
		var rate := 0.15 if absf(target - _offset) > 0.25 else 0.05
		_offset = target if race.state == 0 else move_toward(_offset, target, rate * delta)
	if not Net.is_host() and Net.my_ping > 0 and Net.my_ping != _last_ping:
		_last_ping = Net.my_ping
		_pings.append(Net.my_ping)
		if _pings.size() > 8:
			_pings.pop_front()
	if not _pings.is_empty():
		var ht := minf(float(_pings.min()) / 2000.0, 0.35)
		_half_trip = ht if race.state == 0 else move_toward(_half_trip, ht, 0.05 * delta)
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
			var snap := {"t": "s", "nt": net_time(), "time": race.race_time, "st": race.state, "lt": race.lights_time, "b": pack_states(cars)}
			if race.control != null and race.control.sc_phase > 0:
				snap["sc"] = race.control.sc.net_state()
			elif race.control != null:
				snap["sc"] = [0, 0]
			Net.send(0, snap, false)
		else:
			Net.send(1, {"t": "c", "nt": net_time(), "b": pack_states({race.player.slot: entrant_state(race.player)})}, false)
	if Net.is_host():
		_std_t -= delta
		if _std_t <= 0.0:
			_std_t = 0.25
			# (Numbers as one flat array, 10 per car, and the few retirement
			# reasons on their own: a third of the size of a list of lists.)
			var flat := PackedFloat32Array()
			var why := {}
			for e in race.entrants:
				flat.append_array(PackedFloat32Array([e.slot, e.lap, e.progress, 1 if e.finished else 0, e.finish_time, e.best_lap, e.last_lap, e.position,
					1 if e.dnf else 0, 1 if e.car.visible else 0]))
				if e.dnf_reason != "":
					why[e.slot] = e.dnf_reason
			var vsc: int = race.control.vsc_state() if race.control != null else 0
			Net.send(0, {"t": "std", "f": flat, "why": why, "vsc": vsc})
	else:
		# Follow the host's clock and start lights.
		if _host_time_at > 0.0 and race.state != 0:
			race.race_time = _host_time + (t - _host_time_at)
	# Every physics step only the cars that could touch yours (for contact);
	# the rest move once per drawn frame (_process). On a friend's phone
	# that's nearly every car: doing all 19 at 120 a second as well cost
	# ~0.1 s of every second of racing, enough to make the game stutter.
	var at := net_time() - DRAW_DELAY
	var mine: Vector3 = race.car.global_position
	for e in race.entrants:
		if e.remote and (Net.is_host() or e.car.global_position.distance_squared_to(mine) < 50.0 * 50.0):
			_drive_remote(e, at)
	if race.control != null and not Net.is_host():
		race.control.sc.net_draw(self, at)
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
	# How sure we are where each other phone's car is: firm when its state
	# is fresh, gentler the further it's been guessed ahead (> 0.2 s).
	var soft := {}
	for e in race.entrants:
		if e.remote:
			soft[e.car] = clampf(1.0 - (float(horizon.get(e.slot, 0.0)) - 0.2) / 0.5, 0.4, 1.0)
	for hit in CarContacts.step_against(local_cars, remote_cars, 1.0 / Engine.physics_ticks_per_second, _touching, kicks, soft):
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
	var at := net_time() + Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second) - DRAW_DELAY
	for e in race.entrants:
		if e.remote:
			_drive_remote(e, at)


var cost_us := 0
## How the host's updates arrive here (for the connection readout and tests):
## how many, the longest wait between two, and how many waits over 0.25 s.
var rx_count := 0
var rx_max_gap := 0.0
var rx_stalls := 0
var _rx_last := -1.0

func _note_arrival() -> void:
	var t := now()
	if _rx_last > 0.0:
		var g := t - _rx_last
		if race != null and race.state == 1:
			rx_max_gap = maxf(rx_max_gap, g)
			if g > 0.25:
				rx_stalls += 1
	_rx_last = t
	rx_count += 1

                    # time spent drawing other phones' cars (tests)

func _drive_remote(e, at: float) -> void:
	var t0 := Time.get_ticks_usec()
	_drive_remote_lead(e, at, LEAD_MAX)
	cost_us += Time.get_ticks_usec() - t0


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
	var newest: float = buf[buf.size() - 1][0]
	var f := 0.0
	var pos: Vector3
	var tb := float(a[0])                  # the time the base state is for
	if b[0] > a[0]:
		f = clampf((at - a[0]) / (b[0] - a[0]), 0.0, 1.0)
		pos = Vector3(sa[0], sa[1], sa[2]).lerp(Vector3(sb[0], sb[1], sb[2]), f)
		tb = lerpf(a[0], b[0], f)
	else:
		pos = Vector3(sa[0], sa[1], sa[2])
	var qa := Quaternion(sa[3], sa[4], sa[5], sa[6]).normalized()
	var qb := Quaternion(sb[3], sb[4], sb[5], sb[6]).normalized()
	var c: RaceCar = e.car
	var vel := Vector3(sa[7], sa[8], sa[9]).lerp(Vector3(sb[7], sb[8], sb[9]), f)
	var basis := Basis(qa.slerp(qb, f))
	# Shown at now: carried forward from the base state (also past the
	# newest state, through a hiccup on the connection, up to PRED_MAX).
	# (Now includes how far into the next physics step this frame is, so a
	# car moves on every drawn frame, not in lumps when the frame rate and
	# the physics rate don't line up.)
	var shown_t := minf(minf(at + DRAW_DELAY, at + lead_max), newest + PRED_MAX)
	shown_t = maxf(shown_t, tb)
	var h := shown_t - tb
	horizon[e.slot] = shown_t - newest
	var yr := 0.0
	if b[0] > a[0]:
		var ha := Vector3(sa[7], 0.0, sa[9])
		var hb := Vector3(sb[7], 0.0, sb[9])
		if ha.length() > 3.0 and hb.length() > 3.0:
			yr = ha.signed_angle_to(hb, Vector3.UP) / (b[0] - a[0])
	var ws: float = lerpf(float(_yaw_rate.get(e.slot, yr)), yr, 0.15)
	if sa.size() > 24 and sb.size() > 24:
		ws = lerpf(sa[24], sb[24], f)        # (its own yaw rate, sent with it)
	_yaw_rate[e.slot] = ws
	if h > 0.0 and vel.length() > 1.0:
		# Speeding up or braking (from the last two states), so a car
		# braking for a corner is drawn slowing, not still at full speed.
		# (Over ~0.2 s of states: from one update to the next it's noisy.)
		var acc := 0.0
		var o: Array = b
		for st0 in buf:
			if float(st0[0]) <= float(b[0]) - 0.2:
				o = st0
		if b[0] > o[0]:
			var so: PackedFloat32Array = o[1]
			acc = clampf((Vector3(sb[7], sb[8], sb[9]).length() - Vector3(so[7], so[8], so[9]).length()) / (b[0] - o[0]), -35.0, 12.0)
		# Sliding sideways (a nudge, a squeeze) doesn't last: the tyres stop
		# it within a fraction of a second, so that part isn't carried on
		# like the rest (it would push the car further into yours).
		var fwd := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
		var side := vel - fwd * vel.dot(fwd)
		side.y = 0.0
		var run := vel - side
		var spd := run.length()
		if spd < 1.0:
			run = vel
			side = Vector3.ZERO
			spd = vel.length()
		var t_stop := h if acc >= 0.0 else minf(h, spd / -acc)
		var dist := spd * t_stop + 0.5 * acc * t_stop * t_stop
		var spd1 := maxf(spd + acc * t_stop, 0.0)
		# On round the bend at its yaw rate (tested against carrying it along
		# the track itself: this is closer, the track's line isn't the car's).
		var turn := ws * h
		pos += run.rotated(Vector3.UP, turn * 0.5) / spd * dist + side * 0.15 * (1.0 - exp(-h / 0.15))
		basis = Basis(Vector3.UP, turn) * basis
		vel = run.rotated(Vector3.UP, turn) / spd * spd1 + side * exp(-h / 0.15)
	# Pushes from contact on this phone that its states don't show yet
	# (added after the gliding below: they're known here, not guessed).
	var kick_pos := Vector3.ZERO
	var kick_vel := Vector3.ZERO
	var ks: Array = _kicks.get(e.slot, [])
	if not ks.is_empty():
		var now_t := net_time()
		var k := 0
		while k < ks.size():
			var kt: float = ks[k][0]
			if kt < newest:
				ks.remove_at(k)             # its states include this push by now
				continue
			kick_pos += (ks[k][1] as Vector3) * maxf(now_t - kt, 0.0)
			kick_vel += ks[k][1]
			k += 1
	# What's drawn (and touched) glides onto that: each new state corrects
	# the prediction a little, and those corrections are blended in instead
	# of making the car jump: a small one over a few hundredths of a second,
	# a big one (after a stall on the connection) over up to a third of a
	# second, so the car slides back into place rather than teleporting.
	# Only a reset or the pits (> SNAP) moves it at once.
	var prev_d: Array = _disp.get(e.slot, [])
	if not prev_d.is_empty():
		var dt: float = shown_t - float(prev_d[4])
		if dt >= 0.0 and dt < 0.5:
			var pv: Vector3 = prev_d[2]
			var pturn: float = float(prev_d[3]) * dt
			var guess: Vector3 = (prev_d[0] as Vector3) + pv.rotated(Vector3.UP, pturn * 0.5) * dt
			var err := pos - guess
			var el := err.length()
			if el < SNAP:
				var tau := clampf(GLIDE + el * 0.03, GLIDE, 0.35)
				var kp := 1.0 - exp(-dt / tau)
				pos = guess + err * kp
				var qg := (Basis(Vector3.UP, pturn) * (prev_d[1] as Basis)).get_rotation_quaternion()
				basis = Basis(qg.slerp(basis.get_rotation_quaternion(), 1.0 - exp(-dt / (tau * 0.8))))
	_disp[e.slot] = [pos, basis, vel, ws, shown_t]
	c.remote_yaw = ws
	c.global_transform = Transform3D(basis, pos + kick_pos)
	c.remote_vel = vel + kick_vel
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
			if phase == 3 and was == 2:
				e.pitted_lap = true
				e.stints.append(e.compound)
	if sb.size() >= 24:
		e.pen_pending = sb[20]
		e.pen_total = sb[21]
		e.tl_strikes = int(sb[22])
		e.stops = int(sb[23])
		if e.stops == 0:
			e.stints = [e.compound]            # (the tyre it started on)
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
				_note_late(float(offs.max()) - float(offs[offs.size() - 1]))
				var mine: Dictionary = unpack_states(m.get("b", PackedByteArray()))
				if not mine.is_empty():
					_push(_slot_of_peer[from], mine.values()[0], nt)
		"ready":
			_ready_peers[from] = true
		"s":
			if Net.is_host():
				return
			_note_arrival()
			_host_time = float(m["time"])
			_host_time_at = now()
			# Clock offset: the fastest packet in the last ~2 s is the best
			# estimate (least delayed). The clock then glides towards it.
			_offsets.append(float(m["nt"]) - _sim)
			if _offsets.size() > 40:
				_offsets.pop_front()
			_note_late(float(_offsets.max()) - float(_offsets[_offsets.size() - 1]))
			if _offset == -INF:
				_offset = _offsets[0]
			_host_state = int(m["st"])
			var me: int = race.player.slot
			var cars: Dictionary = unpack_states(m.get("b", PackedByteArray()))
			for slot in cars:
				if int(slot) != me:
					_push(int(slot), cars[slot], float(m["nt"]))
			if m.has("sc") and race.control != null:
				race.control.sc.net_update(m["sc"], float(m["nt"]), self)
			if race.state == 0:
				race.lights_time = float(m["lt"])
				if _host_state != 0:
					race.lights_out_at = 0.0           # lights out on the next tick
		"std":
			if Net.is_host():
				return
			var flat: PackedFloat32Array = m.get("f", PackedFloat32Array())
			var why: Dictionary = m.get("why", {})
			var rows: Array = []
			for k in range(0, flat.size() - 9, 10):
				rows.append([flat[k], flat[k + 1], flat[k + 2], flat[k + 3], flat[k + 4], flat[k + 5], flat[k + 6], flat[k + 7],
					flat[k + 8], String(why.get(int(flat[k]), "")), flat[k + 9]])
			_apply_standings(rows)
			if race.control != null and int(m.get("vsc", 0)) != race.control.vsc_state():
				race.control.set_vsc(int(m.get("vsc", 0)))
		"rc":
			# Race control from another phone; the host passes it on.
			if int(m.get("o", 0)) == Net.my_id:
				return
			if Net.is_host():
				Net.send(0, m)
			if race.control != null:
				race.control.remote_message(String(m.get("m", "")))
		"to_lobby":
			ended = true
			race.go_to_lobby()


## How late packets arrive: the delay covers nine in ten of them. The odd
## very late one (a hiccup in the connection) doesn't push every car further
## back for the next few seconds; the prediction covers it instead.
var _late: Array[float] = []

func _note_late(l: float) -> void:
	_late.append(l)
	if _late.size() > 60:
		_late.pop_front()
	var s := _late.duplicate()
	s.sort()
	_jitter = maxf(_jitter, s[int(0.9 * (s.size() - 1))])


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
		if r.size() >= 11:
			e.dnf = int(r[8]) == 1
			e.dnf_reason = String(r[9])
			if int(r[10]) == 0 and e.car.visible:
				e.car.visible = false


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


## A race control message from this phone, to everyone else.
func send_rc(text: String) -> void:
	if ended:
		return
	Net.send(0 if Net.is_host() else 1, {"t": "rc", "m": text, "o": Net.my_id})


## Host: everyone back to the lobby for the next race.
func back_to_lobby() -> void:
	ended = true
	Net.send(0, {"t": "to_lobby"})
	race.go_to_lobby()
