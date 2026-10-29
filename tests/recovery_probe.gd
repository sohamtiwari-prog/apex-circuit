extends SceneTree
## A full-grid race with you (on autopilot) and bots pitting; prints every
## time a car had to be put back on the track, and why.
##   godot --headless --fixed-fps 120 --script res://tests/recovery_probe.gd -- <track> [laps]
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = int(args[1]) if args.size() > 1 else 2; st["opponents"] = 19; st["track"] = args[0] if args.size() > 0 else "styria"
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var boxed := false
	var t := 0
	var last_hit := {}
	race.car_contact.connect(func(a, b, v):
		last_hit[a] = [race.race_time, v, b]
		last_hit[b] = [race.race_time, v, a])
	var trail := {}            # car -> ring of [time, lat, speed, steer, surface]
	var shown := 0
	while not race._results_shown and t < 120 * 600:
		await physics_frame
		t += 1
		if t % 12 == 0:
			for e in race.entrants:
				var tr: Array = trail.get(e.car, [])
				tr.append("t%.1f lat %+.1f %.0f km/h steer %+.2f grass %d lane %+.1f cap %.0f" % [race.race_time, race.track.lateral(e.car.global_position, e.idx), e.car.speed_kmh(), e.car.steer_input, e.car.wheels_on_grass, e.ai.lane_offset if e.ai != null else 0.0, e.ai.speed_cap if e.ai != null else 0.0])
				if tr.size() > 90:
					tr.pop_front()
				trail[e.car] = tr
		while shown < race.reset_log.size():
			print("RESET ", race.reset_log[shown])
			for e in race.entrants:
				if race.reset_log[shown].begins_with(e.name):
					var h = last_hit.get(e.car, null)
					if h != null:
						var other = null
						for o in race.entrants:
							if o.car == h[2]:
								other = o
						print("    last contact %.1f s before, closing %.1f m/s, with %s" % [race.race_time - h[0], h[1], other.name if other != null else "?"])
					for line in trail.get(e.car, []):
						print("      ", line)
			shown += 1
		if not boxed and race.race_time > 6.0:
			race.weekend.set_box("hard")
			boxed = true
	print("RESULT %s: %d recoveries" % [st["track"], race.recoveries])
	quit(0)
