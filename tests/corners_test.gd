extends SceneTree
## Corner numbers (race control's "turn 7"): close to the real circuits'.
##   godot --headless --script res://tests/corners_test.gd
const REAL := {"silvermoor": 18, "styria": 10, "lakeside": 14, "red_sea": 27, "caspian": 20, "lone_star": 20,
	"duinen": 14, "brianza": 11, "ardennes": 19, "riviera": 19, "marina": 19, "gulf": 16, "desert": 15,
	"pannonia": 14, "ile_royale": 14, "entrelagos": 15, "isebay": 18, "jiading": 16}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 3:
		Track.CORNER_R = float(a[0]); Track.CORNER_MIN = float(a[1]); Track.CORNER_MERGE = float(a[2])
	var bad := 0
	for t in Track.CATALOG:
		var tr := Track.new()
		root.add_child(tr)
		tr.build(t["id"])
		var n: int = tr.corners().size()
		var real: int = REAL.get(String(t["id"]), -1)
		var ok: bool = real < 0 or absi(n - real) <= maxi(5, real / 3)
		if not ok:
			bad += 1
		print("  %s  %-12s %2d corners (real circuit %s)" % ["PASS" if ok else "FAIL", t["id"], n, str(real) if real > 0 else "-"])
		tr.queue_free()
	print("ALL CHECKS PASSED" if bad == 0 else "%d CHECK(S) FAILED" % bad)
	quit(0 if bad == 0 else 1)
