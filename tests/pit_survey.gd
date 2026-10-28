extends SceneTree
## Which tracks get a real pit lane, and on which side.
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	for t in Track.CATALOG:
		var tr := Track.new()
		root.add_child(tr)
		tr.build(String(t["id"]))
		var s := "PIT %-12s style=%-7s pit_lane=%s side=%+.0f boxes=%d off=%.1f %s" % [t["id"], tr.style, tr.has_pit_lane, tr.pit_side, tr.pit_boxes.size(), tr.pit_off, tr.pit_reason] + " entry %.0f lane %.0f before line %.0f" % [tr.PIT_ENTRY_LEN, tr.PIT_STRAIGHT_LEN, tr.PIT_BEFORE_LINE]
		print(s)
		tr.queue_free()
		await process_frame
	quit(0)
