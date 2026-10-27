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
| **Kestrel Park** | original club circuit | 2.06 km |

Layouts are accurate to within ~1% of the official lengths. Elevation is not
yet modelled (the source data has none).

## Install on your phone

1. Open the [latest release](../../releases/latest) on your Android phone.
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

## Racing features

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

## Look

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
- [ ] **Milestone 3: career and garage.** Events, currency, buying cars, upgrades
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

This project is not affiliated with Formula 1, the FIA, any racing team,
car manufacturer or circuit. All names in the game are fictional.
