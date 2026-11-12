extends Node
## Keeps the game's buttons and text clear of an iPhone's notch or Dynamic
## Island, its rounded corners and the home bar, the way the Android
## layout sits on a plain screen: the 3D world and backgrounds still fill
## the whole display, only what you read and tap moves in.
##
## How: every screen (and the race HUD) hangs its contents off a full-screen
## layout node, or off nodes pinned to a screen edge. As each one appears,
## it's moved in by the phone's safe-area insets (in UI units), and again
## whenever the screen changes (turning the phone round). Backgrounds that
## span the screen (ColorRect, panels, pictures) stay where they are.
##
## Where the insets come from:
##   iPhone / iPad app   the system's safe area (DisplayServer)
##   iPhone browser      CSS env(safe-area-inset-*) from the page (web/shell.html)
##   Android             nothing (Android's own layout is the reference)
##   tests               APEX_SAFE="left,top,right,bottom" (UI units, as reported)

## Safe areas include some breathing room of their own on top of the
## notch; the screens already keep a margin from the edge, so this much of
## each inset is covered by that margin.
const OVERLAP := 12.0

var insets := Vector4.ZERO          # left, top, right, bottom in UI units, after OVERLAP
var _tracked: Array[Control] = []
var _simulated := Vector4(-1, -1, -1, -1)


## (Tests: pretend to be a phone with these raw insets; negative: real ones.)
func simulate(raw_insets: Vector4) -> void:
	_simulated = raw_insets
	_refresh()


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	get_viewport().size_changed.connect(_refresh)
	_refresh()
	if OS.get_environment("APEX_SAFE_FRAME") != "":
		_frame()


## (Tests: an iPhone's Dynamic Island and rounded corners drawn over
## everything, to see what they'd cover.)
func _frame() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	var d := Control.new()
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.set_meta("edge_to_edge", true)
	layer.add_child(d)
	d.draw.connect(func():
		var sz := d.size
		var k := sz.y / 393.0                       # UI units per point (iPhone 15 Pro, landscape)
		var island := Rect2(11.0 * k, sz.y * 0.5 - 63.0 * k, 37.0 * k, 126.0 * k)
		d.draw_rect(island.grow(-island.size.x * 0.5).grow(island.size.x * 0.5), Color.BLACK)
		d.draw_circle(island.position + Vector2(island.size.x * 0.5, island.size.x * 0.5), island.size.x * 0.5, Color.BLACK)
		d.draw_circle(island.end - Vector2(island.size.x * 0.5, island.size.x * 0.5), island.size.x * 0.5, Color.BLACK)
		d.draw_rect(Rect2(island.position + Vector2(0, island.size.x * 0.5), Vector2(island.size.x, island.size.y - island.size.x)), Color.BLACK)
		var r := 55.0 * k
		for c in [Vector2(0, 0), Vector2(sz.x, 0), Vector2(0, sz.y), Vector2(sz.x, sz.y)]:
			var pts := PackedVector2Array([c])
			var cen := Vector2(r if c.x == 0 else sz.x - r, r if c.y == 0 else sz.y - r)
			var a0 := atan2(c.y - cen.y, c.x - cen.x)
			for i in 13:
				var a := a0 - PI / 4.0 + PI / 2.0 * i / 12.0
				pts.append(cen + Vector2(cos(a), sin(a)) * r)
			d.draw_colored_polygon(pts, Color.BLACK)
		# The home bar.
		d.draw_rect(Rect2(sz.x * 0.5 - 70.0 * k, sz.y - 8.0 * k - 5.0 * k, 140.0 * k, 5.0 * k), Color(1, 1, 1, 0.85)))


