class_name MqttLink
extends RefCounted
## Minimal MQTT 3.1.1 client over WebSocket (QoS 0), enough to use a public
## broker as a message relay for online races: connect (with a "last will"
## the broker sends if we vanish), subscribe to exact topics, publish.

signal ready                                   # CONNACK accepted
signal message(topic: String, payload: PackedByteArray)
signal closed(reason: String)

var keepalive := 15                            # seconds
var _ws: WebSocketPeer
var _buf := PackedByteArray()
var _sent_connect := false
var _ready := false
var _done := false
var _ping := 0.0
var _pid := 1
var _cid := ""
var _will_topic := ""
var _will_payload := PackedByteArray()


func open(url: String, client_id: String, will_topic := "", will_payload := PackedByteArray()) -> bool:
	_ws = WebSocketPeer.new()
	_ws.supported_protocols = PackedStringArray(["mqtt"])
	_ws.outbound_buffer_size = 1 << 20
	_ws.inbound_buffer_size = 1 << 20
	_cid = client_id
	_will_topic = will_topic
	_will_payload = will_payload
	return _ws.connect_to_url(url) == OK


func is_ready() -> bool:
	return _ready and not _done


func poll(delta: float) -> void:
	if _ws == null or _done:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _sent_connect:
			_sent_connect = true
			_send(_connect_packet())
		while _ws.get_available_packet_count() > 0:
			_buf.append_array(_ws.get_packet())
		_parse()
		if _ready:
			_ping += delta
			if _ping > keepalive * 0.5:
				_ping = 0.0
				_send(PackedByteArray([0xC0, 0x00]))      # PINGREQ
	elif st == WebSocketPeer.STATE_CLOSED:
		_finish("closed (%d)" % _ws.get_close_code())


func subscribe(topic: String) -> void:
	var body := PackedByteArray()
	body.append((_pid >> 8) & 0xff)
	body.append(_pid & 0xff)
	_pid = _pid % 65535 + 1
	body.append_array(_str(topic))
	body.append(0)                                 # QoS 0
	_send(_packet(0x82, body))


func publish(topic: String, payload: PackedByteArray) -> void:
	if not _ready:
		return
	var body := _str(topic)
	body.append_array(payload)
	_send(_packet(0x30, body))


## Clean goodbye: the broker does NOT send the last will.
func close() -> void:
	if _ws != null and not _done:
		if _ready:
			_send(PackedByteArray([0xE0, 0x00]))
		_ws.close()
	_done = true
	_ready = false


# ------------------------------------------------------------ encoding

func _connect_packet() -> PackedByteArray:
	var body := _str("MQTT")
	body.append(4)                                 # protocol level 3.1.1
	var flags := 0x02                              # clean session
	if _will_topic != "":
		flags |= 0x04                              # will flag, QoS 0, no retain
	body.append(flags)
	body.append((keepalive >> 8) & 0xff)
	body.append(keepalive & 0xff)
	body.append_array(_str(_cid))
	if _will_topic != "":
		body.append_array(_str(_will_topic))
		body.append((_will_payload.size() >> 8) & 0xff)
		body.append(_will_payload.size() & 0xff)
		body.append_array(_will_payload)
	return _packet(0x10, body)


static func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var out := PackedByteArray([(b.size() >> 8) & 0xff, b.size() & 0xff])
	out.append_array(b)
	return out


static func _packet(header: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([header])
	var n := body.size()
	while true:
		var d := n % 128
		n /= 128
		if n > 0:
			d |= 0x80
		out.append(d)
		if n == 0:
			break
	out.append_array(body)
	return out


func _send(bytes: PackedByteArray) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


# ------------------------------------------------------------ decoding

func _parse() -> void:
	while _buf.size() >= 2:
		var mult := 1
		var length := 0
		var i := 1
		var complete := false
		while i < _buf.size() and i <= 4:
			var d := _buf[i]
			length += (d & 0x7f) * mult
			mult *= 128
			i += 1
			if d & 0x80 == 0:
				complete = true
				break
		if not complete or _buf.size() < i + length:
			return                                  # wait for the rest
		var head := _buf[0]
		var body := _buf.slice(i, i + length)
		_buf = _buf.slice(i + length)
		_handle(head, body)
		if _done:
			return


func _handle(head: int, body: PackedByteArray) -> void:
	match head >> 4:
		2:                                         # CONNACK
			if body.size() >= 2 and body[1] == 0:
				_ready = true
				ready.emit()
			else:
				_finish("refused (%d)" % (body[1] if body.size() >= 2 else -1))
		3:                                         # PUBLISH
			var qos := (head >> 1) & 3
			var tl := (body[0] << 8) | body[1]
			var topic := body.slice(2, 2 + tl).get_string_from_utf8()
			var start := 2 + tl + (2 if qos > 0 else 0)
			message.emit(topic, body.slice(start))
		_:
			pass                                   # SUBACK, PINGRESP


func _finish(reason: String) -> void:
	if _done:
		return
	_done = true
	_ready = false
	closed.emit(reason)
