extends Node
## The online leaderboard (autoload "Board"): every lap anyone drives goes to
## the game's database (Supabase, server/leaderboard.sql), with the ghost of
## each new best time-trial lap; the game reads back the world's top ten on a
## track in a car, your place among everyone, and any leaderboard lap's ghost
## to race.
##
## Laps wait in a queue on the phone (user://lap_queue.json) and go up in
## batches when there's a connection, so nothing's lost offline. Nothing
## personal is sent: a random id made on this phone, the name you race
## under, and the phone's model and the app's version. Off with the
## "share_laps" setting (Settings > Online leaderboard).
##
## The database's address and public key are in data/online.json; with none
## there the game simply plays offline.

signal posted(kept: int)

const CONFIG := "res://data/online.json"
const QUEUE := "user://lap_queue.json"
const QUEUE_MAX := 400          # laps kept waiting while offline (oldest go first; best laps last)
const BATCH := 20
const RETRY := 30.0             # seconds between tries when the server can't be reached
const TIMEOUT := 12.0
const SEND_HZ := 10.0           # ghost samples a second (scripts/ghost_share.gd)

var url := ""
var key := ""
var _queue: Array = []
var _sending := 0               # laps in the request in flight
var _wait := 2.0
var _http: HTTPRequest


func _ready() -> void:
	if FileAccess.file_exists(CONFIG):
		var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if cfg is Dictionary:
			url = String(cfg.get("url", "")).strip_edges().trim_suffix("/")
			key = String(cfg.get("key", "")).strip_edges()
	if FileAccess.file_exists(QUEUE):
		var q: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUEUE))
		if q is Array:
			_queue = q
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_sent)


## Whether there's a leaderboard to talk to.
func configured() -> bool:
	return url != "" and key != ""


## Whether this player's laps go up (the setting; on unless turned off).
func sharing() -> bool:
	var save := _save()
	return configured() and (save == null or bool(save.get_setting("share_laps")))


## This phone's random id (made once, kept in the save).
func player_id() -> String:
	var save := _save()
	if save == null:
		return ""
	var id := String(save.get_setting("online_id"))
	if id.length() != 36:
		id = _uuid()
		save.set_setting("online_id", id)
	return id


func nickname() -> String:
	var save := _save()
	if save == null:
		return "Driver"
	var n := String(save.data.get("driver", {}).get("name", ""))
	if n == "":
		n = String(save.get_setting("player_name"))
	return n if n != "" else "Driver"


## A lap to send. `lap` has track, car, mode, ranked, lap_ms and whatever
## else is known (sectors, weather, assists, setup); `ghost` is race.gd's
## samples at `hz` for a best time-trial lap (or empty).
func post_lap(lap: Dictionary, ghost := PackedFloat32Array(), hz := 20.0) -> void:
	if not sharing():
		return
	var row := lap.duplicate()
	row["player_id"] = player_id()
	row["nickname"] = nickname()
	row["app_version"] = String(ProjectSettings.get_setting("application/config/version", "?"))
	row["platform"] = OS.get_name()
	row["device"] = OS.get_model_name().substr(0, 80)
	if ghost.size() > 14 * 7:
		var info := {"track": lap["track"], "car": lap["car"], "lap_ms": lap["lap_ms"], "name": row["nickname"]}
		var save := _save()
		if save != null:
			info["team"] = int(save.get_setting("team"))
			info["paint"] = save.my_paint(String(lap["car"]))
		row["ghost"] = Marshalls.raw_to_base64(GhostShare.pack(ghost, hz, info))
		row["ghost_samples"] = ghost_count(ghost.size() / 7, hz)
	_queue.append(row)
	while _queue.size() > QUEUE_MAX:
		# Keep the laps with ghosts (the bests); drop the oldest of the rest.
		var drop := 0
		for i in _queue.size():
			if not (_queue[i] as Dictionary).has("ghost"):
				drop = i
				break
		_queue.remove_at(drop)
	_save_queue()
	_wait = minf(_wait, 1.0)


## How many samples GhostShare.pack keeps of n at hz.
static func ghost_count(n: int, hz: float) -> int:
	var step := hz / SEND_HZ
	return int(floor((n - 1) / step)) + 1


