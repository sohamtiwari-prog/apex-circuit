extends Node3D
## A session at one track: either a time trial (just you) or a race against
## a full grid of AI cars with a standing start, live positions and results.
## Car, track, mode, laps and difficulty come from the player's settings.

enum State { GRID, RACING, FINISHED, QUALI }

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
	var sector := 0             # sector being driven (0..2)
	var slot := -1              # grid slot (multiplayer: the car's id on every phone)
	var net_id := 0             # multiplayer: the peer driving it (0 = bot)
	var remote := false         # driven by another phone
	var drs_armed := false      # passed a detection line within 1 s of the car ahead
	var sector_start := 0.0
	var mini := 0               # minisector being driven (0..MINIS-1)
	var outside := 0.0          # seconds spent beyond the barriers
	var eliminated := false     # eliminator events: out of the race
	var driver := -1            # championship: index in the season's driver list
	# Race weekend (scripts/weekend.gd): tyres and pit stops.
	var compound := "medium"
	var wear := 0.0
	var stops := 0
	var pit_req := false
	var next_compound := "medium"
	var pit_phase := 0          # 0 racing, 1 down the pit lane, 2 stopped, 3 leaving
	var pit_dist := 0.0
	var pit_timer := 0.0
	var pit_driver: AIDriver    # drives you through the pit lane
	var mini_start := 0.0


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
# Ghost of the best lap (time trial): 20 samples/s of position + rotation.
const GHOST_HZ := 20.0
var _ghost_rec := PackedFloat32Array()
var _ghost_play := PackedFloat32Array()
var ghost_car: RaceCar
var session_sectors := [INF, INF, INF]   # fastest of anyone this session
var _my_session_sectors := [INF, INF, INF]
## Minisectors: each sector is split into 8 equal parts (24 a lap), coloured
## purple / green / yellow like the sectors as you cross each one.
const MINIS_PER_SECTOR := 8
const MINIS := MINIS_PER_SECTOR * 3
var session_minis: Array = []
var _my_session_minis: Array = []
var offtrack_limit := 8.0
var invalid_limit := 10.0
var _save_timer := 0.0
var _tick := 0
var _results_shown := false
var _ranked := false                 # this race's rank points have been awarded
var _difficulty := "medium"
var _assist_profile := PackedFloat32Array()
var _assist_centre := PackedFloat32Array()
var _assist_driver: AIDriver = null
var _wedged := 0.0
var _tilt := 0.0
var tyre_fx: TyreFX
var _graphics_high := true
var line_guide: LineGuide
var _still := 0.0                 # player: seconds stuck with the throttle on
var recoveries := 0               # automatic car recoveries (stats/tests)
const STEER_ASSIST_BLEND := 0.35
var autopilot: AIDriver = null     # when set, the AI drives the player's car (tests/demo)
var save: Node                     # the Save autoload, looked up at runtime
var net: NetRace = null            # multiplayer session, if any
var Net: Node                      # the Net autoload, looked up at runtime
var _tod := ""
var replay: Replay
## Career / championship event being raced ({} for a quick race); see
## scripts/career.gd. ev_type: race, duel, overtake, eliminator, time_trial.
var event: Dictionary = {}
var ev_type := ""
var tt_targets: Array = []
var _elim_lap := 0
var last_reward := {}                  # what the results screen showed (tests)
var weekend: Weekend                   # tyres, pits, weather, qualifying (single player)


func _ready() -> void:
	save = get_node("/root/Save")
	Net = get_node("/root/Net")
	car_id = String(save.get_setting("car"))
	track_id = String(save.get_setting("track"))
	mode = String(save.get_setting("mode"))
	total_laps = int(save.get_setting("laps"))
	_tod = String(save.get_setting("time_of_day"))
	_difficulty = String(save.get_setting("difficulty"))
	var net_info: Dictionary = {}
	if Net.is_online() and not Net.start_info.is_empty():
		net_info = Net.start_info
		var st: Dictionary = net_info["settings"]
		track_id = String(st["track"])
		total_laps = int(st["laps"])
		_tod = String(st.get("tod", "day"))
		_difficulty = String(st.get("difficulty", "medium"))
		mode = "race"
		for g in net_info["grid"]:
			if g["kind"] == "player" and int(g["id"]) == Net.my_id:
				car_id = String(g["car"])
	if net_info.is_empty() and not save.pending_event.is_empty():
		event = save.pending_event
		ev_type = String(event["type"])
		track_id = String(event["track"])
		car_id = String(event["car"])
		total_laps = int(event["laps"])
		mode = "time_trial" if ev_type == "time_trial" else "race"
		var sk := float(event.get("skill", 0.92))
		_difficulty = "easy" if sk < 0.89 else ("medium" if sk < 0.93 else "hard")
	lap_key = save.lap_key(track_id, car_id)
	DisplayServer.screen_set_keep_on(true)

	track = Track.new()
	add_child(track)
	track.build(track_id)
	_build_environment()
	offtrack_limit = track.road_half + Track.KERB_W + 0.6     # all four wheels off
	invalid_limit = track.road_half + Track.KERB_W + 2.5

	if not net_info.is_empty():
		_spawn_net_grid(net_info)
	else:
		var team := int(save.get_setting("team"))
		car = RaceCar.new()
		car.setup(save.car_spec(car_id, team if car_id == "gp26" else 0))
		add_child(car)
		player = Entrant.new()
		player.car = car
		player.is_player = true
		player.name = "You"
		player.team = String(car.spec.get("team_name", car.spec["name"]))
		entrants.append(player)
		if mode == "race":
			_spawn_opponents(team)
		if ev_type == "time_trial":
			# Targets from the standard car, so upgrades help you beat them.
			tt_targets = Career.lap_targets(track, CarSpecs.get_spec(car_id))
	_apply_assists()

	audio = CarAudio.new()
	car.add_child(audio)
	audio.attach(car, true)

	cam = RaceCamera.new()
	add_child(cam)
	cam.set_target(car)
	cam.set_mode(int(save.get_setting("camera")))
	cam.current = true

	tyre_fx = TyreFX.new()
	add_child(tyre_fx)
	tyre_fx.camera = cam
	var all_cars: Array = []
	for e in entrants:
		all_cars.append(e.car)
	tyre_fx.setup(all_cars)
	line_guide = LineGuide.new()
	add_child(line_guide)
	if mode == "time_trial":
		_load_ghost()
	_apply_assists()

	hud = Hud.new()
	add_child(hud)
	hud.restart_requested.connect(_restart)
	hud.reset_requested.connect(func(): _reset_to_track(player, true))
	hud.camera_requested.connect(_cycle_camera)
	hud.settings_changed.connect(_apply_assists)
	hud.menu_requested.connect(_quit_to_menu)
	hud.set_camera_name(cam.mode_name())
	hud.set_race_mode(mode == "race", total_laps)
	hud.set_track(track.points)
	if mode == "time_trial":
		hud.set_ideal(save.ideal_lap(lap_key, MINIS))
	if not net_info.is_empty():
		hud.net_mode = true
		net = NetRace.new()
		add_child(net)
		net.setup(self)
		hud.enable_chat(Net.CHAT)
		hud.chat_requested.connect(func(i: int): Net.chat(i))
		Net.chat_received.connect(_on_chat)

	if net == null:
		weekend = Weekend.new()
		add_child(weekend)
		weekend.setup(self)
		hud.box_requested.connect(func(): weekend.toggle_box())
	replay = Replay.new()
	add_child(replay)
	replay.setup(self)
	replay.finished.connect(_on_replay_closed)
	hud.replay_requested.connect(func(): watch_replay(true))
	hud.replay_available = net == null

	_restart()
	if weekend != null and weekend.qualifying:
		weekend.begin_qualifying()


