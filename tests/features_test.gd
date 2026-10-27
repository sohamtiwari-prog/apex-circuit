extends SceneTree
## Sectors, DRS, ghost car: drive (AI on the player's car) and check.
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
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = "styria"; st["car"] = "gp26"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	print("  DRS zones: %d" % race.track.drs_zones.size())
	_check(race.track.drs_zones.size() >= 2, "the long straights get DRS zones")
	while race.state == 0:
		await physics_frame
	var opened := 0
	var max_v_open := 0.0
	var frames := 0
	var start_lap: int = race.player.lap
	while race.player.lap < start_lap + 2 and frames < 120 * 220:
		await physics_frame
		frames += 1
		if race.car.drs_open:
			opened += 1
			max_v_open = maxf(max_v_open, race.car.speed_kmh())
	_check(opened > 120, "DRS opens on the straights in a time trial (%.1f s open)" % (opened / 120.0))
	var key: String = race.lap_key
	var secs: Array = save.data["best_sectors"].get(key, [])
	_check(secs.size() == 3 and int(secs[0]) > 0 and int(secs[1]) > 0 and int(secs[2]) > 0, "all three sector times recorded %s" % str(secs))
	var total := 0
	for x in secs:
		total += int(x)
	var best: int = save.get_best_lap(key)
	_check(absi(total - best) < 1500, "sectors add up to about a lap (%d vs %d ms)" % [total, best])
	# Minisectors: 24 a lap, all recorded, adding up to the sectors.
	var minis: Array = save.data["best_minis"].get(key, [])
	var set_count := 0
	for x in minis:
		if int(x) > 0:
			set_count += 1
	_check(minis.size() == race.MINIS and set_count == race.MINIS, "all %d minisector times recorded (%d set)" % [race.MINIS, set_count])
	for k in 3:
		var part := 0
		for m in range(k * 8, k * 8 + 8):
			part += int(minis[m]) if m < minis.size() else 0
		_check(part <= int(secs[k]) + 20 and part > int(secs[k]) * 0.9, "sector %d's minisectors add up to it (%d vs %d ms)" % [k + 1, part, int(secs[k])])
	var ideal: float = save.ideal_lap(key, race.MINIS)
	_check(ideal > 0.0 and ideal * 1000.0 <= best + 20 and ideal * 1000.0 > best * 0.95, "ideal lap %.3f is at most the best lap %.3f" % [ideal, best / 1000.0])
	var coloured := 0
	var kinds := {}
	for c in race.hud._mini_cols:
		if c != race.hud.MINI_IDLE:
			coloured += 1
			kinds[c.to_html()] = true
	_check(coloured == race.MINIS, "every minisector of the lap is coloured on the HUD (%d)" % coloured)
	_check(race.hud.minimap._minis.size() == race.MINIS, "and painted on the track map (%d)" % race.hud.minimap._minis.size())
	_check(race.hud._ideal_val.get_parent().visible, "the Ideal lap row shows in a time trial")
	print("  minisector colours on lap 2: %d kinds" % kinds.size())
	if race.has_method("ghost_ready"):
		_check(race.ghost_ready(), "a ghost of the best lap is saved and driving")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
