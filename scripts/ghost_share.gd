class_name GhostShare
extends Node
## Ghost challenges: your best lap, sent to a friend as a short code. The
## lap (the car's path, 10 times a second) goes to a public relay as a
## retained message under the code; a friend with the code fetches it and
## races it as a ghost in a time trial, any time later. Nothing to install,
## no accounts: the same free relays the online races use.

signal done(ok: bool, result: Variant)     # upload: the code; download: the challenge

const TOPIC := "apexcircuit/v1/ghost/"
const CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const SEND_HZ := 10.0
const TIMEOUT := 9.0

var _link: MqttLink
var _brokers: Array = []
var _job := ""                 # "up" or "down"
var _code := ""
var _payload := PackedByteArray()
var _t := 0.0
var _waited := 0.0


## Packs a lap (race.gd ghost samples: x, y, z, qx, qy, qz, qw at hz) and
## who/where it was, small: 10 samples a second, rotations in 16 bits.
static func pack(samples: PackedFloat32Array, hz: float, info: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	var n := samples.size() / 7
	var step := hz / SEND_HZ
	var count := int(floor((n - 1) / step)) + 1
	buf.put_u32(count)
	for k in count:
		var i := mini(int(round(k * step)), n - 1) * 7
		buf.put_float(samples[i]); buf.put_float(samples[i + 1]); buf.put_float(samples[i + 2])
		for c in 4:
			buf.put_16(int(round(clampf(samples[i + 3 + c], -1.0, 1.0) * 32767.0)))
	var body := buf.data_array.compress(FileAccess.COMPRESSION_DEFLATE)
	var meta := info.duplicate()
	meta["raw"] = buf.data_array.size()
	meta["path"] = body
	return var_to_bytes(meta)


## Back to race.gd's form (at hz), and the info. {} if it isn't one.
static func unpack(bytes: PackedByteArray, hz: float) -> Dictionary:
	var meta: Variant = bytes_to_var(bytes)
	if not (meta is Dictionary) or not (meta as Dictionary).has("path"):
		return {}
	var raw: PackedByteArray = (meta["path"] as PackedByteArray).decompress(int(meta["raw"]), FileAccess.COMPRESSION_DEFLATE)
	var buf := StreamPeerBuffer.new()
	buf.data_array = raw
	var count := buf.get_u32()
	var pts: Array = []
	for k in count:
		var p := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		var q := Quaternion(buf.get_16() / 32767.0, buf.get_16() / 32767.0, buf.get_16() / 32767.0, buf.get_16() / 32767.0).normalized()
		pts.append([p, q])
	var out := PackedFloat32Array()
	var step := SEND_HZ / hz
	var t := 0.0
	while t <= count - 1:
		var i := int(t)
		var f := t - i
		var a: Array = pts[i]
		var b: Array = pts[mini(i + 1, count - 1)]
		var p: Vector3 = (a[0] as Vector3).lerp(b[0], f)
		var q: Quaternion = (a[1] as Quaternion).slerp(b[1], f)
		out.append_array([p.x, p.y, p.z, q.x, q.y, q.z, q.w])
		t += step
	var info: Dictionary = meta
	info.erase("path")
	info["samples"] = out
	return info


## Where a best lap's ghost is kept (race.gd writes it after a best lap).
static func ghost_path(lap_key: String) -> String:
	return "user://ghosts/%s.bin" % lap_key.replace("|", "__")


## Your saved best lap on a track in a car (race.gd's samples), or empty.
static func saved_lap(lap_key: String) -> PackedFloat32Array:
	var p := ghost_path(lap_key)
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		var v: Variant = f.get_var()
		if v is PackedFloat32Array:
			return v
	return PackedFloat32Array()


## What goes with a shared lap: where, in what, by whom, how fast.
static func info_for(save: Node, track_id: String, car_id: String, lap_ms: int) -> Dictionary:
	var name := String(save.get_setting("player_name"))
	return {"v": 1, "track": track_id, "car": car_id, "team": int(save.get_setting("team")),
		"paint": save.my_paint(car_id), "name": name if name != "" else "A friend", "lap_ms": lap_ms}


## Share your best lap on a track in a car from anywhere (the Quick race
## screen, the pause menu): done(true, code) or done(false, why).
func share_best(save: Node, track_id: String, car_id: String, hz: float, samples := PackedFloat32Array()) -> void:
	var key: String = save.lap_key(track_id, car_id)
	var g := samples if samples.size() > 14 * 7 else saved_lap(key)
	var best: int = save.get_best_lap(key)
	if g.size() <= 14 * 7 or best < 0:
		done.emit.call_deferred(false, "Drive a clean lap here first")
		return
	upload(pack(g, hz, info_for(save, track_id, car_id, best)))


## The message a friend gets.
static func invite_text(save: Node, track_name: String, lap_ms: int, code: String) -> String:
	return "Beat my %s lap at %s in Apex Circuit! Open Quick race, pick Time trial and type ghost code %s" % [
		UIStyle.fmt_time(float(lap_ms) / 1000.0), track_name, code]


static func new_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in 6:
		s += CHARS[rng.randi() % CHARS.length()]
	return s


static func clean_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if CHARS.contains(ch):
			out += ch
	return out


func upload(payload: PackedByteArray) -> void:
	_job = "up"
	_code = new_code()
	_payload = payload
	_brokers = _broker_list()
	_next_broker()


func download(code: String) -> void:
	_job = "down"
	_code = clean_code(code)
	_brokers = _broker_list()
	_next_broker()


func _broker_list() -> Array:
	var net := get_node_or_null("/root/Net")
	return (net.public_brokers as Array).duplicate() if net != null else Array(load("res://scripts/net.gd").PUBLIC_BROKERS)


func _next_broker() -> void:
	if _link != null:
		_link.close()
		_link = null
	if _brokers.is_empty():
		done.emit(false, "Couldn't reach the servers. Check your connection and try again." if _job == "up" else "No ghost found with that code (or the servers can't be reached).")
		_job = ""
		return
	var url: String = _brokers.pop_front()
	_link = MqttLink.new()
	_link.ready.connect(_on_ready)
	_link.message.connect(_on_message)
	_link.closed.connect(func(_r): if _job != "": _next_broker())
	_t = 0.0
	_waited = 0.0
	if not _link.open(url, "apexg-" + new_code().to_lower()):
		_next_broker()


func _on_ready() -> void:
	if _job == "up":
		_link.publish(TOPIC + _code, _payload, true)
		_waited = 0.0
	else:
		_link.subscribe(TOPIC + _code)


func _on_message(topic: String, payload: PackedByteArray) -> void:
	if _job != "down" or topic != TOPIC + _code:
		return
	var ch := unpack(payload, 20.0)
	if ch.is_empty():
		return
	_job = ""
	_link.close()
	done.emit(true, ch)


func _process(delta: float) -> void:
	if _link == null or _job == "":
		return
	_link.poll(delta)
	_t += delta
	if _job == "up" and _link.is_ready():
		# (Give it a moment to go out before saying goodbye.)
		_waited += delta
		if _waited > 1.5:
			_job = ""
			_link.close()
			done.emit(true, _code)
			return
	if _t > TIMEOUT:
		_next_broker()
