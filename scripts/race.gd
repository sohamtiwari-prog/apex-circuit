extends Node3D
## Time-trial race session: countdown, lap timing with checkpoints and
## track limits, best-lap saving, input, resets.
## The car and track come from the player's saved selection.

enum State { COUNTDOWN, RACING }

const GRAVITY := 9.81

var track: Track
var car: RaceCar
var cam: RaceCamera
var hud: Hud
var audio: CarAudio

var car_id := "gp26"
var track_id := "silvermoor"
var lap_key := ""

var state := State.COUNTDOWN
var countdown := 0.0
var lap := 1
var lap_time := 0.0
var last_lap := -1.0
var lap_valid := true
var progress_idx := 0
var next_checkpoint := 1
var flip_timer := 0.0
var offtrack_limit := 8.0
var invalid_limit := 10.0
var _save_timer := 0.0
var autopilot: AIDriver = null     # when set, the AI drives the player's car (tests/demo)
var save: Node                     # the Save autoload, looked up at runtime


func _ready() -> void:
	save = get_node("/root/Save")
	car_id = String(save.get_setting("car"))
	track_id = String(save.get_setting("track"))
	lap_key = save.lap_key(track_id, car_id)
	DisplayServer.screen_set_keep_on(true)
	_build_environment()

	track = Track.new()
	add_child(track)
	track.build(track_id)
	offtrack_limit = track.road_half + Track.KERB_W + 0.6     # all four wheels off
	invalid_limit = track.road_half + Track.KERB_W + 2.5

	car = RaceCar.new()
	car.setup(CarSpecs.get_spec(car_id, int(save.get_setting("team")) if car_id == "gp26" else 0))
	add_child(car)
	_apply_assists()

	audio = CarAudio.new()
	car.add_child(audio)
	audio.attach(car, true)

	cam = RaceCamera.new()
	add_child(cam)
	cam.set_target(car)
	cam.set_mode(int(save.get_setting("camera")))
	cam.current = true

	hud = Hud.new()
	add_child(hud)
	hud.restart_requested.connect(_restart)
	hud.reset_requested.connect(_reset_car_to_track)
	hud.camera_requested.connect(_cycle_camera)
	hud.settings_changed.connect(_apply_assists)
	hud.menu_requested.connect(_quit_to_menu)
	hud.set_camera_name(cam.mode_name())

	_restart()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.45, 0.82)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.9)
	sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.18)
	sky_mat.ground_horizon_color = Color(0.55, 0.62, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.0006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)


func _apply_assists() -> void:
	if car != null:
		car.traction_control = bool(save.get_setting("traction_control"))
		car.abs_enabled = bool(save.get_setting("abs"))


# ------------------------------------------------------------ session

func _place_car(idx: int) -> void:
	car.global_transform = track.pose_at(idx, car.spawn_height())
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_controls()
	cam.snap()


func _restart() -> void:
	var n := track.size()
	progress_idx = (n - 5) % n
	_place_car(progress_idx)
	car.controls_enabled = false
	state = State.COUNTDOWN
	countdown = 3.99
	lap = 1
	lap_time = 0.0
	last_lap = -1.0
	lap_valid = true
	next_checkpoint = 1
	flip_timer = 0.0
	hud.show_banner("%s  ·  %s  ·  TIME TRIAL" % [track.track_name.to_upper(), String(car.spec["name"]).to_upper()], Color.WHITE, 3.0)


func _reset_car_to_track() -> void:
	var idx := track.nearest_index(car.global_position, -1)
	_place_car(idx)
	progress_idx = idx
	flip_timer = 0.0
	if state == State.RACING:
		lap_valid = false
		hud.show_warning("Car reset: lap invalidated")


func _cycle_camera() -> void:
	var m := cam.cycle()
	hud.set_camera_name(cam.mode_name())
	save.set_setting("camera", m)


func _quit_to_menu() -> void:
	save.save()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if hud != null and not hud.is_paused():
			hud.set_paused(true)
		if save != null:
			save.save()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_P:
				hud.set_paused(not hud.is_paused())
			KEY_C:
				_cycle_camera()
			KEY_R:
				_reset_car_to_track()


# ------------------------------------------------------------ per frame

