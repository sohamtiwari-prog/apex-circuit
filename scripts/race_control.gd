class_name RaceControl
extends Node
## Race control for a race (scripts/race.gd): the marshals' flags, time
## penalties, the Virtual Safety Car and retirements, F1 style.
##
##  Yellow flags  the lap is split into 16 marshal sectors. A car stopped or
##                crawling shows a yellow in its sector and the one before it,
##                a double yellow if it's on the racing surface. Bots lift
##                and don't overtake there; you mustn't overtake either.
##  Penalties     (with "Flags & penalties" on) 5 s each, for:
##                  track limits: all four wheels past the kerb. Three
##                    warnings (the third with the black-and-white flag),
##                    then a penalty every time;
##                  overtaking under yellow flags or the VSC (unless you give
##                    the place back within 10 s);
##                  going over the VSC speed limit for more than 3 s;
##                  causing a collision: running into the back of a car.
##                Served at your next pit stop (held in the box before the
##                crew start work), otherwise added to your race time.
##  VSC           the Virtual Safety Car, while marshals clear a stopped car
##                or debris: everyone keeps under a speed limit (about half
##                race speed), no overtaking. "VSC ending" 6 s before green.
##                A cheap time to pit, and the bots know it.
##  Retirements   a bot now and then has a mechanical failure: it pulls off
##                and parks (yellow flags, often a VSC), and is out (DNF).
##
## Multiplayer: every phone judges the cars it drives (its player; the host
## also the bots); penalties travel with each car's state (NetRace). The host
## runs the VSC and retirements and tells everyone.

const SECTORS := 16
const PEN := 5.0
const TL_WARNINGS := 3
const GIVE_BACK := 10.0           # seconds to hand back a place taken under yellow
const VSC_OVER_MAX := 3.0         # seconds over the VSC limit before a penalty
const FAILS := ["Gearbox", "Power unit", "Hydraulics", "Brakes", "Engine", "Suspension"]

var race: Node
var track: Track
var penalties := true              # "Flags & penalties" on (else just flags shown)
var authority := true              # runs the VSC and retirements (single player / host)
var yellow := PackedByteArray()    # per marshal sector: 0 clear, 1 yellow, 2 double yellow
var vsc := false
var vsc_ending := false
var vsc_count := 0
var messages: Array[String] = []   # everything race control said (results, tests)
var _yhold := PackedFloat32Array() # seconds each sector stays yellow (the map)
var _inc := {}                     # entrant -> [where (m), flag level, seconds left]
var _vsc_left := 0.0
var _vsc_limit := {}               # car model -> m/s
var _slow := {}                    # entrant -> seconds crawling
var _off := {}                     # entrant -> seconds past track limits (this excursion)
var _order := {}                   # player entrant -> {other: was ahead}
var _owe := {}                     # player entrant -> {other: [deadline, why]}
var _over := {}                    # entrant -> seconds over the VSC limit this VSC
var _vsc_pen := {}                 # entrant -> already penalised this VSC
var _hit_t := {}                   # entrant -> race time of its last collision penalty
var _fail := {}                    # entrant -> progress (m) where it breaks down
var _retiring := {}                # entrant -> [stage, seconds, side]
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _vsc_on_t := 0.0               # seconds since the VSC came out


func setup(r: Node) -> void:
	race = r
	track = r.track
	yellow.resize(SECTORS)
	_yhold.resize(SECTORS)
	_rng.randomize()
	if r.net != null:
		penalties = String(r.net_settings().get("rules", "on")) == "on"
		authority = r.Net.is_host()
	else:
		penalties = bool(r.save.get_setting("race_control"))
		authority = true
	r.car_contact.connect(_on_contact)


## A new race (also a restart): clear everything, pick who breaks down.
func reset() -> void:
	yellow.fill(0)
	_yhold.fill(0.0)
	vsc = false
	vsc_ending = false
	vsc_count = 0
	_vsc_left = 0.0
	messages.clear()
	for d in [_slow, _off, _order, _owe, _over, _vsc_pen, _hit_t, _fail, _retiring, _inc]:
		d.clear()
	if not (penalties and authority) or race.mode != "race" or race.ev_type in ["duel", "overtake", "eliminator", "time_trial"]:
		return
	# Mechanical failures: about one car in every 400 car-laps... rarely more than one.
	var laps := int(race.total_laps)
	if laps < 3:
		return
	var p := 0.0025 * laps
	for e in race.entrants:
		if e.ai == null or e.remote or _fail.size() >= 2:
			continue
		if _rng.randf() < p:
			_fail[e] = track.total_length * laps * _rng.randf_range(0.12, 0.85)


