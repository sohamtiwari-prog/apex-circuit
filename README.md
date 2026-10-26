# Apex Circuit

An original mobile circuit-racing game for Android, built from scratch in
[Godot 4](https://godotengine.org). Inspired by the feel of classic mobile
sim-racers; every car, track and line of code here is original.

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
invert tilt or change tilt sensitivity. **CAM** cycles chase, far chase,
hood and bumper cameras. On a computer: arrows/WASD, Space to brake,
C for camera, R to reset, Esc to pause.

## Progress is never lost

The profile (`user://save/profile.json`) is written atomically: a temp file is
written, verified, the previous save is copied to a backup, then the temp
file replaces the save. A corrupt save automatically falls back to the
backup. Android's auto-backup is enabled too.

## Roadmap

- [x] **Milestone 1: driving.** One car, the Kestrel Park circuit, tilt/touch controls,
  4 cameras, lap timing with checkpoints and track limits, saved best laps
- [ ] **Milestone 2: racing.** AI opponents, grid starts, positions, results screen
- [ ] **Milestone 3: career and garage.** Events, currency, buying cars, upgrades
- [ ] **Milestone 4: content and polish.** More cars and tracks, servicing, engine audio, menus, cockpit view

## Project layout

```
scripts/
  main.gd            race session: countdown, laps, track limits, input
  track.gd           procedural circuit: spline, road mesh, walls, scenery
  car.gd             VehicleBody3D tuning, aero, brakes, car model
  ai_driver.gd       pure-pursuit steering + curvature speed planner
  race_camera.gd     chase / hood / bumper cameras
  hud.gd             timing HUD and pause/settings menu
  touch_controls.gd  multi-touch pedals and steering buttons
  save_manager.gd    crash-safe profile saving (autoload "Save")
tests/
  sim_test.gd        physics checks (acceleration, braking, steering, AI lap)
  game_test.gd       end-to-end: countdown, laps, save, reload, corruption recovery
```

Every push to `main` runs the tests and builds a signed APK via GitHub Actions
(`.github/workflows/build-apk.yml`), published as a GitHub release.

Run the tests locally:

```
godot --headless --import
godot --headless --fixed-fps 120 --script res://tests/sim_test.gd
godot --headless --fixed-fps 120 --script res://tests/game_test.gd
```

## License

Code is MIT licensed (see `LICENSE`).
