class_name MeshKit
extends RefCounted
## Procedural modelling helpers. All functions append triangles to a
## SurfaceTool (with vertex colours), so a whole car body can be built into
## a few surfaces and drawn in a few calls.
##
##   loft     smooth body from superellipse cross-sections along +Z
##   tube     round tube along a 3D path (halo, wishbones)
##   airfoil  cambered wing element extruded along X
##   lathe    surface of revolution around the X axis (tyres, rims)
##   ellipsoid


## A loft station: centre (x, y) at depth z, half-width a, half-height b,
## superellipse exponent n (2 = ellipse, higher = boxier).
static func station(z: float, y: float, a: float, b: float, n := 2.6, x := 0.0) -> Dictionary:
	return {"z": z, "x": x, "y": y, "a": a, "b": b, "n": n}


## A cross-section from y0 (bottom) to y1 (top) whose half-width changes
## with height: wb at the bottom, wm half way up, wt at the top (a flat-topped
## tub, a sidepod with an undercut). n: squareness of the corners.
static func section(z: float, y0: float, y1: float, wb: float, wm: float, wt: float, n := 3.0, x := 0.0) -> Dictionary:
	return {"z": z, "x": x, "y": (y0 + y1) * 0.5, "a": wm, "b": (y1 - y0) * 0.5, "n": n, "wb": wb, "wm": wm, "wt": wt}


static func _section_pt(s: Dictionary, th: float) -> Vector2:
	if not s.has("wb"):
		return _se(th, s["a"], s["b"], s["n"])
	var u := _se(th, 1.0, 1.0, s["n"])
	var t := (u.y + 1.0) * 0.5
	var w: float = float(s["wb"]) * (2.0 * t - 1.0) * (t - 1.0) + float(s["wm"]) * 4.0 * t * (1.0 - t) + float(s["wt"]) * t * (2.0 * t - 1.0)
	return Vector2(u.x * w, u.y * float(s["b"]))


## A flat horizontal panel (a floor): the outline (Vector2(x, z), going
## round, any simple shape) at height y, `thick` deep.
static func hplate(st: SurfaceTool, outline: Array, y: float, thick: float, color: Color, xform := Transform3D.IDENTITY) -> void:
	var poly := PackedVector2Array(outline)
	var idx := Geometry2D.triangulate_polygon(poly)
	var n := poly.size()
	for side in [-1.0, 1.0]:
		var yy: float = y + side * thick * 0.5
		for i in range(0, idx.size(), 3):
			var a := poly[idx[i]]
			var b := poly[idx[i + 1]]
			var c := poly[idx[i + 2]]
			if side > 0.0:
				_tri(st, xform * Vector3(a.x, yy, a.y), xform * Vector3(b.x, yy, b.y), xform * Vector3(c.x, yy, c.y), color)
			else:
				_tri(st, xform * Vector3(a.x, yy, a.y), xform * Vector3(c.x, yy, c.y), xform * Vector3(b.x, yy, b.y), color)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		_quad(st, xform * Vector3(a.x, y - thick * 0.5, a.y), xform * Vector3(b.x, y - thick * 0.5, b.y),
			xform * Vector3(b.x, y + thick * 0.5, b.y), xform * Vector3(a.x, y + thick * 0.5, a.y), color)


static func _se(theta: float, a: float, b: float, n: float) -> Vector2:
	var c := cos(theta)
	var s := sin(theta)
	return Vector2(a * signf(c) * pow(absf(c), 2.0 / n), b * signf(s) * pow(absf(s), 2.0 / n))


## color_fn(Vector3 local_pos, float theta) -> Color; theta = 0 at +x side,
## PI/2 on top, -PI/2 underneath.
static func loft(st: SurfaceTool, stations: Array, seg: int, color_fn: Callable, xform := Transform3D.IDENTITY, cap := true) -> void:
	var rings: Array = []
	var thetas: Array = []
	for k in range(seg + 1):
		thetas.append(-PI + TAU * k / seg)
	for s in stations:
		var ring := PackedVector3Array()
		for th in thetas:
			var p := _section_pt(s, th)
			ring.append(Vector3(s["x"] + p.x, s["y"] + p.y, s["z"]))
		rings.append(ring)
	for r in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[r]
		var r1: PackedVector3Array = rings[r + 1]
		for k in range(seg):
			var th: float = thetas[k] + PI / seg
			var c: Color = color_fn.call((r0[k] + r1[k + 1]) * 0.5, th)
			_quad(st, xform * r0[k], xform * r0[k + 1], xform * r1[k + 1], xform * r1[k], c)
	if cap:
		for end in [0, rings.size() - 1]:
			var ring: PackedVector3Array = rings[end]
			var centre := Vector3.ZERO
			for p in ring:
				centre += p
			centre /= ring.size()
			var c: Color = color_fn.call(centre, 0.0)
			for k in range(seg):
				if end == 0:
					_tri(st, xform * centre, xform * ring[k + 1], xform * ring[k], c)
				else:
					_tri(st, xform * centre, xform * ring[k], xform * ring[k + 1], c)