func sector_of(idx: int) -> int:
	return clampi(idx * SECTORS / maxi(track.size(), 1), 0, SECTORS - 1)


## Flag level for a car at sample idx: 0 clear, 1 yellow, 2 double yellow.
## Yellow from a sector and a half before an incident until just past it
## (double yellow in the last sector before it); nothing once you're by.
func flag_at(idx: int) -> int:
	if _inc.is_empty():
		return 0
	var L := track.total_length
	var s: float = track.cum[idx]
	var sector := L / SECTORS
	var best := 0
	for inc in _inc.values():
		var d := fposmod(float(inc[0]) - s + 15.0, L) - 15.0
		if d > sector * 1.5:
			continue
		best = maxi(best, int(inc[1]) if d <= sector else 1)
	return best


## Speed limit (m/s) for a car under the VSC: about half its top speed.
func vsc_limit(c: RaceCar) -> float:
	var key := String(c.spec["id"])
	if not _vsc_limit.has(key):
		var prof := track.speed_profile(c.spec)
		var top := 0.0
		for v in prof:
			top = maxf(top, v)
		_vsc_limit[key] = clampf(top * 0.5, 22.0, 44.0)
	return _vsc_limit[key]


## Speed cap for a bot from the flags (999: none).
func ai_cap(e) -> float:
	var cap := 999.0
	if vsc:
		cap = vsc_limit(e.car) - 1.0
	var f := flag_at(e.idx)
	if f > 0:
		# Lift: a little under the usual speed (a double yellow: well under).
		var prof := track.speed_profile(e.car.spec)
		cap = minf(cap, prof[(e.idx + 3) % prof.size()] * (0.93 if f == 1 else 0.8))
	return cap


## No overtaking: the VSC, or a yellow here.
func no_passing(idx: int) -> bool:
	return vsc or flag_at(idx) > 0


# ------------------------------------------------------------ per tick

## 10 times a second while racing (race.gd).
func tick(dt: float) -> void:
	_t += dt
	_vsc_on_t += dt
	_update_yellows(dt)
	if authority:
		_update_vsc(dt)
		_update_retirements(dt)
	for e in race.entrants:
		if e.remote or e.finished or e.eliminated or e.dnf:
			continue
		if penalties:
			_track_limits(e, dt)
			if vsc:
				_vsc_speed(e, dt)
		if e.is_player and penalties:
			_overtakes(e)


func _update_yellows(dt: float) -> void:
	for k in SECTORS:
		_yhold[k] = maxf(_yhold[k] - dt, 0.0)
		if _yhold[k] <= 0.0:
			yellow[k] = 0
	for key in _inc.keys():
		_inc[key][2] = float(_inc[key][2]) - dt
		if float(_inc[key][2]) <= 0.0:
			_inc.erase(key)
	if float(race.race_time) < 8.0:
		return
	for o in race.entrants:
		if o.finished and not o.dnf or o.eliminated or o.pit_phase > 0 or not o.car.visible:
			_slow.erase(o)
			continue
		var crawling: bool = absf(o.car.forward_speed()) < 9.0
		_slow[o] = float(_slow.get(o, 0.0)) + dt if crawling else 0.0
		if float(_slow[o]) < 1.0:
			continue
		var lat := absf(track.lateral(o.car.global_position, o.idx))
		var level := 2 if lat < track.road_half + Track.KERB_W else 1
		_inc[o] = [track.cum[o.idx], level, 2.5]      # (stays 2.5 s after it's cleared)
		var k := sector_of(o.idx)
		var before := posmod(k - 1, SECTORS)
		yellow[k] = maxi(int(yellow[k]), level)
		yellow[before] = maxi(int(yellow[before]), 1)
		_yhold[k] = 2.5
		_yhold[before] = 2.5


## All four wheels past the kerb, at speed, for a moment: one strike.
func _track_limits(e, dt: float) -> void:
	if e.pit_phase > 0 or e.ghost > 0.0 or e.car.forward_speed() < 12.0:
		_off[e] = 0.0
		return
	var lat := absf(track.lateral(e.car.global_position, e.idx))
	var beyond: bool = lat > track.road_half + Track.KERB_W + 1.2
	if beyond and track.has_pit_lane and track.in_pit_area(e.car.global_position, 2.0):
		beyond = false                       # the pit entry and exit roads
	var was := float(_off.get(e, 0.0))
	if beyond:
		_off[e] = was + dt
		if was < 0.3 and was + dt >= 0.3:
			e.tl_strikes += 1
			var n: int = e.tl_strikes
			var turn := "turn %d" % (sector_of(e.idx) + 1)
			if n < TL_WARNINGS:
				_say(e, "%s: track limits at %s. Warning %d." % [_who(e), turn, n], false)
			elif n == TL_WARNINGS:
				_say(e, "%s: black and white flag (track limits)." % _who(e), false)
			else:
				give(e, PEN, "track limits")
	elif lat < track.road_half + Track.KERB_W:
		_off[e] = 0.0


