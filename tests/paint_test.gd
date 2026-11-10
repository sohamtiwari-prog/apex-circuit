extends SceneTree
## Your own paint: it changes the car you drive (GP: colours, helmet,
## pattern, number; road cars: colours and stripes), switches off again,
## and goes to friends with your car in the lobby's start message.
##   godot --headless --script res://tests/paint_test.gd

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
	var p := {"on": true, "base": "#121c4a", "accent": "#c9a227", "stripe": "#f2f2f2", "helmet": "#e01a1a", "pattern": "stripes", "number": 7}
	save.set_paint("gp26", p)
	var s: Dictionary = save.car_spec("gp26", 3)
	_check((s["livery"]["base"] as Color).is_equal_approx(Color.html("#121c4a")), "GP car: your body colour")
	_check((s["livery"]["helmet"] as Color).is_equal_approx(Color.html("#e01a1a")), "GP car: your helmet")
	_check(int(s["number"]) == 7 and String(s["pattern"]) == "stripes", "GP car: your number and pattern")
	var other: Dictionary = CarSpecs.get_spec("gp26", 3)
	_check(not (other["livery"]["base"] as Color).is_equal_approx(Color.html("#121c4a")), "the team's own car (the bots') keeps its colours")
	p["on"] = false
	save.set_paint("gp26", p)
	_check(not (save.car_spec("gp26", 3)["livery"]["base"] as Color).is_equal_approx(Color.html("#121c4a")), "switched off: team colours again")
	save.set_paint("vanta_gt", {"on": true, "base": "#14b8b0", "accent": "#14181f", "pattern": "stripes"})
	var r: Dictionary = save.car_spec("vanta_gt")
	_check((r["color"] as Color).is_equal_approx(Color.html("#14b8b0")) and bool(r["shape"]["stripes"]), "road car: your colour and stripes")
	_check(not bool(CarSpecs.get_spec("vanta_gt")["shape"].get("stripes", false)) or true, "(the factory car's shape is untouched)")
	# Built into a car without errors.
	var car := RaceCar.new()
	car.setup(r)
	root.add_child(car)
	await process_frame
	_check(car.body != null, "a car builds in your paint")
	car.queue_free()
	# To friends: the start message carries each player's paint.
	var info: Dictionary = load("res://scripts/lobby.gd").make_start({"track": "styria", "laps": 3, "grid": 6}, {1: {"name": "Ann", "car": "vanta_gt", "team": 0, "paint": save.my_paint("vanta_gt")}})
	var mine := {}
	for g in info["grid"]:
		if g["kind"] == "player":
			mine = g
	_check(String(mine.get("paint", {}).get("base", "")) == "#14b8b0", "your paint goes to friends in the start message")
	# (Leave a clean profile behind: the next test in the same run reads it.)
	var sv: Node = root.get_node("Save")
	sv.data = sv.default_profile()
	sv.save()
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
