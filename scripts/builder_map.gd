class_name BuilderMap
extends Control
## The track builder's drawing board: the land seen from above, a 100 m
## grid, and your circuit drawn as a road. Draw: trace a loop with your
## finger and it becomes a track. Shape: drag the points to move the road,
## tap the road to add a point, tap a point to pick it. Two fingers zoom
## and pan (in either mode).

signal edited                  # the layout changed (the undo copy was taken before)
signal edit_started            # about to change: take an undo copy now
signal picked(index: int)      # a point picked (-1: none)
signal traced_badly(msg: String)

var ctrl: Array = []           # control points (Vector2, metres)
var mode := "draw"             # "draw" or "shape"
var problems: Array = []       # from MyTracks.problems(): marked in red
var style := "park"
var half_width := 6.5
var selected := -1

var _mpp := 3.0                # metres per pixel
var _centre := Vector2.ZERO    # metres at the middle of the board
var _zoom := 1.0
var _trace := PackedVector2Array()   # metres
var _drawing := false
var _drag := -1                # control point being dragged
var _drag_moved := false
var _down_at := Vector2.ZERO
var _touches := {}             # index -> position (pixels)
var _pinch0 := {}              # two fingers down: where they started
var _pinched := false          # (fingers came down together: no tap or trace till all lift)
var _samples := PackedVector2Array()
var _start := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_fit)


func _fit() -> void:
	if size.x <= 0.0:
		return
	_mpp = maxf(MyTracks.AREA.x / size.x, MyTracks.AREA.y / size.y) / _zoom
	queue_redraw()


## Show the whole of the track (or the whole area if there isn't one).
func frame_all() -> void:
	_zoom = 1.0
	_centre = Vector2.ZERO
	if ctrl.size() >= 3:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in ctrl:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		_centre = (lo + hi) * 0.5
		var ext := (hi - lo) + Vector2(240, 240)
		if size.x > 0.0:
			var base := maxf(MyTracks.AREA.x / size.x, MyTracks.AREA.y / size.y)
			var need := maxf(ext.x / size.x, ext.y / size.y)
			_zoom = clampf(base / need, 0.5, 2.5)
	_fit()


func set_layout(points: Array) -> void:
	ctrl = points.duplicate()
	if selected >= ctrl.size():
		selected = -1
	refresh()


func refresh() -> void:
	_samples = MyTracks.sample(ctrl, 4.0) if ctrl.size() >= 3 else PackedVector2Array()
	_start = Track.straight_start(_samples, 4.0) if _samples.size() > 20 else 0
	queue_redraw()


func zoom_by(f: float) -> void:
	_zoom = clampf(_zoom * f, 0.5, 4.0)
	_fit()


func to_px(m: Vector2) -> Vector2:
	return size * 0.5 + (m - _centre) / _mpp


func to_m(px: Vector2) -> Vector2:
	return _centre + (px - size * 0.5) * _mpp


# ------------------------------------------------------------ drawing

const LAND := {"park": Color("2c4a1f"), "forest": Color("1f3518"), "desert": Color("9c7b52"), "city": Color("4a4c50")}


func _draw() -> void:
	var land: Color = LAND.get(style, LAND["park"])
	draw_rect(Rect2(Vector2.ZERO, size), land)
	# 100 m grid, every 500 m stronger.
	var tl := to_m(Vector2.ZERO)
	var br := to_m(size)
	var x := floorf(tl.x / 100.0) * 100.0
	while x <= br.x:
		var strong := is_zero_approx(fmod(absf(x), 500.0))
		draw_line(to_px(Vector2(x, tl.y)), to_px(Vector2(x, br.y)), Color(1, 1, 1, 0.13 if strong else 0.05), 1.0)
		x += 100.0
	var z := floorf(tl.y / 100.0) * 100.0
	while z <= br.y:
		var strong := is_zero_approx(fmod(absf(z), 500.0))
		draw_line(to_px(Vector2(tl.x, z)), to_px(Vector2(br.x, z)), Color(1, 1, 1, 0.13 if strong else 0.05), 1.0)
		z += 100.0
	# Scale bar, bottom left.
	var bar := 500.0 / _mpp
	var b0 := Vector2(18, size.y - 22)
	draw_line(b0, b0 + Vector2(bar, 0), Color(1, 1, 1, 0.8), 3.0)
	draw_line(b0 - Vector2(0, 6), b0 + Vector2(0, 2), Color(1, 1, 1, 0.8), 2.0)
	draw_line(b0 + Vector2(bar, -6), b0 + Vector2(bar, 2), Color(1, 1, 1, 0.8), 2.0)
	draw_string(UIStyle.font("bold"), b0 + Vector2(bar + 10, 6), "500 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.8))

	if _samples.size() > 3:
		_draw_road()
	if mode == "shape":
		for k in ctrl.size():
			var p := to_px(ctrl[k])
			var on := k == selected
			draw_circle(p, 13.0 if on else 10.0, Color(0, 0, 0, 0.75))
			draw_circle(p, 9.5 if on else 7.0, UIStyle.SIGNAL if on else Color.WHITE)
	for pr in problems:
		if String(pr["kind"]) in ["short", "long"]:
			continue
		var p := to_px(pr["at"])
		draw_arc(p, 26.0, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 7.0)
		draw_arc(p, 26.0, 0.0, TAU, 32, UIStyle.RED, 4.0)
	if _trace.size() > 1:
		var line := PackedVector2Array()
		for m in _trace:
			line.append(to_px(m))
		draw_polyline(line, Color(0, 0, 0, 0.5), 9.0, true)
		draw_polyline(line, UIStyle.SIGNAL, 5.0, true)
		# Back near the start: it will close up.
		var s := to_px(_trace[0])
		draw_arc(s, 34.0, 0.0, TAU, 32, Color(UIStyle.SIGNAL, 0.9 if line[-1].distance_to(s) < 60.0 else 0.35), 3.0)
	if ctrl.is_empty() and _trace.is_empty():
		var f := UIStyle.font("bold")
		var msg := "Draw your track: trace a loop with your finger" if mode == "draw" else "Pick a starting shape, or switch to Draw"
		var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.85))


