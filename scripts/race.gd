extends Node3D
## A session at one track: either a time trial (just you) or a race against
## a full grid of AI cars with a standing start, live positions and results.
## Car, track, mode, laps and difficulty come from the player's settings.

enum State { GRID, RACING, FINISHED }

const GRAVITY := 9.81
const DRIVER_NAMES := [
	"L. Novak", "M. Okafor", "R. Castellano", "D. Lindqvist", "S. Haddad", "K. Watanabe",
	"A. Moreau", "J. Fitzgerald", "T. Varga", "P. Almeida", "E. Kowalski", "H. Brandt",
	"C. Reyes", "N. Ivanova", "F. Rossi", "G. Mbeki", "O. Halvorsen", "V. Sato",
	"I. Dubois", "B. Mendes", "Y. Park", "Z. Abara",
]


## One car in the session, player or AI.
class Entrant:
	var car: RaceCar
	var ai: AIDriver            # null for the player
	var name := ""
	var team := ""
	var idx := 0
	var prev_idx := 0
	var lap := 0                # completed laps
	var next_checkpoint := 1
	var lap_start := 0.0
	var best_lap := -1.0
	var last_lap := -1.0
	var finished := false
	var finish_time := 0.0
	var progress := 0.0         # metres covered since the start
	var position := 0
	var stuck := 0.0
	var ghost := 0.0            # seconds left as a non-colliding ghost after a reset
	var is_player := false


var track: Track
var car: RaceCar
var cam: RaceCamera
var hud: Hud
var audio: CarAudio
var player: Entrant
var entrants: Array[Entrant] = []

var mode := "race"                # "race" or "time_trial"
var total_laps := 3
var car_id := "gp26"
var track_id := "silvermoor"
var lap_key := ""

var state := State.GRID
var race_time := 0.0
var lights_time := 0.0
var lights_out_at := 0.0
var lap_valid := true
var offtrack_limit := 8.0
var invalid_limit := 10.0
var _save_timer := 0.0
var _tick := 0
var _results_shown := false
var autopilot: AIDriver = null     # when set, the AI drives the player's car (tests/demo)
var save: Node                     # the Save autoload, looked up at runtime


func _ready() -> void:
	save = get_node("/root/Save")
	car_id = String(save.get_setting("car"))
	track_id = String(save.get_setting("track"))
	mode = String(save.get_setting("mode"))
	total_laps = int(save.get_setting("laps"))
	lap_key = save.lap_key(track_id, car_id)
	DisplayServer.screen_set_keep_on(true)
	_build_environment()

	track = Track.new()
	add_child(track)
	track.build(track_id)
	offtrack_limit = track.road_half + Track.KERB_W + 0.6     # all four wheels off
	invalid_limit = track.road_half + Track.KERB_W + 2.5

	var team := int(save.get_setting("team"))
	car = RaceCar.new()
	car.setup(CarSpecs.get_spec(car_id, team if car_id == "gp26" else 0))
	add_child(car)
	_apply_assists()
	player = Entrant.new()
	player.car = car
	player.is_player = true
	player.name = "You"
	player.team = String(car.spec.get("team_name", car.spec["name"]))
	entrants.append(player)

	if mode == "race":
		_spawn_opponents(team)

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
	hud.reset_requested.connect(func(): _reset_to_track(player, true))
	hud.camera_requested.connect(_cycle_camera)
	hud.settings_changed.connect(_apply_assists)
	hud.menu_requested.connect(_quit_to_menu)
	hud.set_camera_name(cam.mode_name())
	hud.set_race_mode(mode == "race", total_laps)

	_restart()


func _spawn_opponents(player_team: int) -> void:
	var count := int(save.get_setting("opponents"))
	var difficulty := String(save.get_setting("difficulty"))
	var base_skill: float = {"easy": 0.86, "medium": 0.93, "hard": 0.985}.get(difficulty, 0.93)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_id) + count
	# GP: two cars per team (the player's teammate first); road: varied paint.
	var slots: Array = []
	if car_id == "gp26":
		slots.append(player_team)
		for t in range(CarSpecs.TEAMS.size()):
			if t != player_team:
				slots.append(t)
				slots.append(t)
		slots.append(player_team)
	else:
		for i in range(count):
			slots.append(i + 1)
	for i in range(count):
		var e := Entrant.new()
		var t: int = slots[i % slots.size()]
		var c := RaceCar.new()
		c.setup(CarSpecs.get_spec(car_id, t))
		add_child(c)
		var a := CarAudio.new()
		c.add_child(a)
		a.attach(c, false)
		e.car = c
		e.ai = AIDriver.new()
		# Spread the field: each driver a little different, front-runners quicker.
		e.ai.skill = clampf(base_skill + rng.randf_range(-0.025, 0.02) - i * 0.0015, 0.75, 1.0)
		e.name = DRIVER_NAMES[i % DRIVER_NAMES.size()]
		e.team = String(c.spec.get("team_name", c.spec["name"]))
		entrants.append(e)


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

