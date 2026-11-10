extends SceneTree
## Car setup: each setting does what it says (wing: downforce and drag;
## gearing; brake balance; anti-roll bars; tyre pressure and wear), and the
## car stays drivable at the extremes: a clean flying lap with each.
##   godot --headless --fixed-fps 120 --script res://tests/setup_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _lap(setup: Dictionary, car_id: String) -> Array:
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.set_setup(car_id, setup)
	var st: Dictionary = save.data["settings"]
	st["mode"] = "time_trial"; st["track"] = "styria"; st["car"] = car_id; st["laps"] = 3
	save.pending_event = {}
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var resets0: int = race.reset_log.size()
	var t := 0
	while race.player.lap < 2 and t < 120 * 260:
		await physics_frame
		t += 1
	var lap: float = race.player.last_lap
	var resets: int = race.reset_log.size() - resets0
	race.queue_free()
	await process_frame
	return [lap, resets]


func _run() -> void:
	await process_frame
	Engine.max_physics_steps_per_frame = 48
	var stock := CarSpecs.get_spec("gp26")
	var hi := CarSpecs.apply_setup(CarSpecs.get_spec("gp26"), {"wing": 5, "gearing": -3, "bias": 64, "balance": 3, "pressure": -3})
	_check(float(hi["downforce"]) > float(stock["downforce"]) and float(hi["drag"]) > float(stock["drag"]), "more wing: more downforce and drag")
	_check(float(hi["gears"][0]) > float(stock["gears"][0]), "shorter gearing: higher ratios")
	_check(is_equal_approx(float(hi["brake_bias"]), 0.64), "brake balance 64 %% front (%.2f)" % float(hi["brake_bias"]))
	_check(float(hi["arb_front"]) > float(stock["arb_front"]) and float(hi["arb_rear"]) < float(stock["arb_rear"]), "handling up: stiffer front bar, softer rear")
	_check(float(hi["mu_front"]) > float(stock["mu_front"]) and float(hi["wear_mul"]) > 1.0, "lower pressure: more grip, more wear")
	var Setup = load("res://scripts/setup_screen.gd")
	var lo := CarSpecs.apply_setup(CarSpecs.get_spec("gp26"), {"wing": -5, "gearing": 3})
	_check(Setup.top_speed(lo) > Setup.top_speed(stock) and Setup.top_speed(hi) < Setup.top_speed(stock), "top speed: up with less wing, down with more (%d / %d / %d km/h)" % [int(Setup.top_speed(lo)), int(Setup.top_speed(stock)), int(Setup.top_speed(hi))])
	# Drivable at the extremes.
	var base: Array = await _lap({}, "gp26")
	print("    stock: lap %.2f s, %d resets" % [base[0], base[1]])
	for s in [{"wing": 5, "gearing": -3, "bias": 50, "balance": -3, "pressure": -3},
			{"wing": -5, "gearing": 3, "bias": 70, "balance": 3, "pressure": 3}]:
		var r: Array = await _lap(s, "gp26")
		print("    %s: lap %.2f s, %d resets" % [str(s), r[0], r[1]])
		_check(r[1] == 0 and r[0] > 0.0 and absf(r[0] - base[0]) / base[0] < 0.08, "extreme setup still drives a clean lap (%.2f s vs %.2f s)" % [r[0], base[0]])
	var road: Array = await _lap({"wing": -5, "balance": -3, "pressure": -3, "bias": 50}, "stuttgart9")
	print("    stuttgart9, loosest: lap %.2f s, %d resets" % [road[0], road[1]])
	_check(road[1] == 0 and road[0] > 0.0, "a twitchy road car at its loosest still drives a clean lap")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
