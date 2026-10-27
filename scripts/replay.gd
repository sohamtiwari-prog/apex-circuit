class_name Replay
extends Node
## Race replays.
##
## Every car is recorded 20 times a second for the whole session (position,
## rotation, speed, steering, revs, gear, pedals, DRS), plus the running
## order and the moments worth seeing again (the start, overtakes, contacts,
## fastest laps, the flag). Playback takes over the real cars (frozen,
## posed from the recording with Catmull-Rom curves so it's smooth at any
## speed) and films them with ReplayCamera: TV cameras round the track,
## helicopter, blimp, drone, chase and onboards, or an automatic director.
## When it closes, every car goes back exactly as it was.

signal finished

const HZ := 20.0
const MAX_FRAMES := 18000            # 15 minutes; older footage is dropped
const F := 14                        # floats per car per frame
const SPEEDS := [1.0, 0.5, 0.25, 2.0]
const SPEED_NAMES := ["1x", "1/2", "1/4", "2x"]

var race: Node
var cars: Array = []                 # RaceCar, in entrant order
var names: Array[String] = []
var colors: Array[Color] = []
var is_player: Array[bool] = []
var frames: Array = []               # PackedFloat32Array per car
var order := PackedByteArray()       # race position of every car, per frame
var laps := PackedByteArray()        # completed laps of every car, per frame
var clock := PackedFloat32Array()    # race time, per frame
var events: Array = []               # {f, kind, car, text}
var count := 0
var total_laps := 0
var _acc := 0.0
var _racing := false
var _cur := PackedInt32Array()
var _since := PackedInt32Array()
var _ack := PackedInt32Array()
var _fastest := INF
var _flag := false
var _contact_at := {}

# Playback
var playing := false
var paused := false
var t := 0.0                         # playback position, in frames
var speed_i := 0
var focus := 0
var cam: ReplayCamera
var ui: ReplayUI
var _saved: Array = []
var _race_saved := {}


func setup(r: Node) -> void:
	race = r
	total_laps = int(r.total_laps) if String(r.mode) == "race" else 0
	cars.clear()
	names.clear()
	colors.clear()
	is_player.clear()
	for e in r.entrants:
		cars.append(e.car)
		names.append(String(e.name))
		colors.append(e.car.spec["color"])
		is_player.append(bool(e.is_player))
	r.car_contact.connect(_on_contact)
	clear()


func clear() -> void:
	frames.clear()
	for c in cars:
		frames.append(PackedFloat32Array())
	order = PackedByteArray()
	laps = PackedByteArray()
	clock = PackedFloat32Array()
	events.clear()
	count = 0
	_acc = 0.0
	_racing = false
	_fastest = INF
	_flag = false
	_contact_at.clear()
	_cur.resize(cars.size())
	_since.resize(cars.size())
	_ack.resize(cars.size())


func can_play() -> bool:
	return count >= int(HZ * 2.0)


## Frame to start a full-race replay from: just before the lights go out.
func race_start_frame() -> int:
	for ev in events:
		if ev["kind"] == "start":
			return maxi(int(ev["f"]) - int(HZ * 2.5), 0)
	return 0


# ------------------------------------------------------------ recording

func capture(delta: float) -> void:
	if playing:
		return
	_acc += delta
	while _acc >= 1.0 / HZ:
		_acc -= 1.0 / HZ
		_sample()


func _sample() -> void:
	var ents: Array = race.entrants
	if ents.size() != cars.size():
		return
	for i in cars.size():
		var e = ents[i]
		var c: RaceCar = e.car
		var xf := c.global_transform
		var q := xf.basis.get_rotation_quaternion()
		frames[i].append_array(PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z,
			q.x, q.y, q.z, q.w, c.forward_speed(), c.steering, c.rpm, float(c.gear),
			c.brake_input, c.throttle, 1.0 if c.drs_open else 0.0]))
		order.append(clampi(int(e.position), 0, 255))
		laps.append(clampi(int(e.lap), 0, 255))
	var racing: bool = int(race.state) != 0
	clock.append(float(race.race_time) if racing else 0.0)
	count += 1
	if racing and not _racing:
		_racing = true
		mark(count - 1, "start", -1, "Lights out")
		for i in cars.size():
			_cur[i] = int(ents[i].position)
			_ack[i] = _cur[i]
			_since[i] = count - 1
	if _racing:
		_watch_positions(ents)
	if count > MAX_FRAMES:
		_trim(MAX_FRAMES / 2)


