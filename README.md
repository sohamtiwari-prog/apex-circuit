# Apex Circuit

A mobile Grand Prix racing game for Android, built from scratch in
[Godot 4](https://godotengine.org). Inspired by the feel of classic mobile
sim-racers. Cars and series are original designs with fictional names;
Grand Prix tracks follow real circuit layouts under fictional names.

## Cars and tracks

| Car | Modelled on | | |
|---|---|---|---|
| **Apex GP-26** | current F1 car, 10 team liveries | 1000 hp · 800 kg | 0-100 2.4 s · 342 km/h |
| **Apex Vanta GT** | mid-engined supercar | 720 hp · 1420 kg | 0-100 3.9 s · 339 km/h |
| **Stuttgart 9 Turbo** | rear-engined sports icon | 650 hp · 1640 kg | 0-100 3.8 s · 325 km/h |
| **Marauder V8** | American muscle car | 480 hp · 1750 kg | 0-100 4.9 s · 281 km/h |
| **Toro Furia** | Italian V12 wedge hypercar | 770 hp · 1550 kg | 0-100 3.9 s · 345 km/h |
| **Veloce Hyper** | W16 hypercar | 1500 hp · 1995 kg | 0-100 3.6 s · 387+ km/h |

Cars are modelled procedurally (scripts/mesh_kit.gd: lofted bodywork,
airfoil wings, lathed tyres). Names and teams are fictional.

| Track | Real layout of | Length |
|---|---|---|
| **Silvermoor Circuit** | the British GP venue | 5.86 km |
| **Autodromo di Brianza** | the Italian GP venue | 5.77 km |
| **Circuit des Ardennes** | the Belgian GP venue | 6.96 km |
| **Riviera Street Circuit** | the Monaco street circuit | 3.30 km |
| **Styria Ring** | the Austrian GP venue | 4.29 km |
| **Autodromo Entrelagos** | the Brazilian GP venue | 4.28 km |
| **Desert Sun International Circuit** | the Bahrain GP venue | 5.39 km |
| **Circuit Île-Royale** | the Canadian GP venue | 4.35 km |
| **Pannonia Ring** | the Hungarian GP venue | 4.37 km |
| **Marina Lights Street Circuit** | the Singapore night race | 4.93 km |
| **Gulf Lights Circuit** | the Abu Dhabi GP venue (under lights) | 5.28 km |
| **Kestrel Park** | original club circuit | 2.06 km |

Layouts are accurate to within ~1% of the official lengths, with real
elevation (see below).

**Night races:** Marina Lights and Gulf Lights race at night by default
(lighting towers all the way round, lit city windows, stars and a glow of
light on the horizon); any track can be raced by day, at sunset or at night
("Track's own time" picks the venue's usual one).

## Install on your phone

1. Open the [latest release](../../releases/latest) on your Android phone
   (or the mirror, <https://sohamtiwari-prog.github.io/apex-circuit/>, if that
   download is slow or fails: same file, different servers).
2. Download the `ApexCircuit-v….apk` file and open it.
3. Allow installs from your browser/file manager when Android asks, then tap **Install**.

New versions install **over** the old one and keep your progress, because
every build is signed with the same key (`android_signing/`).

## Game modes

- **Race:** up to 20 cars (choose 20, 12 or 6 in the menu), standing start
  with five red lights, 1/3/5/10 laps, Easy/Medium/Hard AI. You start
  mid-grid. Timing tower with gaps, live circuit map, full classification
  with fastest lap at the flag. AI drivers follow a computed racing line,
  keep a safe braking gap, overtake only into free space and check their
  mirrors, so a full grid races without piling up.
- **Time trial:** you against the clock; best laps saved per car and track.
- **Friends:** race your friends, with bots filling the grid up to 20 cars.
  One phone hosts and picks the track, laps, grid size, bot difficulty and
  time of day; everyone picks their own car. See below.

## Driver ranking

Every race finish earns rank points (RP), and they never go down. Points
depend on where you finish (P1 75 on a 20-car, 3-lap, medium race; last place
still earns a few), with bonuses for a win, a podium and the fastest lap, and
multipliers for harder bots (easy x0.6, hard x1.4), longer races (1 lap x0.5
up to 10 laps x1.8), bigger grids and racing friends (x1.2). Ranks climb from
Rookie through Bronze, Silver, Gold, Platinum and Diamond (III, II, I each)
and Champion to **Legend** at 6000 RP, and past that a star for every 1000 RP.
Your rank is on the main menu (tap it for the whole ladder), the results
screen shows what you earned and animates your progress, and friends see each
other's ranks in the lobby.

## Racing with friends

Everyone needs the app on an Android phone. One person taps **Friends** and
hosts; the others join. The host's phone runs the bots, the start lights and
the timing, so the host should have a decent connection and keep the app open.

**Same place (Wi-Fi or hotspot):** no internet needed.
1. Everyone joins the same Wi-Fi, or connects to the host's phone hotspot.
2. Host taps **Host a game here**.
3. Friends see the game under **Games nearby** and tap it. If it doesn't
   appear (some routers block this), type the address the host's lobby shows.

If joining fails: each phone shows **This phone: 192.168.x.x** on the Friends
screen. The first three numbers must match on every phone; if they don't, one
phone is on a different network (a guest or other-band network). If they do
match and it still fails, the router is blocking phones from talking to each
other ("AP isolation"); use the host's hotspot instead.

**Online (anywhere, nothing to set up):** friends in another city, on
mobile data or any Wi-Fi.
1. Host taps **Create an online game**. A 4-letter code appears.
2. Tap **Invite on WhatsApp** (or **Copy code**) to send it. The message
   includes a link to download the game.
3. Friends open **Friends**, type the code under **Online** and tap **Join**.

This uses free public message servers (EMQX, HiveMQ, Mosquitto test
brokers); the code's first letter says which one, and the host moves to the
next if one is down. They're shared, best-effort services: anyone who knows a
code could listen in on that game's car positions, and they can be slow at
busy times.

**Your own server (optional, faster and private):** deploy `server/relay.js`
once on Render's free plan ([render.com](https://render.com) → sign in with
GitHub → **New → Blueprint** → this repo; it reads `render.yaml`, Singapore
region). Then everyone pastes `wss://<your service>.onrender.com` into **Own
server** on the Friends screen. A sleeping free server takes up to a minute
to wake.

**In the lobby and the race:** quick chat (Let's go! / GG / Nice move! /
Sorry! / Rematch?) and each friend's ping in the lobby (green under 150 ms).

## Controls

| | Tilt (default) | Wheel | Buttons |
|---|---|---|---|
| Steer | Tilt the phone like a steering wheel | Put your left thumb anywhere in the lower left and turn the wheel arc | ◀ ▶ buttons, bottom-left |
| Gas | GAS pedal, bottom-right | GAS, far right | GAS, far right |
| Brake / reverse | BRAKE pedal, bottom-left | BRAKE, next to GAS | BRAKE, next to GAS |

Wheel steering is a floating steering-wheel rim: your thumb lands on top of
it, and turning it (around the arc, or just sliding sideways) steers. It
follows your thumb past full lock and centres when you let go. Steering
sensitivity (pause menu) sets how far you turn (or tilt) for full lock.

Steering is calibrated per car (`tests/steer_calibrate.gd` writes
`data/steer_cal.json`): the input is the share of the car's peak cornering
grip, so 50% steering is 50% of the grip at any speed, and full lock is
exactly the grip peak, never past it.

**Reset** (top-right) puts the car back on the track. Pause (**II**) to switch
steering mode, change tilt sensitivity, invert tilt, turn on auto-accelerate,
toggle the assists and the racing-line guide, or switch graphics to battery saver.

**Assists** (Full by default, like RR3; each can be Off, Moderate or Full):
brake assist brakes for you when you arrive at a corner too fast (Moderate
only steps in when you're clearly too fast, and more gently); steering assist
adds a little racing-line steering while your own input is small and fades
out as soon as you steer (Moderate adds half as much), so you can always use
(or leave) the whole track.

**Racing line** (optional): a guide painted on the road ahead, green where you
can accelerate, yellow where you'll need to ease off, red where you must brake
now for what's coming at your current speed.

## Career, garage and championships

- **Home screen:** Career, Championship, Quick race, Friends and Garage,
  with your car, rank and career stars.
- **Career:** five series (Club Muscle Cup, Sports Car Trophy, Supercar
  Series, Hypercar Challenge, Grand Prix), six events each: races, duels
  against one rival, overtake challenges (start last), eliminators (last
  car out every lap) and time trials (gold / silver / bronze). Up to 3
  stars per event; stars unlock the next series. The Grand Prix series
  ends with a full World Championship season.
- **Garage:** every car is open from the start: no money, no buying, no
  upgrades. Every car races exactly as it comes, so it's down to the
  driving. The garage shows how each car performs (power, weight, top
  speed, grip, braking and its Performance Rating), where it races, and
  lets you pick the car on your home screen or take it for a drive.
- **Daily challenge:** a new event every day (picked from the date, the
  same for everyone) in a car loaned for the day, with a twist: a night
  race, rain, a charge from the back, a duel or a hot lap. Up to 3 stars.
- **Profile & trophies:** your rank, totals (races, wins, podiums, laps,
  distance, stars), your best lap at every track and the trophy
  cabinet from championships.
- **Championship:** pick a class and a car for it, 3 to 10 rounds, 2 to 5
  laps; the same 20 drivers all season, points 25-18-15-12-10-8-6-4-2-1
  (+1 fastest lap), driver and team standings and a trophy.
- **Race weekends:** qualifying (one flying lap from a rolling out-lap,
  or skip it) sets the grid; choose soft / medium / hard / wet tyres; tyres
  wear (grip fades, then drops off a cliff) and you tap the tyre panel to
  box: the car drives itself down the pit side at 80 km/h, stops for new
  tyres and rejoins (about 18 s). Weather can be dry, wet or change during
  the race (glossy track, rain, spray, grey skies; slicks lose grip, so
  pit for wets). The AI makes the same calls. Quick races can have
  qualifying, rain and a tyre choice too.

## Racing features

- **Race engineer:** radio messages under the timing tower: each lap's
  time with the gaps to the cars ahead and behind, fastest laps, places
  gained or lost, a car right behind you, tyres going off, rain coming,
  the last lap and your result.
- **Flags:** yellow when a car has stopped on the track ahead (green once
  it's clear), blue when the leaders come up to lap you.
- **Vibration:** the phone buzzes for contact with other cars and the
  barriers (harder hits buzz longer), and rumbles over kerbs and grass.
  Both can be switched off in the pause menu.

- **Sector times:** each lap in three sectors, coloured like F1 timing:
  purple fastest (anyone this session / your all-time best in time trial),
  green your best this session, yellow slower. Best sectors are saved.
- **Minisectors:** every sector is split into 8 (24 a lap). Each one lights
  up purple, green or yellow as you cross it, on the timing panel and on
  the track map, with its time and gap to your best. In a time trial the
  **Ideal** lap (your best minisectors added up) shows what's possible.
- **DRS (GP car):** zones on the long straights with painted detection and
  activation lines. Within 1 s of the car ahead at detection (from lap 2;
  always in time trial), the flap opens through the zone, cutting drag ~22%,
  until you brake. The AI uses it too.
- **Replays:** watch the whole race again from the results screen, or the
  last 30 seconds from the pause menu. Every car is recorded 20 times a
  second. Cameras: TV towers round the track (broadcast-style zoom, on
  grandstand and building roofs where there's no room), helicopter, blimp
  (straight down), drone orbit, chase, every onboard and a rear-facing one.
  Auto is a director that cuts between them. Play/pause, skip 10 s, drag
  the timeline, 1/2 and 1/4 slow motion (the sound slows too), 2x, follow
  any car. **Highlights** jumps to the start, overtakes, contacts, new
  leaders, fastest laps and the flag; they're marked on the timeline. The
  controls fade while you watch (tap to bring them back), or tap the eye
  for a clean picture.
- **Slipstream:** tuck in behind a car on a straight and its wake cuts your
  drag (up to 24% when close, fading by 40 m): you close in and can pull out
  to pass. The SLIPSTREAM pill fills to show how strong the tow is. The AI
  gets it too.
- **Ghost car (time trial):** your best lap, replayed as a see-through car,
  saved per car and track.
- **Braking boards:** 300 / 200 / 100 m boards before every big stop.
- **Sunset:** race at golden hour (menu option).
- **Brake lights:** cars light up when they brake (the GP car's rear light
  flashes, like a real one harvesting energy).

## Driving model

Cars use their own physics (scripts/car.gd), not a built-in vehicle:
raycast suspension with anti-roll bars (weight moves under braking and
cornering), a Pacejka-style tyre that builds grip progressively, peaks and
holds ~80% in a slide, a friction circle shared by steering and
drive/brakes, aero drag and downforce, and an always-on stability control.
Steering maps through the tyre curve, so 30% tilt gives about 30% of the
cornering force at any speed. Grass costs grip and speed, gravel traps bog
you down, asphalt run-off is safe. Traction control and ABS keep cornering
grip first; switch them off and you can spin the rears or lock the fronts.

Car-to-car contact (scripts/car_contacts.gd) is soft and fair rather than a
rigid crash: each car is a rounded shape seen from above, and overlapping
cars are pushed apart by a firm, heavily damped spring, sideways only. The
car doing the hitting takes 60% of the speed change, the car hit 40%: tap
someone at 12 m/s and they gain about 5 m/s while you lose about 6.5,
instead of them shooting off and you stopping dead. Low body friction and a
reduced turning effect mean rubbing wheels or a nudge doesn't spin anyone.

## Real elevation and landscape

Every real circuit has its true height profile, measured from F1 car-position
telemetry (about 25-30 qualifying laps per track, aligned to our centreline,
pooled and smoothed): Ardennes 102 m from top to bottom (down to the
compression, up the hill and the long straight to the highest corner), Styria
63 m, Entrelagos 43 m, Riviera 42 m, Pannonia 35 m, Desert 16 m, Brianza
12 m, Silvermoor 11 m, Gulf 11 m, Île-Royale 5 m, Marina 5 m. The same data put each lap's start on the real timing line.
`tools/elevation_from_telemetry.py` does this; `tools/terrain.py` then builds
each venue's landscape (`tracks/<id>.terrain`): level shelves by the track for
verges, pits and stands, smooth hillsides between stretches at different
heights, rolling land and woods beyond. The Riviera has its harbour (with
yachts) and the tunnel under the hotel. Far trees switch to simple models and
the landscape is tiled, so frame cost stays about where it was on flat ground.

## Engine sound

The GP car has a V12 voice built from a model of the engine
(`tools/engine_sound.py`): twelve exhaust pulses per cycle through two banks of
pipes with their reflections, the tailpipe bark, fixed body resonances, small
cylinder-to-cylinder differences (the roar under the note), combustion noise
and a little saturation. It is pre-rendered as engine-cycle tables at ten rpm
points, on and off throttle, all phase-locked; your car generates its sound
live from one engine phase that morphs between neighbouring tables, so it
stays one sharp voice and the pitch follows the revs exactly. Revs are voiced
as a big V12 (2300-8600 rpm for the car's 4000-12000) to keep it deep. Upshifts
crack, the overrun crackles. Road cars keep their synthesized engines.

## Look

**Cars:** road cars have real wheel arches (the sides rise over each tyre,
with the fenders standing proud), a shoulder line, a glass greenhouse with
a painted roof and pillars, door mirrors, splitter, side skirts, number
plates, headlights set into the nose, multi-spoke rims with brake discs
and painted calipers (which don't spin with the wheel). GP cars carry
fictional sponsors and race numbers, a T-cam, carbon-fibre weave on the
bare carbon parts, wheel covers, and tyre sidewall bands in the colour of
the compound they're on. Every car has a soft contact shadow, so it sits
on the track at any distance.

**Tracks:** kerbs stand proud of the road (drawn raised, driven flat),
rubber streaks are laid down in every braking zone along the racing line,
the asphalt has a fine aggregate bump that catches the light, grass is a
more natural green, trees have lumpy multi-clump crowns with a leafy
texture, and braking boards have plain backs.

Procedural sky with clouds, filmic tonemapping and glow; rubbered-in racing
line, mown grass, gravel traps and painted run-off; concrete walls with
advertising boards, armco, tyre barriers and catch fencing; a start gantry
whose lights run the start; pit lane and garages in team colours; grandstands
with crowds; bridges; marshal posts; TV camera towers; flagpoles; trees (broadleaf, conifer, palm); distant hills; city
blocks with facades. Skid marks stay on the track and tyres smoke when they
slide. The UI uses Saira Condensed (SIL Open Font License, `fonts/OFL.txt`).
The camera button cycles chase, far chase and the car's onboard cameras
(GP car: cockpit, T-cam, nose; GT: hood, bumper). On a computer: arrows/WASD, Space to brake,
C for camera, R to reset, Esc to pause.

## Progress is never lost

The profile (`user://save/profile.json`) is written atomically: a temp file is
written, verified, the previous save is copied to a backup, then the temp
file replaces the save. A corrupt save automatically falls back to the
backup. Android's auto-backup is enabled too.

## Roadmap

- [x] **Milestone 1: driving.** One car, the Kestrel Park circuit, tilt/touch controls,
  4 cameras, lap timing with checkpoints and track limits, saved best laps
- [x] **Milestone 1.5: Grand Prix.** GP car with downforce and aero-scaled brakes, real
  Silverstone layout, 8-speed gearbox with shift lights, synthesized engine/tyre/wind
  audio, traction control and ABS, cockpit view, main menu with car and track select
- [x] **Milestone 2: racing.** 20-car grids, start lights, overtaking AI, positions, results
- [x] **Multiplayer.** Race friends over Wi-Fi/hotspot or online, bots fill the grid
- [x] **Milestone 3: career and garage.** Career series, garage, championships, race weekends
- [ ] **Milestone 4: content and polish.** More GP tracks (Monza, Spa, ...), more cars,
  realistic textures and models, tyre compounds, pit stops, DRS

## Project layout

```
scripts/
  menu.gd            main menu: car/track select, turntable preview
  race.gd            session: grid, start lights, laps, positions, AI racecraft, results
  track.gd           circuit from data or control points: road mesh, walls, scenery
  car.gd             driving physics: suspension, tyres, gearbox, aero, TC/ABS
  car_wheel.gd       per-wheel suspension and tyre state
  car_specs.gd       every car's physics, gearing, sound and camera spec
  car_body.gd        car 3D models (lofted bodies, wings, liveries, wheels)
  mesh_kit.gd        procedural modelling: loft, tube, airfoil, lathe
  car_audio.gd       engine/tyre/wind sound synthesized in code
  ai_driver.gd       pure-pursuit steering + curvature speed planner
  trackside.gd       barriers, fencing, ads, gantry, pits, grandstands, hills
  look.gd            sky, lighting, post-processing per venue
  tyre_fx.gd         skid marks and tyre smoke
  line_guide.gd      racing-line guide
  ui_style.gd        shared UI look (fonts, colours, panels, buttons)
  rev_gauge.gd       rev arc / shift lights / gear / speed
  mini_map.gd        live circuit map (also the menu track preview)
  race_camera.gd     chase / hood / bumper cameras
  car_contacts.gd    soft car-to-car contact and slipstream
  replay.gd          records every car; replay playback, seeking, highlights
  replay_camera.gd   TV towers, helicopter, blimp, drone, chase, onboards, auto director
  replay_ui.gd       replay controls and timeline
  hub.gd             home screen
  career.gd / career_screen.gd          career series, events, stars, rewards
  garage.gd / garage_screen.gd          Performance Rating, car stats
  championship.gd / championship_screen.gd  seasons, points, standings
  weekend.gd         qualifying, tyre wear, pit stops, weather
  race_engineer.gd   radio messages, flags, vibration
  daily.gd           the daily challenge
  profile_screen.gd  driver profile and trophy cabinet
  tyres.gd           compounds, wear and wet grip
  showroom.gd        the turntable behind the menus
  hud.gd             timing tower, lap timing, pause menu, classification
  touch_controls.gd  multi-touch pedals and steering buttons
  save_manager.gd    crash-safe profile saving (autoload "Save")
  net.gd             multiplayer connection: Wi-Fi (ENet + discovery), free public servers (MQTT) or own relay (autoload "Net")
  mqtt_link.gd       minimal MQTT 3.1.1 client over WebSocket
  net_race.gd        multiplayer race sync: car states, interpolation, standings
  lobby.gd           Friends screen: host/join, players, race settings
tracks/              imported circuit centrelines (JSON)
tools/
  import_circuit.py  converts a real circuit outline (GeoJSON) into a track file
  racing_line.py     adds a minimum-curvature racing line to a track file
tests/
  sim_test.gd        physics checks per car (0-100, top speed, braking, AI laps)
  game_test.gd       end-to-end: countdown, laps, save, reload, corruption recovery
  tracks_test.gd     the AI completes a clean lap of every track
  grip_test.gd       measures each car's cornering grip (calibrates the AI)
  cars_test.gd       every car: 0-100, top speed, clean AI lap
  race_test.gd       a full 20-car race to the results screen
  collision_test.gd  rear-end hits, offset hits, rubbing wheels, slipstream
  replay_test.gd     recording, smooth playback, every replay camera, restore after
  career_test.gd     garage, career events, a championship season
  weekend_test.gd    qualifying, tyre wear, pit stops, changing weather
  engineer_test.gd   radio lap reports, yellow/blue flags, vibration
  perf_test.gd       simulation cost per grid size
  edge_test.gd       no invisible walls: leaving and rejoining the track
  handling_diag.gd   step-steer response, the numbers behind the handling
  car_showcase.gd    renders every car for visual review
```

Every push to `main` runs the tests and builds a signed APK via GitHub Actions
(`.github/workflows/build-apk.yml`), published as a GitHub release.

Run the tests locally:

```
godot --headless --import
godot --headless --fixed-fps 120 --script res://tests/sim_test.gd
godot --headless --fixed-fps 120 --script res://tests/game_test.gd
```

## License and credits

Code is MIT licensed (see `LICENSE`).

Circuit outlines come from [bacinger/f1-circuits](https://github.com/bacinger/f1-circuits),
MIT licence, Copyright (c) 2019-2025 Tomislav Bacinger.

Elevation profiles are derived from position telemetry published by
[TracingInsights](https://github.com/TracingInsights/2025) (Apache-2.0,
originally from the F1 live-timing feed via FastF1); only smoothed height
profiles are kept.

This project is not affiliated with Formula 1, the FIA, any racing team,
car manufacturer or circuit. All names in the game are fictional.
