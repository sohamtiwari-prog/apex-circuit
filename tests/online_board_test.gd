extends SceneTree
## The online leaderboard client (scripts/world_board.gd) against a real
## database: posts laps (one with a ghost), reads the top 50 and your rank
## back, and fetches the ghost to race. Needs a server with
## server/leaderboard.sql (not run in CI):
##   godot --headless --script res://tests/online_board_test.gd -- <url> <key>

var fails := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		fails += 1


func _wait_for(cb: Callable) -> Variant:
	var box := [false, null]
	cb.call(func(v: Variant = null):
		box[0] = true
		box[1] = v)
	for i in 600:
		if box[0]:
			break
		await process_frame
	return box[1]


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var board: Node = root.get_node("Board")
	board.url = args[0] if args.size() > 0 else "http://127.0.0.1:3100"
	board.key = args[1] if args.size() > 1 else "sb_publishable_test"
	board._queue = []
	var me: String = board.player_id()
	_check(me.length() == 36, "a player id is made (%s)" % me)

	# A lap at Silvermoor in the GP car with a ghost: a 90 s path at 20 Hz.
	var hz := 20.0
	var g := PackedFloat32Array()
	for i in int(90.0 * hz):
		var a := i / (90.0 * hz) * TAU
		var q := Quaternion(Vector3.UP, a)
		g.append_array([cos(a) * 900.0, 2.0, sin(a) * 900.0, q.x, q.y, q.z, q.w])
	board.post_lap({"track": "silvermoor", "car": "gp26", "lap_ms": 90000, "ranked": true, "mode": "time_trial",
		"sectors": [30000, 29000, 31000], "weather": "dry", "assists": {"tc": true}, "setup": {}}, g, hz)
	board.post_lap({"track": "silvermoor", "car": "gp26", "lap_ms": 93000, "ranked": false, "mode": "race"})
	board.post_lap({"track": "silvermoor", "car": "gp26", "lap_ms": 9000, "ranked": true, "mode": "time_trial"})
	_check(board.pending() == 3, "three laps wait in the queue")
	var kept: Variant = await _wait_for(func(done): board.posted.connect(done, CONNECT_ONE_SHOT))
	_check(int(kept) == 2, "the server keeps the two real laps and turns the impossible one away (kept %s)" % str(kept))
	_check(board.pending() == 0, "the queue is empty once they're up")

	var rows: Variant = await _wait_for(func(done): board.top("silvermoor", "gp26", done))
	_check(rows is Array and (rows as Array).size() >= 1, "the top 50 comes back")
	var mine: Dictionary = {}
	for r in rows:
		if bool(r["mine"]):
			mine = r
	_check(not mine.is_empty() and int(mine["lap_ms"]) == 90000 and bool(mine["has_ghost"]), "your ranked lap is on it, with its ghost")
	_check(not mine.is_empty() and (mine["sectors"] as Array).size() == 3, "with its sectors")

	var rank: Variant = await _wait_for(func(done): board.rank("silvermoor", "gp26", done))
	_check(rank is Dictionary and int(rank.get("rank", 0)) >= 1 and int(rank.get("best_ms", 0)) == 90000, "your world rank: %s" % str(rank))
	var none: Variant = await _wait_for(func(done): board.rank("riviera", "gp26", done))
	_check(none is Dictionary and (none as Dictionary).is_empty(), "no rank where you haven't driven")

	var ch: Variant = await _wait_for(func(done): board.ghost(int(mine.get("lap_id", 0)), done))
	_check(ch is Dictionary and String(ch.get("track", "")) == "silvermoor" and int(ch.get("lap_ms", 0)) == 90000, "the ghost comes back as a challenge")
	var s: PackedFloat32Array = ch.get("samples", PackedFloat32Array()) if ch is Dictionary else PackedFloat32Array()
	_check(absi(s.size() / 7 - g.size() / 7) <= 2, "the same length of path (%d vs %d samples)" % [s.size() / 7, g.size() / 7])
	if s.size() > 7 * 400:
		var p := Vector3(s[7 * 400], s[7 * 400 + 1], s[7 * 400 + 2])
		var o := Vector3(g[7 * 400], g[7 * 400 + 1], g[7 * 400 + 2])
		_check(p.distance_to(o) < 0.5, "the same path (%.2f m off at 20 s)" % p.distance_to(o))

	# Offline: laps wait, nothing's lost.
	board.url = "http://127.0.0.1:9"
	board.post_lap({"track": "silvermoor", "car": "gp26", "lap_ms": 91000, "ranked": true, "mode": "time_trial"})
	for i in 200:
		await process_frame
	_check(board.pending() == 1, "offline, the lap waits on the phone")
	board._queue = []
	board._save_queue()
	print("")
	print("ALL CHECKS PASSED" if fails == 0 else "%d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