## Overtakes: a place gained or lost (held for a second, so a flicker at
## the line isn't one), for you, and every change of leader.
func _watch_positions(ents: Array) -> void:
	for i in cars.size():
		var p := int(ents[i].position)
		if p != _cur[i]:
			_cur[i] = p
			_since[i] = count - 1
		elif p != _ack[i] and count - 1 - _since[i] >= int(HZ):
			var old := _ack[i]
			_ack[i] = p
			if is_player[i]:
				if p < old:
					mark(_since[i], "gain", i, "You take P%d" % p)
				else:
					mark(_since[i], "loss", i, "You drop to P%d" % p)
			elif p == 1:
				mark(_since[i], "lead", i, "%s takes the lead" % names[i])


func on_lap(e, lap_time: float) -> void:
	var i := cars.find(e.car)
	if i < 0:
		return
	if lap_time < _fastest:
		if _fastest < INF:
			mark(count, "fastest", i, "Fastest lap: %s  %s" % [names[i], UIStyle.fmt_time(lap_time)])
		_fastest = lap_time
	if e.finished:
		if not _flag:
			_flag = true
			mark(count, "finish", i, "Chequered flag: %s wins" % names[i] if not is_player[i] else "Chequered flag: you win!")
		elif is_player[i]:
			mark(count, "finish", i, "You finish P%d" % int(e.position))


func _on_contact(a: RaceCar, b: RaceCar, closing: float) -> void:
	if not _racing or closing < 3.0 or playing:
		return
	var i := cars.find(a)
	var j := cars.find(b)
	if i < 0 or j < 0:
		return
	var key := "%d-%d" % [mini(i, j), maxi(i, j)]
	if count - int(_contact_at.get(key, -100000)) < int(HZ * 3.0):
		return
	_contact_at[key] = count
	if is_player[j]:
		var k := i
		i = j
		j = k
	mark(count, "contact", i, "Contact: %s and %s" % [names[i], names[j]])


func mark(f: int, kind: String, car: int, text: String) -> void:
	# The same thing again within 5 s replaces the earlier note.
	if not events.is_empty():
		var last: Dictionary = events[events.size() - 1]
		if last["kind"] == kind and int(last["car"]) == car and f - int(last["f"]) < int(HZ * 5.0):
			events.remove_at(events.size() - 1)
	events.append({"f": f, "kind": kind, "car": car, "text": text})
	events.sort_custom(func(a, b): return int(a["f"]) < int(b["f"]))


func _trim(drop: int) -> void:
	for i in cars.size():
		frames[i] = (frames[i] as PackedFloat32Array).slice(drop * F)
	order = order.slice(drop * cars.size())
	laps = laps.slice(drop * cars.size())
	clock = clock.slice(drop)
	count -= drop
	var kept: Array = []
	for ev in events:
		ev["f"] = int(ev["f"]) - drop
		if int(ev["f"]) >= 0:
			kept.append(ev)
	events = kept
	for i in cars.size():
		_since[i] = maxi(_since[i] - drop, 0)


# ------------------------------------------------------------ playback

func start(from_frame: int) -> void:
	if playing or not can_play():
		return
	playing = true
	paused = false
	speed_i = 0
	t = clampf(float(from_frame), 0.0, float(count - 1))
	_saved.clear()
	for c in cars:
		var car: RaceCar = c
		var wheel_state: Array = []
		for w in car.wheels:
			wheel_state.append([w.steer_angle, w.spin_rate])
		_saved.append({"xf": car.global_transform, "lv": car.linear_velocity, "av": car.angular_velocity,
			"freeze": car.freeze, "fmode": car.freeze_mode, "pp": car.is_physics_processing(),
			"remote": car.remote, "rv": car.remote_vel, "ce": car.controls_enabled,
			"steer": car.steering, "rpm": car.rpm, "gear": car.gear, "brake": car.brake_input,
			"thr": car.throttle, "load": car.engine_load, "drs": car.drs_open, "slip": car.tyre_slip,
			"layer": car.collision_layer, "mask": car.collision_mask, "wheels": wheel_state,
			"visible": car.visible})
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
		car.set_physics_process(false)
		car.remote = true
		car.controls_enabled = true
		car.tyre_slip = 0.0
		car.visible = true
		car.collision_layer = 0
		car.collision_mask = 0
	_race_saved = {"guide": race.line_guide.visible if race.line_guide != null else false,
		"ghost": race.ghost_car.visible if race.ghost_car != null else false}
	if race.line_guide != null:
		race.line_guide.visible = false
	if race.ghost_car != null:
		race.ghost_car.visible = false
	race.cam.current = false
	race.cam.set_physics_process(false)
	race.hud.visible = false
	race.hud.touch.release_all()
	if race.tyre_fx != null:
		race.tyre_fx.set_physics_process(false)
		race.tyre_fx.stop_smoke()
	if race.audio != null:
		race.audio.replay_mode = true

	focus = maxi(is_player.find(true), 0)
	cam = ReplayCamera.new()
	race.add_child(cam)
	cam.setup(race.track, self)
	cam.set_focus(cars[focus])
	cam.current = true
	ui = ReplayUI.new()
	race.add_child(ui)
	ui.setup(self)
	_pose_all()
	cam.cut()
	cam.follow(0.0)
	_apply_audio()


