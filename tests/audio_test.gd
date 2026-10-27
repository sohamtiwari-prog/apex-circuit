extends SceneTree
## The GP car's V12: tables load, your car generates one phase-locked voice
## whose pitch tracks the revs exactly, blocks join without clicks, it is
## cheap enough for a phone, lifting swaps to the overrun sound, upshifts
## crack, the overrun crackles, and opponents use one cheap loop each.
##   godot --headless --script res://tests/audio_test.gd [-- out.wav]
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _corr(x: PackedFloat32Array, lag: int) -> float:
	var s := 0.0
	var a := 0.0
	var b := 0.0
	for i in range(0, x.size() - lag):
		s += x[i] * x[i + lag]
		a += x[i] * x[i]
		b += x[i + lag] * x[i + lag]
	return s / sqrt(a * b + 1e-12)
func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["track"] = "silvermoor"; st["car"] = "gp26"; st["laps"] = 1; st["opponents"] = 5
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	var a = race.audio
	var tables: int = a._v12_data.get("rpms", PackedFloat32Array()).size()
	_check(a._v12 and a._gen != null and tables >= 8, "your GP car generates the V12 live from %d phase-locked tables" % tables)
	var opp_ok := true
	for c in race.find_children("*", "CarAudio", true, false):
		if c != a and (not c._v12 or c._layers.size() != 1 or c._gen != null):
			opp_ok = false
	_check(opp_ok, "opponents each loop one table")

	# Pitch: the sound repeats every engine cycle (12 firings), at any revs.
	var pitch_ok := true
	var report := ""
	for srpm in [2600.0, 4700.0, 8300.0]:
		a._last = Vector3(-1, 0, 0)
		var x: PackedFloat32Array = a.render(16000, srpm, 1.0, 1.0)
		var cyc := int(round(32000.0 * 120.0 / srpm))
		var on_pitch := _corr(x, cyc)
		var off_pitch := _corr(x, int(round(cyc * 1.06)))
		report += " %.0f rpm: %.2f vs %.2f;" % [srpm, on_pitch, off_pitch]
		if on_pitch < 0.5 or on_pitch < off_pitch + 0.2:
			pitch_ok = false
	print("    repeats every cycle (correlation at the cycle vs 6% off):", report)
	_check(pitch_ok, "pitch follows the revs exactly")

	# Blocks join smoothly (the game fills the buffer a frame at a time).
	a._last = Vector3(-1, 0, 0)
	var b1: PackedFloat32Array = a.render(600, 5000.0, 1.0, 1.0)
	var b2: PackedFloat32Array = a.render(600, 5050.0, 1.0, 1.0)
	var typical := 0.0
	for i in range(1, b1.size()):
		typical = maxf(typical, absf(b1[i] - b1[i - 1]))
	var jump := absf(b2[0] - b1[b1.size() - 1])
	_check(jump <= typical * 1.05, "no click between blocks (jump %.3f, biggest step inside a block %.3f)" % [jump, typical])

	# Cost: one second of audio.
	# Best of three, so a busy test machine doesn't fail it; the limit still
	# catches a real slowdown (alone it's ~35 ms here).
	var ms := INF
	for rep in 3:
		var t0 := Time.get_ticks_usec()
		a.render(32000, 6000.0, 0.8, 1.0)
		ms = minf(ms, (Time.get_ticks_usec() - t0) / 1000.0)
	print("    one second of engine sound took %.1f ms to generate" % ms)
	_check(ms < 200.0, "cheap enough for a phone (%.0f ms per second here)" % ms)

	# Optional: save a run of the game's own output for listening.
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		a._last = Vector3(-1, 0, 0)
		var all := PackedFloat32Array()
		for step in 64:
			var r := 2400.0 + step * 95.0
			all.append_array(a.render(2000, r, 1.0, 0.6 + step * 0.006))
		var bytes := PackedByteArray()
		bytes.resize(all.size() * 2)
		var peak := 0.0
		for v in all:
			peak = maxf(peak, absf(v))
		for i in all.size():
			bytes.encode_s16(i * 2, int(all[i] / maxf(peak, 1e-6) * 30000.0))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 32000
		wav.data = bytes
		wav.save_to_wav(args[0])
		print("    saved ", args[0])

	a._last = Vector3(-1, 0, 0)
	while race.state == 0:
		await physics_frame
	var frames := 0
	var shifts := 0
	var crackle_frames := 0
	var last_gear: int = race.car.gear
	while frames < 120 * 25:
		await physics_frame
		frames += 1
		if a._crackle.volume_db > -60.0:
			crackle_frames += 1
		if race.car.gear > last_gear and a._shift.playing:
			shifts += 1
		last_gear = race.car.gear
	print("    %d upshift cracks heard; crackle on %d frames" % [shifts, crackle_frames])
	_check(shifts >= 2, "upshifts crack (%d)" % shifts)
	_check(crackle_frames > 0, "the exhaust crackles on the overrun")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