## Round tube of `radius` following `path` (local points).
static func tube(st: SurfaceTool, path: Array, radius: float, seg: int, color: Color, xform := Transform3D.IDENTITY) -> void:
	var rings: Array = []
	for i in range(path.size()):
		var p: Vector3 = path[i]
		var t: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var up := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u := t.cross(up).normalized()
		var v := u.cross(t).normalized()
		var ring := PackedVector3Array()
		for k in range(seg + 1):
			var th := TAU * k / seg
			ring.append(p + (u * cos(th) + v * sin(th)) * radius)
		rings.append(ring)
	for r in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[r]
		var r1: PackedVector3Array = rings[r + 1]
		for k in range(seg):
			_quad(st, xform * r0[k], xform * r1[k], xform * r1[k + 1], xform * r0[k + 1], color)


## Wing element: cambered airfoil of `chord` and thickness ratio `thick`,
## spanning x0..x1, leading edge at (y, z), pitched by `aoa` degrees
## (positive = trailing edge up, i.e. downforce).
static func airfoil(st: SurfaceTool, x0: float, x1: float, y: float, z: float, chord: float, thick: float, camber: float, aoa: float, color: Color, xform := Transform3D.IDENTITY) -> void:
	var prof: Array = []
	var m := 10
	# Upper surface trailing->leading, then lower surface leading->trailing.
	for i in range(m, -1, -1):
		prof.append(_foil_pt(float(i) / m, thick, camber, true))
	for i in range(1, m + 1):
		prof.append(_foil_pt(float(i) / m, thick, camber, false))
	var rot := deg_to_rad(aoa)
	var pts: Array = []
	for p in prof:
		var q: Vector2 = p * chord
		# rotate around the leading edge; chord runs towards -z (backwards)
		var zz := -q.x * cos(rot) - q.y * sin(rot)
		var yy := -q.x * sin(rot) * -1.0 + q.y * cos(rot)
		pts.append(Vector2(z + zz, y + yy))
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		_quad(st, xform * Vector3(x0, a.y, a.x), xform * Vector3(x1, a.y, a.x),
			xform * Vector3(x1, b.y, b.x), xform * Vector3(x0, b.y, b.x), color)
	# end caps
	for side in [x0, x1]:
		var c := Vector3(side, y, z - chord * 0.4)
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if side == x0:
				_tri(st, xform * c, xform * Vector3(side, a.y, a.x), xform * Vector3(side, b.y, b.x), color)
			else:
				_tri(st, xform * c, xform * Vector3(side, b.y, b.x), xform * Vector3(side, a.y, a.x), color)


