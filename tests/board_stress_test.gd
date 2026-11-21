extends SceneTree
## Hammer the world leaderboard screen: open and close it while its answers
## are still on the way, scroll, press Race and close, leave the menu
## while it's loading. Any crash ends the run early (no "SURVIVED"); any
## "on a null instance" or "Lambda capture ... was freed" in the log is an
## answer that reached a closed screen. Needs the test server of
## tests/online_board_test.gd, slowed down (answers 0-0.6 s late):
##   godot --headless --script res://tests/board_stress_test.gd
func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	save.data["settings"]["online_id"] = "00691541-0cce-484c-a776-d730eb7700d3"
	var board: Node = root.get_node("Board")
	board.url = "http://127.0.0.1:3100"
	board.key = "sb_publishable_test"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	change_scene_to_file("res://scenes/menu.tscn")
	await _frames(5)
	for round in 60:
		var menu := current_scene
		var p := WorldBoardPanel.open(menu, "silvermoor", "gp26")
		var what := round % 6
		match what:
			0:
				p.queue_free()                         # closed at once, answers still coming
			1:
				await _frames(rng.randi_range(1, 30))
				if is_instance_valid(p):
					p.queue_free()
			2:
				await _frames(rng.randi_range(40, 90))  # loaded: scroll about
				if is_instance_valid(p) and is_instance_valid(p._scroll):
					for k in 20:
						p._scroll.scroll_vertical = rng.randi_range(0, 3000)
						await process_frame
				if is_instance_valid(p):
					p.queue_free()
			3:
				await _frames(rng.randi_range(40, 90))  # press Race, then close before the ghost comes
				if is_instance_valid(p):
					for b in p.find_children("*", "Button", true, false):
						if (b as Button).text == "Race" and not (b as Button).disabled:
							(b as Button).pressed.emit()
							break
					await _frames(rng.randi_range(0, 3))
					if is_instance_valid(p):
						p.queue_free()
			4:
				await _frames(rng.randi_range(1, 20))  # leave the menu while it loads
				change_scene_to_file("res://scenes/hub.tscn")
				await _frames(4)
				change_scene_to_file("res://scenes/menu.tscn")
				await _frames(4)
			5:
				# Tap the dark around it (closes) twice in a row.
				await _frames(rng.randi_range(1, 40))
				if is_instance_valid(p):
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = true
					ev.position = Vector2(5, 5)
					root.push_input(ev)
					root.push_input(ev)
		await _frames(rng.randi_range(0, 10))
		if current_scene == null or current_scene.scene_file_path.ends_with("race.tscn"):
			change_scene_to_file("res://scenes/menu.tscn")
			await _frames(6)
	await _frames(120)   # let every late answer land
	print("SURVIVED")
	quit(0)