## The raw insets (UI units) before OVERLAP, or zero where there are none.
func raw() -> Vector4:
	if _simulated.x >= 0.0:
		return _simulated
	var env := OS.get_environment("APEX_SAFE")
	if env != "":
		var p := env.split(",")
		if p.size() == 4:
			return Vector4(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
	var vp_h := get_viewport().get_visible_rect().size.y
	if OS.has_feature("ios"):
		var screen := Vector2(DisplayServer.screen_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if screen.y <= 0.0 or safe.size.x <= 0.0:
			return Vector4.ZERO
		var k := vp_h / screen.y
		return Vector4(safe.position.x, safe.position.y, screen.x - safe.end.x, screen.y - safe.end.y) * k
	if OS.has_feature("web"):
		var css: Variant = JavaScriptBridge.eval("window.__apexSafe ? window.__apexSafe() : ''", true)
		var p2 := String(css).split(",")
		if p2.size() == 5 and float(p2[4]) > 0.0:
			var k2 := vp_h / float(p2[4])        # UI units per CSS pixel
			return Vector4(float(p2[0]), float(p2[1]), float(p2[2]), float(p2[3])) * k2
	return Vector4.ZERO


func _refresh() -> void:
	var r := raw()
	insets = Vector4(maxf(0.0, r.x - OVERLAP), maxf(0.0, r.y - OVERLAP), maxf(0.0, r.z - OVERLAP), maxf(0.0, r.w - OVERLAP))
	for c in _tracked.duplicate():
		if is_instance_valid(c):
			_apply(c)
		else:
			_tracked.erase(c)


func _on_node_added(n: Node) -> void:
	if n is Control:
		# (Deferred: screens set anchors and offsets just after adding.)
		_consider.call_deferred(n)


## Moves `c` in from the edges it's pinned to (if it's a layout node at the
## top of a screen).
func _consider(c: Control) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree() or c.has_meta("safe_base"):
		return
	var p := c.get_parent()
	# The top of a screen: under a CanvasLayer, or under a screen that is
	# itself a full-screen Control (whose own backdrop stays put).
	if not (p is CanvasLayer or (p is Control and p.get_parent() == get_tree().root)):
		return
	if c.has_meta("edge_to_edge"):
		return
	var spans_x := is_zero_approx(c.anchor_left) and is_equal_approx(c.anchor_right, 1.0)
	var spans_y := is_zero_approx(c.anchor_top) and is_equal_approx(c.anchor_bottom, 1.0)
	var pinned := is_zero_approx(c.anchor_right) or is_equal_approx(c.anchor_left, 1.0) \
		or is_zero_approx(c.anchor_bottom) or is_equal_approx(c.anchor_top, 1.0)
	if not (spans_x or spans_y or pinned):
		return
	# A full-screen backdrop stays full screen.
	if (spans_x and spans_y) and (c is ColorRect or c is TextureRect or c is Panel or c is PanelContainer or c is BaseButton):
		return
	c.set_meta("safe_base", [c.offset_left, c.offset_top, c.offset_right, c.offset_bottom])
	_tracked.append(c)
	_apply(c)


func _apply(c: Control) -> void:
	var b: Array = c.get_meta("safe_base")
	var dl := 0.0
	var dr := 0.0
	var dt := 0.0
	var db := 0.0
	# Each side of the node pinned to that side of the screen moves in.
	if is_zero_approx(c.anchor_left):
		dl = insets.x
	if is_equal_approx(c.anchor_right, 1.0):
		dr = -insets.z
	if is_zero_approx(c.anchor_top):
		dt = insets.y
	if is_equal_approx(c.anchor_bottom, 1.0):
		db = -insets.w
	# A node pinned by one edge only moves with that edge (keeps its size).
	if is_zero_approx(c.anchor_left) and is_zero_approx(c.anchor_right):
		dr = dl
	elif is_equal_approx(c.anchor_left, 1.0) and is_equal_approx(c.anchor_right, 1.0):
		dl = dr
	if is_zero_approx(c.anchor_top) and is_zero_approx(c.anchor_bottom):
		db = dt
	elif is_equal_approx(c.anchor_top, 1.0) and is_equal_approx(c.anchor_bottom, 1.0):
		dt = db
	c.offset_left = float(b[0]) + dl
	c.offset_top = float(b[1]) + dt
	c.offset_right = float(b[2]) + dr
	c.offset_bottom = float(b[3]) + db
