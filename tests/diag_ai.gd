extends SceneTree
## Prints the AI's state every 0.25 s on one track: tests/diag_ai.gd -- <track> <car> <from_s> <to_s>
func _initialize() -> void:
	_run()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var world := Node3D.new(); root.add_child(world)
	var track := Track.new(); world.add_child(track); track.build(a[0])
	var car := RaceCar.new(); car.setup(CarSpecs.get_spec(a[1])); world.add_child(car)
	await physics_frame
	var n := track.size()
	car.global_transform = track.pose_at(n - 5, car.spawn_height())
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	var t := 0.0
	for k in range(n):
		pass
	for i in range(60): await physics_frame
	var ai := AIDriver.new()
	var prof := track.speed_profile(car.spec)
	var plan := 0.0
	for k in range(n):
		plan += Track.SPACING / maxf(prof[k], 1.0)
	print("planned lap %.1f s" % plan)
	for f in range(120 * 60):
		ai.update(car, track)
		await physics_frame
		var i := ai.idx
		if f % 15 == 0 and track.cum[i] > float(a[2]) and track.cum[i] < float(a[3]):
			var vel := car.linear_velocity
			var slip := rad_to_deg(car.global_basis.z.signed_angle_to(vel.normalized(), Vector3.UP)) if vel.length() > 1 else 0.0
			print("s=%5.0f v=%5.1f tgt=%5.1f lat=%5.2f line=%5.2f steer=%5.2f thr=%.2f brk=%.2f R=%4.0f slip=%5.1fdeg latacc=%5.1f" % [track.cum[i], car.forward_speed(), ai.target_speed, track.lateral(car.global_position, i), track.line_offset[i], car.steer_input, car.throttle, car.brake_input, 1.0/maxf(absf(track.line_curv[i]),0.0001), slip, absf(car.angular_velocity.y)*vel.length()])
		if f > 600 and track.cum[i] > float(a[3]) and track.cum[i] < float(a[3]) + 50.0: break
	quit(0)
