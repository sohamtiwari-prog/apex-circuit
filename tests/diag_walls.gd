extends SceneTree
## Lists barrier sections that sit within a car's width of any part of the road.
func _initialize() -> void:
	for t in Track.CATALOG:
		var tr := Track.new()
		root.add_child(tr)
		tr.build(t["id"])
		var bad := 0
		var worst := INF
		for body in tr.get_children():
			if body is StaticBody3D:
				for cs in body.get_children():
					if cs is CollisionShape3D and cs.shape is BoxShape3D:
						var box: BoxShape3D = cs.shape
						var xf: Transform3D = cs.transform
						for f in [-0.5, 0.0, 0.5]:
							var p: Vector3 = xf.origin + xf.basis.z * box.size.z * float(f)
							var d := tr.dist_to_centerline(p, tr.wall_offset + 4.0)
							worst = minf(worst, d)
							if d < tr.road_half + 0.5:
								bad += 1
		print("%-12s walls inside road: %d  (closest %.1f m from a centreline, road half %.1f)" % [t["id"], bad, worst, tr.road_half])
		tr.free()
	quit(0)
