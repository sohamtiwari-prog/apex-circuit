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
			var p := _se(th, s["a"], s["b"], s["n"])
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
