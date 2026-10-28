class_name Weekend
extends Node
## Race weekend systems for a single-player race (scripts/race.gd):
##
##  Tyres     every car has a compound and wear (scripts/tyres.gd); grip
##            follows them, for the AI too.
##  Pit stops tap the tyre panel to box: at the pit entry (260 m before the
##            line) the car drives itself down the pit side of the straight
##            at 80 km/h, stops 2.4 s for new tyres, and rejoins 180 m after
##            the line; about 18 s lost. The AI pits when its tyres are
##            gone or the weather turns.
##  Weather   dry, wet, or changing (rain arrives part-way through): the
##            track gets darker and glossy, rain falls, cars throw spray,
##            and slicks lose grip until you fit wets.
##  Qualifying one flying lap (from a rolling out-lap) against the AI's
##            times; the order sets the grid. You can skip it.

const PIT_LEN := 440.0
const STOP_AT := 200.0
const PIT_SPEED := 22.2
const STOP_TIME := 2.4
const ENTRY_BEFORE_LINE := 260.0

var race: Node
var track: Track
var weather := "dry"
var wetness := 0.0
var _rain_from := -1.0                 # changing: leader's race fraction when the rain comes
var qualifying := false
var quali_done := false
var in_quali := false
var grid_order: Array = []             # entrants, pole first (after qualifying)
var quali_results: Array = []          # [{entrant, time}] fastest first
var player_compound := "medium"
var _q_phase := 0
var _q_t := 0.0
var _q_start := 0.0
var _q_valid := true
var _q_best := INF
var _rain: CPUParticles3D
var _spray := {}                       # car -> CPUParticles3D
var _rng := RandomNumberGenerator.new()
var _sun: DirectionalLight3D
var _sun_energy := 1.0
var _env: Environment
var _env_base := {}
var _sky: ShaderMaterial
var _sky_base := {}
var _est_cache := {}
var _tick := 0


func setup(r: Node) -> void:
	race = r
	track = r.track
	var ev: Dictionary = r.event
	var save: Node = r.save
	_rng.seed = hash(track.track_id) + int(Time.get_unix_time_from_system()) % 1000
	weather = String(ev.get("weather", save.get_setting("weather") if ev.is_empty() else "dry"))
	if r.mode != "race":
		weather = String(ev.get("weather", "dry"))
	if ev.is_empty():
		qualifying = r.mode == "race" and bool(save.get_setting("qualifying"))
	else:
		qualifying = bool(ev.get("qualifying", false))
	wetness = 1.0 if weather == "wet" else 0.0
	if weather == "changing":
		_rain_from = _rng.randf_range(0.2, 0.5)
	player_compound = String(ev.get("tyres", save.get_setting("tyres")))
	if not Tyres.COMPOUNDS.has(player_compound):
		player_compound = "medium"
	if weather == "wet":
		player_compound = "wet"
	var laps := float(maxi(int(r.total_laps), 1))
	var k := 0
	for e in r.entrants:
		e.wear = 0.0
		e.stops = 0
		e.pit_phase = 0
		e.pit_req = false
		if e.is_player:
			e.compound = player_compound
		else:
			# A spread of strategies: most on the tyre that lasts the race.
			var best := Tyres.best_for(wetness, laps, track.total_length)
			e.compound = best
			if best != "wet":
				var opts := ["soft", "medium", "hard"]
				var shift: int = [0, 0, 0, 1, -1][k % 5]
				e.compound = opts[clampi(opts.find(best) + shift, 0, 2)]
			k += 1
	for n in r.find_children("*", "DirectionalLight3D", true, false):
		_sun = n
		_sun_energy = _sun.light_energy
	for n in r.find_children("*", "WorldEnvironment", true, false):
		_env = (n as WorldEnvironment).environment
		_env_base = {"fog": _env.fog_density, "amb": _env.ambient_light_energy, "exp": _env.tonemap_exposure}
		if _env.sky != null and _env.sky.sky_material is ShaderMaterial:
			_sky = _env.sky.sky_material
			_sky_base = {"top": _sky.get_shader_parameter("top_color"), "hor": _sky.get_shader_parameter("horizon_color"),
				"cover": _sky.get_shader_parameter("cloud_cover"), "cloud": _sky.get_shader_parameter("cloud_color"),
				"shade": _sky.get_shader_parameter("cloud_shade")}
			for key in _sky_base:
				if _sky_base[key] == null:
					_sky_base[key] = {"top": Color(0.16, 0.36, 0.72), "hor": Color(0.66, 0.78, 0.9), "cover": 0.45, "cloud": Color.WHITE, "shade": Color(0.62, 0.68, 0.78)}[key]
	if weather != "dry":
		_build_rain()
	_apply_weather()


