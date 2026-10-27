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
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
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
	elif kind == "public":
		h.public_brokers = [url, url, url]
		c.public_brokers = [url, url, url]
		h.host_public("Soham")
		_check(await _wait(func(): return h.my_id == 1 and h.room_code.length() == 4, 10.0), "public: room created (code %s)" % h.room_code)
		c.join_public(h.room_code.to_lower())
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
	if kind == "public":
		_check(await _wait(func(): return c.my_ping >= 0 and h.pings.has(c.my_id), 6.0), "public: ping measured both ways (%d ms)" % c.my_ping)
		# A phone that vanishes without saying goodbye (the broker's last will).
		var c2: Node = NetScript.new()
		root.add_child(c2)
		c2.public_brokers = [url, url, url]
		c2.join_public(h.room_code)
		_check(await _wait(func(): return c2.my_id > 1, 10.0), "public: a second friend joins (id %d)" % c2.my_id)
		var gone: Array = []
		h.peer_left.connect(func(id): gone.append(id))
		var vanished_id: int = c2.my_id
		c2._mq._ws.close()              # no MQTT goodbye: like the app being killed
		c2.set_process(false)
		_check(await _wait(func(): return gone.has(vanished_id), 8.0), "public: the host notices a friend's phone vanishing")
		c2.queue_free()
		var bad: Node = NetScript.new()
		root.add_child(bad)
		bad.public_brokers = [url, url, url]
		var why: Array = []
		bad.failed.connect(func(r): why.append(r))
		var wrong := "ZZZZ" if h.room_code != "ZZZZ" else "YYYY"
		bad.join_public(wrong)
		_check(await _wait(func(): return why.size() > 0, 20.0), "public: a wrong code is refused (%s)" % (why[0] if why.size() > 0 else "-"))
		bad.queue_free()
		# First server down: the host moves to the next, and the code tells
		# joiners which one.
		var h2: Node = NetScript.new()
		var c3: Node = NetScript.new()
		root.add_child(h2)
		root.add_child(c3)
		var dead := "ws://127.0.0.1:9/mqtt"
		h2.public_brokers = [dead, url, url]
		c3.public_brokers = [dead, url, url]
		h2.host_public("Cousin")
		_check(await _wait(func(): return h2.my_id == 1, 20.0), "public: first server down, hosting moves to the next (code %s, server %d)" % [h2.room_code, h2._mq_try])
		c3.join_public(h2.room_code)
		_check(await _wait(func(): return c3.my_id > 1, 10.0), "public: and a friend still finds the game from the code")
		h2.leave()
		c3.leave()
		h2.queue_free()
		c3.queue_free()
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
## The address a host shows must be its Wi-Fi one, never mobile data.
func _addresses() -> void:
	var NetScript = load("res://scripts/net.gd")
	var phone := [
		{"name": "lo", "addresses": ["127.0.0.1", "::1"]},
		{"name": "rmnet_data0", "addresses": ["10.71.23.5", "2409:4042::1"]},
		{"name": "v4-rmnet_data0", "addresses": ["192.0.0.4"]},
		{"name": "wlan0", "addresses": ["fe80::1", "192.168.1.23"]},
	]
	var got: Array = NetScript.pick_lan(phone)
	_check(got == ["192.168.1.23"], "Wi-Fi + mobile data: shows only the Wi-Fi address %s" % str(got))
	var hotspot := [
		{"name": "rmnet_data1", "addresses": ["100.72.1.2"]},
		{"name": "swlan0", "addresses": ["192.168.43.1"]},
	]
	got = NetScript.pick_lan(hotspot)
	_check(got == ["192.168.43.1"], "hotspot host: shows the hotspot address %s" % str(got))
	var router10 := [
		{"name": "ccmni1", "addresses": ["10.12.0.9"]},
		{"name": "wlan0", "addresses": ["10.0.0.14"]},
	]
	got = NetScript.pick_lan(router10)
	_check(got == ["10.0.0.14"], "a 10.x home router still beats mobile data %s" % str(got))


## Joiners find a host by asking each address directly (broadcasts are
## often dropped by phones), and through the normal list.
func _discovery() -> void:
	var NetScript = load("res://scripts/net.gd")
	var h: Node = NetScript.new()
	root.add_child(h)
	_check(h.host_lan("Soham"), "discovery: hosting starts")
	var raw := PacketPeerUDP.new()
	raw.bind(47099)
	raw.set_dest_address("127.0.0.1", h.PROBE_PORT)
	raw.put_packet("apex-circuit-probe".to_utf8_buffer())
	var answered := await _wait(func(): return raw.get_available_packet_count() > 0, 3.0)
	var info: Variant = JSON.parse_string(raw.get_packet().get_string_from_utf8()) if answered else null
	_check(answered and info is Dictionary and info["name"] == "Soham", "discovery: the host answers a direct probe (%s)" % str(info))
	raw.close()
	var c: Node = NetScript.new()
	root.add_child(c)
	var lists: Array = []
	c.games_found.connect(func(g): lists.append(g))
	c.start_discovery()
	var ok := await _wait(func(): return lists.size() > 0 and lists[-1].size() > 0, 6.0)
	var ips: Array = []
	if ok:
		for g in lists[-1]:
			ips.append(g["ip"])
	_check(ok, "discovery: the game shows under Games nearby %s" % str(ips))
	c.stop_discovery()
	h.leave()
	c.queue_free()
	h.queue_free()
	await process_frame


func _run() -> void:
	await process_frame
	_addresses()
	await _discovery()
	await _pair("lan")
	# Args: [relay ws url] [mqtt broker ws url]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "-":
		await _pair("online", args[0])
	if args.size() > 1:
		await _pair("public", args[1])
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