## Grid slot k: two columns, staggered, 8 m between rows, behind the line.
func _grid_pose(k: int) -> Transform3D:
	var n := track.size()
	var back := 6.0 + (k / 2) * 8.0 + (k % 2) * 4.0
	var idx := (n - int(back / Track.SPACING)) % n
	var side := (-1.0 if k % 2 == 0 else 1.0) * minf(track.road_half * 0.45, 3.2)
	return track.pose_at(idx, entrants[0].car.spawn_height(), side)


func _place(e: Entrant, xform: Transform3D) -> void:
	e.car.global_transform = xform
	e.car.linear_velocity = Vector3.ZERO
	e.car.angular_velocity = Vector3.ZERO
	e.car.reset_controls()
	e.idx = track.nearest_index(xform.origin, -1)
	e.prev_idx = e.idx
	if e.ai != null:
		e.ai.idx = e.idx
		e.ai.lane_offset = 0.0
		e.ai.speed_cap = 999.0


func _restart() -> void:
	_results_shown = false
	hud.hide_results()
	# Player starts mid-grid in a race; on the line in a time trial.
	var player_slot := mini(9, entrants.size() - 1) if mode == "race" else 0
	var k := 0
	for e in entrants:
		var slot := player_slot if e.is_player else (k if k < player_slot else k + 1)
		if not e.is_player:
			k += 1
		_place(e, _grid_pose(slot))
		e.car.controls_enabled = false
		e.lap = 0
		e.next_checkpoint = 1
		e.lap_start = 0.0
		e.best_lap = -1.0
		e.last_lap = -1.0
		e.finished = false
		e.progress = 0.0
		e.stuck = 0.0
		e.ghost = 0.0
		e.car.set_ghost(false)
	cam.snap()
	state = State.GRID
	race_time = 0.0
	lights_time = 0.0
	lights_out_at = 5.0 + randf_range(0.2, 1.4)
	lap_valid = true
	var title := "RACE · %d LAPS" % total_laps if mode == "race" else "TIME TRIAL"
	hud.show_banner("%s  ·  %s" % [track.track_name.to_upper(), title], Color.WHITE, 3.0)
	hud.show_center("")
	for e in entrants:
		e.idx = track.nearest_index(e.car.global_position, -1)
		e.progress = track.cum[e.idx] - (track.total_length if e.idx > track.size() / 2 else 0.0)
	_update_positions()


func _reset_to_track(e: Entrant, manual: bool) -> void:
	var idx := track.nearest_index(e.car.global_position, -1)
	_place(e, track.pose_at(idx, e.car.spawn_height(), track.line_offset[idx]))
	e.car.controls_enabled = state == State.RACING
	if state != State.GRID:
		e.ghost = 3.0
		e.car.set_ghost(true)
	if e.is_player:
		cam.snap()
		if manual and state == State.RACING and mode == "time_trial":
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
		if hud != null and not hud.is_paused() and not _results_shown:
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
				_reset_to_track(player, true)


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
	_tick += 1
	if autopilot != null:
		autopilot.update(car, track)
	else:
		_read_input()

	match state:
		State.GRID:
			_update_lights(delta)
		State.RACING, State.FINISHED:
			race_time += delta

	# AI drivers think at 60 Hz (half the physics rate) and check traffic at
	# 30 Hz: plenty for driving, and keeps a full grid cheap on a phone.
	if _tick % 4 == 0:
		_traffic()
	if _tick % 2 == 0:
		for e in entrants:
			if e.ai != null and not (e.finished and e.car.forward_speed() < 1.0):
				e.ai.update(e.car, track)
				if e.finished:
					e.ai.speed_cap = 25.0      # cool-down lap

	for e in entrants:
		_update_entrant(e, delta)
	if _tick % 6 == 0 or state == State.FINISHED:
		_update_positions()

	# Grass slows the player; going well wide invalidates a time-trial lap.
	var lat := absf(track.lateral(car.global_position, player.idx))
	car.surface_drag = 0.55 if lat > offtrack_limit else 0.0
	if mode == "time_trial" and state == State.RACING and lat > invalid_limit and lap_valid:
		lap_valid = false
		hud.show_warning("Track limits: lap invalidated", 2.5)

	_save_timer += delta
	if _save_timer > 30.0:
		_save_timer = 0.0
		save.save()
	if state != State.GRID:
		save.add_distance(absf(car.forward_speed()) * delta)

	if _tick % 3 == 0:
		_update_hud()


