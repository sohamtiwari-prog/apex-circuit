extends Node
## Multiplayer connection (autoload "Net"). One phone hosts; others join.
##
## Three transports, same game protocol:
##   Wi-Fi / hotspot ("lan"): ENet straight between phones; hosts announce
##     themselves with a UDP broadcast so joiners see them in a list.
##   Online, free public servers ("public"): every phone connects to a public
##     MQTT broker (no setup); the room code picks the broker and the topics.
##   Online, own server ("online"): every phone opens a WebSocket to the small
##     relay server (server/relay.js) and joins a room by its 4-letter code.
## Star topology either way: clients talk to the host (id 1), the host talks
## to everyone. Messages are Dictionaries (var_to_bytes, no objects).

signal peer_joined(id: int)
signal peer_left(id: int)
signal message(from_id: int, msg: Dictionary)
signal joined                       # client: connected and given an id
signal failed(reason: String)       # couldn't connect / room not found
signal closed(reason: String)       # session ended (host left, connection lost)
signal games_found(games: Array)    # LAN discovery: [{name, ip, players}]
signal chat_received(from_id: int, text: String)

## Quick-chat phrases (sent as an index, so they're short and clean).
const CHAT := ["Let's go!", "GG", "Nice move!", "Sorry!", "Rematch?"]

const GAME_PORT := 47010
const BEACON_PORT := 47011          # joiners listen here (host announcements, probe replies)
const PROBE_PORT := 47012           # hosts listen here for "who's hosting?" probes
const DEFAULT_SERVER := "wss://apex-circuit-relay.onrender.com"
## Free public MQTT brokers (WebSocket + TLS). The first letter of a room code
## says which one the game is on, so joiners need nothing but the code.
const PUBLIC_BROKERS := [
	"wss://broker.emqx.io:8084/mqtt",
	"wss://broker.hivemq.com:8884/mqtt",
	"wss://test.mosquitto.org:8081/mqtt",
]
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
var public_brokers: Array = PUBLIC_BROKERS.duplicate()   # tests use a local broker

var role := "offline"               # "offline", "host", "client"
var transport := ""                 # "lan" or "online"
var my_id := 0
var room_code := ""
var host_name := ""
var start_info: Dictionary = {}     # set by the lobby when the host starts a race

var _enet: ENetMultiplayerPeer
var _ws: WebSocketPeer
var _ws_open := false
var _beacon: PacketPeerUDP
var _beacon_timer := 0.0
var _listen: PacketPeerUDP
var _probe: PacketPeerUDP           # host: answers probes from joiners
var _probe_timer := 0.0
var _found := {}                    # ip -> {name, players, seen}
var _connect_timer := 0.0
var lobby_players := 0              # for the LAN beacon
var _pending_end := ""              # close after polling, never inside a callback
# Ping, for every transport: clients ask every 2 s, the host answers.
var my_ping := -1                   # ms, this phone to the host
var pings := {}                     # host: peer id -> ms
var _ping_timer := 0.0
# Public servers (MQTT).
const MqttLinkScript := preload("res://scripts/mqtt_link.gd")
var _mq: RefCounted                 # MqttLink
var _mq_events: Array = []
var _mq_try := 0
var _tok := ""                      # client: our name on the room topics
var _peer_tok := {}                 # host: id -> token
var _tok_peer := {}                 # host: token -> id
var _next_id := 2
var _last_seen := {}                # host: id -> msec of the last message
var _last_host := 0                 # client: msec of the last message from the host
var _join_timer := 0.0


func is_online() -> bool:
	return role != "offline"


func is_host() -> bool:
	return role == "host"


# ------------------------------------------------------------ Wi-Fi (ENet)

func host_lan(name: String) -> bool:
	leave()
	_enet = ENetMultiplayerPeer.new()
	if _enet.create_server(GAME_PORT, 19) != OK:
		_enet = null
		failed.emit("Couldn't start hosting on this network.")
		return false
	_enet.peer_connected.connect(func(id: int): peer_joined.emit(id))
	_enet.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	role = "host"
	transport = "lan"
	my_id = 1
	host_name = name
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	# Many Android phones drop Wi-Fi broadcasts, so joiners also ask every
	# address on the network directly; this socket answers them.
	_probe = PacketPeerUDP.new()
	if _probe.bind(PROBE_PORT) != OK:
		_probe = null
	return true


func join_lan(ip: String) -> void:
	leave()
	_enet = ENetMultiplayerPeer.new()
	if _enet.create_client(ip.strip_edges(), GAME_PORT) != OK:
		_enet = null
		failed.emit("That address doesn't look right: %s" % ip)
		return
	_enet.peer_disconnected.connect(func(id: int):
		if id == 1:
			_pending_end = "The host left the game.")
	role = "client"
	transport = "lan"
	_connect_timer = 8.0


