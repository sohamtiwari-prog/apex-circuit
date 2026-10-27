extends SceneTree
## Connection layer, both transports, in one process (two Net instances).
##   godot --headless --script res://tests/net_test.gd [-- ws://127.0.0.1:8090]
var failures: Array[String] = []
var log: Array = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await process_frame
		t += 1.0 / 60.0
	return cond.call()
func _pair(kind: String, url := "") -> void:
	var NetScript = load("res://scripts/net.gd")
	var h: Node = NetScript.new()
	var c: Node = NetScript.new()
	root.add_child(h)
	root.add_child(c)
	var got_h: Array = []
	var got_c: Array = []
	var joins: Array = []
	var closed_c: Array = []
	h.message.connect(func(f, m): got_h.append([f, m]))
	c.message.connect(func(f, m): got_c.append([f, m]))
	h.peer_joined.connect(func(id): joins.append(id))
	c.closed.connect(func(r): closed_c.append(r))
	if kind == "lan":
		_check(h.host_lan("Soham"), "lan: hosting starts")
		c.join_lan("127.0.0.1")
	else:
		h.host_online(url, "Soham")
		_check(await _wait(func(): return h.my_id == 1 and h.room_code.length() == 4, 10.0), "online: room created (code %s)" % h.room_code)
		c.join_online(url, h.room_code.to_lower())
	_check(await _wait(func(): return c.my_id > 1, 10.0), "%s: client joins (id %d)" % [kind, c.my_id])
	_check(await _wait(func(): return joins.size() == 1, 5.0), "%s: host sees the join" % kind)
	c.send(1, {"t": "hello", "name": "Friend", "s": PackedFloat32Array([1.5, 2.5])})
	_check(await _wait(func(): return got_h.size() > 0, 5.0), "%s: host receives the client's message" % kind)
	if got_h.size() > 0:
		_check(got_h[0][0] == c.my_id and got_h[0][1]["name"] == "Friend" and got_h[0][1]["s"][1] == 2.5, "%s: message intact, sender id right" % kind)
	for k in range(30):
		h.send(0, {"t": "snap", "k": k}, false)
	_check(await _wait(func(): return got_c.size() >= 25, 5.0), "%s: host broadcast reaches the client (%d/30 unreliable)" % [kind, got_c.size()])
	# Wrong room code.
	if kind == "online":
		var bad: Node = NetScript.new()
		root.add_child(bad)
		var why: Array = []
		bad.failed.connect(func(r): why.append(r))
		bad.join_online(url, "ZZZZ")
		_check(await _wait(func(): return why.size() > 0, 10.0), "online: a wrong code is refused (%s)" % (why[0] if why.size() > 0 else "-"))
		bad.queue_free()
	h.leave()
	_check(await _wait(func(): return closed_c.size() > 0, 10.0), "%s: client is told when the host leaves" % kind)
	h.queue_free()
	c.queue_free()
	await process_frame
func _run() -> void:
	await process_frame
	await _pair("lan")
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		await _pair("online", args[0])
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
