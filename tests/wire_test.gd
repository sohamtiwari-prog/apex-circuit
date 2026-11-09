extends SceneTree
## What goes over the network: a car's state survives packing (position to
## the centimetre, rotation, speed, inputs, tyres and pit stop), its slowly
## changing part only goes when it changes (and is remembered in between),
## and a 20-car update stays small.
##   godot --headless --script res://tests/wire_test.gd

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)


func _state(i: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-PI, PI), rng.randf_range(-0.2, 0.2)))
	var q := b.get_rotation_quaternion()
	var v := b * Vector3(rng.randf_range(-3, 3), rng.randf_range(-2, 2), rng.randf_range(0, 95))
	return PackedFloat32Array([rng.randf_range(-3000, 3000), rng.randf_range(-50, 150), rng.randf_range(-3000, 3000),
		q.x, q.y, q.z, q.w, v.x, v.y, v.z, rng.randf_range(-0.5, 0.5), rng.randf_range(3000, 15000), i % 9, rng.randf(), i % 2,
		rng.randf(), i % 5, rng.randf(), i % 4, (i + 1) % 5, 5.0, 10.0, i % 3, i % 4, rng.randf_range(-1.5, 1.5)])


func _run() -> void:
	var net: Node = load("res://scripts/net_race.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var cars := {}
	for i in 20:
		cars[i] = _state(i, rng)
	var buf := StreamPeerBuffer.new()
	buf.put_double(123.456); buf.put_float(30.0); buf.put_u8(1); buf.put_float(0.0)
	net._pack_cars(buf, cars)
	var first: int = var_to_bytes({"t": "s", "b": buf.data_array}).size()
	var buf2 := StreamPeerBuffer.new()
	buf2.put_double(123.506); buf2.put_float(30.05); buf2.put_u8(1); buf2.put_float(0.0)
	net._pack_cars(buf2, cars)
	net._pack_cars(StreamPeerBuffer.new(), cars)
	net._pack_cars(StreamPeerBuffer.new(), cars)
	var buf5 := StreamPeerBuffer.new()
	buf5.put_double(123.656); buf5.put_float(30.2); buf5.put_u8(1); buf5.put_float(0.0)
	net._pack_cars(buf5, cars)
	var steady: int = var_to_bytes({"t": "s", "b": buf5.data_array}).size()
	print("    a 20-car update: %d bytes with every car's tyres and pit stop, %d bytes once they've gone out" % [first, steady])
	_check(first < 800 and steady < 560, "a 20-car update is small (%d / %d bytes; it was 2408, then 1068)" % [first, steady])
	# Read back: the first update (everything) then the later one (fast part
	# only: the slow part remembered).
	var known := {}
	var rb := StreamPeerBuffer.new()
	rb.data_array = buf.data_array
	_check(is_equal_approx(rb.get_double(), 123.456), "the update's time comes through")
	rb.get_float(); rb.get_u8(); rb.get_float()
	var got: Dictionary = NetRace.unpack_states(rb, known)
	var rb5 := StreamPeerBuffer.new()
	rb5.data_array = buf5.data_array
	rb5.get_double(); rb5.get_float(); rb5.get_u8(); rb5.get_float()
	var got5: Dictionary = NetRace.unpack_states(rb5, known)
	_check(got.size() == 20 and got5.size() == 20, "every car comes through (%d, %d)" % [got.size(), got5.size()])
	var worst_p := 0.0
	var worst_a := 0.0
	var worst_v := 0.0
	var inputs_ok := true
	var slow_ok := true
	for i in 20:
		var s: PackedFloat32Array = cars[i]
		for g in [got[i], got5[i]]:
			var r: PackedFloat32Array = g
			worst_p = maxf(worst_p, Vector3(s[0], s[1], s[2]).distance_to(Vector3(r[0], r[1], r[2])))
			worst_a = maxf(worst_a, Quaternion(s[3], s[4], s[5], s[6]).normalized().angle_to(Quaternion(r[3], r[4], r[5], r[6])))
			worst_v = maxf(worst_v, Vector3(s[7], s[8], s[9]).distance_to(Vector3(r[7], r[8], r[9])))
			inputs_ok = inputs_ok and absf(s[10] - r[10]) < 0.01 and absf(s[11] - r[11]) <= 32.0 and int(s[12]) == int(r[12]) \
				and absf(s[13] - r[13]) < 0.04 and int(s[14]) == int(r[14]) and absf(s[15] - r[15]) < 0.04 and absf(s[24] - r[24]) < 0.02
			slow_ok = slow_ok and int(r[16]) == int(s[16]) and absf(r[17] - s[17]) < 0.001 and int(r[18]) == int(s[18]) \
				and int(r[19]) == int(s[19]) and is_equal_approx(r[20], s[20]) and is_equal_approx(r[21], s[21]) and int(r[22]) == int(s[22]) and int(r[23]) == int(s[23])
	_check(worst_p < 0.01, "position to the centimetre (worst %.4f m)" % worst_p)
	_check(worst_a < 0.01, "rotation within half a degree (worst %.2f deg)" % rad_to_deg(worst_a))
	_check(worst_v < 0.06, "speed within 6 cm/s (worst %.3f m/s)" % worst_v)
	_check(inputs_ok, "steering, revs, gear, pedals, DRS and yaw rate come through")
	_check(slow_ok, "tyres, wear, pit stop and penalties come through, and are remembered between")
	# A change in the slow part goes out at once.
	var s3: PackedFloat32Array = cars[3]
	s3[18] = 2.0
	cars[3] = s3
	var bc := StreamPeerBuffer.new()
	net._pack_cars(bc, cars)
	bc.seek(0)
	var after: Dictionary = NetRace.unpack_states(bc, known)
	_check(int(after[3][18]) == 2, "a pit stop starting goes out in the next update")
	net.free()
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
