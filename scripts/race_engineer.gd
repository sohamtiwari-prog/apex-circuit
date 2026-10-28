class_name RaceEngineer
extends Node
## The voice on the radio, the marshals' flags and the feel through your
## hands, for the player's car.
##
##  Radio   lap times with the gaps ahead and behind, places gained and
##          lost, a car closing in behind, fastest laps, worn tyres, rain,
##          the last lap and the result.
##  Flags   yellow when a car has stopped or spun on the track ahead of you
##          (within 300 m), blue when the leaders come to lap you.
##  Haptics a buzz through the phone for contact with other cars and the
##          barriers (stronger for harder hits), kerbs and grass.

var race: Node
var radio_log: Array[String] = []        # everything said (tests)
var flags_seen := {}                     # kind -> true (tests)
var buzzes := 0                          # vibrations requested (tests)
var _last_buzz_ms := -100000
var _last_pos := 0
var _pos_since := 0.0
var _said_pos := 0
var _close_said_lap := -1
var _tyre_said := false
var _wet_said := false
var _fastest := INF
var _prev_v := Vector3.ZERO
var _kerb_t := 0.0
var _impact_t := 0.0
var _flag := ""
var _flag_t := 0.0
var _slow := {}                          # entrant -> seconds crawling


func setup(r: Node) -> void:
	race = r
	race.car_contact.connect(_on_contact)


func _enabled(key: String) -> bool:
	return bool(race.save.get_setting(key))


func say(text: String, secs := 4.5) -> void:
	radio_log.append(text)
	if _enabled("engineer"):
		race.hud.show_radio(text, secs)


