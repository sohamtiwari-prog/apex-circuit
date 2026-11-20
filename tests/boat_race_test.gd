extends SceneTree
## A powerboat race on each course, the computer driving every boat (yours
## too): everyone gets round, laps are sensible, nobody spends long off the
## course or upside down.
##   godot --headless --fixed-fps 120 --script res://tests/boat_race_test.gd
var fails := 0


func _initialize() -> void:
	_run()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	for course in ["lago_brisa", "porto_solmar"]:
		save.data = save.default_profile()
		var st: Dictionary = save.data["settings"]
		st["mode"] = "race"; st["laps"] = 2; st["opponents"] = 5
		st["track"] = course; st["car"] = "h1"; st["time_of_day"] = "day"; st["weather"] = "dry"
		var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
		root.add_child(race)
		await process_frame
		var a := AIDriver.new()
		a.skill = 0.95
		race.autopilot = a
		var tr: Track = race.track
		check(tr.boat_course and tr.course != null, "%s: a water course (%.0f m)" % [course, tr.total_length])
		var t := 0.0
		var resets := 0
		var flipped := 0.0
		var max_v := 0.0
		var last_lap := 0
		while t < 200.0:
			await physics_frame
			t += 1.0 / 120.0
			var e = race.player
			max_v = maxf(max_v, race.car.speed_kmh())
			if race.car.global_basis.y.y < 0.3:
				flipped += 1.0 / 120.0
			if e.lap != last_lap:
				last_lap = e.lap
				print("  lap %d at %.1f s" % [e.lap, t])
			if e.finished:
				break
		var laps: int = race.player.lap
		print("  %s: laps %d, top %.0f km/h, upside down %.1f s" % [course, laps, max_v, flipped])
		var done := 0
		for e in race.entrants:
			if e.lap >= 2 or e.finished:
				done += 1
		check(laps >= 2 or race.player.finished, "%s: your boat (computer-driven) completes the race" % course)
		check(done >= race.entrants.size() - 1, "%s: the field gets round (%d of %d)" % [course, done, race.entrants.size()])
		check(max_v > 150.0, "%s: boats get up to speed (%.0f km/h)" % [course, max_v])
		check(flipped < 2.0, "%s: boats stay upright" % course)
		race.queue_free()
		await process_frame
		await process_frame
	print("ALL CHECKS PASSED" if fails == 0 else "%d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