## Reset tyres for a restart (same weather).
func reset() -> void:
	for e in race.entrants:
		e.wear = 0.0
		e.stops = 0
		e.pit_phase = 0
		e.pit_req = false
		if e.is_player:
			e.compound = player_compound
	if weather == "changing":
		wetness = 0.0
	_apply_weather()


# ------------------------------------------------------------ per tick

## Before the AI drives: point pitting cars down the pit lane.
func pre_drive() -> void:
	var n := track.size()
	for e in race.entrants:
		if e.pit_phase == 0:
			continue
		var drv: AIDriver = e.ai if e.ai != null else e.pit_driver
		var lane := track.pit_side * (track.road_half - 1.2)
		drv.lane_offset = lane - track.line_offset[(e.idx + 6) % n]
		drv.speed_cap = 0.0 if e.pit_phase == 2 else PIT_SPEED


func player_in_pit() -> bool:
	return race.player != null and race.player.pit_phase > 0


func drive_player() -> void:
	race.player.pit_driver.update(race.car, track)


func physics(delta: float) -> void:
	_tick += 1
	var racing: bool = int(race.state) == 1 or int(race.state) == 2
	# Changing weather: the rain arrives part-way through the race.
	if _rain_from >= 0.0 and racing:
		var lead := 0.0
		for e in race.entrants:
			lead = maxf(lead, e.progress)
		var frac: float = lead / maxf(track.total_length * race.total_laps, 1.0)
		if frac > _rain_from and wetness < 1.0:
			if wetness == 0.0 and _rain == null:
				_build_rain()
			if wetness == 0.0:
				race.hud.show_banner("Rain is starting: the track will be wet in a lap", UIStyle.YELLOW, 4.0)
			wetness = minf(wetness + delta / 45.0, 1.0)
	for e in race.entrants:
		if e.remote:
			continue
		var c: RaceCar = e.car
		var v := absf(c.forward_speed())
		if racing:
			e.wear = minf(e.wear + Tyres.wear(e.compound, v * delta, c.tyre_slip, wetness), 1.0)
		c.grip_scale = Tyres.grip(e.compound, e.wear, wetness)
		if e.ai != null:
			e.ai.grip_scale = c.grip_scale
		elif e.is_player and race.autopilot != null:
			race.autopilot.grip_scale = c.grip_scale
		if racing:
			_strategy(e)
			_pit(e, delta, v)
	if _tick % 30 == 0:
		_apply_weather()
	if _tick % 6 == 0 and wetness > 0.2:
		_update_spray()
	if in_quali:
		_quali_tick(delta)


## AI: box when the tyres are gone (with racing left) or for the weather.
func _strategy(e) -> void:
	if e.is_player or e.finished or e.pit_req or e.pit_phase > 0 or e.eliminated:
		return
	var laps_left: float = float(race.total_laps) - e.progress / track.total_length
	if laps_left < 0.6:
		return
	var want := Tyres.best_for(wetness, laps_left, track.total_length)
	var weather_call: bool = (want == "wet") != (e.compound == "wet")
	if e.wear > 0.8 or weather_call:
		e.pit_req = true
		e.next_compound = want


## Tyre to fit at your next stop: what suits the conditions and the laps left.
func player_next() -> String:
	var e = race.player
	var laps_left: float = float(race.total_laps) - e.progress / track.total_length
	return Tyres.best_for(wetness, maxf(laps_left - 0.5, 0.5), track.total_length)


func toggle_box() -> void:
	var e = race.player
	if e == null or e.pit_phase > 0 or e.finished:
		return
	e.pit_req = not e.pit_req
	e.next_compound = player_next()
	race.hud.show_banner(("Box this lap: %s tyres" % Tyres.NAMES[e.next_compound]) if e.pit_req else "Staying out", UIStyle.YELLOW if e.pit_req else UIStyle.PAPER, 2.0)