func _spawn_opponents(player_team: int) -> void:
	var count := int(save.get_setting("opponents"))
	var difficulty := String(save.get_setting("difficulty"))
	var base_skill: float = {"easy": 0.86, "medium": 0.93, "hard": 0.985}.get(difficulty, 0.93)
	var models: Array = [car_id]
	if not event.is_empty():
		count = int(event["opponents"])
		base_skill = float(event["skill"])
		models = event.get("cars", [car_id])
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
		var model: String = models[(i + 1) % models.size()] if models.size() > 1 else String(models[0])
		if model != "gp26" and car_id == "gp26":
			t = i + 1
		var drv: Dictionary = {}
		if event.has("drivers") and i + 1 < (event["drivers"] as Array).size():
			drv = event["drivers"][i + 1]
			model = String(drv["car"])
			t = int(drv["team"])
		c.setup(CarSpecs.get_spec(model, t))
		add_child(c)
		if c.body != null:
			c.body.set_number(_race_number(i, t))
		var a := CarAudio.new()
		c.add_child(a)
		a.attach(c, false)
		e.car = c
		e.ai = AIDriver.new()
		# Spread the field: each driver a little different, front-runners quicker.
		e.ai.skill = clampf(base_skill + rng.randf_range(-0.025, 0.02) - i * 0.0015, 0.75, 1.0)
		if ev_type == "duel":
			e.ai.skill = base_skill               # one rival: no spread
		e.name = DRIVER_NAMES[i % DRIVER_NAMES.size()]
		if not drv.is_empty():
			e.ai.skill = float(drv["skill"])
			e.name = String(drv["name"])
			e.driver = i + 1
		e.team = String(c.spec.get("team_name", c.spec["name"]))
		entrants.append(e)


## A car's race number: team-mates get neighbouring numbers.
static func _race_number(i: int, team: int) -> int:
	return [4, 7, 11, 16, 22, 27, 31, 44, 55, 63, 77, 81, 3, 10, 14, 18, 23, 38, 50, 88][(team * 2 + i % 2) % 20]


func _build_environment() -> void:
	Look.build(self, track.style, _tod)


## Multiplayer grid from the host's start message: your car, your friends'
## cars (driven by their phones) and bots (driven by the host's phone).
func _spawn_net_grid(info: Dictionary) -> void:
	for g in info["grid"]:
		var e := Entrant.new()
		e.slot = int(g["slot"])
		e.name = String(g["name"])
		var c := RaceCar.new()
		c.setup(CarSpecs.get_spec(String(g["car"]), int(g["team"])))
		add_child(c)
		e.car = c
		e.team = String(c.spec.get("team_name", c.spec["name"]))
		if g["kind"] == "player":
			e.net_id = int(g["id"])
		if g["kind"] == "player" and e.net_id == Net.my_id:
			e.is_player = true
			player = e
			car = c
		else:
			if g["kind"] == "bot" and Net.is_host():
				e.ai = AIDriver.new()
				e.ai.skill = float(g["skill"])
			else:
				e.remote = true
				NetRace.make_remote(c)
			var a := CarAudio.new()
			c.add_child(a)
			a.attach(c, false)
			if e.net_id > 0:
				# Friends get a name tag above their car.
				var tag := Label3D.new()
				tag.text = e.name
				tag.font = UIStyle.font("bold", true)
				tag.font_size = 64
				tag.pixel_size = 0.012
				tag.outline_size = 14
				tag.modulate = UIStyle.PAPER
				tag.outline_modulate = Color(0, 0, 0, 0.7)
				tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				tag.no_depth_test = true
				tag.position = Vector3(0, 1.9, 0)
				tag.visibility_range_end = 160.0
				c.add_child(tag)
		entrants.append(e)


func _apply_assists() -> void:
	if car != null:
		car.traction_control = bool(save.get_setting("traction_control"))
		car.abs_enabled = bool(save.get_setting("abs"))
	if line_guide != null:
		line_guide.visible = bool(save.get_setting("racing_line"))
	var high := String(save.get_setting("graphics")) != "saver"
	if high != _graphics_high:
		_graphics_high = high
		Look.apply_quality(self, high)


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
	var drv: AIDriver = e.ai if e.ai != null else (autopilot if e.is_player else null)
	if drv != null:
		drv.idx = e.idx
		drv.lane_offset = 0.0
		drv.speed_cap = 999.0


