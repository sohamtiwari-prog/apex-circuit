extends SceneTree
## Replays: a 1-lap, 20-car race is recorded; then the replay is watched
## from the results: cars follow the recording exactly and smoothly, every
## camera keeps the car in shot and above ground, TV towers cover most of
## the lap, slow motion, seeking and highlights work, and closing the replay
## puts every car back exactly as it was. Also from the pause menu, and a
## restart clears the recording.
##   godot --headless --fixed-fps 120 --script res://tests/replay_test.gd [track]
# (No game class names here: this file compiles before the Save autoload exists.)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var track_id: String = args[0] if args.size() > 0 else "styria"
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"
	st["laps"] = 1
	st["opponents"] = 19
	st["track"] = track_id
	st["car"] = "gp26"
	save.save()

	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var frames := 0
	var max_tow := 0.0
	while not race._results_shown and frames < 120 * 200:
		await physics_frame
		frames += 1
		for e in race.entrants:
			max_tow = maxf(max_tow, e.car.tow)
	var rp = race.replay
	print("  race: %d physics frames; replay recorded %d frames (%.1f s)" % [frames, rp.count, rp.count / 20.0])
	for ev in rp.events:
		print("    %6.1f s  %-8s %s" % [ev["f"] / 20.0, ev["kind"], ev["text"]])
	_check(absi(rp.count - frames / 6) <= 3, "recorded 20 times a second (%d frames for %d ticks)" % [rp.count, frames])
	var kinds := {}
	for ev in rp.events:
		kinds[ev["kind"]] = true
	_check(kinds.has("start") and kinds.has("finish"), "the start and the flag are marked as highlights")
	_check(max_tow > 0.3, "cars catch a slipstream during the race (strongest %.2f)" % max_tow)

	# Snapshot, then watch from the results.
	var before: Array = []
	for e in race.entrants:
		before.append([e.car.global_transform, e.car.linear_velocity, e.car.freeze, e.car.controls_enabled])
	race.watch_replay(false)
	await physics_frame
	_check(rp.playing and race.entrants[0].car.freeze and not race.hud.visible and rp.cam.current, "replay takes over: cars frozen, HUD hidden, replay camera live")
	_check(rp.focus == race.entrants.find(race.player), "replay starts on your car")

	# Exactly on the recording at whole frames.
	var worst := 0.0
	for k in [40, 300, rp.count / 2, rp.count - 5]:
		rp.seek(float(k))
		for i in race.entrants.size():
			var a: PackedFloat32Array = rp.frames[i]
			var p := Vector3(a[k * 14], a[k * 14 + 1], a[k * 14 + 2])
			worst = maxf(worst, p.distance_to(race.entrants[i].car.global_position))
	_check(worst < 0.01, "cars sit exactly on the recording (%.4f m off)" % worst)

	# Smooth at 1x from the start: per-tick movement matches the speed.
	rp.seek(float(rp.race_start_frame()))
	rp.set_paused(false)
	var focus_car: RaceCar = race.entrants[rp.focus].car
	var prev := focus_car.global_position
	var jerk := 0.0
	var moved := 0.0
	var shots := {}
	for f in 2400:
		await physics_frame
		var p := focus_car.global_position
		var step := p.distance_to(prev)
		var expect := absf(focus_car.forward_speed()) / 120.0
		jerk = maxf(jerk, absf(step - expect))
		moved += step
		prev = p
		shots[rp.cam.shot] = true
	print("  20 s of replay: car moved %.0f m; worst per-tick mismatch %.3f m; Auto showed %s" % [moved, jerk, ", ".join(shots.keys())])
	_check(moved > 150.0 and jerk < 0.08, "playback is smooth (no jumps between samples)")
	_check(shots.size() >= 3, "the auto director cuts between cameras (%d kinds in 20 s)" % shots.size())

	# Every camera: car in shot, camera above the ground.
	var track = race.track
	var cam = rp.cam
	for m in range(1, cam.modes.size()):
		cam.mode = m
		cam.cut()
		var in_shot := 0
		var low := 0
		var n := 0
		for f in 150:
			await physics_frame
			n += 1
			var g: float = track.ground_height(cam.global_position.x, cam.global_position.z)
			if not is_nan(track.sea_level):
				g = maxf(g, track.sea_level)
			if cam.global_position.y < g + 0.25:
				low += 1
			if cam.is_position_in_frustum(focus_car.global_position + Vector3.UP * 0.5) or cam.modes[m] in ["Cockpit", "T-cam", "Nose", "Rear-facing"]:
				in_shot += 1
		print("    %-12s car in shot %3d%%, below ground %d frames" % [cam.modes[m], 100 * in_shot / n, low])
		_check(in_shot >= n * 0.95 and low == 0, "%s camera keeps the car in shot, above ground" % cam.modes[m])

	# TV towers cover most of the lap.
	cam.mode = 1
	cam.cut()
	rp.seek(float(rp.race_start_frame()) + 200.0)
	var towers := 0
	var used := {}
	var tv_n := 0
	rp.speed_i = 3                    # 2x, to cover more of the lap
	for f in 2400:
		await physics_frame
		tv_n += 1
		if cam._tower >= 0:
			towers += 1
			used[cam._tower] = true
	rp.speed_i = 0
	print("  TV: %d towers on this track, %d used; a tower had the car %d%% of the time" % [cam._towers.size(), used.size(), 100 * towers / tv_n])
	_check(towers >= tv_n * 0.8 and used.size() >= 6, "TV cameras cover most of the lap")

	# Slow motion and pause.
	rp.cycle_speed()
	rp.cycle_speed()
	var t0: float = rp.t
	for f in 120:
		await physics_frame
	_check(absf(rp.t - t0 - 5.0) < 0.6 and is_equal_approx(AudioServer.playback_speed_scale, 0.25), "quarter speed: 1 s of real time plays 0.25 s (and the sound slows too)")
	rp.set_paused(true)
	t0 = rp.t
	for f in 30:
		await physics_frame
	_check(rp.t == t0 and AudioServer.is_bus_mute(0), "pause holds the frame (and mutes)")
	rp.set_paused(false)
	rp.speed_i = 0

	# Highlights jump to just before the next event, watching its car.
	rp.seek(0.0)
	rp.next_highlight()
	var ev: Dictionary = {}
	for e in rp.events:
		if int(e["f"]) > int(20 * 3.5):
			ev = e
			break
	_check(not ev.is_empty() and absf(rp.t - (float(ev["f"]) - 60.0)) < 1.0 and (int(ev["car"]) < 0 or rp.focus == int(ev["car"])), "Highlights jumps 3 s before the next moment, on the car involved")

	# Close: everything back as it was.
	rp.stop()
	await physics_frame
	var off := 0.0
	var same := true
	for i in race.entrants.size():
		var c: RaceCar = race.entrants[i].car
		off = maxf(off, c.global_position.distance_to((before[i][0] as Transform3D).origin))
		same = same and c.freeze == before[i][2] and c.controls_enabled == before[i][3]
	_check(off < 1.5 and same, "closing the replay puts every car back (%.2f m after one tick)" % off)
	_check(race.hud.visible and race.cam.current and is_equal_approx(AudioServer.playback_speed_scale, 1.0) and not AudioServer.is_bus_mute(0), "HUD, camera and sound are back to normal")
	var pos0: Array = []
	for e in race.entrants:
		pos0.append(e.car.global_position)
	for f in 240:
		await physics_frame
	var running := 0
	for i in race.entrants.size():
		if race.entrants[i].car.global_position.distance_to(pos0[i]) > 5.0:
			running += 1
	_check(running >= 10, "the cool-down carries on after the replay (%d cars moving)" % running)

	# From the pause menu: last 30 s, then back to the pause menu.
	race.hud.set_paused(true)
	race.watch_replay(true)
	await physics_frame
	var during: bool = paused
	var from_t: float = rp.t
	rp.stop()
	await process_frame
	_check(not during and rp.count - from_t <= 20 * 30 + 4 and paused and race.hud.pause_panel.visible, "pause menu replay: the last 30 s, then back to the pause menu")
	race.hud.set_paused(false)

	# A restart clears the recording.
	race._restart()
	_check(rp.count == 0 and rp.events.is_empty(), "restarting the race clears the replay")

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECK(S) FAILED" % failures.size())
		quit(1)
