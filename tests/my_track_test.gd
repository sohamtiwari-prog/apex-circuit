extends SceneTree
## The track builder (scripts/my_tracks.gd): codes go there and back with
## the same id, bad layouts are caught, a freehand loop becomes a track, and
## every starting shape, with every scenery and the steepest hills, builds a
## circuit the AI can lap: on the road, never flipping, the land never above
## the road, a pit lane on the long straight. Then a 6-car race on one.
##   godot --headless --fixed-fps 120 --script res://tests/my_track_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _make(kind: String, style: String, hills: int, width := 1) -> Dictionary:
	var t := MyTracks.new_track(MyTracks.template(kind), "Test %s" % kind)
	t["style"] = style
	t["hills"] = hills
	t["width"] = width
	t["seed"] = 777 + hills
	t["id"] = MyTracks.make_id(t)
	MyTracks.extra[t["id"]] = t
	return t


func _codes() -> void:
	for kind in ["gp", "kidney", "oval", "club"]:
		var t := _make(kind, "forest", 2)
		var code := MyTracks.encode(t)
		var back := MyTracks.decode("Race my track!\n" + code + "\nsee you")
		_check(String(back.get("id", "")) == String(t["id"]) and String(back.get("name", "")) == String(t["name"]) and String(back.get("style", "")) == "forest",
			"%s: a code (%d letters) comes back as the same track" % [kind, code.length()])
		var link := MyTracks.decode("https://x/apex-circuit/?track=" + code.substr(MyTracks.PREFIX.length()))
		_check(String(link.get("id", "")) == String(t["id"]), "%s: so does a link" % kind)
		_check(MyTracks.problems(MyTracks.control(t), 1).is_empty(), "%s: nothing wrong with the shape" % kind)
	_check(MyTracks.decode("APX1-hello").is_empty() and MyTracks.decode("nonsense").is_empty(), "rubbish isn't a track")
	var t := _make("gp", "park", 1)
	var t2 := t.duplicate(true)
	t2["name"] = "Renamed"
	t2["style"] = "city"
	_check(MyTracks.make_id(t2) == String(t["id"]), "a new name or scenery keeps the id (and your laps)")
	t2["hills"] = 3
	_check(MyTracks.make_id(t2) != String(t["id"]), "different hills: a different track")
	# A figure of eight runs into itself; a tiny loop is too short; a spike is too tight.
	var eight := [Vector2(-400, -200), Vector2(0, 0), Vector2(400, 200), Vector2(500, 0), Vector2(400, -200), Vector2(0, 0.5), Vector2(-400, 200), Vector2(-500, 0)]
	var kinds := []
	for p in MyTracks.problems(eight, 1):
		kinds.append(p["kind"])
	_check(not kinds.is_empty() and kinds[0] == "cross", "a figure of eight is caught (%s)" % [kinds])
	var tiny := [Vector2(0, 0), Vector2(80, 0), Vector2(80, 60), Vector2(0, 60)]
	kinds = []
	for p in MyTracks.problems(tiny, 1):
		kinds.append(p["kind"])
	_check(kinds.has("short"), "a tiny loop is too short (%s)" % [kinds])
	var spike: Array = MyTracks.template("oval")
	spike.insert(4, Vector2(spike[3]) + Vector2(0, 260))
	spike.insert(5, Vector2(spike[3]) + Vector2(14, 0))
	kinds = []
	for p in MyTracks.problems(spike, 1):
		kinds.append(p["kind"])
	_check(not kinds.is_empty(), "a spike out of the oval is caught (%s)" % [kinds])
	# A wobbly hand-drawn circle, not quite closed: a track.
	var trace := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 330:
		var a := TAU * k / 340.0
		trace.append(Vector2(cos(a) * 560.0, sin(a) * 330.0) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)))
	var pts := MyTracks.from_trace(trace)
	var pr := MyTracks.problems(pts, 1)
	_check(pts.size() >= 8 and pr.is_empty(), "a hand-drawn loop becomes a track (%d points, %s)" % [pts.size(), pr])
	# Kept, found, removed.
	var keep := MyTracks.new_track(pts, "Kept")
	var id := MyTracks.store(keep)
	_check(MyTracks.ids().has(id) and Track.catalog_name(id) == "Kept" and Track.catalog_entry(id).get("custom", false), "saved: the menus know it")
	MyTracks.remove(id)
	_check(not MyTracks.ids().has(id), "deleted")