func _pit(e, delta: float, v: float) -> void:
	var L := track.total_length
	var s: float = track.cum[e.idx]
	match e.pit_phase:
		0:
			if not e.pit_req or e.finished:
				return
			var d := fposmod(s - (L - ENTRY_BEFORE_LINE), L)
			if d < 30.0:
				e.pit_phase = 1
				e.pit_dist = d
				e.car.set_ghost(true)
				e.ghost = 0.0
				if e.is_player:
					e.pit_driver = AIDriver.new()
					e.pit_driver.idx = e.idx
					race.hud.show_banner("Pit lane: 80 km/h", UIStyle.YELLOW, 3.0)
		1, 2, 3:
			e.pit_dist += v * delta
			if e.pit_phase == 1 and e.pit_dist >= STOP_AT:
				e.pit_phase = 2
				e.pit_timer = 0.0
			elif e.pit_phase == 2:
				if v < 1.0:
					e.pit_timer += delta
				var need := STOP_TIME + (0.0 if e.is_player else float(e.idx % 7) * 0.12)
				if e.pit_timer >= need:
					e.compound = e.next_compound if Tyres.COMPOUNDS.has(e.next_compound) else "medium"
					e.wear = 0.0
					e.stops += 1
					e.pit_phase = 3
					if e.is_player:
						race.hud.show_banner("%s tyres on: go, go, go!" % Tyres.NAMES[e.compound], UIStyle.GREEN, 2.5)
			elif e.pit_phase == 3 and e.pit_dist >= PIT_LEN:
				e.pit_phase = 0
				e.pit_req = false
				e.ghost = 1.5                  # back to solid once clear (race.gd)
				var drv: AIDriver = e.ai if e.ai != null else e.pit_driver
				drv.lane_offset = 0.0
				drv.speed_cap = 999.0
				if e.is_player:
					e.pit_driver = null


# ------------------------------------------------------------ weather

func _apply_weather() -> void:
	if track.road_mat != null:
		track.road_mat.set_shader_parameter("wetness", wetness)
	var w := wetness if weather != "dry" else 0.0
	if _sun != null:
		_sun.light_energy = _sun_energy * lerpf(1.0, 0.3, w)
		_sun.shadow_opacity = lerpf(1.0, 0.35, w)
	if _sky != null and not _sky_base.is_empty():
		# Overcast: grey sky, full cloud, no sun disc.
		var grey := Color(0.5, 0.53, 0.57)
		_sky.set_shader_parameter("top_color", (_sky_base["top"] as Color).lerp(grey * 0.85, w))
		_sky.set_shader_parameter("horizon_color", (_sky_base["hor"] as Color).lerp(grey * 1.15, w))
		_sky.set_shader_parameter("cloud_cover", lerpf(float(_sky_base["cover"]), 1.0, w))
		_sky.set_shader_parameter("cloud_color", (_sky_base["cloud"] as Color).lerp(Color(0.62, 0.64, 0.67), w))
		_sky.set_shader_parameter("cloud_shade", (_sky_base["shade"] as Color).lerp(Color(0.36, 0.38, 0.42), w))
	if _env != null and not _env_base.is_empty():
		_env.fog_density = float(_env_base["fog"]) * lerpf(1.0, 4.5, w)
		_env.ambient_light_energy = float(_env_base["amb"]) * lerpf(1.0, 0.8, w)
		_env.tonemap_exposure = float(_env_base["exp"]) * lerpf(1.0, 0.9, w)
	if _rain != null:
		_rain.emitting = w > 0.05


func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 1400
	_rain.lifetime = 0.9
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22, 1, 22)
	_rain.direction = Vector3(0.08, -1, 0.04)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0, -12, 0)
	_rain.initial_velocity_min = 22.0
	_rain.initial_velocity_max = 28.0
	_rain.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.85, 0.95, 0.32)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	_rain.mesh = q
	_rain.emitting = false
	add_child(_rain)


func _process(_delta: float) -> void:
	# Rain falls around whichever camera is live.
	if _rain != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_rain.global_position = cam.global_position + Vector3.UP * 14.0 - cam.global_basis.z * 8.0


## Spray off the rear tyres of nearby cars at speed.
func _update_spray() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for e in race.entrants:
		var c: RaceCar = e.car
		var near := c.visible and c.global_position.distance_squared_to(cam.global_position) < 140.0 * 140.0
		var on: bool = near and absf(c.forward_speed()) > 12.0
		if on and not _spray.has(c):
			_spray[c] = _make_spray(c)
		if _spray.has(c):
			var p: CPUParticles3D = _spray[c]
			p.emitting = on and wetness > 0.3