func _read_input() -> void:
	var t: TouchControls = hud.touch
	var steer := 0.0
	if save.get_setting("control_mode") == "tilt":
		var acc := Input.get_accelerometer()
		# In landscape, gravity along the screen's x axis = steering-wheel roll.
		# Full lock at roughly 30 degrees of tilt.
		var s := acc.x / (GRAVITY * 0.5) * float(save.get_setting("tilt_sensitivity"))
		if bool(save.get_setting("invert_tilt")):
			s = -s
		if absf(s) < 0.04:
			s = 0.0
		steer = clampf(s, -1.0, 1.0)
	else:
		steer = t.steer
	var gas: float = t.gas
	var brk: float = t.brake

	# Keyboard, for testing on a computer.
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		steer = -1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		steer = 1.0
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		gas = 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_SPACE):
		brk = 1.0

	car.steer_input = steer
	car.throttle = gas
	car.brake_input = brk


func _physics_process(delta: float) -> void:
	if autopilot != null:
		autopilot.update(car, track)
	else:
		_read_input()
	var n := track.size()
	var pos := car.global_position
	var idx := track.nearest_index(pos, progress_idx)
	var lat := absf(track.lateral(pos, idx))

	# Grass slows the car; going well wide invalidates the lap (track limits).
	car.surface_drag = 0.55 if lat > offtrack_limit else 0.0
	if state == State.RACING and lat > invalid_limit and lap_valid:
		lap_valid = false
		hud.show_warning("Track limits: lap invalidated", 2.5)

	if state == State.COUNTDOWN:
		countdown -= delta
		if countdown <= 0.0:
			state = State.RACING
			car.controls_enabled = true
			hud.show_center("GO!")
			get_tree().create_timer(0.8).timeout.connect(func(): hud.show_center(""))
		else:
			hud.show_center(str(int(ceil(countdown))))
	else:
		lap_time += delta
		save.add_distance(absf(car.forward_speed()) * delta)
		# Checkpoints at 25/50/75% must be passed in order.
		var quarter := int(idx * 4 / n)
		if quarter == next_checkpoint and next_checkpoint < 4:
			next_checkpoint += 1
		# Crossing the start/finish line forwards.
		if progress_idx > n * 0.9 and idx < n * 0.1:
			if next_checkpoint >= 4:
				_complete_lap()
			next_checkpoint = 1

	progress_idx = idx

	# Auto-recover when upside down or stuck on its side.
	if car.global_basis.y.y < 0.35 and car.linear_velocity.length() < 4.0:
		flip_timer += delta
		if flip_timer > 2.0:
			_reset_car_to_track()
	else:
		flip_timer = 0.0

	_save_timer += delta
	if _save_timer > 30.0:
		_save_timer = 0.0
		save.save()

	var best_ms: int = save.get_best_lap(lap_key)
	hud.update_timing(lap, lap_time if state == State.RACING else 0.0, last_lap,
		best_ms / 1000.0 if best_ms >= 0 else -1.0, lap_valid)
	hud.update_speed(car.speed_kmh())
	hud.update_engine(car.gear, car.rpm, float(car.spec["upshift_rpm"]), float(car.spec["redline"]))


func _complete_lap() -> void:
	last_lap = lap_time
	var ms := int(round(lap_time * 1000.0))
	if lap_valid:
		var prev_best: int = save.get_best_lap(lap_key)
		var is_best: bool = save.submit_lap(lap_key, ms)
		if is_best:
			var msg := "NEW BEST  " + Hud.fmt_time(lap_time)
			if prev_best >= 0:
				msg += "   (-%.3f)" % ((prev_best - ms) / 1000.0)
			hud.show_banner(msg, Color(0.35, 1.0, 0.45))
		else:
			var diff := (ms - prev_best) / 1000.0
			hud.show_banner("LAP %d  %s   (+%.3f)" % [lap, Hud.fmt_time(lap_time), diff], Color.WHITE)
	else:
		hud.show_banner("LAP %d  %s   INVALID" % [lap, Hud.fmt_time(lap_time)], Color(1, 0.5, 0.4))
	lap += 1
	lap_time = 0.0
	lap_valid = true
