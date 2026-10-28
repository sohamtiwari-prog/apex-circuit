extends SceneTree
## Calibration: AI lap times (skill 1.0 and 0.9) against Track.lap_estimate.
func _initialize() -> void:
	_run()
func _run() -> void:
	for tid in OS.get_cmdline_user_args():
		for cid in ["marauder", "gp26"]:
			for skill in [1.0, 0.9]:
				var world := Node3D.new()
				root.add_child(world)
				var track := Track.new()
				world.add_child(track)
				track.build(tid)
				var car := RaceCar.new()
				car.setup(CarSpecs.get_spec(cid))
				world.add_child(car)
				var n := track.size()
				car.global_transform = track.pose_at(n - 150, car.spawn_height(), track.line_offset[n - 150])
				car.controls_enabled = true
				var ai := AIDriver.new()
				ai.skill = skill
				var crossings := 0
				var t0 := 0.0
				var t := 0.0
				var prev := n - 150
				while crossings < 3 and t < 400.0:
					await physics_frame
					ai.update(car, track)
					t += 1.0 / 120.0
					var idx := track.track_index(car.global_position, prev)
					if prev > n * 0.9 and idx < n * 0.1:
						crossings += 1
						if crossings == 2:
							t0 = t
					prev = idx
				var lap := t - t0
				var est := track.lap_estimate(car.spec, skill)
				print("%s %s skill %.2f: AI lap %.2f  estimate %.2f  ratio %.3f" % [tid, cid, skill, lap, est, lap / est])
				world.queue_free()
				await process_frame
	quit(0)