func _draw_road() -> void:
	var line := PackedVector2Array()
	for m in _samples:
		line.append(to_px(m))
	line.append(line[0])
	var w := maxf(half_width * 2.0 / _mpp, 7.0)
	var verge := Color(0.86, 0.88, 0.84) if style != "desert" else Color(0.95, 0.9, 0.78)
	draw_polyline(line, Color(0, 0, 0, 0.35), w + 9.0, true)
	draw_polyline(line, verge, w + 4.0, true)
	draw_polyline(line, Color("2a2b2e"), w, true)
	# Which way round: chevrons every ~250 m.
	var n := _samples.size()
	var every := maxi(1, int(250.0 / 4.0))
	for i in range(every / 2, n, every):
		var p := to_px(_samples[i])
		var d := (to_px(_samples[(i + 2) % n]) - to_px(_samples[(i - 2 + n) % n])).normalized()
		var side := Vector2(-d.y, d.x)
		var s := minf(w * 0.45, 6.0) + 2.0
		draw_polyline(PackedVector2Array([p - d * s + side * s, p + d * s * 0.6, p - d * s - side * s]), Color(1, 1, 1, 0.85), 2.0, true)
	# Start / finish: a chequered bar across the road.
	var s0 := to_px(_samples[_start])
	var dir := (to_px(_samples[(_start + 2) % n]) - to_px(_samples[(_start - 2 + n) % n])).normalized()
	var across := Vector2(-dir.y, dir.x)
	var half := w * 0.5 + 6.0
	var cells := 6
	for c in cells:
		for r in 2:
			var a := s0 + across * (-half + 2.0 * half * c / cells) + dir * (r * 4.0 - 4.0)
			var col := Color.WHITE if (c + r) % 2 == 0 else Color.BLACK
			draw_colored_polygon(PackedVector2Array([a, a + across * (2.0 * half / cells), a + across * (2.0 * half / cells) + dir * 4.0, a + dir * 4.0]), col)


# ------------------------------------------------------------ input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() >= 2:
			_cancel_single()
			_start_pinch()
			_pinched = true
		elif _touches.size() < 2:
			_pinch0 = {}
		if t.pressed and _touches.size() == 1:
			_pinched = false
			_press(t.position)
		elif not t.pressed and not _pinched and _touches.is_empty():
			_release(t.position)
		accept_event()
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			_pinch()
		elif not _pinched:
			_move(d.position)
		accept_event()
	elif ev is InputEventMouseButton and ev.pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15)


func _start_pinch() -> void:
	var keys := _touches.keys()
	_pinch0 = {"a": _touches[keys[0]], "b": _touches[keys[1]], "zoom": _zoom, "centre": _centre}


func _pinch() -> void:
	if _pinch0.is_empty():
		_start_pinch()
		return
	var keys := _touches.keys()
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	var d0 := (_pinch0["a"] as Vector2).distance_to(_pinch0["b"])
	var d1 := a.distance_to(b)
	if d0 > 10.0:
		_zoom = clampf(float(_pinch0["zoom"]) * d1 / d0, 0.5, 4.0)
		_mpp = maxf(MyTracks.AREA.x / size.x, MyTracks.AREA.y / size.y) / _zoom
	var m0 := ((_pinch0["a"] as Vector2) + (_pinch0["b"] as Vector2)) * 0.5
	var m1 := (a + b) * 0.5
	# Keep the spot between the fingers under them.
	var base_mpp := maxf(MyTracks.AREA.x / size.x, MyTracks.AREA.y / size.y)
	var under: Vector2 = (_pinch0["centre"] as Vector2) + (m0 - size * 0.5) * base_mpp / float(_pinch0["zoom"])
	_centre = under - (m1 - size * 0.5) * _mpp
	queue_redraw()


