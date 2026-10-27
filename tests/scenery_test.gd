extends SceneTree
## No large scenery (buildings, grandstands) may sit on or across the road:
## every footprint the track recorded is checked on a grid of points.
var failures: Array[String] = []
func _initialize() -> void:
	for t in Track.CATALOG:
		var tr := Track.new()
		root.add_child(tr)
		tr.build(t["id"])
		var bad := 0
		for box in tr.scenery_boxes:
			if not box.get("overhead", false) and not tr.footprint_clear(box["xf"], box["size"], 0.5):
				bad += 1
		print("%-12s %3d large objects, %d on or across the road" % [t["id"], tr.scenery_boxes.size(), bad])
		if bad > 0 or tr.scenery_boxes.is_empty():
			failures.append(t["id"])
		tr.free()
	print("ALL CHECKS PASSED" if failures.is_empty() else "FAIL: scenery problem at " + ", ".join(failures))
	quit(0 if failures.is_empty() else 1)