## This phone's address on the Wi-Fi / hotspot (what joiners can type in).
func local_ip() -> String:
	var all := lan_addresses()
	return all[0] if not all.is_empty() else ""


## Every Wi-Fi / hotspot / Ethernet IPv4 address of this device, best first.
## Mobile-data addresses (often 10.x on Indian carriers) are left out: a
## friend on the Wi-Fi can never reach them.
func lan_addresses() -> Array[String]:
	return pick_lan(IP.get_local_interfaces())


const _MOBILE := ["rmnet", "ccmni", "seth", "pdp", "clat", "v4-", "tun", "ppp", "lo", "dummy", "ifb", "ipsec", "wwan", "usb_mbim"]
const _LOCAL_LINK := ["wlan", "swlan", "ap", "softap", "wifi", "eth", "en", "wl", "rndis", "bt-pan", "p2p"]

static func pick_lan(ifaces: Array) -> Array[String]:
	var scored: Array = []
	for i in ifaces:
		var name := String(i.get("name", "")).to_lower()
		var skip := false
		for m in _MOBILE:
			if name.begins_with(m) or name.contains("rmnet"):
				skip = true
		if skip:
			continue
		var link := 0
		for w in _LOCAL_LINK:
			if name.begins_with(w):
				link = 1
		for a in i.get("addresses", []):
			var ip := String(a)
			if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
				continue
			var priv := 0
			if ip.begins_with("192.168."):
				priv = 3
			elif ip.begins_with("172.") and int(ip.get_slice(".", 1)) >= 16 and int(ip.get_slice(".", 1)) <= 31:
				priv = 2
			elif ip.begins_with("10."):
				priv = 1
			scored.append([link * 10 + priv, ip])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	var out: Array[String] = []
	for x in scored:
		if not out.has(x[1]):
			out.append(x[1])
	return out


## Start listening for hosts on the same Wi-Fi (games_found is emitted).
func start_discovery() -> void:
	stop_discovery()
	_listen = PacketPeerUDP.new()
	_listen.set_broadcast_enabled(true)
	if _listen.bind(BEACON_PORT) != OK:
		_listen.bind(0)               # another copy is listening; probe replies still arrive
	_found.clear()
	_probe_timer = 0.0


func stop_discovery() -> void:
	if _listen != null:
		_listen.close()
		_listen = null


# ------------------------------------------------------------ online (relay)

func host_online(url: String, name: String) -> void:
	_open_ws(url, {"op": "host", "name": name})
	role = "host"
	transport = "online"
	host_name = name


func join_online(url: String, code: String) -> void:
	_open_ws(url, {"op": "join", "room": code.strip_edges().to_upper()})
	role = "client"
	transport = "online"


var _hello: Dictionary = {}

func _open_ws(url: String, hello: Dictionary) -> void:
	leave()
	_ws = WebSocketPeer.new()
	_ws.outbound_buffer_size = 1 << 20
	_ws.inbound_buffer_size = 1 << 20
	if _ws.connect_to_url(url) != OK:
		_ws = null
		failed.emit("Couldn't open the online server address.")
		return
	_ws_open = false
	_hello = hello
	# A free server that has gone to sleep takes up to a minute to wake.
	_connect_timer = 70.0


# ------------------------------------------------------------ online (free public servers)

## Which public server a room code lives on.
static func broker_for(code: String, count: int) -> int:
	return maxi(CODE_CHARS.find(code.substr(0, 1).to_upper()), 0) % maxi(count, 1)


func host_public(name: String) -> void:
	leave()
	role = "host"
	transport = "public"
	host_name = name
	_mq_try = 0
	_public_host_attempt()


func _public_host_attempt() -> void:
	if _mq_try >= public_brokers.size():
		leave()
		failed.emit("Couldn't reach the free online servers. Check your internet and try again.")
		return
	var code := ""
	while code == "" or broker_for(code, public_brokers.size()) != _mq_try:
		code = _rand(4, CODE_CHARS)
	room_code = code
	_mq_open(public_brokers[_mq_try], "apex-h-" + _rand(10), _base() + "c", _ctl({"op": "host_left"}))
	_connect_timer = 12.0


func join_public(code: String) -> void:
	leave()
	role = "client"
	transport = "public"
	room_code = code.strip_edges().to_upper()
	_tok = _rand(10)
	var url: String = public_brokers[broker_for(room_code, public_brokers.size())]
	_mq_open(url, "apex-c-" + _tok, _base() + "h", _ctl({"op": "bye", "tok": _tok}))
	_connect_timer = 15.0