## At most one vibration every 0.15 s: cars rubbing report contact every
## physics tick, and a call to the vibrator 120 times a second stutters.
func buzz(ms: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_buzz_ms < 150:
		return
	_last_buzz_ms = now
	buzzes += 1
	if _enabled("vibration") and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ------------------------------------------------------------ events

func on_lap(e, lap_time: float) -> void:
	if not e.is_player or race.mode != "race":
		return
	var total := int(race.total_laps)
	var p = race.player
	var faster := lap_time < _fastest
	var any_faster := true
	for o in race.entrants:
		if o != e and o.best_lap > 0.0 and o.best_lap < lap_time:
			any_faster = false
	if faster:
		_fastest = lap_time
	if e.finished:
		var pos := int(p.position)
		var msg := "P%d. " % pos
		if pos == 1:
			msg += "You've won it! Brilliant drive."
		elif pos <= 3:
			msg += "On the podium, great job."
		elif pos <= 10:
			msg += "Good points today."
		else:
			msg += "We'll go again."
		say(msg, 6.0)
		return
	var ahead = _neighbour(p, -1)
	var behind = _neighbour(p, 1)
	var parts: Array[String] = ["Lap %d: %s." % [int(p.lap), UIStyle.fmt_time(lap_time)]]
	if any_faster and int(p.lap) >= 2:
		parts[0] = "Fastest lap! %s." % UIStyle.fmt_time(lap_time)
	if ahead != null:
		parts.append("%s ahead by %.1f." % [UIStyle.code(ahead.name), race._gap_seconds(ahead, p)])
	if behind != null:
		parts.append("%s %.1f behind." % [UIStyle.code(behind.name), race._gap_seconds(p, behind)])
	if int(p.lap) == total - 1:
		parts.append("Last lap!")
	say(" ".join(parts))


func _neighbour(p, d: int):
	var want := int(p.position) + d
	for o in race.entrants:
		if int(o.position) == want and not o.eliminated:
			return o
	return null


func _on_contact(a: RaceCar, b: RaceCar, closing: float) -> void:
	if a != race.car and b != race.car:
		return
	if closing > 1.0:
		buzz(int(clampf(25.0 + closing * 12.0, 30.0, 160.0)))


# ------------------------------------------------------------ per tick

## Called every physics tick while racing.
func tick(delta: float) -> void:
	var p = race.player
	if p == null:
		return
	var car: RaceCar = race.car
	var racing: bool = int(race.state) == 1
	# Hard hits (barriers): a sudden change of velocity not from the brakes.
	var v := car.linear_velocity
	var dv := (v - _prev_v).length() / maxf(delta, 0.001)
	_prev_v = v
	_impact_t -= delta
	if dv > 45.0 and _impact_t <= 0.0 and racing:
		buzz(int(clampf(dv * 1.2, 50.0, 200.0)))
		_impact_t = 0.4
	# Kerbs and grass rumble: a few longer pulses a second rather than a
	# stream of tiny ones (each one is a call into the phone's vibrator
	# service, which can hold up a frame).
	_kerb_t -= delta
	if _kerb_t <= 0.0 and absf(car.forward_speed()) > 12.0:
		var lat := absf(race.track.lateral(car.global_position, p.idx))
		var on_kerb: bool = lat > race.track.road_half - 0.2 and lat < race.track.road_half + Track.KERB_W
		if car.wheels_on_grass > 0:
			buzz(45)
			_kerb_t = 0.3
		elif on_kerb:
			buzz(30)
			_kerb_t = 0.25
	if not racing or race.mode != "race":
		_set_flag("")
		return
	_flag_t -= delta
	if _flag_t <= 0.0:
		_flag_t = 0.25
		_update_flags(p)
		_update_radio(p, 0.25)


func _update_radio(p, dt: float) -> void:
	# Places gained or lost (once they've stuck for 2 s).
	var pos := int(p.position)
	if pos != _last_pos:
		_last_pos = pos
		_pos_since = 0.0
	else:
		_pos_since += dt
	if _said_pos == 0:
		_said_pos = pos
	if _pos_since > 2.0 and pos != _said_pos:
		if pos < _said_pos:
			say("Good move! P%d." % pos if _said_pos - pos == 1 else "Up to P%d, great work." % pos)
		else:
			say("Lost a place, P%d. Stay with them." % pos)
		_said_pos = pos
	# Someone right on your gearbox.
	var behind = _neighbour(p, 1)
	if behind != null and int(p.lap) != _close_said_lap and race._gap_seconds(p, behind) < 0.45 and float(behind.progress) > 400.0:
		_close_said_lap = int(p.lap)
		say("%s is right behind you. Defend." % UIStyle.code(behind.name))
	# Tyres and weather (race weekend).
	if race.weekend != null:
		if p.wear > 0.72 and not _tyre_said and not p.pit_req:
			_tyre_said = true
			say("Tyres are going off. Box when you're ready: tap the tyre panel.", 6.0)
		if p.wear < 0.2:
			_tyre_said = false
		var w: float = race.weekend.wetness
		if w > 0.35 and p.compound != "wet" and not _wet_said:
			_wet_said = true
			say("Track's getting wet. Box for wets!", 6.0)
		if w < 0.1:
			_wet_said = false


func _update_flags(p) -> void:
	var L: float = race.track.total_length
	var my_s: float = p.progress
	# Yellow: a car stopped or crawling (for over a second) on the track in
	# the next 300 m. Not in the first seconds after the start.
	var yellow := false
	for o in race.entrants:
		if o == p or o.finished or o.eliminated or o.pit_phase > 0 or not o.car.visible:
			_slow.erase(o)
			continue
		var crawling: bool = absf(o.car.forward_speed()) < 9.0 and float(race.race_time) > 8.0
		_slow[o] = float(_slow.get(o, 0.0)) + 0.25 if crawling else 0.0
		var ahead := fposmod(float(o.progress) - my_s, L)
		if ahead < 300.0 and ahead > 5.0 and float(_slow[o]) > 1.0:
			yellow = true
	# Blue: a car at least a lap up, close behind.
	var blue := false
	for o in race.entrants:
		if o == p or o.finished:
			continue
		var gap := float(o.progress) - my_s
		if gap > L * 0.75 and gap < L + 5.0 and gap > L - 70.0:
			blue = true
	if yellow:
		_set_flag("yellow")
	elif blue:
		_set_flag("blue")
	elif _flag == "yellow":
		_set_flag("green")
		get_tree().create_timer(2.0).timeout.connect(func():
			if _flag == "green":
				_set_flag(""))
	elif _flag == "blue":
		_set_flag("")


func _set_flag(kind: String) -> void:
	if kind == _flag:
		return
	if kind == "yellow" and _flag != "yellow":
		say("Yellow flag ahead: car off. Careful.", 3.0)
	_flag = kind
	if kind != "":
		flags_seen[kind] = true
	race.hud.set_flag(kind)