func _lap(t: Dictionary, car_id: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var track := Track.new()
	world.add_child(track)
	var t0 := Time.get_ticks_msec()
	track.build(String(t["id"]))
	var ms := Time.get_ticks_msec() - t0
	var tag := "%s/%s/hills %d" % [t["name"], t["style"], t["hills"]]
	# The land stays under the road and verges.
	var above := 0
	for i in range(0, track.size(), 3):
		var p: Vector3 = track.points[i]
		for lat in [-track.road_half - 2.0, 0.0, track.road_half + 2.0]:
			var q: Vector3 = p + track.rights[i] * lat
			if track.drawn_ground(q.x, q.z) > p.y - 0.05:
				above += 1
	_check(above == 0, "%s: built in %d ms, %.2f km, the land never comes up through the road (%d)" % [tag, ms, track.total_length / 1000.0, above])
	var car := RaceCar.new()
	car.setup(CarSpecs.get_spec(car_id))
	world.add_child(car)
	await physics_frame
	var n := track.size()
	car.global_transform = track.pose_at(n - 5, car.spawn_height())
	car.reset_controls()
	for i in range(60):
		await physics_frame
	var ai := AIDriver.new()
	var prev := n - 5
	var crossings := 0
	var frames := 0
	var max_lat := 0.0
	var flips := 0
	var stuck := 0
	for f in range(120 * 300):
		ai.update(car, track)
		await physics_frame
		var idx := track.nearest_index(car.global_position, prev)
		max_lat = maxf(max_lat, absf(track.lateral(car.global_position, idx)))
		if car.global_basis.y.y < 0.3:
			flips += 1
		stuck = stuck + 1 if car.speed_kmh() < 5.0 else 0
		if stuck > 600:
			break
		if prev > n * 0.9 and idx < n * 0.1:
			crossings += 1
			if crossings == 2:
				break
			frames = 0
			max_lat = 0.0
		frames += 1
		prev = idx
	var lap := frames / 120.0
	var limit := track.road_half + Track.KERB_W + 1.0
	_check(crossings == 2 and max_lat < limit and flips == 0,
		"%s: %s laps it in %d:%06.3f, on the road (%.1f m of %.1f), never flips" % [tag, car_id, int(lap) / 60, fmod(lap, 60.0), max_lat, limit])
	world.queue_free()
	await physics_frame


func _race(t: Dictionary) -> void:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = 1; st["opponents"] = 5; st["track"] = String(t["id"]); st["car"] = "gp26"
	st["qualifying"] = false; st["time_of_day"] = "auto"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = AIDriver.new()
	race.autopilot.skill = 0.9
	_check(race._tod == String(t["tod"]), "the race is at the track's own time of day (%s)" % race._tod)
	var t_end := 0.0
	while race.race_time < 240.0:
		await physics_frame
		if race.state == race.State.FINISHED or (race.player != null and race.player.finished):
			t_end = race.race_time
			break
	var done := 0
	for e in race.entrants:
		if e.lap >= 1 or e.finished:
			done += 1
	_check(t_end > 0.0 and done >= 5, "a 6-car race finishes (%d of %d round, %.0f s)" % [done, race.entrants.size(), t_end])
	race.queue_free()
	await physics_frame


func _run() -> void:
	await process_frame
	_codes()
	await _lap(_make("gp", "park", 3), "gp26")
	await _lap(_make("kidney", "forest", 3), "gp26")
	await _lap(_make("oval", "desert", 2, 2), "gp26")
	await _lap(_make("club", "city", 1, 0), "kart")
	var w := Node3D.new()
	root.add_child(w)
	var pit := Track.new()
	w.add_child(pit)
	pit.build(String(_make("gp", "park", 0)["id"]))
	_check(pit.has_pit_lane, "the GP shape gets a pit lane (%s)" % pit.pit_reason)
	w.queue_free()
	var rt := _make("kidney", "park", 2)
	rt["tod"] = "sunset"
	await _race(rt)
	print("")
	if failures.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILED" % failures.size())
		quit(1)