func _base() -> String:
	return "apexcircuit/v1/%s/" % room_code


static func _ctl(d: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([0])
	out.append_array(JSON.stringify(d).to_utf8_buffer())
	return out


static func _rand(n: int, chars := "abcdefghijkmnpqrstuvwxyz23456789") -> String:
	var s := ""
	for i in n:
		s += chars[randi() % chars.length()]
	return s


func _mq_open(url: String, cid: String, will_topic: String, will: PackedByteArray) -> void:
	if _mq != null:
		_mq.close()
	_mq = MqttLinkScript.new()
	_mq_events.clear()
	_mq.ready.connect(func(): _mq_events.append(["ready"]))
	_mq.message.connect(func(t: String, p: PackedByteArray): _mq_events.append(["msg", t, p]))
	_mq.closed.connect(func(r: String): _mq_events.append(["closed", r]))
	if not _mq.open(url, cid, will_topic, will):
		_mq_events.append(["closed", "bad address"])


func _poll_mq(delta: float) -> void:
	_mq.poll(delta)
	var evs := _mq_events
	_mq_events = []
	for ev in evs:
		if _mq == null:
			return
		match ev[0]:
			"ready":
				_mq_ready()
			"msg":
				_mq_message(ev[1], ev[2])
			"closed":
				_mq_closed()
	if _mq == null:
		return
	var now := Time.get_ticks_msec()
	if my_id == 0:
		_connect_timer -= delta
		if role == "client" and _mq.is_ready():
			_join_timer -= delta
			if _join_timer <= 0.0:
				_join_timer = 1.5
				_mq.publish(_base() + "h", _ctl({"op": "join", "tok": _tok}))
		if _connect_timer <= 0.0:
			if role == "host":
				_mq_try += 1
				_public_host_attempt()
			else:
				var reachable: bool = _mq.is_ready()
				var code := room_code
				leave()
				failed.emit(("No game with code %s. Check the code with the host." % code) if reachable else "Couldn't reach the free online servers. Check your internet and try again.")
		return
	# Nobody can tell us a phone vanished except silence: 12 s and it's gone.
	if role == "host":
		for id in _last_seen.keys():
			if now - int(_last_seen[id]) > 12000:
				_drop_peer(id)
	elif now - _last_host > 12000:
		_end("Lost connection to the host.")


func _mq_ready() -> void:
	if role == "host":
		_mq.subscribe(_base() + "h")
		my_id = 1
		joined.emit()
	else:
		_mq.subscribe(_base() + "c")
		_mq.subscribe(_base() + "p/" + _tok)
		_join_timer = 0.3
		_connect_timer = 7.0              # server reached: the host answers fast or there's no game


func _mq_closed() -> void:
	if role == "host" and my_id == 0:
		_mq_try += 1
		_public_host_attempt()
	elif my_id == 0:
		leave()
		failed.emit("Couldn't reach the free online servers. Check your internet and try again.")
	else:
		_end("Lost connection to the online server.")


func _mq_message(topic: String, payload: PackedByteArray) -> void:
	if payload.is_empty():
		return
	var kind := payload[0]
	var rest := payload.slice(1)
	if kind == 0:
		var c: Variant = JSON.parse_string(rest.get_string_from_utf8())
		if c is Dictionary:
			_mq_control(c)
		return
	var msg: Variant = bytes_to_var(rest)
	if not (msg is Dictionary):
		return
	if role == "host":
		if not _peer_tok.has(int(kind)):
			return
		_last_seen[int(kind)] = Time.get_ticks_msec()
		_deliver(int(kind), msg)
	else:
		_last_host = Time.get_ticks_msec()
		_deliver(1, msg)


func _mq_control(c: Dictionary) -> void:
	var op := String(c.get("op", ""))
	if role == "host":
		var tok := String(c.get("tok", ""))
		if op == "join" and tok != "":
			var fresh := not _tok_peer.has(tok)
			if fresh and _peer_tok.size() >= 19:
				_mq.publish(_base() + "p/" + tok, _ctl({"op": "error", "msg": "That game is full (20 players)."}))
				return
			if fresh:
				_tok_peer[tok] = _next_id
				_peer_tok[_next_id] = tok
				_next_id = _next_id + 1 if _next_id < 250 else 2
			var id := int(_tok_peer[tok])
			_last_seen[id] = Time.get_ticks_msec()
			_mq.publish(_base() + "p/" + tok, _ctl({"op": "welcome", "id": id, "room": room_code}))
			if fresh:
				peer_joined.emit(id)
		elif op == "bye" and _tok_peer.has(tok):
			_drop_peer(int(_tok_peer[tok]))
	else:
		match op:
			"welcome":
				if my_id == 0:
					my_id = int(c["id"])
					_last_host = Time.get_ticks_msec()
					joined.emit()
			"error":
				var why := String(c.get("msg", "Couldn't join."))
				leave()
				failed.emit(why)
			"host_left":
				if my_id != 0:
					_end("The host left the game.")


func _drop_peer(id: int) -> void:
	var tok := String(_peer_tok.get(id, ""))
	_peer_tok.erase(id)
	_tok_peer.erase(tok)
	_last_seen.erase(id)
	pings.erase(id)
	peer_left.emit(id)


## Quick chat: the host passes every phrase on to everyone.
func chat(index: int) -> void:
	if role == "host":
		send(0, {"t": "_chat", "from": 1, "m": index})
		chat_received.emit(1, CHAT[clampi(index, 0, CHAT.size() - 1)])
	elif my_id != 0:
		send(1, {"t": "_chat", "m": index})


## Every received game message passes through here; ping and chat stay inside.
func _deliver(from: int, msg: Dictionary) -> void:
	match String(msg.get("t", "")):
		"_chat":
			var i := clampi(int(msg.get("m", 0)), 0, CHAT.size() - 1)
			if role == "host":
				send(0, {"t": "_chat", "from": from, "m": i})
				chat_received.emit(from, CHAT[i])
			else:
				chat_received.emit(int(msg.get("from", 1)), CHAT[i])
			return
		"_ping":
			if role == "host":
				pings[from] = int(msg.get("rtt", -1))
				send(from, {"t": "_pong", "ts": msg.get("ts", 0)}, false)
			return
		"_pong":
			my_ping = Time.get_ticks_msec() - int(msg.get("ts", 0))
			return
	message.emit(from, msg)


# ------------------------------------------------------------ sending

## to_id: 1 = host, 0 = everyone else (host only), or a peer id (host only).
func send(to_id: int, msg: Dictionary, reliable := true) -> void:
	var bytes := var_to_bytes(msg)
	if _enet != null:
		_enet.set_target_peer(to_id)
		_enet.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
		_enet.set_transfer_channel(0 if reliable else 1)
		_enet.put_packet(bytes)
	elif _ws != null and _ws_open:
		var framed := PackedByteArray([to_id & 0xff])
		framed.append_array(bytes)
		_ws.send(framed, WebSocketPeer.WRITE_MODE_BINARY)
	elif _mq != null and _mq.is_ready() and my_id != 0:
		if role == "host":
			var framed := PackedByteArray([1])
			framed.append_array(bytes)
			if to_id == 0:
				_mq.publish(_base() + "c", framed)
			elif _peer_tok.has(to_id):
				_mq.publish(_base() + "p/" + String(_peer_tok[to_id]), framed)
		else:
			var framed := PackedByteArray([my_id & 0xff])
			framed.append_array(bytes)
			_mq.publish(_base() + "h", framed)


func leave() -> void:
	if _enet != null:
		_enet.close()
		_enet = null
	if _ws != null:
		_ws.close()
		_ws = null
	_ws_open = false
	if _mq != null:
		# A clean goodbye skips the broker's "last will", so say it ourselves.
		if _mq.is_ready() and my_id != 0:
			if role == "host":
				_mq.publish(_base() + "c", _ctl({"op": "host_left"}))
			else:
				_mq.publish(_base() + "h", _ctl({"op": "bye", "tok": _tok}))
		_mq.close()
		_mq = null
	_mq_events.clear()
	_peer_tok.clear()
	_tok_peer.clear()
	_last_seen.clear()
	_next_id = 2
	pings.clear()
	my_ping = -1
	if _beacon != null:
		_beacon.close()
		_beacon = null
	if _probe != null:
		_probe.close()
		_probe = null
	role = "offline"
	transport = ""
	my_id = 0
	room_code = ""
	_connect_timer = 0.0
	_pending_end = ""


func _end(reason: String) -> void:
	leave()
	closed.emit(reason)


# ------------------------------------------------------------ polling

func _process(delta: float) -> void:
	_poll_discovery(delta)
	if _enet != null:
		_poll_enet(delta)
	elif _ws != null:
		_poll_ws(delta)
	elif _mq != null:
		_poll_mq(delta)
	if role == "client" and my_id != 0:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 2.0
			send(1, {"t": "_ping", "ts": Time.get_ticks_msec(), "rtt": my_ping}, false)


func _poll_enet(delta: float) -> void:
	_enet.poll()
	if _pending_end != "":
		var why := _pending_end
		_pending_end = ""
		_end(why)
		return
	if role == "client" and my_id == 0:
		if _enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			my_id = _enet.get_unique_id()
			joined.emit()
		else:
			_connect_timer -= delta
			if _connect_timer <= 0.0:
				leave()
				failed.emit("No game answered at that address. Both phones must show the same first three numbers under Games nearby (e.g. 192.168.1.x). If they do, your router may block phones talking to each other: use one phone's hotspot instead.")
				return
	while _enet != null and _enet.get_available_packet_count() > 0:
		var from := _enet.get_packet_peer()
		var pkt := _enet.get_packet()
		var msg: Variant = bytes_to_var(pkt)
		if msg is Dictionary:
			_deliver(from, msg)
	if role == "host":
		_host_announce(delta)


func _poll_ws(delta: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _ws_open:
			_ws_open = true
			_ws.send_text(JSON.stringify(_hello))
		while _ws != null and _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				_control(JSON.parse_string(pkt.get_string_from_utf8()))
			elif pkt.size() > 1:
				var from := int(pkt[0])
				var msg: Variant = bytes_to_var(pkt.slice(1))
				if msg is Dictionary:
					_deliver(from, msg)
	elif st == WebSocketPeer.STATE_CLOSED:
		var was_in := my_id != 0
		var reason := "Lost connection to the online server." if was_in else "Couldn't reach the online server."
		leave()
		if was_in:
			closed.emit(reason)
		else:
			failed.emit(reason)
	elif my_id == 0:
		_connect_timer -= delta
		if _connect_timer <= 0.0:
			leave()
			failed.emit("The online server didn't answer. Try again in a minute.")


func _host_info() -> PackedByteArray:
	return JSON.stringify({"game": "apex-circuit", "name": host_name, "players": lobby_players}).to_utf8_buffer()


## Host: broadcast once a second (to everyone and to each network's own
## broadcast address) and answer joiners' probes directly.
func _host_announce(delta: float) -> void:
	if _probe != null:
		while _probe.get_available_packet_count() > 0:
			var pkt := _probe.get_packet()
			var ip := _probe.get_packet_ip()
			var port := _probe.get_packet_port()
			if pkt.get_string_from_utf8().contains("apex-circuit-probe"):
				_probe.set_dest_address(ip, port)
				_probe.put_packet(_host_info())
	if _beacon == null:
		return
	_beacon_timer -= delta
	if _beacon_timer > 0.0:
		return
	_beacon_timer = 1.0
	var targets := ["255.255.255.255"]
	for a in lan_addresses():
		targets.append(_subnet(a) + "255")
	for t in targets:
		_beacon.set_dest_address(t, BEACON_PORT)
		_beacon.put_packet(_host_info())


static func _subnet(ip: String) -> String:
	var p := ip.split(".")
	return "%s.%s.%s." % [p[0], p[1], p[2]] if p.size() == 4 else ""


## Joiner: ask every address on this phone's networks "are you hosting?".
## Direct (unicast) packets get through where broadcasts are filtered.
func _send_probes() -> void:
	var msg := "apex-circuit-probe".to_utf8_buffer()
	var targets := ["255.255.255.255"]
	for a in lan_addresses():
		var net := _subnet(a)
		targets.append(net + "255")
		for h in range(1, 255):
			targets.append(net + str(h))
	for t in targets:
		_listen.set_dest_address(t, PROBE_PORT)
		_listen.put_packet(msg)


## Relay control messages (text frames).
func _control(c: Variant) -> void:
	if not (c is Dictionary):
		return
	match String(c.get("op", "")):
		"welcome":
			my_id = int(c["id"])
			room_code = String(c.get("room", ""))
			joined.emit()
		"error":
			var why := String(c.get("msg", "Couldn't join."))
			leave()
			failed.emit(why)
		"peer_joined":
			peer_joined.emit(int(c["id"]))
		"peer_left":
			peer_left.emit(int(c["id"]))
		"host_left":
			_end("The host left the game.")


func _poll_discovery(delta: float) -> void:
	if _listen == null:
		return
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = 2.0
		_send_probes()
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var info: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if info is Dictionary and info.get("game", "") == "apex-circuit":
			if not _found.has(ip):
				changed = true
			_found[ip] = {"name": String(info.get("name", "Game")), "ip": ip, "players": int(info.get("players", 1)), "seen": 3.0}
	for ip in _found.keys():
		_found[ip]["seen"] -= delta
		if _found[ip]["seen"] <= 0.0:
			_found.erase(ip)
			changed = true
	if changed:
		games_found.emit(_found.values())