func _make_spray(c: RaceCar) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 0.7
	p.local_coords = false
	p.position = Vector3(0, 0.15, float(c.spec["wheel_rear_z"]) - 0.4)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(float(c.spec["track_rear"]) + 0.2, 0.1, 0.2)
	p.direction = Vector3(0, 0.35, -1)
	p.spread = 18.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -1.5, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.85, 0.88, 0.92, 0.1)
	m.albedo_texture = TyreFX._puff_texture()
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	c.add_child(p)
	return p


# ------------------------------------------------------------ qualifying

## Everyone else off the track; you on a rolling out-lap 700 m before the line.
func begin_qualifying() -> void:
	in_quali = true
	race.state = 3
	for e in race.entrants:
		if e.is_player:
			continue
		e.car.visible = false
		e.car.set_ghost(true)
		e.car.freeze = true
	var n := track.size()
	var i := n - int(700.0 / Track.SPACING)
	race._place(race.player, track.pose_at(i, race.car.spawn_height(), track.line_offset[i]))
	race.car.controls_enabled = true
	race.player.idx = i
	_q_phase = 0
	_q_t = 0.0
	_q_valid = true
	_q_best = INF
	race.cam.snap()
	race.hud.show_lights(0, true)
	race.hud.show_banner("Qualifying: one flying lap from the line. Out-lap first.", UIStyle.PAPER, 4.0)
	race.hud.show_action("Skip qualifying", func(): finish_qualifying(-1.0))


func _quali_tick(delta: float) -> void:
	_q_t += delta
	var e = race.player
	var n := track.size()
	if e.prev_idx > n * 0.9 and e.idx < n * 0.1:
		if _q_phase == 1 and _q_valid:
			finish_qualifying(_q_t - _q_start)
			return
		if _q_phase == 1:
			race.hud.show_banner("Lap deleted (track limits): go again", UIStyle.RED, 2.5)
		else:
			race.hud.show_banner("Flying lap!", UIStyle.GREEN, 1.5)
		_q_phase = 1
		_q_start = _q_t
		_q_valid = true
	if _q_phase == 1 and _q_valid and absf(track.lateral(race.car.global_position, e.idx)) > race.invalid_limit:
		_q_valid = false
		race.hud.show_warning("Track limits: lap deleted", 2.0)
	race.hud.update_timing(1, _q_t - _q_start if _q_phase == 1 else 0.0, -1.0, -1.0, _q_valid)


## AI qualifying pace, from each driver's skill (calibrated against real AI
## laps: tests/lap_calibrate.gd).
func ai_quali_time(e) -> float:
	var model := String(e.car.spec["id"])
	if not _est_cache.has(model):
		_est_cache[model] = track.lap_estimate(CarSpecs.get_spec(model))
	var skill: float = e.ai.skill if e.ai != null else 0.95
	return float(_est_cache[model]) * 0.975 * (1.0 + 0.6 * (1.0 - skill)) * (1.0 + _rng.randf_range(-0.004, 0.004))


## Done (time < 0: skipped, so you get a typical lap for your car).
func finish_qualifying(player_time: float) -> void:
	if not in_quali:
		return
	in_quali = false
	race.hud.hide_action()
	var me: float = player_time
	if me <= 0.0:
		me = track.lap_estimate(race.car.spec) * 0.975 * (1.0 + 0.6 * 0.06)
	quali_results.clear()
	for e in race.entrants:
		quali_results.append({"e": e, "time": me if e.is_player else ai_quali_time(e), "skipped": e.is_player and player_time <= 0.0})
	quali_results.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	grid_order.clear()
	for r in quali_results:
		grid_order.append(r["e"])
	quali_done = true
	race.car.controls_enabled = false
	race.car.linear_velocity = Vector3.ZERO
	var rows: Array = []
	var pole := float(quali_results[0]["time"])
	for k in quali_results.size():
		var r: Dictionary = quali_results[k]
		var e = r["e"]
		rows.append({"pos": k + 1, "name": e.name, "team": e.team, "player": e.is_player,
			"color": e.car.spec["color"], "time": UIStyle.fmt_time(float(r["time"])) + (" *" if r["skipped"] else ""),
			"gap": "" if k == 0 else "+%.3f" % (float(r["time"]) - pole)})
	race.hud.show_quali(rows, player_compound, weather, func(compound: String):
		player_compound = compound
		_end_qualifying())


func _end_qualifying() -> void:
	for e in race.entrants:
		e.car.visible = true
		e.car.set_ghost(false)
		if not e.remote:
			e.car.freeze = false
	race._restart()