func _restart() -> void:
	_results_shown = false
	_ranked = false
	_rewarded = false
	hud.hide_results()
	replay.clear()
	# Player starts mid-grid in a race; on the line in a time trial.
	var player_slot := mini(9, entrants.size() - 1) if mode == "race" else 0
	match ev_type:
		"race", "eliminator":
			player_slot = int((entrants.size() - 1) * 0.6)
		"overtake":
			player_slot = entrants.size() - 1
		"duel":
			player_slot = 1
	var k := 0
	for e in entrants:
		var slot := player_slot if e.is_player else (k if k < player_slot else k + 1)
		if not e.is_player:
			k += 1
		if net != null:
			slot = e.slot
		elif weekend != null and not weekend.grid_order.is_empty():
			slot = weekend.grid_order.find(e)
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
		e.sector = 0
		e.sector_start = 0.0
		e.mini = 0
		e.mini_start = 0.0
		e.drs_armed = false
		e.car.drs_open = false
		e.eliminated = false
		e.car.visible = true
		if not e.remote:
			e.car.freeze = false
	if weekend != null:
		weekend.reset()
	session_sectors = [INF, INF, INF]
	_my_session_sectors = [INF, INF, INF]
	session_minis.resize(MINIS)
	session_minis.fill(INF)
	_my_session_minis.resize(MINIS)
	_my_session_minis.fill(INF)
	_ghost_rec = PackedFloat32Array()
	if ghost_car != null:
		ghost_car.visible = false
	hud.reset_sectors()
	cam.snap()
	state = State.GRID
	race_time = 0.0
	lights_time = 0.0
	lights_out_at = 5.0 + randf_range(0.2, 1.4)
	if net != null and not Net.is_host():
		lights_out_at = 1e9              # the host decides when the lights go out
	lap_valid = true
	_elim_lap = 0
	var title := "%d-lap race" % total_laps if mode == "race" else "Time trial"
	if not event.is_empty():
		title = "%s: %s" % [Career.TYPE_NAMES.get(ev_type, "Race"), title]
	if not tt_targets.is_empty():
		get_tree().create_timer(3.2).timeout.connect(func():
			hud.show_banner("Gold %s   Silver %s   Bronze %s" % [UIStyle.fmt_time(tt_targets[0]), UIStyle.fmt_time(tt_targets[1]), UIStyle.fmt_time(tt_targets[2])], UIStyle.YELLOW, 4.0))
	hud.show_banner("%s, %s" % [track.track_name, title], UIStyle.PAPER, 3.0)
	hud.show_center("")
	for e in entrants:
		e.idx = track.nearest_index(e.car.global_position, -1)
		e.progress = track.cum[e.idx] - (track.total_length if e.idx > track.size() / 2 else 0.0)
	_update_positions()


func _reset_to_track(e: Entrant, manual: bool) -> void:
	if not manual:
		recoveries += 1
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


## Replays: from the results (the whole race) or the pause menu (the last
## 30 seconds, then back to the pause menu).
var _replay_from_pause := false

func watch_replay(from_pause: bool) -> void:
	if replay.playing or not replay.can_play():
		return
	if net != null:
		for e in entrants:
			if not e.finished:
				return
	_replay_from_pause = from_pause
	var from := replay.race_start_frame()
	if from_pause:
		hud.set_paused(false)
		from = maxi(replay.count - int(Replay.HZ * 30.0), 0)
	replay.start(from)


func _on_replay_closed() -> void:
	if _replay_from_pause:
		hud.set_paused(true)


## Slipstream for the cars simulated here (scripts/car_contacts.gd).
func _slipstream() -> void:
	var mine: Array = []
	var all: Array = []
	for e in entrants:
		if e.eliminated:
			continue
		all.append(e.car)
		if not e.remote:
			mine.append(e.car)
	CarContacts.slipstream(mine, all)


func _cycle_camera() -> void:
	var m := cam.cycle()
	hud.set_camera_name(cam.mode_name())
	save.set_setting("camera", m)


func _on_chat(from: int, text: String) -> void:
	var players: Dictionary = Net.get_meta("players", {})
	var who := "Host" if from == 1 else "Friend"
	if players.has(from):
		who = String(players[from].get("name", who))
	hud.show_chat(who, text)


## Car-to-car contact between the cars simulated on this phone
## (scripts/car_contacts.gd); other players' cars are handled by NetRace.
## A car-to-car contact began: (car_a, car_b, closing speed m/s).
signal car_contact(a: RaceCar, b: RaceCar, closing: float)
var _touching := {}
func _car_contacts(delta: float) -> void:
	var cars: Array = []
	for e in entrants:
		if not e.remote and not e.car.freeze and not e.car.is_ghost:
			cars.append(e.car)
	for hit in CarContacts.step(cars, delta, _touching):
		car_contact.emit(hit[0], hit[1], hit[2])


func leave_to_menu() -> void:
	_quit_to_menu()