func _vsc_speed(e, dt: float) -> void:
	if e.pit_phase > 0 or _vsc_pen.has(e) or _vsc_on_t < 3.0:
		return                               # (3 s to slow down when it comes out)
	var over: bool = e.car.forward_speed() > vsc_limit(e.car) + 1.5
	if over:
		_over[e] = float(_over.get(e, 0.0)) + dt
		if e.is_player and int(_t * 10.0) % 8 == 0:
			race.hud.show_warning("VSC: slow down!", 0.8)
		if float(_over[e]) > VSC_OVER_MAX:
			_vsc_pen[e] = true
			give(e, PEN, "speeding under the VSC")


## Places taken while the yellows (or the VSC) are out: give them back or
## take a penalty. Passing a car that's crawling (stricken) is allowed.
func _overtakes(p) -> void:
	if not _order.has(p):
		_order[p] = {}
		_owe[p] = {}
	var order: Dictionary = _order[p]
	var owe: Dictionary = _owe[p]
	var t := float(race.race_time)
	for o in race.entrants:
		if o == p or o.finished or o.dnf or o.eliminated:
			order.erase(o)
			continue
		var gap: float = float(o.progress) - float(p.progress)
		var ahead := gap > 0.0
		var near := absf(gap) < 80.0
		if p.pit_phase > 0 or o.pit_phase > 0 or not near:
			order[o] = ahead
			continue
		var was: Variant = order.get(o)
		order[o] = ahead
		if was == true and not ahead and absf(o.car.forward_speed()) > 15.0 and (vsc or no_passing(p.idx)):
			if not owe.has(o):
				owe[o] = t + GIVE_BACK
				var why := "the VSC" if vsc else "yellow flags"
				race.hud.show_warning("Overtook under %s: let %s back past" % [why, UIStyle.code(o.name)], 4.0)
				race.engineer.say("You passed %s under %s. Give the place back!" % [UIStyle.code(o.name), why], 4.0)
		elif owe.has(o) and ahead:
			owe.erase(o)
			race.hud.show_banner("Place given back", UIStyle.GREEN, 2.0)
	for o in owe.keys():
		if t > float(owe[o]):
			owe.erase(o)
			give(p, PEN, "overtaking under %s" % ("the VSC" if vsc else "yellow flags"))


func _on_contact(a: RaceCar, b: RaceCar, closing: float) -> void:
	if closing < 9.0 or int(race.state) != 1 or race.mode != "race":
		return
	var ea = _entrant(a)
	var eb = _entrant(b)
	if ea == null or eb == null:
		return
	# Debris: a hard hit sometimes brings out the VSC.
	if authority and closing > 12.0 and penalties and _rng.randf() < 0.35:
		deploy_vsc("debris at turn %d" % (sector_of(ea.idx) + 1))
	if not penalties:
		return
	for pair in [[ea, eb], [eb, ea]]:
		var x = pair[0]
		var y = pair[1]
		if x.remote or x.pit_phase > 0 or y.pit_phase > 0:
			continue
		# x ran into the back of y: y just ahead along the track, x the faster.
		var gap := fposmod(track.cum[y.idx] - track.cum[x.idx], track.total_length)
		if gap > 0.5 and gap < 7.0 and x.car.forward_speed() > y.car.forward_speed() + 4.0:
			if float(race.race_time) - float(_hit_t.get(x, -99.0)) > 8.0:
				_hit_t[x] = float(race.race_time)
				give(x, PEN, "causing a collision with %s" % UIStyle.code(y.name))


func _entrant(c: RaceCar):
	for e in race.entrants:
		if e.car == c:
			return e
	return null


# ------------------------------------------------------------ VSC

func deploy_vsc(why: String) -> void:
	if vsc or not authority or vsc_count >= 3 or race.mode != "race":
		return
	var lead := 0.0
	for e in race.entrants:
		lead = maxf(lead, float(e.progress))
	var left: float = track.total_length * float(race.total_laps) - lead
	if left < track.total_length * 0.6 or float(race.race_time) < 15.0:
		return                                  # not in the last half lap
	vsc_count += 1
	_vsc_left = _rng.randf_range(22.0, 34.0)
	set_vsc(1)
	announce("VIRTUAL SAFETY CAR DEPLOYED: %s." % why)


