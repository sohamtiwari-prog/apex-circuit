extends SceneTree
## The landscape must never show through the road or the verges: at every
## sample, across the road and out to the barrier, the drawn ground is below
## the surface cars drive on (with a margin for depth precision on phones).
var failures: Array[String] = []
func _initialize() -> void:
	_run()
func _check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		failures.append(msg)
func _run() -> void:
	var margin := float(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 0.25
	for t in Track.CATALOG:
		var tr := Track.new()
		root.add_child(tr)
		tr.build(t["id"])
		var n := tr.size()
		var bad := 0
		var worst := -INF
		var worst_at := ""
		var checked := 0
		for i in range(0, n):
			for side in [-1.0, 1.0]:
				var lat := 0.0
				while lat <= tr.wall_at(i, side) + 2.0:
					var p: Vector3 = tr.points[i] + tr.rights[i] * lat * side
					var surface := p.y + (Track.GROUND_Y if lat > tr.road_half + Track.KERB_W + 1.0 else 0.0)
					var g := tr.drawn_ground(p.x, p.z)
					# Full margin on the driving area; behind the barrier it only
					# has to stay under the verge.
					var m := margin if lat <= tr.wall_at(i, side) else 0.05
					var over := g - (surface - m)
					checked += 1
					if over > 0.0:
						bad += 1
						if over > worst:
							worst = over
							worst_at = "%.0f m, %s %.0f m" % [tr.cum[i], "right" if side > 0 else "left", lat]
					lat += 1.0
		print("  %-12s %7d points, %5d too close to the surface (worst %.2f m at %s)" % [t["id"], checked, bad, worst, worst_at])
		# The far ground must stay outside the landscape (it once cut across
		# it at mid height and buried the road).
		var ring: Rect2 = tr.far_ring_rect()
		var inside := true
		for q in tr.points:
			if not ring.grow(-300.0).has_point(Vector2(q.x, q.z)):
				inside = false
		_check(inside, "%s: the circuit is well inside the landscape (far ground is only around it)" % t["id"])
		_check(bad == 0, "%s: landscape stays at least %.2f m below road and verges" % [t["id"], margin])
		tr.queue_free()
		await process_frame
	print("ALL CHECKS PASSED" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
