extends SceneTree
## Two-phone multiplayer race, run as two processes (real time):
##   godot --headless --script res://tests/mp_test.gd -- host lan  [laps]
##   godot --headless --script res://tests/mp_test.gd -- client lan
## (or "online ws://127.0.0.1:8090"). Both drive with the AI and report what
## they saw; tests/run_mp_test.sh runs the pair and checks both pass.
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _wait(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if cond.call():
			return true
		await process_frame
	return cond.call()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var role: String = args[0]
	var kind: String = args[1]
	var url: String = args[2] if kind != "lan" else ""
	Engine.max_fps = 60              # like a phone (and so the two processes share the CPU)
	await process_frame
	var save: Node = root.get_node("Save")
	var net: Node = root.get_node("Net")
	save.data = save.default_profile()
	save.data["settings"]["car"] = "gp26"
	var lobby: Node = (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await process_frame
	lobby._name_edit.text = "Host" if role == "host" else "Friend"
	if kind == "public":
		net.public_brokers = [url, url, url]
		lobby._server_edit.text = ""         # the free servers (here: a local stand-in)
	var chats: Array = []
	net.chat_received.connect(func(f, t): chats.append([f, t]))
	if role == "host":
		if kind == "lan":
			net.host_lan("Host")
			lobby._enter_as_host()
		elif kind == "public":
			lobby._create_online()
			await _wait(func(): return net.my_id == 1, 20.0)
			FileAccess.open("user://mp_code.txt", FileAccess.WRITE).store_string(net.room_code)
		else:
			net.host_online(url, "Host")
			await _wait(func(): return net.room_code != "", 20.0)
			FileAccess.open("user://mp_code.txt", FileAccess.WRITE).store_string(net.room_code)
		_check(await _wait(func(): return lobby._players().size() == 2, 40.0), "host: the friend appears in the lobby")
		_check(await _wait(func(): return chats.size() > 0, 10.0), "host: receives the friend's quick chat (%s)" % str(chats))
		await _wait(func(): return false, 3.0)
		lobby._settings()["laps"] = 1
		lobby._settings()["track"] = "styria"
		lobby._settings()["grid"] = 20
		lobby._broadcast_lobby()
		await _wait(func(): return false, 1.0)
		lobby._start_race()
	else:
		if kind == "lan":
			lobby._join_ip("127.0.0.1")
		else:
			var code := [""]            # (lambdas capture locals by value: use a holder)
			await _wait(func():
				if FileAccess.file_exists("user://mp_code.txt"):
					code[0] = FileAccess.get_file_as_string("user://mp_code.txt")
				return String(code[0]).length() == 4, 30.0)
			if kind == "public":
				lobby._join_code(code[0])
			else:
				net.join_online(url, code[0])
		_check(await _wait(func(): return net.my_id > 1, 30.0), "client: joined the host")
		_check(await _wait(func(): return lobby._players().size() == 2, 10.0), "client: sees both players in the lobby")
		net.chat(1)
		_check(await _wait(func(): return chats.size() > 0, 5.0), "client: quick chat comes back from the host (%s)" % str(chats))
		_check(await _wait(func(): return int(lobby._players().get(net.my_id, {}).get("ping", -1)) >= 0, 8.0), "client: its ping shows in the lobby (%d ms)" % int(lobby._players().get(net.my_id, {}).get("ping", -1)))
	_check(await _wait(func(): return current_scene != null and current_scene.name == "Race", 30.0), "%s: the race loads" % role)
	var race: Node = current_scene
	await process_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.96 if role == "host" else 0.95
	_check(race.entrants.size() == 20, "%s: 20 cars on the grid (%d)" % [role, race.entrants.size()])
	var remote := 0
	var bots := 0
	for e in race.entrants:
		if e.remote:
			remote += 1
		if e.ai != null:
			bots += 1
	if role == "host":
		_check(remote == 1 and bots == 18, "host: runs 18 bots, the friend's car is remote (%d bots, %d remote)" % [bots, remote])
	else:
		_check(remote == 19 and bots == 0, "client: every other car comes from the host (%d remote)" % remote)
	_check(await _wait(func(): return race.state == 1, 40.0), "%s: lights go out" % role)
	var go_time := Time.get_ticks_msec()
	# The other human's car must move on this phone.
	var other = null
	for e in race.entrants:
		if e.net_id > 0 and not e.is_player:
			other = e
	var start_pos: Vector3 = other.car.global_position
	var max_jump := 0.0
	var path := 0.0
	var big := 0
	var big_when := {}
	var ticks := 0
	var last_sim: float = race.net._sim
	var last_pos := start_pos
	var frames := 0
	while not race._results_shown and Time.get_ticks_msec() - go_time < 200000:
		await process_frame          # what you see: once per drawn frame
		frames += 1
		var p: Vector3 = other.car.global_position
		var step := p.distance_to(last_pos)
		# How far from where its own speed says it should be this tick.
		# Game clock (what your own car and the camera move by).
		var now_t: float = race.net._sim + Engine.get_physics_interpolation_fraction() / 120.0
		var dt: float = now_t - last_sim
		last_sim = now_t
		var expect: float = (other.car.remote_vel.length() if other.car.remote else other.car.linear_velocity.length()) * dt
		var err := absf(step - expect)
		ticks += 1
		if err > 0.5:
			big += 1
			var b := int((Time.get_ticks_msec() - go_time) / 5000) * 5
			big_when[b] = big_when.get(b, 0) + 1
		max_jump = maxf(max_jump, err)
		path += step
		last_pos = p
		var secs := (Time.get_ticks_msec() - go_time) / 1000.0
		if frames % 300 == 0:
			print("    t=%4.1fs me P%d %.0f m %.0f km/h | other P%d" % [secs, race.player.position, race.player.progress, race.player.car.speed_kmh(), other.position])
	_check(path > 2000.0, "%s: the other player's car drives on this phone (%.0f m driven)" % [role, path])
	print("    big jumps by time (s: frames): ", big_when, "   other car stuck/reset events seen: ", other.stuck)
	_check(big <= ticks / 100, "%s: and moves smoothly (%d of %d frames off by > 0.5 m; worst %.2f m)" % [role, big, ticks, max_jump])
	_check(race._results_shown, "%s: finishes and sees the results" % role)
	var seen := {}
	for e in race.entrants:
		seen[e.position] = true
	_check(seen.size() == 20, "%s: positions 1..20 all distinct" % role)
	print("  %s: finished P%d, other player P%d (automatic recoveries on this phone: %d)" % [role, race.player.position, other.position, race.recoveries]); print("  %s: interpolation delay %.2f s, jitter %.3f s" % [role, race.net.delay, race.net._jitter])
	# Host: back to the lobby together.
	if role == "host":
		_check(await _wait(func(): return other.finished, 120.0), "host: the friend finishes too")
		await _wait(func(): return false, 3.0)
		race.net.back_to_lobby()
		_check(await _wait(func(): return current_scene != null and current_scene.name == "Lobby", 10.0), "host: back to the lobby")
		await _wait(func(): return false, 4.0)
	else:
		_check(await _wait(func(): return current_scene != null and current_scene.name == "Lobby", 40.0), "client: the host brings everyone back to the lobby")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	net.leave()
	quit(0 if failures.is_empty() else 1)
