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
func secs_now(t0: int) -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0


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
		lobby._settings()["laps"] = 2
		lobby._settings()["pits"] = "on"
		lobby._settings()["track"] = "styria"
		lobby._settings()["grid"] = 20
		if OS.has_environment("APEX_PARTY"):
			lobby._settings()["party"] = OS.get_environment("APEX_PARTY")     # (by hand: party modes)
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
	# (Listening from the start: when the host finishes last, the friend's
	# "Rematch?" can come before the host's own results are up.)
	var asked := [false]
	if role == "host":
		net.chat_received.connect(func(_f, t):
			print("  [%.1f s] host: chat from %d: %s" % [secs_now(go_time), _f, t])
			if t == "Rematch?":
				asked[0] = true)
		net.peer_left.connect(func(id): print("  [%.1f s] host: peer %d left" % [secs_now(go_time), id]))
	var truth_log: FileAccess = null
	if OS.has_environment("TRUTH_DIR"):
		truth_log = FileAccess.open(OS.get_environment("TRUTH_DIR") + "/truth_%s.csv" % role, FileAccess.WRITE)
	var truth_t := -1.0
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
	# Contact quality for this phone's own car: touches, spins, trips off.
	var touches := [0]
	race.car_contact.connect(func(a, b, _v):
		if a == race.car or b == race.car:
			touches[0] += 1)
	var spins := 0
	var boxed := false
	var saw_other_pit := false
	var saw_other_crew := false
	var spinning := false
	var offs := 0
	var off_now := false
	# Every car near you on this phone (bots too, on a friend's phone): how
	# often one visibly jumps (> 0.5 m from where its speed takes it).
	var near_last := {}
	var near_frames := 0
	var near_jumps := 0
	var near_worst := 0.0
	var near_when := {}
	while not race._results_shown and Time.get_ticks_msec() - go_time < 330000:
		await process_frame          # what you see: once per drawn frame
		# Truth and what's drawn, at the same real moment (both phones run on
		# this one computer; tests/mp_truth.py compares them: how far from
		# where it really is each other car is drawn).
		if truth_log != null and race.net.net_time() - truth_t > 0.1:
			truth_t = race.net.net_time()
			for e in race.entrants:
				if not e.car.visible:
					continue
				var q: Vector3 = e.car.global_position
				var near: bool = q.distance_to(race.car.global_position) < 60.0
				truth_log.store_line("%.3f,%d,%s,%.2f,%.2f,%.2f,%d,%d" % [Time.get_unix_time_from_system(), e.slot, "D" if e.remote else "T", q.x, q.y, q.z, 1 if near else 0, e.pit_phase])
		frames += 1
		# Both players box for hard tyres early in the race (stop at the end of lap 1).
		if not boxed and Time.get_ticks_msec() - go_time > 6000 and race.weekend != null:
			race.weekend.set_box("hard")
			boxed = true
		if other.pit_phase == 2:
			saw_other_pit = true
			saw_other_crew = saw_other_crew or (race.weekend != null and race.weekend.crew.has(other))
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
			if big <= 6 or (big % 10 == 0 and big < 100):
				var bf: Array = race.net._buffers.get(other.slot, [])
				var newest: float = bf[bf.size() - 1][0] if not bf.is_empty() else -1.0
				print("      jump %.2f m at %.1f s: other in pit phase %d%s, step %.2f m vs %.2f expected, drawn speed %.1f, newest state %.2f s old, at %s" % [err, secs_now(go_time), other.pit_phase, " (finished)" if other.finished else "", step, expect, other.car.remote_vel.length(), race.net.net_time() - newest, str(p)])
			var b := int((Time.get_ticks_msec() - go_time) / 5000) * 5
			big_when[b] = big_when.get(b, 0) + 1
		max_jump = maxf(max_jump, err)
		path += step
		last_pos = p
		for e in race.entrants:
			if e == race.player or not e.car.visible:
				continue
			var q: Vector3 = e.car.global_position
			if q.distance_to(race.car.global_position) < 60.0 and near_last.has(e.slot) and e.pit_phase == 0:
				var vel: float = e.car.remote_vel.length() if e.car.remote else e.car.linear_velocity.length()
				var er := absf(q.distance_to(near_last[e.slot]) - vel * dt)
				near_frames += 1
				if er > 0.5:
					near_jumps += 1
					var nb := int((Time.get_ticks_msec() - go_time) / 10000) * 10
					near_when[nb] = near_when.get(nb, 0) + 1
				near_worst = maxf(near_worst, er)
			near_last[e.slot] = q
		var me = race.player
		if not me.finished and me.pit_phase == 0:
			var trk = race.track
			var yaw_rel: float = absf(race.car.angular_velocity.y - race.car.forward_speed() * trk.curv[me.idx])
			if yaw_rel > 1.6 and not spinning:
				spins += 1
			spinning = yaw_rel > 1.0
			var wide: bool = absf(trk.lateral(race.car.global_position, me.idx)) > trk.road_half + Track.KERB_W + 2.5
			if wide and not off_now:
				offs += 1
			off_now = wide
		var secs := (Time.get_ticks_msec() - go_time) / 1000.0
		if frames % 300 == 0:
			print("    t=%4.1fs me P%d %.0f m %.0f km/h | other P%d" % [secs, race.player.position, race.player.progress, race.player.car.speed_kmh(), other.position])
	_check(path > 2000.0, "%s: the other player's car drives on this phone (%.0f m driven)" % [role, path])
	print("    contact: %d touches on this phone's car, %d spins, %d trips off the track" % [touches[0], spins, offs])
	_check(spins == 0 and offs <= 1, "%s: touching other cars doesn't spin you or throw you off (%d touches, %d spins, %d offs)" % [role, touches[0], spins, offs])
	print("    big jumps by time (s: frames): ", big_when, "   other car stuck/reset events seen: ", other.stuck)
	print("    cars near you: %d jumps in %d car-frames (worst %.2f m), by time (s: count) %s" % [near_jumps, near_frames, near_worst, near_when])
	_check(near_jumps <= near_frames / 200, "%s: every car near you moves smoothly (%d of %d car-frames jump > 0.5 m; worst %.2f m)" % [role, near_jumps, near_frames, near_worst])
	_check(big <= ticks / 100, "%s: and moves smoothly (%d of %d frames off by > 0.5 m; worst %.2f m)" % [role, big, ticks, max_jump])
	_check(race._results_shown, "%s: finishes and sees the results" % role)
	_check(race.weekend != null and race.player.stops == 1 and race.player.compound == "hard", "%s: your pit stop with friends: in, new hard tyres, out (%d stop, %s)" % [role, race.player.stops, race.player.compound])
	_check(saw_other_pit and saw_other_crew and other.compound == "hard", "%s: sees the other player's stop: crew and new hard tyres (%s)" % [role, other.compound])
	var seen := {}
	for e in race.entrants:
		seen[e.position] = true
	_check(seen.size() == 20, "%s: positions 1..20 all distinct" % role)
	var race_secs := (Time.get_ticks_msec() - go_time) / 1000.0
	if role == "client":
		print("  client: connection: ping %d ms, %d updates from the host (%.1f a second), longest wait %.2f s, %d waits over 0.25 s" % [net.my_ping, race.net.rx_count, race.net.rx_count / maxf(race_secs, 1.0), race.net.rx_max_gap, race.net.rx_stalls])
	print("  %s: drawing the other phone's cars took %.1f ms per second of racing" % [role, race.net.cost_us / 1000.0 / maxf(race_secs, 1.0)])
	print("  %s: finished P%d, other player P%d (automatic recoveries on this phone: %d)" % [role, race.player.position, other.position, race.recoveries]); print("  %s: interpolation delay %.2f s, jitter %.3f s" % [role, race.net.delay, race.net._jitter])
	# Host: a rematch (the friend asks for one), then back to the lobby together.
	if role == "host":
		_check(await _wait(func(): return other.finished, 120.0), "host: the friend finishes too")
		# Replays open once every car is home.
		var all_home := func():
			for e in race.entrants:
				if not e.finished:
					return false
			return true
		_check(await _wait(all_home, 90.0), "host: every car finishes")
		await _wait(func(): return false, 1.0)
		_check(race.hud.replay_button != null and not race.hud.replay_button.disabled, "host: Replay is available once everyone is home")
		race.watch_replay(false)
		await _wait(func(): return false, 2.0)
		_check(race.replay.playing, "host: the replay plays")
		race.replay.stop()
		_check(await _wait(func(): return asked[0], 90.0), "host: the friend's \"Rematch?\" arrives")
		var old := race
		race.net.rematch()
		_check(await _wait(func(): return current_scene != null and current_scene != old and current_scene.name == "Race" and current_scene.get("player") != null, 20.0), "host: the rematch starts")
		race = current_scene
		var pl: Array = []
		for e in race.entrants:
			if e.net_id > 0:
				pl.append(e)
		_check(pl.size() == 2, "host: both players are on the rematch grid (%d)" % pl.size())
		await _wait(func(): return false, 8.0)
		race.net.back_to_lobby()
		_check(await _wait(func(): return current_scene != null and current_scene.name == "Lobby", 10.0), "host: back to the lobby")
		await _wait(func(): return false, 4.0)
	else:
		var all_home := func():
			for e in race.entrants:
				if not e.finished:
					return false
			return true
		net.closed.connect(func(r): print("  [%.1f s] client: session closed: %s" % [secs_now(go_time), r]))
		var home: bool = await _wait(all_home, 90.0)
		var left: Array = []
		for e in race.entrants:
			if not e.finished:
				left.append("%s(slot %d)" % [e.name, e.slot])
		print("  [%.1f s] client: all home %s %s" % [secs_now(go_time), home, str(left)])
		await _wait(func(): return false, 1.0)
		net.chat(net.CHAT.find("Rematch?"))
		print("  [%.1f s] client: asked for a rematch (my id %d, role %s)" % [secs_now(go_time), net.my_id, net.role])
		race.watch_replay(false)
		var watching: bool = race.replay.playing
		if watching:
			race.replay.cycle_speed()
			race.replay.cycle_speed()      # 1/4 speed: sound slowed until the replay closes
		_check(watching, "client: watching the replay when the host heads back")
		var saw_rematch := [false]
		_check(await _wait(func():
			if current_scene != null and current_scene != race and current_scene.name == "Race":
				saw_rematch[0] = true
			return current_scene != null and current_scene.name == "Lobby", 70.0), "client: the host brings everyone back to the lobby")
		_check(saw_rematch[0], "client: joined the host's rematch on the way")
		_check(is_equal_approx(AudioServer.playback_speed_scale, 1.0) and not AudioServer.is_bus_mute(0), "client: sound back to normal after leaving mid-replay")
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	net.leave()
	quit(0 if failures.is_empty() else 1)