## Wing element along a span path: sections[k] = [x, y, z, chord, aoa]
## (leading edge at x, y, z; chord running back towards -z; aoa degrees),
## so an element can curve up, sweep and twist along its span.
## color_fn(x: float, upper: bool) -> Color.
static func wing(st: SurfaceTool, sections: Array, thick: float, camber: float, color_fn: Callable, xform := Transform3D.IDENTITY) -> void:
	var m := 5
	var prof: Array = []
	for i in range(m, -1, -1):
		prof.append([_foil_pt(float(i) / m, thick, camber, true), true])
	for i in range(1, m + 1):
		prof.append([_foil_pt(float(i) / m, thick, camber, false), false])
	var rings: Array = []
	for s in sections:
		var rot := deg_to_rad(float(s[4]))
		var ring := PackedVector3Array()
		for p in prof:
			var q: Vector2 = (p[0] as Vector2) * float(s[3])
			ring.append(Vector3(float(s[0]), float(s[1]) + q.x * sin(rot) + q.y * cos(rot), float(s[2]) - q.x * cos(rot) + q.y * sin(rot)))
		rings.append(ring)
	for r in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[r]
		var r1: PackedVector3Array = rings[r + 1]
		var xm := (float(sections[r][0]) + float(sections[r + 1][0])) * 0.5
		for i in range(prof.size() - 1):
			var c: Color = color_fn.call(xm, prof[i][1])
			if float(sections[r + 1][0]) > float(sections[r][0]):
				_quad(st, xform * r0[i], xform * r1[i], xform * r1[i + 1], xform * r0[i + 1], c)
			else:
				_quad(st, xform * r0[i], xform * r0[i + 1], xform * r1[i + 1], xform * r1[i], c)
	for end in [0, rings.size() - 1]:
		var ring: PackedVector3Array = rings[end]
		var centre := Vector3.ZERO
		for p in ring:
			centre += p
		centre /= ring.size()
		var c: Color = color_fn.call(float(sections[end][0]), true)
		for i in range(ring.size() - 1):
			if (end == 0) == (float(sections[rings.size() - 1][0]) > float(sections[0][0])):
				_tri(st, xform * centre, xform * ring[i], xform * ring[i + 1], c)
			else:
				_tri(st, xform * centre, xform * ring[i + 1], xform * ring[i], c)


## A flat panel (endplate, fin): the outline (Vector2(z, y), going round,
## star-shaped about its centre) extruded `thick` across x, centred on x.
static func plate(st: SurfaceTool, outline: Array, x: float, thick: float, color: Color, xform := Transform3D.IDENTITY) -> void:
	_plate(st, outline, x, thick, func(_z, _y): return color, xform)


## A band along the top of a panel: the strip from the line `top`
## (Vector2(z, y) points) down by `depth`, `thick` across x.
static func strip(st: SurfaceTool, top: Array, depth: float, x: float, thick: float, color: Color, xform := Transform3D.IDENTITY) -> void:
	for i in range(top.size() - 1):
		var a: Vector2 = top[i]
		var b: Vector2 = top[i + 1]
		var quad := [a, b, b - Vector2(0, depth), a - Vector2(0, depth)]
		_plate(st, quad, x, thick, func(_z, _y): return color, xform)


static func _plate(st: SurfaceTool, outline: Array, x: float, thick: float, color_fn: Callable, xform := Transform3D.IDENTITY) -> void:
	var centre := Vector2.ZERO
	for p in outline:
		centre += p
	centre /= outline.size()
	var n := outline.size()
	for side in [-1.0, 1.0]:
		var xx: float = x + side * thick * 0.5
		for i in n:
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % n]
			var c: Color = color_fn.call((a.x + b.x + centre.x) / 3.0, (a.y + b.y + centre.y) / 3.0)
			var pc := Vector3(xx, centre.y, centre.x)
			var pa := Vector3(xx, a.y, a.x)
			var pb := Vector3(xx, b.y, b.x)
			if side > 0.0:
				_tri(st, xform * pc, xform * pa, xform * pb, c)
			else:
				_tri(st, xform * pc, xform * pb, xform * pa, c)
	for i in n:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var c: Color = color_fn.call((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
		_quad(st, xform * Vector3(x - thick * 0.5, a.y, a.x), xform * Vector3(x + thick * 0.5, a.y, a.x),
			xform * Vector3(x + thick * 0.5, b.y, b.x), xform * Vector3(x - thick * 0.5, b.y, b.x), c)


static func _foil_pt(t: float, thick: float, camber: float, upper: bool) -> Vector2:
	# NACA-style thickness + simple parabolic camber line.
	var yt := 5.0 * thick * (0.2969 * sqrt(t) - 0.126 * t - 0.3516 * t * t + 0.2843 * t * t * t - 0.1015 * t * t * t * t)
	var yc := camber * 4.0 * t * (1.0 - t)
	return Vector2(t, yc + (yt if upper else -yt))


## Surface of revolution around the X axis. profile: Array of Vector2(x, r).
static func lathe(st: SurfaceTool, profile: Array, seg: int, color: Color, xform := Transform3D.IDENTITY) -> void:
	for i in range(profile.size() - 1):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for k in range(seg):
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p00 := Vector3(a.x, cos(t0) * a.y, sin(t0) * a.y)
			var p01 := Vector3(a.x, cos(t1) * a.y, sin(t1) * a.y)
			var p10 := Vector3(b.x, cos(t0) * b.y, sin(t0) * b.y)
			var p11 := Vector3(b.x, cos(t1) * b.y, sin(t1) * b.y)
			_quad(st, xform * p00, xform * p10, xform * p11, xform * p01, color)


static func ellipsoid(st: SurfaceTool, centre: Vector3, radii: Vector3, seg: int, color: Color, xform := Transform3D.IDENTITY) -> void:
	var rows := maxi(seg / 2, 3)
	for i in range(rows):
		var v0 := PI * i / rows - PI / 2
		var v1 := PI * (i + 1) / rows - PI / 2
		for k in range(seg):
			var u0 := TAU * k / seg
			var u1 := TAU * (k + 1) / seg
			var p := func(u: float, v: float) -> Vector3:
				return centre + Vector3(cos(v) * cos(u) * radii.x, sin(v) * radii.y, cos(v) * sin(u) * radii.z)
			_quad(st, xform * p.call(u0, v0), xform * p.call(u1, v0), xform * p.call(u1, v1), xform * p.call(u0, v1), color)


static func box(st: SurfaceTool, size: Vector3, centre: Vector3, color: Color, rot_deg := Vector3.ZERO, xform := Transform3D.IDENTITY) -> void:
	var b := Basis.from_euler(rot_deg * (PI / 180.0))
	var h := size * 0.5
	var corners := []
	for i in range(8):
		var c := Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1))
		corners.append(xform * (centre + b * c))
	var faces := [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
	for f in faces:
		_quad(st, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], color)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func new_tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Finishes a SurfaceTool into a mesh with smooth normals.
