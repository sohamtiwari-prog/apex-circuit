# Apex Circuit

A mobile Grand Prix racing game for Android, built from scratch in
[Godot 4](https://godotengine.org). Inspired by the feel of classic mobile
sim-racers. Cars and series are original designs with fictional names;
Grand Prix tracks follow real circuit layouts under fictional names.

## Cars and tracks

| Car | | |
|---|---|---|
| **Apex GP-26** | Grand Prix car | ~1000 hp, 800 kg, 8-speed seamless, 0-100 in 2.4 s, 340 km/h |
| **Apex Vanta GT** | Mid-engined GT | 560 hp, 1250 kg, 7-speed, 0-100 in 4.0 s, 319 km/h |

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

## Controls

| | Tilt mode (default) | Button mode |
|---|---|---|
| Steer | Tilt the phone like a steering wheel | ◀ ▶ buttons, bottom-left |
| Gas | GAS pedal, bottom-right | GAS pedal, bottom-right |
| Brake / reverse | BRAKE pedal, bottom-left | BRAKE pedal |

Pause (**II**, top-right) to switch steering mode, turn on auto-accelerate,
invert tilt, change tilt sensitivity, or toggle traction control and ABS.
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
- [ ] **Milestone 2: racing.** AI opponents, grid starts, positions, results screen
- [ ] **Milestone 3: career and garage.** Events, currency, buying cars, upgrades
- [ ] **Milestone 4: content and polish.** More GP tracks (Monza, Spa, ...), more cars,
  realistic textures and models, tyre compounds, pit stops, DRS

## Project layout

```
scripts/
  menu.gd            main menu: car/track select, turntable preview
  race.gd            race session: countdown, laps, track limits, input
  track.gd           circuit from data or control points: road mesh, walls, scenery
  car.gd             VehicleBody3D driving model: gearbox, aero, brakes, TC/ABS
  car_specs.gd       every car's physics, gearing, sound and camera spec
  car_body.gd        car 3D models built from primitives
  car_audio.gd       engine/tyre/wind sound synthesized in code
  ai_driver.gd       pure-pursuit steering + curvature speed planner
  race_camera.gd     chase / hood / bumper cameras
  hud.gd             timing HUD and pause/settings menu
  touch_controls.gd  multi-touch pedals and steering buttons
  save_manager.gd    crash-safe profile saving (autoload "Save")
tracks/              imported circuit centrelines (JSON)
tools/
  import_circuit.py  converts a real circuit outline (GeoJSON) into a track file
  racing_line.py     adds a minimum-curvature racing line to a track file
tests/
  sim_test.gd        physics checks per car (0-100, top speed, braking, AI laps)
  game_test.gd       end-to-end: countdown, laps, save, reload, corruption recovery
  tracks_test.gd     the AI completes a clean lap of every track
  grip_test.gd       measures each car's cornering grip (calibrates the AI)
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
