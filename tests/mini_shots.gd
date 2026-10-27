extends SceneTree
## HUD alone with sample minisector colours (fast: no 3D scene).
##   godot --rendering-driver opengl3 --resolution 1600x720 --script res://tests/mini_shots.gd -- <out.png> [race]
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.36, 0.33)
	bg.size = Vector2(1600, 720)
	root.add_child(bg)
	var hud = load("res://scripts/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var pts := PackedVector3Array()
	for i in 400:
		var a := TAU * i / 400.0
		pts.append(Vector3(cos(a) * 600.0 + cos(3.0 * a) * 120.0, 0, sin(a) * 350.0))
	hud.set_track(pts)
	var race := args.size() > 1 and args[1] == "race"
	hud.set_race_mode(race, 3)
	if not race:
		hud.set_ideal(84.317)
	var U = load("res://scripts/ui_style.gd")
	var cols := [U.PURPLE, U.GREEN, U.YELLOW, U.GREEN, U.GREEN, U.PURPLE, U.YELLOW, U.GREEN, U.YELLOW, U.GREEN, U.PURPLE, U.GREEN, U.YELLOW, U.GREEN]
	for m in cols.size():
		hud.show_mini(m, 3.2 + m * 0.01, -0.041 if cols[m] != U.YELLOW else 0.083, cols[m])
	hud.show_sector(0, 27.412, -0.112, U.GREEN)
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0])
	print("saved ", args[0])
	quit(0)
