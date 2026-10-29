extends SceneTree
## Bot behaviour over a full-grid race (you on autopilot): counts the things
## that look like glitches from the cockpit, per track:
##   resets     a bot put back on the track (a visible jump)
##   twitches   a sudden yaw (> 0.8 rad/s more than the bend asks for) at speed
##   weaves     swinging left-right-left across the track within 2 s at speed
##   offs       a bot with all four wheels past the kerb
##   stops      a bot crawling (< 8 m/s) for over a second outside the pits
##   contacts   bot-to-bot contacts (> 2 m/s)
## and race control: messages, penalties, retirements, VSCs.
##   godot --headless --fixed-fps 120 --script res://tests/bot_probe.gd -- <track> [laps] [verbose]
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var tid: String = args[0] if args.size() > 0 else "styria"
	var laps: int = int(args[1]) if args.size() > 1 else 2
	var verbose := args.has("verbose")
	var save: Node = root.get_node("Save")
	save.data = save.default_profile()
	var st: Dictionary = save.data["settings"]
	st["mode"] = "race"; st["laps"] = laps; st["opponents"] = 19; st["track"] = tid
	st["car"] = "gp26"; st["qualifying"] = false; st["weather"] = "dry"
	var race: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	await physics_frame
	race.autopilot = load("res://scripts/ai_driver.gd").new()
	race.autopilot.skill = 0.97
	var tr: Track = race.track
	if args.has("fail"):
		# A breakdown for sure: the bot in 5th on the grid, a third of the way in.
		for e in race.entrants:
			if e.ai != null and e.grid == 5:
				race.control._fail[e] = tr.total_length * laps * 0.33
	var n := {"twitch": 0, "weave": 0, "off": 0, "stop": 0, "contact": 0}
	var where: Array[String] = []
	var yaw_on := {}
	var off_on := {}
	var slow := {}
	var lat_v := {}          # car -> [last sign, time of last reversal, reversals in window]
	race.car_contact.connect(func(a, b, v):
		if v > 2.0 and a != race.car and b != race.car:
			n["contact"] += 1)
	var t := 0
	while not race._results_shown and t < 120 * 60 * laps * 3:
		await physics_frame
		t += 1
		if race.state != 1 or t % 3 != 0:
			continue
		var rt: float = race.race_time
		for e in race.entrants:
			if e.ai == null or e.pit_phase > 0 or e.finished or e.dnf or e.ghost > 0.0:
				continue
			var c: RaceCar = e.car
			var v := c.forward_speed()
			var tag := "%s %.0f m lap %d t%.0f" % [e.name, tr.cum[e.idx], e.lap + 1, rt]
			# Twitch: yaw rate beyond the bend's.
			var excess := absf(c.angular_velocity.y - v * tr.curv[e.idx])
			var tw: bool = v > 20.0 and excess > 0.8
			if tw and not yaw_on.get(c, false):
				n["twitch"] += 1
				where.append("twitch " + tag + " (%.2f rad/s)" % excess)
			yaw_on[c] = tw
			# Weave: lateral speed across the track reversing quickly.
			var lv := c.linear_velocity.dot(tr.rights[e.idx])
			var sgn := 0 if absf(lv) < 2.0 else (1 if lv > 0.0 else -1)
			var w: Array = lat_v.get(c, [0, -9.0, 0])
			if sgn != 0 and sgn != int(w[0]) and v > 30.0:
				if int(w[0]) != 0 and rt - float(w[1]) < 2.0:
					w[2] = int(w[2]) + 1
					if int(w[2]) == 2:
						n["weave"] += 1
						where.append("weave " + tag)
				else:
					w[2] = 0
				w[0] = sgn
				w[1] = rt
			lat_v[c] = w
			# Off: all four wheels past the kerb.
			var off: bool = absf(tr.lateral(c.global_position, e.idx)) > tr.road_half + Track.KERB_W + 1.2
			if off and not off_on.get(c, false):
				n["off"] += 1
				where.append("off " + tag)
			off_on[c] = off
			# Stop.
			var s: float = float(slow.get(c, 0.0))
			s = s + 0.025 if v < 8.0 and rt > 6.0 else 0.0
			if s >= 1.0 and float(slow.get(c, 0.0)) < 1.0:
				n["stop"] += 1
				where.append("stop " + tag)
			slow[c] = s
	var rc = race.control
	var pens := 0
	for e in race.entrants:
		pens += int(e.pen_total / 5.0)
	print("RESULT %-12s resets %d  twitches %d  weaves %d  offs %d  stops %d  contacts %d  | penalties %d  retirements %d  VSCs %d  messages %d" % [tid,
		race.recoveries, n["twitch"], n["weave"], n["off"], n["stop"], n["contact"], pens,
		race.entrants.filter(func(e): return e.dnf).size(), rc.vsc_count if rc != null else 0, rc.messages.size() if rc != null else 0])
	if verbose:
		for line in race.reset_log:
			print("    reset ", line)
		for line in where:
			print("    ", line)
		if rc != null:
			for m in rc.messages:
				print("    RC ", m)
	quit(0)