func _update_lights(delta: float) -> void:
	lights_time += delta
	var lit := clampi(int(lights_time), 0, 5)
	if lights_time < lights_out_at:
		hud.show_lights(lit, false)
	else:
		hud.show_lights(0, true)
		state = State.RACING
		race_time = 0.0
		for e in entrants:
			e.car.controls_enabled = true
			e.lap_start = 0.0
		hud.show_center("GO!")
		get_tree().create_timer(0.8).timeout.connect(func(): hud.show_center(""))


func _update_entrant(e: Entrant, delta: float) -> void:
	var n := track.size()
	e.prev_idx = e.idx
	e.idx = track.track_index(e.car.global_position, e.idx)
	if e.ghost > 0.0:
		e.ghost -= delta
		if e.ghost <= 0.0:
			e.car.set_ghost(false)
	if state == State.GRID:
		return
	# Checkpoints at 25/50/75% must be passed in order.
	var quarter := int(e.idx * 4 / n)
	if quarter == e.next_checkpoint and e.next_checkpoint < 4:
		e.next_checkpoint += 1
	# Crossing the line forwards.
	if e.prev_idx > n * 0.9 and e.idx < n * 0.1:
		if e.next_checkpoint >= 4 and not e.finished:
			_complete_lap(e)
		e.next_checkpoint = 1
	e.progress = e.lap * track.total_length + track.cum[e.idx]
	if e.idx > n * 0.9 and e.lap == 0 and e.next_checkpoint == 1:
		e.progress -= track.total_length        # still behind the line at the start

	# AI recovery: flipped or stuck for a while -> back on the racing line.
	var ai_driven := e.ai != null or (e.is_player and autopilot != null)
	if ai_driven and not e.finished:
		var flipped := e.car.global_basis.y.y < 0.35
		var slow := e.car.forward_speed() < 4.0
		var off_road := absf(track.lateral(e.car.global_position, e.idx)) > track.road_half + 4.0
		e.stuck = e.stuck + delta if (flipped or slow or off_road) else maxf(e.stuck - delta, 0.0)
		if e.stuck > 3.5:
			e.stuck = 0.0
			_reset_to_track(e, false)
	elif e.is_player:
		if e.car.global_basis.y.y < 0.35 and e.car.linear_velocity.length() < 4.0:
			e.stuck += delta
			if e.stuck > 2.0:
				e.stuck = 0.0
				_reset_to_track(e, false)
		else:
			e.stuck = 0.0


func _complete_lap(e: Entrant) -> void:
	var lap_time := race_time - e.lap_start
	e.lap_start = race_time
	e.lap += 1
	e.last_lap = lap_time
	if e.best_lap < 0.0 or lap_time < e.best_lap:
		e.best_lap = lap_time
	if mode == "race" and e.lap >= total_laps:
		e.finished = true
		e.finish_time = race_time
	if e.is_player:
		_player_lap(lap_time)
		if e.finished:
			_player_finished()


func _player_lap(lap_time: float) -> void:
	var ms := int(round(lap_time * 1000.0))
	if mode == "race" or lap_valid:
		var prev_best: int = save.get_best_lap(lap_key)
		var is_best: bool = save.submit_lap(lap_key, ms)
		if is_best:
			var msg := "NEW BEST  " + Hud.fmt_time(lap_time)
			if prev_best >= 0:
				msg += "   (-%.3f)" % ((prev_best - ms) / 1000.0)
			hud.show_banner(msg, Color(0.35, 1.0, 0.45))
		elif prev_best >= 0:
			hud.show_banner("LAP %d  %s   (+%.3f)" % [player.lap, Hud.fmt_time(lap_time), (ms - prev_best) / 1000.0], Color.WHITE)
	else:
		hud.show_banner("LAP %d  %s   INVALID" % [player.lap, Hud.fmt_time(lap_time)], Color(1, 0.5, 0.4))
	lap_valid = true
	if mode == "race" and player.lap == total_laps - 1:
		hud.show_center("FINAL LAP")
		get_tree().create_timer(1.5).timeout.connect(func(): hud.show_center(""))


func _player_finished() -> void:
	state = State.FINISHED
	if autopilot == null:
		# Hand the car to the AI for the cool-down lap.
		autopilot = AIDriver.new()
		autopilot.speed_cap = 30.0
	hud.show_center("P%d" % player.position)
	save.record_race(track_id, car_id, player.position, entrants.size())
	get_tree().create_timer(2.5).timeout.connect(_show_results)


