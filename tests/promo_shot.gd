extends SceneTree
## The results of the career race that promotes you: karting to F4.
##   godot --resolution 1600x720 --script res://tests/promo_shot.gd -- <out_dir>
func _initialize() -> void:
	_run()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.data["career"] = {"kart_2": 3, "kart_3": 3, "kart_4": 3}         # 9: one short
	var ev: Dictionary = Career.event(0, 0)
	ev["car"] = "kart"
	ev["opponents"] = 11
	ev["laps"] = 1
	ev["return_to"] = "res://scenes/career.tscn"
	save.pending_event = ev
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	for i in range(120 * 4):
		await physics_frame
	for e in race.entrants:
		e.best_lap = 52.0 + randf() * 2.0
	# You won it.
	race.player.progress = 99999.0
	race.player.finished = true
	race._show_results()
	for i in 90:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/promo.png")
	print("saved ", out + "/promo.png", "  promoted: ", race.last_reward.get("promoted", ""), "  stars now ", Career.series_stars(save, 0))
	quit(0)