## 0 off, 1 deployed, 2 ending (the host's state, on every phone).
func set_vsc(state: int) -> void:
	var was := vsc
	vsc = state > 0
	vsc_ending = state == 2
	if vsc and not was:
		_over.clear()
		_vsc_pen.clear()
		_vsc_on_t = 0.0
		if race.engineer != null:
			race.engineer.say("VSC, VSC. Keep under the limit, no overtaking.", 4.0)
	elif was and not vsc:
		if race.engineer != null:
			race.engineer.say("Green, green, green! Go!", 3.0)


func vsc_state() -> int:
	return 0 if not vsc else (2 if vsc_ending else 1)


func _update_vsc(dt: float) -> void:
	if not vsc:
		return
	_vsc_left -= dt
	if _vsc_left < 6.0 and not vsc_ending:
		set_vsc(2)
		announce("VSC ENDING.")
	if _vsc_left <= 0.0:
		set_vsc(0)
		announce("VSC ENDED. Green flag.")


# ------------------------------------------------------------ retirements

func _update_retirements(dt: float) -> void:
	for e in _fail.keys():
		if e.finished or e.eliminated or e.pit_phase > 0 or e.ai == null:
			continue
		if float(e.progress) >= float(_fail[e]):
			_fail.erase(e)
			_begin_retirement(e)
	for e in _retiring.keys():
		var st: Array = _retiring[e]
		st[1] = float(st[1]) + dt
		var drv: AIDriver = e.ai
		match int(st[0]):
			0:
				# Coasting off the racing line to the side of the track.
				drv.speed_cap = maxf(26.0 - float(st[1]) * 4.0, 0.0)
				if float(st[1]) > 7.0 or (float(st[1]) > 2.0 and absf(e.car.forward_speed()) < 0.8):
					st[0] = 1
					st[1] = 0.0
					drv.speed_cap = 0.0
					if _rng.randf() < 0.7:
						deploy_vsc("%s stopped at turn %d" % [_who(e), sector_of(e.idx) + 1])
			1:
				# Parked; marshals recover it (when the VSC ends, or after 30 s).
				drv.speed_cap = 0.0
				if (not vsc and float(st[1]) > 12.0) or float(st[1]) > 40.0:
					_retiring.erase(e)
					e.car.visible = false
					e.car.set_ghost(true)
					e.car.freeze = true
					e.car.controls_enabled = false


func _begin_retirement(e) -> void:
	e.dnf = true
	e.dnf_reason = FAILS[_rng.randi() % FAILS.size()]
	e.finished = true
	e.finish_time = race.race_time
	e.pit_req = false
	var lat := track.lateral(e.car.global_position, e.idx)
	var side := signf(lat) if absf(lat) > 1.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
	_retiring[e] = [0, 0.0, side]
	var off := track.road_half + Track.KERB_W + 4.0
	e.ai.path_lat = func(_i: int) -> float: return side * off
	announce("%s HAS STOPPED: %s. Out of the race." % [_who(e).to_upper(), e.dnf_reason.to_lower()])


## Still being driven (bots: race.gd leaves these to race control).
func is_retiring(e) -> bool:
	return _retiring.has(e) or (e.dnf and e.ai != null)


# ------------------------------------------------------------ penalties

## A time penalty for a car this phone drives.
func give(e, secs: float, why: String) -> void:
	e.pen_pending += secs
	e.pen_total += secs
	_say(e, "%s: %d SECOND TIME PENALTY, %s." % [_who(e).to_upper(), int(secs), why], true)
	if e.is_player:
		race.engineer.say("We've got a %d second penalty: %s. We'll serve it at the stop, or it goes on the race time." % [int(secs), why], 5.0)


## A penalty was served at a pit stop (weekend.gd).
func served(e, secs: float) -> void:
	if e.is_player:
		race.engineer.say("Serving the %d second penalty, hold it there..." % int(round(secs)), 3.0)


func _who(e) -> String:
	return "You" if e.is_player else UIStyle.code(e.name)


func _say(e, text: String, important: bool) -> void:
	# Penalties go to everyone; your own warnings to your screen; other
	# cars' warnings only into the log.
	if important:
		announce(text, e.is_player)
	elif e.is_player:
		messages.append(text)
		race.hud.show_race_control(text, true)
	else:
		messages.append(text)


## A race control message: on screen, and to the other phones.
func announce(text: String, mine := false) -> void:
	messages.append(text)
	race.hud.show_race_control(text, mine)
	if race.net != null:
		race.net.send_rc(text)


## A message from another phone's race control.
func remote_message(text: String) -> void:
	messages.append(text)
	race.hud.show_race_control(text, false)