func stop() -> void:
	if not playing:
		return
	playing = false
	for i in cars.size():
		var car: RaceCar = cars[i]
		var s: Dictionary = _saved[i]
		car.freeze_mode = s["fmode"]
		car.global_transform = s["xf"]
		car.freeze = s["freeze"]
		if not car.freeze:
			car.linear_velocity = s["lv"]
			car.angular_velocity = s["av"]
		car.set_physics_process(s["pp"])
		car.remote = s["remote"]
		car.remote_vel = s["rv"]
		car.controls_enabled = s["ce"]
		car.steering = s["steer"]
		car.rpm = s["rpm"]
		car.gear = s["gear"]
		car.brake_input = s["brake"]
		car.throttle = s["thr"]
		car.engine_load = s["load"]
		car.drs_open = s["drs"]
		car.tyre_slip = s["slip"]
		car.collision_layer = s["layer"]
		car.collision_mask = s["mask"]
		car.visible = s["visible"]
		for k in car.wheels.size():
			car.wheels[k].steer_angle = s["wheels"][k][0]
			car.wheels[k].spin_rate = s["wheels"][k][1]
	_saved.clear()
	if cam != null:
		cam.release()
		cam.queue_free()
		cam = null
	if ui != null:
		ui.queue_free()
		ui = null
	if race.line_guide != null:
		race.line_guide.visible = _race_saved["guide"]
	if race.ghost_car != null:
		race.ghost_car.visible = _race_saved["ghost"]
	race.cam.current = true
	race.cam.set_physics_process(true)
	race.cam.snap()
	race.hud.visible = true
	if race.tyre_fx != null:
		race.tyre_fx.set_physics_process(true)
	if race.audio != null:
		race.audio.replay_mode = false
	_reset_audio()
	finished.emit()


func _exit_tree() -> void:
	_reset_audio()


func _reset_audio() -> void:
	AudioServer.playback_speed_scale = 1.0
	AudioServer.set_bus_mute(0, false)


func _apply_audio() -> void:
	AudioServer.playback_speed_scale = SPEEDS[speed_i]
	AudioServer.set_bus_mute(0, paused)


func set_paused(p: bool) -> void:
	paused = p
	if p == false and t >= count - 1.5:
		t = float(race_start_frame())        # play again from the start
		if cam != null:
			cam.cut()
	_apply_audio()


func toggle_pause() -> void:
	set_paused(not paused)


func cycle_speed() -> void:
	speed_i = (speed_i + 1) % SPEEDS.size()
	_apply_audio()


func seek(frame: float) -> void:
	t = clampf(frame, 0.0, float(count - 1))
	if cam != null:
		cam.cut()
	_pose_all()


func skip(seconds: float) -> void:
	seek(t + seconds * HZ)


func set_focus(i: int) -> void:
	focus = posmod(i, cars.size())
	if cam != null:
		cam.set_focus(cars[focus])


## Next / previous car by race position at this moment of the replay.
func step_focus(dir: int) -> void:
	var n := cars.size()
	var p := position_of(focus)
	for k in range(1, n + 1):
		var want := posmod(p - 1 + dir * k, n) + 1
		for i in n:
			if position_of(i) == want:
				set_focus(i)
				return


## Jump to just before the next highlight after this point, watching the
## car it's about.
func next_highlight() -> void:
	var now := int(t) + int(HZ * 3.5)
	for ev in events:
		if int(ev["f"]) > now:
			seek(float(int(ev["f"])) - HZ * 3.0)
			if int(ev["car"]) >= 0:
				set_focus(int(ev["car"]))
			set_paused(false)
			return
	# None left: back to the first one.
	if not events.is_empty():
		var ev: Dictionary = events[0]
		seek(maxf(float(int(ev["f"])) - HZ * 3.0, 0.0))
		if int(ev["car"]) >= 0:
			set_focus(int(ev["car"]))


