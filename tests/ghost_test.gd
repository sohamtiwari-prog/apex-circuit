extends SceneTree
## Ghost challenges: a lap packed small and back (within centimetres and a
## degree), sent to the relay under a code and fetched back with it, and
## a made-up code finds nothing.
##   godot --headless --script res://tests/ghost_test.gd -- ws://127.0.0.1:8091/mqtt
## (… -- <url> fetch <code>: only fetch a code, e.g. one sent minutes ago,
## to see a real server keeps it: .github/workflows/ghost-probe.yml)

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _run() -> void:
	await process_frame
	var url: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "ws://127.0.0.1:8091/mqtt"
	root.get_node("Net").public_brokers = [url]
	var args := OS.get_cmdline_user_args()
	if args.size() > 2 and args[1] == "fetch":
		var g := GhostShare.new()
		root.add_child(g)
		var r := [null]
		g.done.connect(func(ok, res): r[0] = [ok, res])
		g.download(args[2])
		var tt := 0
		while r[0] == null and tt < 1500:
			await process_frame
			tt += 1
		_check(r[0] != null and r[0][0], "code %s still there" % args[2])
		quit(0 if failures.is_empty() else 1)
		return
	# A lap: 80 s at 20 Hz round a wobbly circle.
	var lap := PackedFloat32Array()
	for i in 1600:
		var a := i / 1600.0 * TAU
		var p := Vector3(cos(a) * 400.0, 3.0 + sin(a * 3.0), sin(a) * 300.0)
		var q := Basis(Vector3.UP, -a).get_rotation_quaternion()
		lap.append_array([p.x, p.y, p.z, q.x, q.y, q.z, q.w])
	var info := {"track": "styria", "car": "gp26", "team": 2, "name": "Ann", "lap_ms": 80000, "paint": {"on": true, "base": "#121c4a"}}
	var bytes := GhostShare.pack(lap, 20.0, info)
	print("    an 80 s lap: %d bytes" % bytes.size())
	_check(bytes.size() < 24000, "small enough to send (%d bytes)" % bytes.size())
	var back := GhostShare.unpack(bytes, 20.0)
	var s: PackedFloat32Array = back["samples"]
	var worst := 0.0
	var worst_a := 0.0
	for i in range(0, mini(s.size(), lap.size()) / 7):
		var k := i * 7
		worst = maxf(worst, Vector3(s[k], s[k + 1], s[k + 2]).distance_to(Vector3(lap[k], lap[k + 1], lap[k + 2])))
		worst_a = maxf(worst_a, Quaternion(s[k + 3], s[k + 4], s[k + 5], s[k + 6]).angle_to(Quaternion(lap[k + 3], lap[k + 4], lap[k + 5], lap[k + 6])))
	_check(absi(s.size() - lap.size()) <= 7 * 20, "the same length of lap (%d / %d samples)" % [s.size() / 7, lap.size() / 7])
	_check(worst < 0.6 and rad_to_deg(worst_a) < 2.0, "the path comes back (worst %.2f m, %.2f deg)" % [worst, rad_to_deg(worst_a)])
	_check(String(back["name"]) == "Ann" and int(back["lap_ms"]) == 80000 and String(back["paint"]["base"]) == "#121c4a", "who, the time and their paint come back")
	# Through the relay.
	var up := GhostShare.new()
	root.add_child(up)
	var got := [null]
	up.done.connect(func(ok, res): got[0] = [ok, res])
	up.upload(bytes)
	var t := 0
	while got[0] == null and t < 1200:
		await process_frame
		t += 1
	_check(got[0] != null and got[0][0], "uploaded, with a code (%s)" % str(got[0]))
	var code: String = got[0][1] if got[0] != null and got[0][0] else ""
	print("    code: ", code)
	var down := GhostShare.new()
	root.add_child(down)
	var res := [null]
	down.done.connect(func(ok, r): res[0] = [ok, r])
	down.download(code.to_lower().insert(3, " "))       # (typed any old how)
	t = 0
	while res[0] == null and t < 1200:
		await process_frame
		t += 1
	_check(res[0] != null and res[0][0] and String(res[0][1]["track"]) == "styria", "a friend fetches it with the code")
	var none := GhostShare.new()
	root.add_child(none)
	var nres := [null]
	none.done.connect(func(ok, r): nres[0] = [ok, r])
	none.download("ZZZZ99")
	t = 0
	while nres[0] == null and t < 1500:
		await process_frame
		t += 1
	_check(nres[0] != null and not nres[0][0], "a made-up code finds nothing (%s)" % (str(nres[0][1]) if nres[0] != null else "no answer"))
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