func _show_results() -> void:
	if _results_shown:
		return
	_results_shown = true
	hud.show_center("")
	var rows: Array = []
	var ordered := entrants.duplicate()
	ordered.sort_custom(_by_position)
	var winner: Entrant = ordered[0]
	for e in ordered:
		var gap := ""
		if e == winner:
			gap = Hud.fmt_time(e.finish_time) if e.finished else ""
		elif e.finished:
			gap = "+%.3f" % (e.finish_time - winner.finish_time)
		else:
			var laps_down: int = winner.lap - e.lap
			gap = "+%d lap%s" % [laps_down, "" if laps_down == 1 else "s"] if laps_down >= 1 else "running"
		rows.append({"pos": e.position, "name": e.name, "team": e.team, "gap": gap,
			"best": Hud.fmt_time(e.best_lap) if e.best_lap > 0.0 else "-", "player": e.is_player})
	hud.show_results(rows, func(): _restart(), func(): _quit_to_menu())


# ------------------------------------------------------------ race order

func _by_position(a: Entrant, b: Entrant) -> bool:
	# Finished cars by finishing time, then everyone else by distance covered.
	if a.finished and b.finished:
		return a.finish_time < b.finish_time
	if a.finished != b.finished:
		return a.finished
	return a.progress > b.progress


func _update_positions() -> void:
	var ordered := entrants.duplicate()
	ordered.sort_custom(_by_position)
	for i in range(ordered.size()):
		(ordered[i] as Entrant).position = i + 1


## Simple racecraft: when a slower car is just ahead on a similar line, pull
## out to pass if faster, otherwise hold back to its speed. Slow or stopped
## cars (crashed, spun) are obstacles to drive around, never cars to queue behind.
func _traffic() -> void:
	if entrants.size() < 2 or state == State.GRID:
		return
	var L := track.total_length
	for e in entrants:
		var drv: AIDriver = e.ai
		if drv == null and e.is_player:
			drv = autopilot
		if drv == null:
			continue
		var my_lat := track.lateral(e.car.global_position, e.idx)
		var v := e.car.forward_speed()
		var cap := 999.0
		var want_offset := 0.0
		var best_gap := 999.0
		for o in entrants:
			if o == e:
				continue
			var gap := fposmod(track.cum[o.idx] - track.cum[e.idx], L)
			if gap > 45.0 or gap < 0.5:
				continue
			var o_lat := track.lateral(o.car.global_position, o.idx)
			var o_v := o.car.forward_speed()
			var dlat := o_lat - my_lat
			if absf(dlat) > 2.6:
				continue                       # not on our line
			var closing := v - o_v
			if closing <= 0.5 and gap > 10.0:
				continue
			if gap > best_gap:
				continue                       # react to the nearest car only
			best_gap = gap
			# Pass on the side with more room.
			var room_left := track.road_half + o_lat
			var room_right := track.road_half - o_lat
			var side := 1.0 if room_right > room_left else -1.0
			want_offset = side * 3.2 + (o_lat - track.line_offset[e.idx])
			var obstacle := o_v < 12.0
			if not obstacle and gap < 14.0 and absf(dlat) < 2.0 and maxf(room_left, room_right) < 4.5:
				cap = o_v + (gap - 6.0) * 0.6   # no room to pass: follow
			elif obstacle and gap < 25.0:
				cap = 14.0                      # slow down to thread past
		drv.speed_cap = maxf(cap, 6.0)
		drv.lane_offset = move_toward(drv.lane_offset, clampf(want_offset, -6.0, 6.0), 0.16)


# ------------------------------------------------------------ HUD

func _update_hud() -> void:
	var lap_time := race_time - player.lap_start if state != State.GRID else 0.0
	var best_ms: int = save.get_best_lap(lap_key)
	var shown_lap := mini(player.lap + 1, total_laps) if mode == "race" else player.lap + 1
	hud.update_timing(shown_lap, lap_time, player.last_lap,
		best_ms / 1000.0 if best_ms >= 0 else -1.0, lap_valid or mode == "race")
	hud.update_speed(car.speed_kmh())
	hud.update_engine(car.gear, car.rpm, float(car.spec["upshift_rpm"]), float(car.spec["redline"]))
	if mode == "race" and _tick % 12 == 0:
		var ordered := entrants.duplicate()
		ordered.sort_custom(_by_position)
		var rows: Array = []
		var me := player.position - 1
		for i in range(ordered.size()):
			var e: Entrant = ordered[i]
			if i < 2 or absf(i - me) <= 1:
				var gap := ""
				if i > 0:
					var ahead: Entrant = ordered[i - 1]
					var v := maxf(e.car.forward_speed(), 15.0)
					gap = "+%.1f" % ((ahead.progress - e.progress) / v)
				rows.append({"pos": i + 1, "name": e.name, "gap": gap, "player": e.is_player})
		hud.update_position(player.position, entrants.size(), rows)