static func finish(st: SurfaceTool, mesh: ArrayMesh = null) -> ArrayMesh:
	st.generate_normals()
	return st.commit(mesh)


static var _crisp_cache := {}

## Finishes a SurfaceTool into a mesh whose normals are smooth across gentle
## curves but crisp where faces meet at more than `crease` degrees: wing
## plates, endplates and panel edges catch a sharp highlight, bodywork
## stays smooth (generate_normals smooths everything, so a thin plate reads
## as a soft blob). The normals for a given `key` are worked out once and
## reused (every car of a model shares its shape; only colours differ).
static func finish_crisp(st: SurfaceTool, mesh: ArrayMesh = null, key := "", crease := 38.0) -> ArrayMesh:
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := verts.size()
	if n == 0:
		return mesh if mesh != null else ArrayMesh.new()
	var normals: PackedVector3Array
	if key != "" and _crisp_cache.has(key) and (_crisp_cache[key] as PackedVector3Array).size() == n:
		normals = _crisp_cache[key]
	else:
		normals = crisp_normals(verts, crease)
		if key != "":
			_crisp_cache[key] = normals
	arrays[Mesh.ARRAY_NORMAL] = normals
	if mesh == null:
		mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Per-vertex normals for a triangle list: each corner averages the
## (area-weighted) normals of the triangles meeting at that point whose
## faces are within `crease` degrees of its own. Same orientation as
## SurfaceTool.generate_normals.
static func crisp_normals(verts: PackedVector3Array, crease: float) -> PackedVector3Array:
	var n := verts.size()
	var tris := n / 3
	var fn := PackedVector3Array()
	fn.resize(tris)
	var fu := PackedVector3Array()
	fu.resize(tris)
	for t in tris:
		var a := verts[t * 3]
		var nn := (a - verts[t * 3 + 2]).cross(a - verts[t * 3 + 1])
		fn[t] = nn
		fu[t] = nn.normalized()
	# Corners at the same point (to a tenth of a millimetre).
	var groups := {}
	for i in n:
		var p := verts[i]
		var k := Vector3i(roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0))
		if groups.has(k):
			(groups[k] as Array).append(i)
		else:
			groups[k] = [i]
	var lim := cos(deg_to_rad(crease))
	var out := PackedVector3Array()
	out.resize(n)
	for k in groups:
		var g: Array = groups[k]
		for i in g:
			var own := fu[i / 3]
			var sum := Vector3.ZERO
			for j in g:
				var f := fu[j / 3]
				if own.dot(f) >= lim:
					sum += fn[j / 3]
			out[i] = sum.normalized() if sum.length_squared() > 0.0 else own
	return out
