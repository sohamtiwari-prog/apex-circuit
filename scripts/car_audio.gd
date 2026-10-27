class_name CarAudio
extends Node3D
## Engine, tyre and wind sound for a RaceCar, generated in code.
##
## The engine is a looped waveform built from the harmonics of a base
## firing frequency; playback pitch follows the real firing frequency
## (rpm / 60 * cylinders / 2), so every gear change and rev sounds right.
## Two layers (on-throttle / off-throttle) crossfade with engine load.
##
## The GP car's V12 is pre-rendered (tools/engine_sound.py ->
## data/audio/gp_*.pcm) as engine-cycle tables at ten rpm points, on and off
## throttle, all phase-locked (cylinder 1 fires at the same point in every
## table). Your car generates its sound live: ONE engine phase advancing with
## the revs, morphing between the two nearest tables at that same phase, so
## it stays a single sharp voice (mixing two separately pitched loops smears).
## Plus an upshift crack and overrun crackle. Opponents loop one table.

const MIX_RATE := 22050
const LOOP_SECONDS := 0.4   # whole number of periods for every harmonic used

static var _cache := {}

var car: RaceCar
var _on: AudioStreamPlayer3D
var _off: AudioStreamPlayer3D
var _tyre: AudioStreamPlayer3D
var _wind: AudioStreamPlayer
var _base_hz := 200.0
var _cyl := 8
# Recorded V12 (GP car)
var _v12 := false
var _layers: Array = []          # opponents: [{rpm, on: player}]
var _map: Array[Vector2] = [Vector2(4000, 2300), Vector2(12000, 8600)]
var _gen: AudioStreamPlayer3D
var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _last := Vector3(-1, 0, 0)    # previous block's (sound rpm, load, loudness)
const GEN_RATE := 32000.0
var _crackle: AudioStreamPlayer3D
var _shift: AudioStreamPlayer3D
var _last_gear := 0
var _flutter := 0.0
static var _v12_data: Dictionary = {}


func attach(target: RaceCar, local_player: bool) -> void:
	car = target
	_base_hz = car.spec["engine_base_hz"]
	_cyl = car.spec["cylinders"]
	var tone: String = car.spec["engine_tone"]
	if tone == "v12gp" and _load_v12():
		_attach_v12(local_player)
		return
	_on = _player3d(_engine_wave(tone, true), -2.0)
	if not local_player:
		# Opponents: a single engine voice keeps a full grid cheap to mix.
		_on.max_distance = 220.0
		return
	_off = _player3d(_engine_wave(tone, false), -8.0)
	_tyre = _player3d(_noise_wave("tyre"), -80.0)
	if local_player:
		_wind = AudioStreamPlayer.new()
		_wind.stream = _noise_wave("wind")
		_wind.volume_db = -80.0
		add_child(_wind)
		_wind.play()