func go_to_lobby() -> void:
	save.save()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _quit_to_menu() -> void:
	if net != null:
		net.ended = true
		Net.leave()
	save.save()
	get_tree().paused = false
	var back := String(event.get("return_to", "res://scenes/menu.tscn"))
	save.pending_event = {}
	get_tree().change_scene_to_file(back if net == null else "res://scenes/hub.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if replay != null and replay.playing:
			replay.set_paused(true)
		elif hud != null and not hud.is_paused() and not _results_shown:
			hud.set_paused(true)
		if save != null:
			save.save()


func _unhandled_input(event: InputEvent) -> void:
	if replay.playing:
		return
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
	var control := String(save.get_setting("control_mode"))
	if control == "tilt":
		var acc := Input.get_accelerometer()
		# In landscape, gravity along the screen's x axis = steering-wheel roll.
		# Full lock at roughly 30 degrees of tilt.
		var s := acc.x / (GRAVITY * 0.5) * float(save.get_setting("tilt_sensitivity"))
		if bool(save.get_setting("invert_tilt")):
			s = -s
		if absf(s) < 0.04:
			s = 0.0
		# Smooth out hand tremor and sensor noise (~60 ms).
		_tilt = lerpf(_tilt, clampf(s, -1.0, 1.0), 1.0 - exp(-16.0 * get_physics_process_delta_time()))
		steer = _tilt
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

	# Steering assist (like RR3's): adds a little racing-line steering while
	# your own input is small, and fades out completely as soon as you steer
	# yourself, so it never holds you back from using the whole track (or
	# leaving it). No invisible walls. Moderate = half the help.
	var steer_help: float = save.assist_level("steer_assist")
	if steer_help > 0.0:
		if _assist_driver == null:
			_assist_driver = AIDriver.new()
		var share := STEER_ASSIST_BLEND * steer_help * clampf(1.0 - absf(steer) * 1.4, 0.0, 1.0)
		if share > 0.0:
			var fix := clampf(_assist_driver.line_steer(car, track, player.idx) - steer, -0.4, 0.4)
			# Moderate never steers against you (it only adds to your turn);
			# Full may pull you back towards the line, which beginners need.
			if steer_help < 1.0 and absf(steer) > 0.06 and signf(fix) != signf(steer):
				fix *= 0.25
			steer = clampf(steer + fix * share, -1.0, 1.0)

	# Brake assist: brakes for you when arriving at a corner too fast.
	# Full: brakes to the ideal corner speed. Moderate: only steps in when
	# you're clearly too fast, and more gently, so late braking is yours.
	var brake_help: float = save.assist_level("brake_assist")
	if brake_help > 0.0 and state == State.RACING:
		if _assist_profile.size() != track.size():
			_assist_profile = track.speed_profile(car.spec)
		if _assist_centre.size() != track.size():
			_assist_centre = track.speed_profile(car.spec, true)
		var v := car.forward_speed()
		var ahead := (player.idx + 3 + int(absf(v) * 0.05)) % track.size()
		var full := brake_help >= 1.0
		# Off the racing line the corner is tighter: blend towards the speeds
		# for the middle of the road the further you are from the line.
		var off_line := absf(track.lateral(car.global_position, player.idx) - track.line_offset[player.idx])
		var planned: float = lerpf(_assist_profile[ahead], minf(_assist_profile[ahead], _assist_centre[ahead]), clampf(off_line / 3.0, 0.0, 1.0))
		var target: float = planned * (1.04 if full else 1.12)
		var margin := 1.0 if full else 2.5
		if v > target + margin:
			var assist := clampf((v - target) / (6.0 if full else 10.0), 0.0, 1.0 if full else 0.6)
			brk = maxf(brk, assist)
			gas = minf(gas, 1.0 - assist)

	# Wedged against a wall with the throttle down: recover automatically
	# when assists are on (otherwise the RESET button is there).
	if steer_help > 0.0 and state == State.RACING and gas > 0.5 and absf(car.forward_speed()) < 1.0:
		_wedged += get_physics_process_delta_time()
		if _wedged > 3.0:
			_wedged = 0.0
			_reset_to_track(player, false)
			hud.show_warning("Car reset to track")
	else:
		_wedged = 0.0

	car.steer_input = steer
	car.throttle = gas
	car.brake_input = brk


func _physics_process(delta: float) -> void:
	if replay.playing:
		return                          # the replay is posing the cars
	_tick += 1
	if weekend != null and weekend.player_in_pit():
		weekend.drive_player()
	elif autopilot != null:
		autopilot.update(car, track)
	else:
		_read_input()

	_car_contacts(delta)
	match state:
		State.GRID:
			_update_lights(delta)
		State.RACING, State.FINISHED:
			race_time += delta

	# AI drivers think at 60 Hz (half the physics rate) and check traffic at
	# 30 Hz: plenty for driving, and keeps a full grid cheap on a phone.
	if _tick % 4 == 0 and state != State.QUALI:
		_traffic()
	if weekend != null:
		weekend.pre_drive()
	if _tick % 2 == 0 and state != State.QUALI:
		for e in entrants:
			if e.ai != null and not (e.finished and e.car.forward_speed() < 1.0) and not e.eliminated:
				e.ai.update(e.car, track)
				if e.finished:
					e.ai.speed_cap = 25.0      # cool-down lap

	if net != null:
		net.physics_tick(delta)
	for e in entrants:
		_update_entrant(e, delta)
	if weekend != null:
		weekend.physics(delta)
	if (_tick % 6 == 0 or state == State.FINISHED) and (net == null or Net.is_host()):
		_update_positions()

	# Grass and gravel: less grip and more rolling drag per wheel that's on
	# them (kerbs and asphalt run-off count as track). Going well wide invalidates a time-trial lap.
	if _tick % 2 == 0:
		for e in entrants:
			for w in e.car.wheels:
				w.surface = track.surface_at(e.idx, track.lateral(w.global_position, e.idx))
	var lat := absf(track.lateral(car.global_position, player.idx))
	if mode == "time_trial" and state == State.RACING and lat > invalid_limit and lap_valid:
		lap_valid = false
		hud.show_warning("Track limits: lap invalidated", 2.5)

	_save_timer += delta
	if _save_timer > 30.0:
		_save_timer = 0.0
		save.save()
	if state != State.GRID:
		save.add_distance(absf(car.forward_speed()) * delta)

	if mode == "time_trial":
		_update_ghost()

	if line_guide != null and line_guide.visible:
		if _assist_profile.size() != track.size():
			_assist_profile = track.speed_profile(car.spec)
		line_guide.update_guide(car, track, _assist_profile, player.idx, delta)

	if _tick % 2 == 1:
		_slipstream()
	if net != null and _results_shown and _tick % 30 == 0 and hud.replay_button != null:
		# With friends, the replay opens once every car is home (watching
		# stops this phone's part of the race).
		var done := true
		for e in entrants:
			done = done and e.finished
		hud.replay_button.disabled = not done
		hud.replay_button.text = "Replay" if done else "Replay soon"
	if _tick % 3 == 0:
		_update_hud()
	replay.capture(delta)


func _update_lights(delta: float) -> void:
	if net != null:
		if Net.is_host():
			if not net.all_ready(delta):
				return                    # wait for everyone's phone to load
			lights_time += delta
		# Clients: lights_time comes from the host.
	else:
		lights_time += delta
	var lit := clampi(int(lights_time), 0, 5)
	if lights_time < lights_out_at:
		hud.show_lights(lit, false)
		track.trackside.set_lights(lit)
	else:
		hud.show_lights(0, true)
		track.trackside.set_lights(0)
		state = State.RACING
		race_time = 0.0
		for e in entrants:
			e.car.controls_enabled = true
			e.lap_start = 0.0
			var drv: AIDriver = e.ai if e.ai != null else (autopilot if e.is_player else null)
			if drv != null:
				# Start from the grid column, not the racing line.
				var i := (e.idx + 6) % track.size()
				drv.lane_offset = track.lateral(e.car.global_position, e.idx) - track.line_offset[i]
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
	if state == State.GRID or state == State.QUALI:
		return
	# Checkpoints at 25/50/75% must be passed in order.
	var quarter := int(e.idx * 4 / n)
	if quarter == e.next_checkpoint and e.next_checkpoint < 4:
		e.next_checkpoint += 1
	if not track.drs_zones.is_empty() and e.car.spec["body"] == "gp":
		_update_drs(e)
	# Sector lines at a third and two thirds of the lap.
	for k in [0, 1]:
		var line: int = n * (k + 1) / 3
		if e.sector == k and e.prev_idx < line and e.idx >= line and e.idx - e.prev_idx < n / 4:
			_complete_sector(e, k)
	_update_minis(e)
	# Crossing the line forwards.
	if e.prev_idx > n * 0.9 and e.idx < n * 0.1:
		if e.next_checkpoint >= 4 and not e.finished:
			_complete_lap(e)
		e.next_checkpoint = 1
	e.progress = e.lap * track.total_length + track.cum[e.idx]
	if e.idx > n * 0.9 and e.lap == 0 and e.next_checkpoint == 1:
		e.progress -= track.total_length        # still behind the line at the start

	# Beyond the barriers (or under the track): back on after a second.
	if not e.remote and state == State.RACING and not e.finished:
		var pos := e.car.global_position
		var lat := track.lateral(pos, e.idx)
		var beyond := absf(lat) > track.wall_at(e.idx, signf(lat)) + 1.2
		if beyond or pos.y < track.points[e.idx].y - 3.0:
			e.outside += delta
			if e.outside > 1.0:
				e.outside = 0.0
				_reset_to_track(e, false)
				if e.is_player:
					hud.show_banner("Back on track", UIStyle.YELLOW, 2.0)
					if mode == "time_trial":
						lap_valid = false
				return
		else:
			e.outside = 0.0
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
		# Sitting still against something with the throttle on: point at Reset.
		if state == State.RACING and not e.finished and e.car.linear_velocity.length() < 1.5 and e.car.throttle > 0.3:
			_still += delta
			if _still > 4.0:
				_still = -6.0
				hud.show_banner("Stuck? Tap Reset", UIStyle.YELLOW, 3.0)
		else:
			_still = 0.0
		if e.car.global_basis.y.y < 0.35 and e.car.linear_velocity.length() < 4.0:
			e.stuck += delta
			if e.stuck > 2.0:
				e.stuck = 0.0
				_reset_to_track(e, false)
		else:
			e.stuck = 0.0


## True if the car passed sample `mark` between its last two positions.
func _crossed(e: Entrant, mark: int) -> bool:
	var n := track.size()
	var step := posmod(e.idx - e.prev_idx, n)
	var to_mark := posmod(mark - e.prev_idx, n)
	return step < n / 4 and to_mark > 0 and to_mark <= step


## DRS: armed at the detection line if within 1 s of the car ahead (from
## lap 2 in a race; always in a time trial); open through the zone until
## the driver brakes.
func _update_drs(e: Entrant) -> void:
	for z in track.drs_zones:
		if _crossed(e, z["detect"]):
			e.drs_armed = mode == "time_trial" or (e.lap >= 1 and _gap_ahead(e) < 1.0)
	var zone := track.drs_zone_at(e.idx)
	if zone < 0:
		if e.car.drs_open:
			e.drs_armed = false
		e.car.drs_open = false
	elif e.drs_armed and state == State.RACING:
		if e.car.brake_input > 0.05:
			e.car.drs_open = false
			e.drs_armed = false
		elif e.car.throttle > 0.5:
			e.car.drs_open = true


## Seconds behind the car one place ahead (99 if leading).
func _gap_ahead(e: Entrant) -> float:
	for o in entrants:
		if o.position == e.position - 1:
			return (o.progress - e.progress) / maxf(e.car.forward_speed(), 15.0)
	return 99.0


## Purple: fastest of anyone this session (time trial: your all-time best).
## Green: your best this session. Yellow: slower. Grey: lap not valid.
func _rate(t: float, pb: float, session_best: float, my_best: float) -> Color:
	if not (mode == "race" or lap_valid):
		return UIStyle.FOG
	var fastest: bool = t <= session_best and (pb < 0.0 or t <= pb or mode == "race")
	if mode == "time_trial":
		fastest = pb < 0.0 or t <= pb
	if fastest:
		return UIStyle.PURPLE
	if t <= my_best:
		return UIStyle.GREEN
	return UIStyle.YELLOW


## The first sector/minisector of a race also covers the run from the grid,
## so it never counts as a best.
func _standing_start(e: Entrant, first: bool) -> bool:
	return first and e.lap == 0 and mode == "race"


func _complete_sector(e: Entrant, k: int) -> void:
	var t := race_time - e.sector_start
	e.sector_start = race_time
	e.sector = (k + 1) % 3
	if t < 3.0:
		return
	var counts := not _standing_start(e, k == 0)
	if not e.is_player:
		if counts:
			session_sectors[k] = minf(session_sectors[k], t)
		return
	var pb: float = save.get_best_sector(lap_key, k)
	var colour := UIStyle.YELLOW
	if counts:
		colour = _rate(t, pb, session_sectors[k], _my_session_sectors[k])
		if colour != UIStyle.FOG:
			_my_session_sectors[k] = minf(_my_session_sectors[k], t)
			session_sectors[k] = minf(session_sectors[k], t)
			save.submit_sector(lap_key, k, t)
	hud.show_sector(k, t, (t - pb) if pb > 0.0 else 0.0, colour)


## Minisector lines are equal slices of the lap; the last one is the finish
## line, completed in _complete_lap.
func _update_minis(e: Entrant) -> void:
	var n := track.size()
	if e.mini < MINIS - 1 and _crossed(e, n * (e.mini + 1) / MINIS):
		_complete_mini(e, e.mini)
		return
	# A reset that jumped the car forward: skip the minisectors it missed.
	var cur: int = clampi(e.idx * MINIS / n, 0, MINIS - 1)
	var ahead := posmod(cur - e.mini, MINIS)
	if ahead >= 2 and ahead < MINIS / 2:
		if e.is_player:
			for m in range(e.mini, cur):
				hud.show_mini(m, -1.0, 0.0, UIStyle.FOG)
		e.mini = cur
		e.mini_start = race_time


func _complete_mini(e: Entrant, m: int) -> void:
	var t := race_time - e.mini_start
	e.mini_start = race_time
	e.mini = (m + 1) % MINIS
	if t < 0.3:
		return
	var counts := not _standing_start(e, m == 0)
	if not e.is_player:
		if counts:
			session_minis[m] = minf(session_minis[m], t)
		return
	var pb: float = save.get_best_mini(lap_key, m)
	var colour := UIStyle.YELLOW
	if counts:
		colour = _rate(t, pb, session_minis[m], _my_session_minis[m])
		if colour != UIStyle.FOG:
			_my_session_minis[m] = minf(_my_session_minis[m], t)
			session_minis[m] = minf(session_minis[m], t)
			if save.submit_mini(lap_key, m, t) and mode == "time_trial":
				hud.set_ideal(save.ideal_lap(lap_key, MINIS))
	hud.show_mini(m, t, (t - pb) if pb > 0.0 else 0.0, colour)


func _complete_lap(e: Entrant) -> void:
	if e.sector == 2:
		_complete_sector(e, 2)
	e.sector = 0
	e.sector_start = race_time
	if e.mini == MINIS - 1:
		_complete_mini(e, MINIS - 1)
	e.mini = 0
	e.mini_start = race_time
	var lap_time := race_time - e.lap_start
	e.lap_start = race_time
	e.lap += 1
	e.last_lap = lap_time
	if e.best_lap < 0.0 or lap_time < e.best_lap:
		e.best_lap = lap_time
	if mode == "race" and e.lap >= total_laps:
		e.finished = true
		e.finish_time = race_time
	if ev_type == "time_trial" and e.is_player and e.lap >= total_laps:
		e.finished = true
		e.finish_time = race_time
	replay.on_lap(e, lap_time)
	if ev_type == "eliminator" and e.lap > _elim_lap and e.lap < total_laps and not e.eliminated:
		_elim_lap = e.lap
		_eliminate_last()
	if e.is_player and not e.eliminated:
		_player_lap(lap_time)
		if e.finished:
			_player_finished()


func _player_lap(lap_time: float) -> void:
	var ms := int(round(lap_time * 1000.0))
	if mode == "race" or lap_valid:
		var prev_best: int = save.get_best_lap(lap_key)
		var is_best: bool = save.submit_lap(lap_key, ms)
		if is_best and mode == "time_trial" and _ghost_rec.size() > 14 * 7:
			_ghost_play = _ghost_rec.duplicate()
			_save_ghost()
		if is_best:
			var msg := "New best lap  " + Hud.fmt_time(lap_time)
			if prev_best >= 0:
				msg += "   -%.3f" % ((prev_best - ms) / 1000.0)
			hud.show_banner(msg, UIStyle.PURPLE)
		elif prev_best >= 0:
			hud.show_banner("Lap %d  %s   +%.3f" % [player.lap, Hud.fmt_time(lap_time), (ms - prev_best) / 1000.0], UIStyle.PAPER)
	else:
		hud.show_banner("Lap %d  %s   invalid (track limits)" % [player.lap, Hud.fmt_time(lap_time)], UIStyle.RED)
	lap_valid = true
	_ghost_rec = PackedFloat32Array()
	if mode == "race" and player.lap == total_laps - 1:
		hud.show_center("Final lap")
		get_tree().create_timer(1.5).timeout.connect(func(): hud.show_center(""))


func _player_finished() -> void:
	state = State.FINISHED
	if autopilot == null:
		# Hand the car to the AI for the cool-down lap.
		autopilot = AIDriver.new()
		autopilot.speed_cap = 30.0
	if ev_type == "time_trial":
		hud.show_center("")
	else:
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
	var fastest: Entrant = null
	for e in ordered:
		if e.best_lap > 0.0 and (fastest == null or e.best_lap < fastest.best_lap):
			fastest = e
	for e in ordered:
		var gap := ""
		if e == winner:
			gap = Hud.fmt_time(e.finish_time) if e.finished else ""
		elif e.eliminated:
			gap = "Out, lap %d" % (e.lap + 1)
		elif e.finished:
			gap = "+%.3f" % (e.finish_time - winner.finish_time)
		else:
			var laps_down: int = winner.lap - e.lap
			gap = "+%d lap%s" % [laps_down, "" if laps_down == 1 else "s"] if laps_down >= 1 else "Running"
		rows.append({"pos": e.position, "name": e.name, "team": e.team, "gap": gap,
			"best": Hud.fmt_time(e.best_lap) if e.best_lap > 0.0 else "-", "player": e.is_player,
			"color": e.car.spec["color"], "fastest": e == fastest})
	var rank := _award_rank(fastest == player)
	var watch := func(): watch_replay(false)
	var reward := _settle_rewards()
	last_reward = reward
	if ev_type == "champ_round":
		# Points are in: no retries, on to the standings.
		hud.show_results(rows, func(): _quit_to_menu(), func(): _quit_to_menu(), "Standings", rank, watch, reward)
	elif net == null:
		hud.show_results(rows, func(): _restart(), func(): _quit_to_menu(), "Try again" if not event.is_empty() else "Race again", rank, watch, reward)
	elif Net.is_host():
		hud.show_results(rows, func(): net.back_to_lobby(), func(): _quit_to_menu(), "Back to lobby", rank, watch)
	else:
		hud.show_results(rows, Callable(), func(): _quit_to_menu(), "Race again", rank, watch)
	if net != null and hud.replay_button != null:
		hud.replay_button.disabled = true      # until every car is home (see _physics_process)


## Credits (and career stars) for this finish, once per race.
var _rewarded := false

func _settle_rewards() -> Dictionary:
	if net != null or _rewarded or player == null:
		return {}
	_rewarded = true
	if event.is_empty():
		if mode != "race" or not player.finished:
			return {}
		var cr := Career.quick_reward(player.position, entrants.size(), total_laps, _difficulty)
		save.add_credits(cr)
		return {"credits": cr}
	if ev_type == "champ_round":
		var order: Array = []
		var ordered := entrants.duplicate()
		ordered.sort_custom(_by_position)
		var fastest := -1
		var fl := INF
		for e in ordered:
			order.append(maxi(e.driver, 0) if not e.is_player else 0)
			if e.best_lap > 0.0 and e.best_lap < fl:
				fl = e.best_lap
				fastest = 0 if e.is_player else e.driver
		var out := Championship.record_round(save, order, fastest)
		var base := int({"gp": 6000, "hyper": 4500, "super": 3500, "sports": 2500, "muscle": 1800}.get(String(Championship.active(save).get("class", "gp")), 3000))
		var cr := Garage.race_reward(base, player.position, entrants.size())
		save.add_credits(cr)
		return {"champ": out, "credits": cr, "event": event, "position": player.position}
	if not event.has("id") or String(event["id"]) == "":
		return {}
	var stars := 0
	if ev_type == "time_trial":
		stars = Career.stars_for_lap(player.best_lap, tt_targets)
	else:
		stars = Career.stars_for_position(ev_type, player.position)
	var prev: int = save.career_stars(String(event["id"]))
	var fresh: int = save.set_career_stars(String(event["id"]), stars)
	var cr := Career.reward(event, player.position, entrants.size(), stars, fresh)
	save.add_credits(cr)
	return {"event": event, "stars": stars, "prev": prev, "new": fresh, "credits": cr,
		"targets": tt_targets, "best": player.best_lap, "position": player.position}


## Eliminator: the last car still running is out.
func _eliminate_last() -> void:
	_update_positions()
	var left := 0
	var last: Entrant = null
	for e in entrants:
		if e.eliminated:
			continue
		left += 1
		if last == null or e.position > last.position:
			last = e
	if last == null or left <= 1:
		return
	last.eliminated = true
	last.finished = true
	last.finish_time = race_time
	last.car.set_ghost(true)
	last.car.visible = false
	last.car.controls_enabled = false
	last.car.freeze = true
	_update_positions()
	if last.is_player:
		hud.show_banner("You're out!  P%d" % last.position, UIStyle.RED)
		_player_finished()
	else:
		hud.show_banner("%s is out" % last.name, UIStyle.RED, 2.5)


## Rank points for this finish (races only, once per race).
func _award_rank(fastest_lap: bool) -> Dictionary:
	if mode != "race" or _ranked or player == null or not player.finished:
		return {}
	_ranked = true
	var humans := 0
	for e in entrants:
		if e.is_player or e.net_id > 0:
			humans += 1
	var award := Ranks.race_points(player.position, entrants.size(), _difficulty, total_laps, fastest_lap, humans > 1)
	var before := int(save.data.get("rank_points", 0))
	var after: int = save.add_rank_points(int(award["total"]))
	if Net.is_online():
		Net.set_meta("my_rp", after)
	return {"award": award, "before": before, "after": after}


# ------------------------------------------------------------ race order

func _by_position(a: Entrant, b: Entrant) -> bool:
	# Knocked out (eliminator): behind everyone still in, the last out ahead.
	if a.eliminated != b.eliminated:
		return b.eliminated
	if a.eliminated:
		return a.finish_time > b.finish_time
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
## Racecraft for every AI-driven car, 30 times a second:
##  - keeps a gap it could always stop in behind the car ahead in its path;
##  - overtakes only into free space (no car alongside or about to be);
##  - never steers into a car that is alongside;
##  - off the start, holds its grid column until the field has spread out.
const CAR_LEN := 5.4
const SIDE_CLEAR := 2.95          # centre-to-centre lateral spacing when alongside
const FOLLOW_DECEL := 7.0         # m/s^2: braking assumed when keeping a safe gap

func _traffic() -> void:
	if entrants.size() < 2 or state == State.GRID:
		return
	var L := track.total_length
	var n := track.size()
	var lim := maxf(track.road_half - 1.2, 0.5)
	for e in entrants:
		var drv: AIDriver = e.ai
		if drv == null and e.is_player:
			drv = autopilot
		if drv == null or e.pit_phase > 0 or e.eliminated:
			continue
		var my_s: float = track.cum[e.idx]
		var my_lat := track.lateral(e.car.global_position, e.idx)
		var v := e.car.forward_speed()
		var line_here: float = track.line_offset[(e.idx + 6) % n]
		var lead: Entrant = null
		var lead_gap := 999.0
		var lead_lat := 0.0
		var beside: Array[float] = []        # lateral positions of cars alongside
		for o in entrants:
			if o == e or o.ghost > 0.0 or o.eliminated or o.pit_phase > 0:
				continue
			var gap := fposmod(track.cum[o.idx] - my_s + L * 0.5, L) - L * 0.5
			# Mirrors: a faster car coming up behind counts as alongside sooner.
			var mirror := CAR_LEN * 1.4 + maxf(o.car.forward_speed() - v, 0.0) * 0.8
			if gap < -mirror or gap > 80.0:
				continue
			var o_lat := track.lateral(o.car.global_position, o.idx)
			var dlat := o_lat - my_lat
			# Ahead and in our path (even if only partly): the car to follow.
			if gap > 0.5 and absf(dlat) < 2.6 and gap < lead_gap:
				lead = o
				lead_gap = gap
				lead_lat = o_lat
			# Overlapping lengthwise: keep lateral clearance from it.
			if gap < CAR_LEN * 1.4 and absf(dlat) < SIDE_CLEAR + 1.6:
				beside.append(o_lat)

		var cap := 999.0
		var target := line_here + drv.lane_offset    # by default: keep the current lane
		var returning := true
		if lead != null:
			var o_v := lead.car.forward_speed()
			var room := lead_gap - CAR_LEN
			# Safe following (Gipps): slow enough to stop behind them even if
			# they brake as hard as we can, allowing a reaction delay.
			cap = sqrt(o_v * o_v + 2.0 * FOLLOW_DECEL * maxf(room, 0.0)) - FOLLOW_DECEL * 0.35
			if room < 1.0:
				cap = minf(cap, o_v - 2.0)
			# Faster than them, or they're slow: look for a way past.
			if lead_gap < 45.0 and (v > o_v + 0.5 or o_v < 15.0):
				var room_right := track.road_half - lead_lat
				var room_left := track.road_half + lead_lat
				var sides := [1.0, -1.0] if room_right > room_left else [-1.0, 1.0]
				for side in sides:
					var want: float = clampf(lead_lat + side * 3.1, -lim, lim)
					if absf(want - lead_lat) < 2.6:
						continue                   # not enough road on that side
					if _lane_free(want, beside):
						target = want
						returning = false
						break
		elif e.lap == 0 and e.progress < 280.0 and drv.lane_offset != 0.0:
			# Opening run: stay in the grid column, merge gently.
			target = line_here + move_toward(drv.lane_offset, 0.0, 0.02)
			returning = false
		if returning and lead == null:
			target = line_here                         # back to the racing line
		# Never steer into a car alongside: keep SIDE_CLEAR from each.
		for b in beside:
			if absf(target - b) < SIDE_CLEAR:
				var away := signf(my_lat - b)
				if away == 0.0:
					away = 1.0
				target = b + away * SIDE_CLEAR
		target = clampf(target, -lim, lim)
		drv.speed_cap = maxf(cap, 4.0)
		var want_offset := target - line_here
		drv.lane_offset = move_toward(drv.lane_offset, want_offset, 0.09)


func _lane_free(lat: float, beside: Array[float]) -> bool:
	for b in beside:
		if absf(lat - b) < SIDE_CLEAR:
			return false
	return true


# ------------------------------------------------------------ HUD

func _update_hud() -> void:
	var lap_time := race_time - player.lap_start if state != State.GRID else 0.0
	var best_ms: int = save.get_best_lap(lap_key)
	var shown_lap := mini(player.lap + 1, total_laps) if mode == "race" else player.lap + 1
	if state != State.QUALI:
		hud.update_timing(shown_lap, lap_time, player.last_lap,
			best_ms / 1000.0 if best_ms >= 0 else -1.0, lap_valid or mode == "race")
	if weekend != null and mode == "race":
		hud.set_tyres(player.compound, player.wear, player.pit_req, player.next_compound, player.pit_phase > 0)
	hud.update_engine(car.gear, car.rpm, float(car.spec["upshift_rpm"]), float(car.spec["redline"]),
		float(car.spec["idle_rpm"]), car.speed_kmh())
	hud.set_tow(car.tow)
	if car.spec["body"] == "gp" and not track.drs_zones.is_empty():
		hud.set_drs(3 if car.drs_open else (2 if player.drs_armed else 1))
	else:
		hud.set_drs(0)
	if _tick % 9 == 0:
		var dots: Array = []
		for e in entrants:
			dots.append([e.car.global_position, e.car.spec["color"], e.is_player])
		hud.update_map(dots)
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
				rows.append({"pos": i + 1, "name": e.name, "gap": gap, "player": e.is_player, "color": e.car.spec["color"]})
		hud.update_position(player.position, entrants.size(), rows)


# ------------------------------------------------------------ ghost car

func _ghost_path() -> String:
	return "user://ghosts/%s.bin" % lap_key.replace("|", "__")


func _load_ghost() -> void:
	if FileAccess.file_exists(_ghost_path()):
		var f := FileAccess.open(_ghost_path(), FileAccess.READ)
		var v: Variant = f.get_var()
		if v is PackedFloat32Array:
			_ghost_play = v


func _save_ghost() -> void:
	DirAccess.make_dir_recursive_absolute("user://ghosts")
	var f := FileAccess.open(_ghost_path(), FileAccess.WRITE)
	if f != null:
		f.store_var(_ghost_play)


func ghost_ready() -> bool:
	return ghost_car != null and _ghost_play.size() > 14 * 7


func _make_ghost_car() -> void:
	ghost_car = RaceCar.new()
	ghost_car.setup(CarSpecs.get_spec(car_id, int(save.get_setting("team")) if car_id == "gp26" else 0))
	ghost_car.freeze = true
	ghost_car.collision_layer = 0
	ghost_car.collision_mask = 0
	add_child(ghost_car)
	ghost_car.set_physics_process(false)
	ghost_car.collision_layer = 0
	ghost_car.collision_mask = 0
	for g in ghost_car.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		gi.transparency = 0.62
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Records this lap and replays the best one, in step with the lap clock.
func _update_ghost() -> void:
	if state != State.RACING:
		return
	var t := (race_time - player.lap_start) * GHOST_HZ
	# Record.
	while _ghost_rec.size() / 7 <= int(t):
		var xf := car.global_transform
		var q := xf.basis.get_rotation_quaternion()
		_ghost_rec.append_array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w])
	# Replay.
	var show := bool(save.get_setting("ghost")) and _ghost_play.size() > 14 * 7
	if not show:
		if ghost_car != null:
			ghost_car.visible = false
		return
	if ghost_car == null:
		_make_ghost_car()
	var count := _ghost_play.size() / 7
	var i := int(t)
	if i + 1 >= count:
		ghost_car.visible = false
		return
	var f := t - i
	var a := i * 7
	var b := a + 7
	var p := Vector3(_ghost_play[a], _ghost_play[a + 1], _ghost_play[a + 2]).lerp(
		Vector3(_ghost_play[b], _ghost_play[b + 1], _ghost_play[b + 2]), f)
	var qa := Quaternion(_ghost_play[a + 3], _ghost_play[a + 4], _ghost_play[a + 5], _ghost_play[a + 6])
	var qb := Quaternion(_ghost_play[b + 3], _ghost_play[b + 4], _ghost_play[b + 5], _ghost_play[b + 6])
	ghost_car.global_transform = Transform3D(Basis(qa.slerp(qb, f)), p)
	# Fade it out when it's right on top of you.
	ghost_car.visible = p.distance_to(car.global_position) > 2.5
