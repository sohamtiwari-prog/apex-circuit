extends SceneTree
## Drivers and keeping progress: the first visit asks for a driver; an old
## save with progress is somebody's already; several drivers share a phone
## (each with their own progress and ghost laps, switched without losing
## any); a backup code carries everything to another phone and restores as
## a driver there; the menus' look setting; sharing a best lap as a ghost
## from outside the race needs a lap first.
##   godot --headless --script res://tests/driver_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _ghost_file(text: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://ghosts")
	var f := FileAccess.open("user://ghosts/test.bin", FileAccess.WRITE)
	f.store_var(text)
	f.close()


func _ghost_text() -> String:
	if not FileAccess.file_exists("user://ghosts/test.bin"):
		return ""
	var f := FileAccess.open("user://ghosts/test.bin", FileAccess.READ)
	return String(f.get_var())


func _run() -> void:
	await process_frame
	var save: Node = root.get_node("Save")
	# Start from nobody: clear any drivers left from before.
	var dir := DirAccess.open("user://save/drivers")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		for d in dir.get_directories():
			save._remove_dir("user://save/drivers/" + d)
	save.data = save.default_profile()
	save._migrate(save.data)
	_check(not bool(save.driver()["created"]), "a brand-new game has no driver yet (home asks for one)")
	_check(String(save.driver()["id"]).length() == 8, "every save gets a driver id")

	# An older save with progress belongs to someone already.
	var old: Dictionary = save.default_profile()
	old.erase("driver")
	old["settings"]["player_name"] = "Kabir"
	old["best_laps"] = {"styria|gp26": 99000}
	var prof: Dictionary = save.default_profile()
	save._merge(prof, old)
	save._migrate(prof)
	_check(bool(prof["driver"]["created"]) and String(prof["driver"]["name"]) == "Kabir", "an old save with progress: its driver is made from it (no questions)")

	# v8, Grand Prix only: an older save's road cars and its season in a
	# class that's gone.
	var v7: Dictionary = save.default_profile()
	v7["schema"] = 7
	v7["settings"]["car"] = "marauder"
	v7["settings"]["garage_car"] = "veloce"
	v7["settings"]["career_series"] = 4
	v7["championship"] = {"class": "muscle", "rounds": ["styria"], "round": 0}
	save._migrate(v7)
	_check(String(v7["settings"]["car"]) == "gp26" and String(v7["settings"]["garage_car"]) == "gp26", "an older save's road car is the GP car now")
	_check((v7["championship"] as Dictionary).is_empty() and int(v7["settings"]["career_series"]) == 0, "...its season in a class that's gone is over; the career is the Grand Prix series")

	# Create a driver.
	save.set_driver("  Soham ", 7, "#e01a1a", "000000")
	var d: Dictionary = save.driver()
	_check(String(d["name"]) == "Soham" and int(d["number"]) == 7 and String(d["helmet"]) == "e01a1a", "name, number and helmet are kept (tidied)")
	_check(String(save.get_setting("player_name")) == "Soham", "the name is the one friends see online too")
	save.data["rank_points"] = 900
	save.data["best_laps"] = {"silvermoor|gp26": 101000}
	_ghost_file("soham's lap")
	save.save()
	var soham := String(d["id"])

	# A second driver on the same phone.
	save.new_driver()
	_check(not bool(save.driver()["created"]) and String(save.driver()["id"]) != soham, "Add a driver: a fresh seat")
	_check(int(save.data["rank_points"]) == 0 and (save.data["best_laps"] as Dictionary).is_empty(), "the new driver starts with nothing")
	_check(_ghost_text() == "", "...and none of the first driver's ghost laps")
	save.set_driver("Aarav", 44, "38b6ff", "f2f2f2")
	save.data["rank_points"] = 150
	_ghost_file("aarav's lap")
	save.save()
	var aarav := String(save.driver()["id"])
	var list: Array = save.drivers()
	_check(list.size() == 2 and bool(list[0]["active"]) and String(list[0]["name"]) == "Aarav" and String(list[1]["name"]) == "Soham", "both drivers are listed, the one driving first")

	# Switch back: everything as it was.
	_check(save.switch_driver(soham), "switch to the first driver")
	_check(String(save.driver()["name"]) == "Soham" and int(save.data["rank_points"]) == 900, "their name and rank points are back")
	_check(int(save.data["best_laps"].get("silvermoor|gp26", -1)) == 101000, "their best laps are back")
	_check(_ghost_text() == "soham's lap", "their ghost laps are back")
	save._load()
	_check(String(save._load()["driver"]["name"]) == "Soham", "the switch is saved (it survives closing the game)")
	_check(save.switch_driver(aarav) and _ghost_text() == "aarav's lap" and int(save.data["rank_points"]) == 150, "and over to the second again")

	# Backup code: everything, as text, restored on another phone.
	save.switch_driver(soham)
	var code: String = save.backup_code()
	_check(code.begins_with("APEX1:") and code.length() < 20000, "a backup code is one line of text (%d characters)" % code.length())
	_check(not save.read_backup(code).is_empty(), "it reads back")
	_check(save.read_backup(code.substr(0, code.length() - 12)).is_empty(), "a cut-off code is refused, not half-restored")
	_check(save.restore_backup("hello") != "", "something that isn't a code: a message saying what to copy")
	# "Another phone": nobody on it.
	save.delete_driver(aarav)
	save.data = save.default_profile()
	save._migrate(save.data)
	save.save()
	_check(save.restore_backup(code) == "", "restore on a new phone")
	_check(String(save.driver()["name"]) == "Soham" and int(save.data["rank_points"]) == 900 and int(save.data["best_laps"].get("silvermoor|gp26", -1)) == 101000, "...and it's all there: name, rank, best laps")
	_check(bool(save.driver()["created"]), "...straight to the home screen (no Create your driver)")
	# Restoring yourself over yourself doesn't add a second you.
	var before: int = save.drivers().size()
	_check(save.restore_backup(code) == "" and save.drivers().size() == before, "restoring the same driver again replaces, never duplicates")

	# Look: light, dark, or the phone's.
	save.set_setting("look", "dark")
	UIStyle.use_menus()
	_check(UIStyle.theme == "garage_dark" and UIStyle.PAPER.is_equal_approx(Color.WHITE), "Dark: black boards, white type")
	save.set_setting("look", "light")
	UIStyle.use_menus()
	_check(UIStyle.theme == "garage" and UIStyle.PAPER.is_equal_approx(Color.BLACK), "Light: white boards, black type")
	save.set_setting("look", "auto")
	UIStyle.use_menus()
	_check(UIStyle.theme in ["garage", "garage_dark"], "Match phone: one or the other")
	UIStyle.use("board")
	_check(UIStyle.theme == "board" and UIStyle.TARMAC.is_equal_approx(Color.BLACK), "the race is pit boards whatever the menus' look")

	# Sharing a ghost from the Quick race screen needs a lap there first.
	var gs := GhostShare.new()
	root.add_child(gs)
	var got := []
	gs.done.connect(func(ok, res): got.append([ok, res]))
	gs.share_best(save, "styria", "gp26", 20.0)
	await process_frame
	await process_frame
	_check(got.size() == 1 and not bool(got[0][0]) and String(got[0][1]).contains("lap"), "no lap there yet: says so, sends nothing")
	gs.queue_free()

	# (Leave a clean profile behind: the next test in the same run reads it.)
	var dd := DirAccess.open("user://save/drivers")
	if dd != null:
		for f in dd.get_files():
			dd.remove(f)
		for x in dd.get_directories():
			save._remove_dir("user://save/drivers/" + x)
	save._remove_dir("user://ghosts")
	save.data = save.default_profile()
	save.save()
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
