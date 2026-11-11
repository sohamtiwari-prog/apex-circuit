extends SceneTree
## Time trials start with a run-up, and a friend's ghost keeps lapping:
## the car starts a few hundred metres before the line, the clock stays at
## zero until it crosses it at racing speed; the ghost waits on the line,
## sets off as you cross, and never disappears, however far behind it you
## are (past the end of its lap it goes round again). Races still start on
## the grid, from a standstill.
##   godot --headless --fixed-fps 120 --script res://tests/flying_start_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var f := FileAccess.open_compressed("res://data/ideal/silvermoor__gp26.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var v: Dictionary = f.get_var()
	save.challenge = {"track": "silvermoor", "car": "gp26", "samples": v["xf"], "lap_ms": int(float(v["time"]) * 1000.0), "name": "Test"}
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.9
	Engine.max_physics_steps_per_frame = 48
	_check(race.flying_start and race.out_lap, "a time trial starts with a run-up")
	var tr: Track = race.track
	var behind: float = tr.total_length - tr.cum[race.player.idx]
	_check(behind > 200.0 and behind < 620.0, "the car starts %.0f m before the line" % behind)
	var clock_ran := false
	var cross_kmh := -1.0
	var hidden := 0
	var frames := 0
	var ghost_lap: float = (race._ghost_play.size() / 7) / race.GHOST_HZ
	while race.player.lap < 1 or race.race_time - race.player.lap_start < 4.0:
		await physics_frame
		if race.race_time > 400.0:
			break
		if race.state != 1:
			continue
		if race.out_lap:
			if race.race_time - race.player.lap_start > 0.001:
				clock_ran = true
			continue
		if cross_kmh < 0.0:
			cross_kmh = race.car.linear_velocity.length() * 3.6
		frames += 1
		if race.ghost_car == null or not race.ghost_car.visible:
			if race.ghost_car == null or race.ghost_car.global_position.distance_to(race.car.global_position) > 2.6:
				hidden += 1
	_check(not clock_ran, "the lap clock stays at zero on the run-up")
	_check(cross_kmh > 150.0, "the line is crossed at racing speed (%.0f km/h)" % cross_kmh)
	_check(race.player.lap >= 1 and race.player.last_lap > 0.0, "the first timed lap counts (%.1f s)" % race.player.last_lap)
	_check(race.player.last_lap > ghost_lap + 5.0, "(this lap took longer than the ghost's, %.1f s, so it had to go round again)" % ghost_lap)
	_check(frames > 0 and hidden == 0, "the friend's ghost never vanished (%d of %d frames hidden)" % [hidden, frames])
	race.queue_free()
	await process_frame
	save.challenge = {}

	# A race: still the grid and a standstill.
	save.data = save.default_profile()
	save.data["settings"]["mode"] = "race"
	save.data["settings"]["track"] = "silvermoor"
	race = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	behind = race.track.total_length - race.track.cum[race.player.idx]
	_check(not race.flying_start and behind < 120.0, "a race still starts on the grid (%.0f m back)" % behind)
	race.queue_free()
	await process_frame

	save.data = save.default_profile()
	save.save()
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
