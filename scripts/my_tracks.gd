class_name MyTracks
extends RefCounted
## Tracks you draw yourself (scripts/track_builder.gd), raced like any other.
##
## A track is a loop of control points (metres, on a 2 m grid) plus a few
## choices: scenery, time of day, how hilly, how wide. Track.build() turns it
## into a circuit the same way as the real ones: smooth centreline, racing
## line, kerbs, barriers, pit lane, grandstands, and a landscape made for it.
##
## They're kept in the profile ("my_tracks"), so a backup code carries them.
## A track travels as a short code (APX1-...), which also gives its id: the
## same shape, width and hills are the same id on every phone, so a friend
## racing your track has their laps, and your shared ghost, on the same key.

const PREFIX := "APX1-"
const STYLES := ["park", "forest", "desert", "city"]
const STYLE_NAMES := {"park": "Parkland", "forest": "Forest", "desert": "Desert", "city": "Street circuit"}
const TODS := ["day", "sunset", "night"]
const TOD_NAMES := {"day": "Daytime", "sunset": "Sunset", "night": "Night race"}
const HILL_NAMES := ["Flat", "Gentle hills", "Rolling hills", "Mountain"]
## Road half-widths (m): kart-narrow, a club circuit, a Grand Prix track.
const WIDTHS := [4.6, 6.5, 7.5]
const WIDTH_NAMES := ["Narrow", "Standard", "Wide"]
## Height of the hills the road runs over (m, either way), per HILL_NAMES.
const HILL_AMP := [0.0, 4.0, 9.0, 16.0]
const MIN_LEN := 700.0
const MAX_LEN := 8000.0
const MAX_POINTS := 160
## The area you draw in (m): what the builder's map shows.
const AREA := Vector2(2400, 1350)

## Tracks loaded but not saved (one opened from a code, or being test-driven
## from the builder): id -> track. Track.build() finds them here too.
static var extra := {}
## Racing lines worked out this session: id -> PackedFloat32Array.
static var lines := {}


static func is_mine(id: String) -> bool:
	return id.begins_with("my_")


static func _save() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Save") if tree != null else null


## Every saved track, newest first.
static func all() -> Array:
	var sv := _save()
	if sv == null:
		return []
	if not sv.data.has("my_tracks") or typeof(sv.data["my_tracks"]) != TYPE_ARRAY:
		sv.data["my_tracks"] = []
	return sv.data["my_tracks"]


static func ids() -> Array:
	var out := []
	for t in all():
		out.append(String(t["id"]))
	return out


static func get_track(id: String) -> Dictionary:
	if extra.has(id):
		return extra[id]
	for t in all():
		if String(t["id"]) == id:
			return t
	return {}


static func has_track(id: String) -> bool:
	return not get_track(id).is_empty()


## Saves `t` (new, or over the one with its id). Returns its id.
static func store(t: Dictionary) -> String:
	t["id"] = make_id(t)
	var list := all()
	for k in list.size():
		if String(list[k]["id"]) == String(t["id"]):
			list[k] = t
			_flush()
			return t["id"]
	list.push_front(t)
	_flush()
	return t["id"]


static func remove(id: String) -> void:
	var list := all()
	for k in range(list.size() - 1, -1, -1):
		if String(list[k]["id"]) == id:
			list.remove_at(k)
	_flush()


static func _flush() -> void:
	var sv := _save()
	if sv != null:
		sv.save()


## What the menus show for it, shaped like a Track.CATALOG entry.
static func entry(id: String) -> Dictionary:
	var t := get_track(id)
	if t.is_empty():
		return {}
	var style := String(t.get("style", "park"))
	var tod := String(t.get("tod", "day"))
	return {"id": id, "name": String(t.get("name", "My track")),
		"desc": "Your track · %s · %s" % [STYLE_NAMES.get(style, "Parkland"), String(HILL_NAMES[clampi(int(t.get("hills", 0)), 0, 3)]).to_lower()],
		"style": style, "night": tod == "night", "tod": tod, "custom": true}


static func half_width(t: Dictionary) -> float:
	return float(WIDTHS[clampi(int(t.get("width", 1)), 0, WIDTHS.size() - 1)])


## Barriers: close on a street circuit, run-off elsewhere.
static func wall_offset(t: Dictionary) -> float:
	var hw := half_width(t)
	if String(t.get("style", "park")) == "city":
		return hw + 3.6
	return hw + (6.5 if hw < 5.0 else 13.0)


static func control(t: Dictionary) -> Array:
	var out := []
	for c in t.get("ctrl", []):
		out.append(Vector2(float(c[0]), float(c[1])))
	return out


