extends Node
## Multiplayer connection (autoload "Net"). One phone hosts; others join.
##
## Two transports, same game protocol:
##   Wi-Fi / hotspot ("lan"): ENet straight between phones; hosts announce
##     themselves with a UDP broadcast so joiners see them in a list.
##   Online ("online"): every phone opens a WebSocket to a small relay server
##     (server/relay.js) and joins a room by its 4-letter code.
## Star topology either way: clients talk to the host (id 1), the host talks
## to everyone. Messages are Dictionaries (var_to_bytes, no objects).

signal peer_joined(id: int)
signal peer_left(id: int)
signal message(from_id: int, msg: Dictionary)
signal joined                       # client: connected and given an id
signal failed(reason: String)       # couldn't connect / room not found
signal closed(reason: String)       # session ended (host left, connection lost)
signal games_found(games: Array)    # LAN discovery: [{name, ip, players}]

const GAME_PORT := 47010
const BEACON_PORT := 47011
const DEFAULT_SERVER := "wss://apex-circuit-relay.onrender.com"

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
var _found := {}                    # ip -> {name, players, seen}
var _connect_timer := 0.0
var lobby_players := 0              # for the LAN beacon
var _pending_end := ""              # close after polling, never inside a callback


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
	_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	return true


func join_lan(ip: String) -> void:
	leave()
	_enet = ENetMultiplayerPeer.new()
	if _enet.create_client(ip.strip_edges(), GAME_PORT) != OK:
		_enet = null
		failed.emit("Couldn't reach %s." % ip)
		return
	_enet.peer_disconnected.connect(func(id: int):
		if id == 1:
			_pending_end = "The host left the game.")
	role = "client"
	transport = "lan"
	_connect_timer = 8.0


## This phone's address on the local network (what joiners can type in).
func local_ip() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
		best = a
	return best


## Start listening for hosts on the same Wi-Fi (games_found is emitted).
func start_discovery() -> void:
	stop_discovery()
	_listen = PacketPeerUDP.new()
	_listen.bind(BEACON_PORT)
	_found.clear()


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


func leave() -> void:
	if _enet != null:
		_enet.close()
		_enet = null
	if _ws != null:
		_ws.close()
		_ws = null
	_ws_open = false
	if _beacon != null:
		_beacon.close()
		_beacon = null
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
				failed.emit("No game found at that address. Check you're on the same Wi-Fi.")
				return
	while _enet != null and _enet.get_available_packet_count() > 0:
		var from := _enet.get_packet_peer()
		var pkt := _enet.get_packet()
		var msg: Variant = bytes_to_var(pkt)
		if msg is Dictionary:
			message.emit(from, msg)
	if role == "host" and _beacon != null:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = 1.0
			var info := {"game": "apex-circuit", "name": host_name, "players": lobby_players}
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())


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
					message.emit(from, msg)
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