func _player3d(stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.unit_size = 12.0
	p.max_distance = 400.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	if car == null:
		return
	if _v12:
		_process_v12(delta)
		return
	var firing := car.rpm / 60.0 * _cyl * 0.5
	var pitch := clampf(firing / _base_hz, 0.2, 4.0)
	_on.pitch_scale = pitch
	var eng_load := car.engine_load
	var rev := clampf((car.rpm - float(car.spec["idle_rpm"])) / (float(car.spec["redline"]) - float(car.spec["idle_rpm"])), 0.0, 1.0)
	if _off == null:
		_on.volume_db = lerpf(-12.0, -2.0 + rev * 3.0, maxf(eng_load, 0.4))
		return
	_off.pitch_scale = pitch
	_on.volume_db = lerpf(-30.0, -1.0 + rev * 3.0, eng_load)
	_off.volume_db = lerpf(-6.0 + rev * 2.0, -30.0, eng_load)
	var slip := car.tyre_slip
	var spd := absf(car.forward_speed())
	_tyre.volume_db = -80.0 if slip < 0.05 or spd < 4.0 else lerpf(-24.0, -4.0, slip)
	_tyre.pitch_scale = 0.9 + slip * 0.25
	if _wind != null:
		_wind.volume_db = -80.0 if spd < 5.0 else lerpf(-34.0, -9.0, clampf(spd / 90.0, 0.0, 1.0))
		_wind.pitch_scale = 0.8 + clampf(spd / 90.0, 0.0, 1.0) * 0.5


# ------------------------------------------------------------ recorded V12

static func _pcm(name: String, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes("res://data/audio/" + name)
	if bytes.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = bytes.size() / 2
	return wav


## Loads the V12 recordings once per session.
static func _load_v12() -> bool:
	if not _v12_data.is_empty():
		return true
	var f := FileAccess.open("res://data/audio/gp.json", FileAccess.READ)
	if f == null:
		return false
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	var rate := int(meta["sample_rate"])
	var per_cycle := int(meta["per_cycle"])
	var rpms := PackedFloat32Array()
	var log_rpms := PackedFloat32Array()
	var on_t: Array[PackedFloat32Array] = []
	var off_t: Array[PackedFloat32Array] = []
	var on_wav: Array = []
	for l in meta["layers"]:
		var a := _table(String(l["on"]))
		var b := _table(String(l["off"]))
		if a.is_empty() or b.is_empty():
			return false
		rpms.append(float(l["rpm"]))
		log_rpms.append(log(float(l["rpm"])))
		on_t.append(a)
		off_t.append(b)
		# As a loop that plays at its own rpm natively (for opponents).
		var wav := _pcm(String(l["on"]), int(per_cycle * float(l["rpm"]) / 120.0), true)
		on_wav.append(wav)
	_v12_data = {"rpms": rpms, "log": log_rpms, "on": on_t, "off": off_t, "on_wav": on_wav,
		"per_cycle": per_cycle, "size": on_t[0].size(), "map": meta["rpm_map"],
		"crackle": _pcm(String(meta["crackle"]), rate, true), "shift": _pcm(String(meta["shift"]), rate, false)}
	return true


static func _table(name: String) -> PackedFloat32Array:
	var bytes := FileAccess.get_file_as_bytes("res://data/audio/" + name)
	var out := PackedFloat32Array()
	out.resize(bytes.size() / 2)
	for i in out.size():
		out[i] = bytes.decode_s16(i * 2) / 32768.0
	return out


func _attach_v12(local_player: bool) -> void:
	_v12 = true
	var m: Array = _v12_data["map"]
	_map = [Vector2(m[0][0], m[0][1]), Vector2(m[1][0], m[1][1])]
	var rpms: PackedFloat32Array = _v12_data["rpms"]
	if not local_player:
		# Opponents: one table from the upper-middle of the range, looped.
		var k := rpms.size() * 2 / 3
		_layers = [{"rpm": rpms[k], "on": _player3d(_v12_data["on_wav"][k], -80.0)}]
		_layers[0]["on"].max_distance = 240.0
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = GEN_RATE
	gen.buffer_length = 0.1
	_gen = _player3d(gen, 0.0)
	_pb = _gen.get_stream_playback()
	_crackle = _player3d(_v12_data["crackle"], -80.0)
	_shift = AudioStreamPlayer3D.new()
	_shift.stream = _v12_data["shift"]
	_shift.unit_size = 12.0
	_shift.max_distance = 400.0
	add_child(_shift)
	_tyre = _player3d(_noise_wave("tyre"), -80.0)
	_wind = AudioStreamPlayer.new()
	_wind.stream = _noise_wave("wind")
	_wind.volume_db = -80.0
	add_child(_wind)
	_wind.play()
	_last_gear = car.gear


## The next n samples of the engine, gliding from the previous block's revs,
## load and loudness to these (so nothing steps between frames).
func render(n: int, srpm: float, load: float, loud: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	if _last.x < 0.0:
		_last = Vector3(srpm, load, loud)
	var rpms: PackedFloat32Array = _v12_data["rpms"]
	var lr: PackedFloat32Array = _v12_data["log"]
	var on_t: Array = _v12_data["on"]
	var off_t: Array = _v12_data["off"]
	var per_cycle: float = _v12_data["per_cycle"]
	var size: int = _v12_data["size"]
	# Neighbouring tables and morph weight at the start and end of the block.
	var mid := (srpm + _last.x) * 0.5
	var k := 0
	while k < rpms.size() - 2 and rpms[k + 1] < mid:
		k += 1
	var w0 := clampf((log(_last.x) - lr[k]) / (lr[k + 1] - lr[k]), 0.0, 1.0)
	var w1 := clampf((log(srpm) - lr[k]) / (lr[k + 1] - lr[k]), 0.0, 1.0)
	var a_on: PackedFloat32Array = on_t[k]
	var b_on: PackedFloat32Array = on_t[k + 1]
	var a_off: PackedFloat32Array = off_t[k]
	var b_off: PackedFloat32Array = off_t[k + 1]
	var inv := 1.0 / maxf(n, 1)
	for i in n:
		var t := i * inv
		var r := lerpf(_last.x, srpm, t)
		_phase += r * per_cycle / (120.0 * GEN_RATE)
		if _phase >= size:
			_phase -= size
		var i0 := int(_phase)
		var fr := _phase - i0
		var i1 := i0 + 1 if i0 + 1 < size else 0
		var w := lerpf(w0, w1, t)
		var ld := lerpf(_last.y, load, t)
		var on := lerpf(lerpf(a_on[i0], a_on[i1], fr), lerpf(b_on[i0], b_on[i1], fr), w)
		var off := lerpf(lerpf(a_off[i0], a_off[i1], fr), lerpf(b_off[i0], b_off[i1], fr), w)
		out[i] = (on * ld + off * (1.0 - ld) * 0.6) * lerpf(_last.z, loud, t)
	_last = Vector3(srpm, load, loud)
	return out


## The car's revs as the V12's revs.
func sound_rpm() -> float:
	var t := (car.rpm - _map[0].x) / (_map[1].x - _map[0].x)
	return _map[0].y + t * (_map[1].y - _map[0].y)


func _process_v12(delta: float) -> void:
	var srpm := maxf(sound_rpm(), 600.0)
	var rev := clampf((car.rpm - float(car.spec["idle_rpm"])) / (float(car.spec["redline"]) - float(car.spec["idle_rpm"])), 0.0, 1.0)
	var load := clampf(car.engine_load, 0.0, 1.0)
	var loud := 0.55 + 0.45 * rev
	if _gen == null:
		var l: Dictionary = _layers[0]
		var p: AudioStreamPlayer3D = l["on"]
		p.pitch_scale = clampf(srpm / float(l["rpm"]), 0.25, 3.0)
		p.volume_db = linear_to_db(loud * lerpf(0.35, 1.0, maxf(load, 0.3))) - 1.0
		return
	var frames := _pb.get_frames_available()
	if frames > 0:
		var block := render(frames, srpm, load, loud)
		var buf := PackedVector2Array()
		buf.resize(frames)
		for i in frames:
			buf[i] = Vector2(block[i], block[i])
		_pb.push_buffer(buf)
	# Upshift crack as the next gear bites.
	if car.gear > _last_gear and _last_gear > 0 and car.throttle > 0.5:
		_shift.volume_db = -3.0
		_shift.pitch_scale = randf_range(0.92, 1.08)
		_shift.play()
	_last_gear = car.gear
	# Overrun crackle: lifted at high revs, flickering.
	var spd := absf(car.forward_speed())
	_flutter = lerpf(_flutter, randf(), 0.25)
	var crack := 0.0
	if car.throttle < 0.15 and spd > 10.0:
		crack = clampf((srpm - 4200.0) / 3000.0, 0.0, 1.0) * (0.5 + 0.5 * _flutter)
	_crackle.volume_db = linear_to_db(crack * 0.7) if crack > 0.01 else -80.0
	# Tyres and wind as before.
	var slip := car.tyre_slip
	_tyre.volume_db = -80.0 if slip < 0.05 or spd < 4.0 else lerpf(-24.0, -4.0, slip)
	_tyre.pitch_scale = 0.9 + slip * 0.25
	_wind.volume_db = -80.0 if spd < 5.0 else lerpf(-34.0, -9.0, clampf(spd / 90.0, 0.0, 1.0))
	_wind.pitch_scale = 0.8 + clampf(spd / 90.0, 0.0, 1.0) * 0.5


# ------------------------------------------------------------ synthesis

static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav


## One loop of an engine note. The loop length holds a whole number of
## base periods so it repeats seamlessly.
func _engine_wave(tone: String, on_load: bool) -> AudioStreamWAV:
	var key := "%s|%s|%s" % [tone, on_load, _base_hz]
	if _cache.has(key):
		return _cache[key]
	var n := int(MIX_RATE * LOOP_SECONDS)
	var f0 := _base_hz
	var harmonics: Array = []
	var gains: Array = []
	match tone:
		"gp":
			# High-revving turbo V6: strong fundamental, bright upper harmonics,
			# a half-order "turbo/MGU" whine.
			harmonics = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0]
			gains = [0.18, 1.0, 0.25, 0.55, 0.4, 0.28, 0.16, 0.12, 0.06]
		"v8flat":
			# Flat-plane V8: high-revving rasp, little rumble.
			harmonics = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
			gains = [0.2, 1.0, 0.3, 0.6, 0.35, 0.2]
		"flat6":
			# Boxer six: the signature mix of half orders.
			harmonics = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 6.0]
			gains = [0.3, 1.0, 0.5, 0.5, 0.25, 0.3, 0.15, 0.08]
		"v12":
			# V12: smooth and pure, almost no sub-harmonics.
			harmonics = [1.0, 2.0, 3.0, 4.0, 6.0]
			gains = [1.0, 0.7, 0.5, 0.3, 0.15]
		"w16":
			# W16: deep, heavy and turbocharged.
			harmonics = [0.25, 0.5, 1.0, 2.0, 3.0]
			gains = [0.4, 0.7, 1.0, 0.45, 0.2]
		_:
			# Cross-plane V8: rumbly sub-harmonics and a rich low end.
			harmonics = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
			gains = [0.35, 0.6, 0.3, 1.0, 0.35, 0.45, 0.22, 0.1]
	if not on_load:
		for k in range(gains.size()):
			gains[k] = gains[k] / (1.0 + harmonics[k] * 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var out := PackedFloat32Array()
	out.resize(n)
	var norm := 0.0
	for g in gains:
		norm += g
	var noise := 0.0
	var phases: Array = []
	for k in range(harmonics.size()):
		phases.append(rng.randf() * TAU)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var s := 0.0
		for k in range(harmonics.size()):
			s += gains[k] * sin(TAU * f0 * harmonics[k] * t + phases[k])
		# Combustion roughness: noise gated by the firing pulses.
		noise = noise * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3
		var pulse := 0.5 + 0.5 * sin(TAU * f0 * t)
		s += noise * pulse * (0.35 if on_load else 0.15) * norm
		out[i] = s / norm * 0.8
	var wav := _to_wav(out)
	_cache[key] = wav
	return wav


func _noise_wave(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var n := int(MIX_RATE * 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 if kind == "tyre" else 9
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var bp := 0.0
	for i in range(n):
		var w := rng.randf_range(-1.0, 1.0)
		if kind == "tyre":
			# Band-passed noise plus a tonal squeal around 1.1 kHz.
			lp += 0.35 * (w - lp)
			bp = lp - bp * 0.2
			var tone := sin(TAU * 1100.0 * i / MIX_RATE) * 0.35 + sin(TAU * 1650.0 * i / MIX_RATE) * 0.15
			out[i] = (bp * 0.6 + tone) * 0.7
		else:
			lp += 0.06 * (w - lp)
			out[i] = lp * 2.2
	# Fade the loop seam.
	for i in range(200):
		var f := float(i) / 200.0
		out[i] *= f
		out[n - 1 - i] *= f
	var wav := _to_wav(out)
	_cache[kind] = wav
	return wav