# ------------------------------------------------------------ codes

## The part of a code that decides how the track drives (its id).
static func _shape_bytes(t: Dictionary) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(clampi(int(t.get("width", 1)), 0, 255))
	b.append(clampi(int(t.get("hills", 0)), 0, 255))
	var seed := int(t.get("seed", 0)) & 0xffff
	b.append(seed & 255)
	b.append(seed >> 8)
	var pts: Array = t.get("ctrl", [])
	b.append(mini(pts.size(), 255))
	var prev := Vector2i.ZERO
	for k in mini(pts.size(), 255):
		var q := Vector2i(int(round(float(pts[k][0]) / 2.0)), int(round(float(pts[k][1]) / 2.0)))
		if k == 0:
			var tmp := PackedByteArray()
			tmp.resize(4)
			tmp.encode_s16(0, q.x)
			tmp.encode_s16(2, q.y)
			b.append_array(tmp)
		else:
			var d := q - prev
			b.append(clampi(d.x, -127, 127) & 255)
			b.append(clampi(d.y, -127, 127) & 255)
		prev = q
	return b


static func make_id(t: Dictionary) -> String:
	return "my_" + _shape_bytes(t).hex_encode().md5_text().substr(0, 10)


static func encode(t: Dictionary) -> String:
	var b := PackedByteArray()
	b.append(1)
	b.append(maxi(STYLES.find(String(t.get("style", "park"))), 0))
	b.append(maxi(TODS.find(String(t.get("tod", "day"))), 0))
	var nm := String(t.get("name", "")).to_utf8_buffer()
	if nm.size() > 40:
		nm = nm.slice(0, 40)
	b.append(nm.size())
	b.append_array(nm)
	b.append_array(_shape_bytes(t))
	return PREFIX + Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").replace("=", "")


## A track from a code (also finds a code inside a longer message, or a
## link with ?track=). {} if there isn't a whole one.
static func decode(text: String) -> Dictionary:
	var s := text.strip_edges()
	var at := s.find(PREFIX)
	if at < 0:
		at = s.find("track=")
		if at < 0:
			return {}
		s = PREFIX + s.substr(at + 6)
		at = 0
	s = s.substr(at + PREFIX.length())
	var body := ""
	for ch in s:
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_":
			body += ch
		else:
			break
	if body.length() % 4 == 1 or body.length() < 12:
		return {}
	body = body.replace("-", "+").replace("_", "/")
	while body.length() % 4 != 0:
		body += "="
	var b := Marshalls.base64_to_raw(body)
	if b.size() < 10 or b[0] != 1:
		return {}
	var t := {}
	t["style"] = STYLES[clampi(b[1], 0, STYLES.size() - 1)]
	t["tod"] = TODS[clampi(b[2], 0, TODS.size() - 1)]
	var nl: int = b[3]
	var o := 4 + nl
	if b.size() < o + 5 + 4:
		return {}
	t["name"] = b.slice(4, o).get_string_from_utf8()
	t["width"] = clampi(b[o], 0, WIDTHS.size() - 1)
	t["hills"] = clampi(b[o + 1], 0, HILL_AMP.size() - 1)
	t["seed"] = b[o + 2] | (b[o + 3] << 8)
	var n: int = b[o + 4]
	o += 5
	if n < 4 or b.size() < o + 4 + (n - 1) * 2:
		return {}
	var q := Vector2i(b.decode_s16(o), b.decode_s16(o + 2))
	o += 4
	var pts := [[q.x * 2, q.y * 2]]
	for k in n - 1:
		var dx: int = b[o]
		var dz: int = b[o + 1]
		o += 2
		q += Vector2i(dx - 256 if dx > 127 else dx, dz - 256 if dz > 127 else dz)
		pts.append([q.x * 2, q.y * 2])
	t["ctrl"] = pts
	if String(t["name"]).strip_edges() == "":
		t["name"] = "Shared track"
	t["id"] = make_id(t)
	return t


## The message that goes with a shared track.
static func share_text(t: Dictionary, km: float) -> String:
	var code := encode(t)
	return "Race my track \"%s\" (%.2f km) in Apex Circuit!\n\nTap to open it: %s?track=%s\n\nIn the Android app: copy this message, open Track builder and tap Paste a code.\n%s" % [
		String(t.get("name", "My track")), km, WebBridge.SITE, code.substr(PREFIX.length()), code]


# ------------------------------------------------------------ checking

