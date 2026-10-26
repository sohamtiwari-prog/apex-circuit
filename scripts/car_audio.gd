class_name CarAudio
extends Node3D
## Engine, tyre and wind sound for a RaceCar, generated in code.
##
## The engine is a looped waveform built from the harmonics of a base
## firing frequency; playback pitch follows the real firing frequency
## (rpm / 60 * cylinders / 2), so every gear change and rev sounds right.
## Two layers (on-throttle / off-throttle) crossfade with engine load.

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


func attach(target: RaceCar, local_player: bool) -> void:
	car = target
	_base_hz = car.spec["engine_base_hz"]
	_cyl = car.spec["cylinders"]
	var tone: String = car.spec["engine_tone"]
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