func _cancel_single() -> void:
	if _drawing:
		_drawing = false
		_trace = PackedVector2Array()
	if _drag >= 0 and _drag_moved:
		edited.emit()
	_drag = -1
	queue_redraw()


func _press(px: Vector2) -> void:
	_down_at = px
	if mode == "draw":
		_drawing = true
		_trace = PackedVector2Array([to_m(px)])
		queue_redraw()
		return
	_drag = _handle_at(px)
	_drag_moved = false


func _move(px: Vector2) -> void:
	if _drawing:
		var m := to_m(px)
		if _trace.is_empty() or m.distance_to(_trace[-1]) > _mpp * 3.0:
			_trace.append(m)
			queue_redraw()
		return
	if _drag >= 0:
		if not _drag_moved and px.distance_to(_down_at) < 8.0:
			return
		if not _drag_moved:
			edit_started.emit()
			_drag_moved = true
			selected = _drag
			picked.emit(selected)
		var m := to_m(px)
		ctrl[_drag] = Vector2(round(m.x / 2.0) * 2.0, round(m.y / 2.0) * 2.0)
		refresh()
	elif mode == "shape" and px.distance_to(_down_at) > 8.0:
		# One finger on empty ground: pan.
		_centre -= (px - _down_at) * _mpp
		_down_at = px
		queue_redraw()


func _release(px: Vector2) -> void:
	if _drawing:
		_drawing = false
		_finish_trace()
		return
	if _drag >= 0:
		if _drag_moved:
			edited.emit()
		else:
			selected = _drag if selected != _drag else -1
			picked.emit(selected)
			queue_redraw()
		_drag = -1
		return
	if mode == "shape" and px.distance_to(_down_at) < 8.0:
		# A tap on the road: a new point there.
		var at := _insert_index(to_m(px))
		if at >= 0:
			edit_started.emit()
			var m := to_m(px)
			ctrl.insert(at, Vector2(round(m.x / 2.0) * 2.0, round(m.y / 2.0) * 2.0))
			selected = at
			refresh()
			picked.emit(selected)
			edited.emit()
		elif selected >= 0:
			selected = -1
			picked.emit(-1)
			queue_redraw()


func _finish_trace() -> void:
	var tr := _trace
	_trace = PackedVector2Array()
	queue_redraw()
	if tr.size() < 10:
		return
	var length := 0.0
	for i in range(1, tr.size()):
		length += tr[i].distance_to(tr[i - 1])
	if length < 400.0:
		traced_badly.emit("Draw a bigger loop: at least %.1f km of track." % (MyTracks.MIN_LEN / 1000.0))
		return
	var gap := tr[0].distance_to(tr[-1])
	if gap > maxf(length * 0.25, 250.0):
		traced_badly.emit("Finish where you started, so the track is a loop.")
		return
	var pts := MyTracks.from_trace(tr)
	if pts.size() < 4:
		return
	edit_started.emit()
	ctrl = pts
	selected = -1
	refresh()
	edited.emit()


func _handle_at(px: Vector2) -> int:
	var best := -1
	var best_d := 30.0
	for k in ctrl.size():
		var d := to_px(ctrl[k]).distance_to(px)
		if d < best_d:
			best_d = d
			best = k
	return best


## Where a point tapped on the road goes in the list (-1: not on the road).
func _insert_index(m: Vector2) -> int:
	if _samples.size() < 4 or ctrl.size() < 3:
		return -1
	var best := -1
	var best_d := maxf(half_width + 10.0, _mpp * 22.0)
	for i in _samples.size():
		var d := _samples[i].distance_to(m)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return -1
	# The control point just after that sample along the lap.
	var n := ctrl.size()
	var best_k := 0
	var best_cd := INF
	for k in n:
		var d := (ctrl[k] as Vector2).distance_to(_samples[best])
		if d < best_cd:
			best_cd = d
			best_k = k
	# Ahead of or behind the nearest point? Compare along the lap.
	var near := _nearest_sample(ctrl[best_k])
	var ns := _samples.size()
	var ahead := posmod(best - near, ns) < ns / 2
	return (best_k + 1) % (n + 1) if ahead else best_k


func _nearest_sample(m: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in _samples.size():
		var d := _samples[i].distance_to(m)
		if d < best_d:
			best_d = d
			best = i
	return best