## Points along the loop as drawn (a smooth curve through the control
## points, sampled every `step` metres), flat.
static func sample(ctrl: Array, step := 4.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	if n < 3:
		return out
	var curve := Curve3D.new()
	curve.bake_interval = step
	for i in range(n + 1):
		var p: Vector2 = ctrl[i % n]
		var pv: Vector2 = ctrl[(i - 1 + n) % n]
		var nx: Vector2 = ctrl[(i + 1) % n]
		var h: Vector2 = (nx - pv) * 0.2
		curve.add_point(Vector3(p.x, 0, p.y), Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, h.y))
	var length := curve.get_baked_length()
	var count := maxi(int(round(length / step)), 3)
	for k in count:
		var b := curve.sample_baked(k * length / count, true)
		out.append(Vector2(b.x, b.z))
	return out


static func length_of(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in pts.size():
		total += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return total


## What's wrong with a layout, if anything: [{"kind", "at": Vector2, "text"}].
## kind: "short", "long", "cross" (it runs into itself), "close" (two bits
## of track too close side by side), "tight" (a corner tighter than a car
## can turn).
static func problems(ctrl: Array, width := 1) -> Array:
	var out := []
	if ctrl.size() < 4:
		return [{"kind": "short", "at": Vector2.ZERO, "text": "Draw a loop: start and finish in the same place."}]
	var step := 4.0
	var pts := sample(ctrl, step)
	var n := pts.size()
	var length := length_of(pts)
	if length < MIN_LEN:
		out.append({"kind": "short", "at": pts[0], "text": "Too short: %.2f km. Make it at least %.1f km." % [length / 1000.0, MIN_LEN / 1000.0]})
	if length > MAX_LEN:
		out.append({"kind": "long", "at": pts[0], "text": "Too long: %.1f km. Keep it under %.0f km." % [length / 1000.0, MAX_LEN / 1000.0]})
	var hw := float(WIDTHS[clampi(width, 0, WIDTHS.size() - 1)])
	# Corners: the radius over ~12 m of road.
	var min_r := maxf(9.0, hw * 1.7)
	var k := 3
	var worst := INF
	var worst_at := Vector2.ZERO
	for i in n:
		var a := pts[(i - k + n) % n]
		var b := pts[i]
		var c := pts[(i + k) % n]
		var t1 := (b - a).normalized()
		var t2 := (c - b).normalized()
		var ang := absf(atan2(t1.cross(t2), t1.dot(t2)))
		var r := (k * step) / maxf(ang, 0.0001)
		if r < worst:
			worst = r
			worst_at = b
	if worst < min_r:
		out.append({"kind": "tight", "at": worst_at, "text": "A corner is too tight to drive. Round it off a little."})
	# Crossings and stretches too close together (a grid, so it's quick).
	var gap := 2.0 * hw + 7.0
	var cell := gap
	var grid := {}
	for i in n:
		var key := Vector2i(int(floor(pts[i].x / cell)), int(floor(pts[i].y / cell)))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var found_cross := false
	for i in n:
		var a1 := pts[i]
		var a2 := pts[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var b1 := pts[j]
			var b2 := pts[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
				out.append({"kind": "cross", "at": a1, "text": "The track runs into itself. Bridges aren't possible here: move one part away."})
				found_cross = true
				break
		if found_cross:
			break
	if not found_cross:
		for i in n:
			var key := Vector2i(int(floor(pts[i].x / cell)), int(floor(pts[i].y / cell)))
			var hit := false
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for j in grid.get(key + Vector2i(dx, dz), []):
						var arc := absi(int(j) - i)
						arc = mini(arc, n - arc)
						var d := pts[i].distance_to(pts[j])
						# Close in space, but a long way apart round the lap.
						if d < gap and arc * step > d * 3.0 + 40.0:
							hit = true
							break
					if hit:
						break
				if hit:
					break
			if hit:
				out.append({"kind": "close", "at": pts[i], "text": "Two parts of the track are too close side by side. Pull them apart."})
				break
	# The worst first: running into itself, then side by side, then the rest.
	var order := {"cross": 0, "close": 1, "tight": 2, "short": 3, "long": 4}
	out.sort_custom(func(a, b): return int(order[a["kind"]]) < int(order[b["kind"]]))
	return out


# ------------------------------------------------------------ drawing

## A freehand trace (screen-free: metres) to control points: closed up,
## smoothed, then a point about every `spacing` metres (more in the bends).
static func from_trace(trace: PackedVector2Array, spacing := 70.0) -> Array:
	if trace.size() < 8:
		return []
	# Even steps along the trace.
	var even := PackedVector2Array()
	var step := 6.0
	even.append(trace[0])
	var carry := 0.0
	for i in range(1, trace.size() + 1):
		var a := trace[i - 1]
		var b := trace[i % trace.size()]
		var seg := a.distance_to(b)
		var t := step - carry
		while t <= seg:
			even.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	var n := even.size()
	if n < 12:
		return []
	# Smooth (a closed loop: wraps round).
	for _pass in 6:
		var sm := PackedVector2Array()
		sm.resize(n)
		for i in n:
			sm[i] = (even[(i - 2 + n) % n] + even[(i - 1 + n) % n] * 2.0 + even[i] * 3.0 + even[(i + 1) % n] * 2.0 + even[(i + 2) % n]) / 9.0
		even = sm
	# Keep a point every `spacing` metres, closer where it bends.
	var out := []
	var since := 0.0
	var turned := 0.0
	for i in n:
		var p := even[i]
		if i == 0:
			out.append(p)
			continue
		since += p.distance_to(even[i - 1])
		var t1 := (even[i] - even[i - 1]).normalized()
		var t2 := (even[(i + 1) % n] - even[i]).normalized()
		turned += absf(t1.angle_to(t2))
		if since >= spacing or (turned > 0.7 and since > 18.0):
			out.append(p)
			since = 0.0
			turned = 0.0
	# (The last point mustn't sit on top of the first.)
	while out.size() > 3 and (out[-1] as Vector2).distance_to(out[0]) < spacing * 0.4:
		out.pop_back()
	var snapped := []
	for p in out:
		snapped.append(Vector2(round(p.x / 2.0) * 2.0, round(p.y / 2.0) * 2.0))
	return snapped


## Starting shapes, in metres (centred on 0, 0).
static func template(kind: String) -> Array:
	var raw: Array
	match kind:
		"oval":
			raw = []
			for k in 16:
				var a := TAU * k / 16.0
				raw.append(Vector2(cos(a) * 520.0, sin(a) * 260.0))
			# Flatten the sides into straights.
			for k in raw.size():
				var p: Vector2 = raw[k]
				raw[k] = Vector2(clampf(p.x * 1.25, -560.0, 560.0), p.y)
		"kidney":
			raw = [Vector2(-500, 220), Vector2(-150, 260), Vector2(200, 250), Vector2(470, 200), Vector2(560, 60),
				Vector2(500, -100), Vector2(320, -160), Vector2(150, -60), Vector2(-20, -40), Vector2(-160, -170),
				Vector2(-380, -230), Vector2(-560, -130), Vector2(-600, 60)]
		"club":
			raw = []
			for v in Track.KESTREL_LAYOUT:
				raw.append(Vector2(v.x - 125.0, v.y - 240.0))
		_:  # "gp": long straights, a hairpin, esses, a fast sweep
			raw = [Vector2(-700, 300), Vector2(-300, 300), Vector2(100, 300), Vector2(480, 300), Vector2(620, 240),
				Vector2(640, 120), Vector2(560, 60), Vector2(420, 80), Vector2(320, 20), Vector2(340, -90),
				Vector2(480, -160), Vector2(640, -230), Vector2(700, -330), Vector2(600, -400), Vector2(380, -380),
				Vector2(150, -330), Vector2(-60, -280), Vector2(-200, -170), Vector2(-150, -60), Vector2(-260, 20),
				Vector2(-450, -20), Vector2(-620, -100), Vector2(-760, -40), Vector2(-820, 120), Vector2(-790, 250)]
	var out := []
	for p in raw:
		out.append(Vector2(round(p.x / 2.0) * 2.0, round(p.y / 2.0) * 2.0))
	return out


## Control points ready to keep: on the 2 m grid, and no gap over 200 m
## (a code stores each step from the last in under 254 m).
static func tidy(ctrl: Array) -> Array:
	var out := []
	var n := ctrl.size()
	for k in n:
		var a: Vector2 = ctrl[k]
		var b: Vector2 = ctrl[(k + 1) % n]
		out.append(Vector2(round(a.x / 2.0) * 2.0, round(a.y / 2.0) * 2.0))
		var parts := int(ceil(a.distance_to(b) / 200.0))
		for j in range(1, parts):
			var m := a.lerp(b, float(j) / parts)
			out.append(Vector2(round(m.x / 2.0) * 2.0, round(m.y / 2.0) * 2.0))
	return out


static func new_track(ctrl: Array, name := "My track") -> Dictionary:
	var pts := []
	for p in tidy(ctrl):
		pts.append([int(p.x), int(p.y)])
	return {"name": name, "ctrl": pts, "style": "park", "tod": "day", "hills": 1, "width": 1,
		"seed": randi() % 65536}