func _process(delta: float) -> void:
	if _sending > 0 or _queue.is_empty() or not configured():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	var batch := _queue.slice(0, BATCH)
	var err := _http.request(url + "/rest/v1/rpc/submit_laps", _headers(), HTTPClient.METHOD_POST, JSON.stringify({"p_laps": batch}))
	if err != OK:
		_wait = RETRY
		return
	_sending = batch.size()


func _on_sent(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	var n := _sending
	_sending = 0
	if result != HTTPRequest.RESULT_SUCCESS or code == 0 or code >= 500 or code in [401, 403, 404, 429]:
		_wait = RETRY      # offline, the server's busy, or it isn't set up yet: try again later
		return
	# Sent (or turned away for good: a bad request won't get better by sending it again).
	_queue = _queue.slice(n)
	_save_queue()
	_wait = 0.5
	if code >= 200 and code < 300:
		posted.emit(int(str_to_var(body.get_string_from_utf8())) if body.size() > 0 else 0)
	else:
		push_warning("Leaderboard turned %d laps away (%d): %s" % [n, code, body.get_string_from_utf8().substr(0, 200)])


func _save_queue() -> void:
	var f := FileAccess.open(QUEUE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_queue))


## Laps waiting to go up.
func pending() -> int:
	return _queue.size()


# ------------------------------------------------------------ reading

## The world's top `limit` on a track in a car: done(rows) with rows of
## {lap_id, nickname, lap_ms, sectors, weather, set_at, has_ghost, mine},
## or done(null) when it can't be reached.
func top(track_id: String, car_id: String, done: Callable, limit := 10) -> void:
	_call("leaderboard", {"p_track": track_id, "p_car": car_id, "p_me": player_id(), "p_limit": limit}, func(ok: bool, v: Variant):
		done.call(v if ok and v is Array else null))


## Your place: done({rank, total, best_ms}), done({}) with no time set
## there yet, or done(null) when it can't be reached.
func rank(track_id: String, car_id: String, done: Callable) -> void:
	_call("my_rank", {"p_track": track_id, "p_car": car_id, "p_me": player_id()}, func(ok: bool, v: Variant):
		if not ok or not (v is Array):
			done.call(null)
		elif (v as Array).is_empty():
			done.call({})
		else:
			done.call(v[0]))


## A leaderboard lap to race as a ghost: done(challenge) - the same as a
## friend's ghost code gives (scripts/ghost_share.gd) - or done({}).
func ghost(lap_id: int, done: Callable) -> void:
	_call("get_ghost", {"p_lap": lap_id}, func(ok: bool, v: Variant):
		if not ok or not (v is Array) or (v as Array).is_empty():
			done.call({})
			return
		var row: Dictionary = v[0]
		var ch := GhostShare.unpack(Marshalls.base64_to_raw(String(row.get("ghost", ""))), 20.0)
		if ch.is_empty():
			done.call({})
			return
		ch["track"] = String(row["track"])
		ch["car"] = String(row["car"])
		ch["lap_ms"] = int(row["lap_ms"])
		ch["name"] = String(row["nickname"])
		done.call(ch))


## Calls a database function: done(ok, result).
func _call(fn: String, args: Dictionary, done: Callable) -> void:
	if not configured():
		done.call_deferred(false, null)
		return
	var h := HTTPRequest.new()
	h.timeout = TIMEOUT
	add_child(h)
	h.request_completed.connect(func(result: int, code: int, _hd: PackedStringArray, body: PackedByteArray):
		h.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			done.call(false, null)
			return
		done.call(true, JSON.parse_string(body.get_string_from_utf8())))
	if h.request(url + "/rest/v1/rpc/" + fn, _headers(), HTTPClient.METHOD_POST, JSON.stringify(args)) != OK:
		h.queue_free()
		done.call_deferred(false, null)


func _headers() -> PackedStringArray:
	var h := PackedStringArray(["Content-Type: application/json", "apikey: " + key])
	# (The older "anon" keys are tokens and go here too; the newer
	# "publishable" keys go only in apikey.)
	if key.begins_with("eyJ"):
		h.append("Authorization: Bearer " + key)
	return h


func _save() -> Node:
	return get_node_or_null("/root/Save")


static func _uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var b := PackedByteArray()
	for i in 16:
		b.append(rng.randi() & 0xff)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var hx := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [hx.substr(0, 8), hx.substr(8, 4), hx.substr(12, 4), hx.substr(16, 4), hx.substr(20, 12)]