func frame_index() -> int:
	return clampi(int(t), 0, count - 1)


func position_of(i: int) -> int:
	return int(order[frame_index() * cars.size() + i])


func lap_of(i: int) -> int:
	return int(laps[frame_index() * cars.size() + i])


func time_at() -> float:
	var k := frame_index()
	var k1 := mini(k + 1, count - 1)
	return lerpf(clock[k], clock[k1], t - float(k))


## The event being shown around now (within its first 4 s), or {}.
func caption() -> Dictionary:
	for ev in events:
		var d := t - float(int(ev["f"]))
		if d >= -0.2 * HZ and d < 4.0 * HZ:
			return ev
	return {}


func _physics_process(delta: float) -> void:
	if not playing:
		return
	if not paused:
		t += delta * HZ * SPEEDS[speed_i]
		if t >= float(count - 1):
			t = float(count - 1)
			set_paused(true)
	_pose_all()
	if cam != null:
		cam.follow(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not playing or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE, KEY_K:
			toggle_pause()
		KEY_LEFT, KEY_J:
			skip(-5.0)
		KEY_RIGHT, KEY_L:
			skip(5.0)
		KEY_C:
			cam.cycle_mode()
		KEY_UP:
			step_focus(-1)
		KEY_DOWN:
			step_focus(1)
		KEY_H:
			next_highlight()
		KEY_ESCAPE, KEY_BACKSPACE:
			stop()
	get_viewport().set_input_as_handled()


func _pose_all() -> void:
	var rate: float = 0.0 if paused else SPEEDS[speed_i]
	for i in cars.size():
		_pose(i, rate)


func _pos(a: PackedFloat32Array, k: int) -> Vector3:
	return Vector3(a[k * F], a[k * F + 1], a[k * F + 2])


func _pose(i: int, rate: float) -> void:
	var a: PackedFloat32Array = frames[i]
	var k := frame_index()
	var f := t - float(k)
	var k1 := mini(k + 1, count - 1)
	var p1 := _pos(a, k)
	var p2 := _pos(a, k1)
	var pos: Vector3
	var vel: Vector3
	if p1.distance_squared_to(p2) > 25.0 * 25.0:
		# A reset (teleport): no curve across it.
		pos = p1 if f < 0.5 else p2
		vel = Vector3.ZERO
		f = 0.0 if f < 0.5 else 1.0
	else:
		var p0 := _pos(a, maxi(k - 1, 0))
		var p3 := _pos(a, mini(k + 2, count - 1))
		if p0.distance_squared_to(p1) > 25.0 * 25.0:
			p0 = p1 - (p2 - p1)
		if p3.distance_squared_to(p2) > 25.0 * 25.0:
			p3 = p2 + (p2 - p1)
		var f2 := f * f
		var f3 := f2 * f
		pos = 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)
		vel = 0.5 * ((p2 - p0) + 2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f + 3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f2) * HZ
	var o1 := k * F
	var o2 := k1 * F
	var q1 := Quaternion(a[o1 + 3], a[o1 + 4], a[o1 + 5], a[o1 + 6]).normalized()
	var q2 := Quaternion(a[o2 + 3], a[o2 + 4], a[o2 + 5], a[o2 + 6]).normalized()
	var c: RaceCar = cars[i]
	c.global_transform = Transform3D(Basis(q1.slerp(q2, f)), pos)
	c.remote_vel = vel
	c.steering = lerpf(a[o1 + 8], a[o2 + 8], f)
	c.rpm = lerpf(a[o1 + 9], a[o2 + 9], f)
	c.gear = int(a[o2 + 10]) if f > 0.5 else int(a[o1 + 10])
	c.brake_input = lerpf(a[o1 + 11], a[o2 + 11], f)
	c.throttle = lerpf(a[o1 + 12], a[o2 + 12], f)
	c.engine_load = c.throttle
	c.drs_open = (a[o2 + 13] if f > 0.5 else a[o1 + 13]) > 0.5
	var v := lerpf(a[o1 + 7], a[o2 + 7], f)
	for w in c.wheels:
		w.steer_angle = c.steering if w.use_as_steering else 0.0
		w.spin_rate = v / w.wheel_radius * rate
