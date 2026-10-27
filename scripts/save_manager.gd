extends Node
## Persistent player profile.
##
## Progress must never be lost, so every save is:
##   1. written to a temporary file,
##   2. read back and verified,
##   3. the previous good save is copied to a backup,
##   4. the temporary file is renamed over the real save.
## On load, a corrupt or missing save falls back to the backup.

const SAVE_DIR := "user://save"
const SAVE_PATH := SAVE_DIR + "/profile.json"
const BACKUP_PATH := SAVE_DIR + "/profile.bak.json"
const TMP_PATH := SAVE_DIR + "/profile.tmp.json"
const SCHEMA_VERSION := 3

signal saved

var data: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	data = _load()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save()


func default_profile() -> Dictionary:
	# Always a deep copy: the literal below is built from constants, and the
	# loader merges saved data into the result, so it must never be shared.
	return _DEFAULTS.duplicate(true)


const _DEFAULTS := {
	"schema": SCHEMA_VERSION,
	"settings": {
		"control_mode": "tilt",       # "tilt", "drag" or "buttons"
		"auto_accelerate": false,
		"invert_tilt": false,
		"tilt_sensitivity": 1.0,
		"camera": 0,
		"traction_control": true,
		"abs": true,
		"brake_assist": "full",       # "off", "moderate" or "full"
		"steer_assist": "full",
		"racing_line": false,
		"ghost": true,
		"time_of_day": "day",       # "day" or "sunset"
		"player_name": "",          # multiplayer
		"last_ip": "",
		"server_url": "",
		"graphics": "high",         # "high" or "saver"
		"car": "gp26",
		"team": 0,
		"track": "silvermoor",
		"mode": "race",             # "race" or "time_trial"
		"laps": 3,
		"opponents": 19,
		"difficulty": "medium",     # easy, medium, hard
	},
	"best_laps": {},                  # "track|car" -> milliseconds
	"best_sectors": {},               # "track|car" -> [ms, ms, ms], best of each sector
	"best_minis": {},                 # "track|car" -> [ms x 24], best of each minisector
	"stats": {
		"laps": 0,
		"distance_m": 0.0,
		"races": 0,
		"wins": 0,
		"podiums": 0,
	},
	"best_finish": {},               # "track|car" -> best race position
}


# ---------------------------------------------------------------- settings

func get_setting(key: String) -> Variant:
	return data["settings"].get(key, default_profile()["settings"].get(key))


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	save()


# ---------------------------------------------------------------- laps

func lap_key(track_id: String, car_id: String) -> String:
	return track_id + "|" + car_id


## Best lap in milliseconds, or -1 if none recorded.
func get_best_lap(track_id: String) -> int:
	if data["best_laps"].has(track_id):
		return int(data["best_laps"][track_id])
	return -1


## Records a completed valid lap. Returns true if it is a new best.
func submit_lap(track_id: String, ms: int) -> bool:
	data["stats"]["laps"] = int(data["stats"]["laps"]) + 1
	var best := get_best_lap(track_id)
	var is_best := best < 0 or ms < best
	if is_best:
		data["best_laps"][track_id] = ms
	save()
	return is_best


func record_race(track_id: String, car_id: String, position: int, field: int) -> void:
	var st: Dictionary = data["stats"]
	st["races"] = int(st["races"]) + 1
	if position == 1:
		st["wins"] = int(st["wins"]) + 1
	if position <= 3:
		st["podiums"] = int(st["podiums"]) + 1
	var key := lap_key(track_id, car_id)
	var best := int(data["best_finish"].get(key, 99))
	if position < best:
		data["best_finish"][key] = position
	save()


func add_distance(meters: float) -> void:
	data["stats"]["distance_m"] = float(data["stats"]["distance_m"]) + meters


# ---------------------------------------------------------------- io

func save() -> void:
	if data.is_empty():
		return
	var text := JSON.stringify(data, "\t")
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Save: cannot open temp file (%s)" % FileAccess.get_open_error())
		return
	f.store_string(text)
	f.flush()
	f.close()
	if _read(TMP_PATH) == null:
		push_error("Save: verification failed, keeping previous save")
		return
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
	if DirAccess.rename_absolute(TMP_PATH, SAVE_PATH) != OK:
		# Some platforms refuse to rename over an existing file.
		DirAccess.remove_absolute(SAVE_PATH)
		DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
	saved.emit()


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed


func _load() -> Dictionary:
	var loaded: Variant = _read(SAVE_PATH)
	if loaded == null:
		loaded = _read(BACKUP_PATH)
	var profile := default_profile()
	if loaded != null:
		_merge(profile, loaded)
	_migrate(profile)
	return profile


## Upgrades saves from older versions in place.
func _migrate(profile: Dictionary) -> void:
	# v1 stored best laps per track only (all set with the Vanta GT).
	var laps: Dictionary = profile["best_laps"]
	for key in laps.keys():
		if not String(key).contains("|"):
			var new_key := lap_key(String(key), "vanta_gt")
			if not laps.has(new_key):
				laps[new_key] = laps[key]
			laps.erase(key)
	# Assists were on/off before they had levels: on -> full.
	var st: Dictionary = profile["settings"]
	for key in ["brake_assist", "steer_assist"]:
		if typeof(st.get(key)) == TYPE_BOOL:
			st[key] = "full" if st[key] else "off"
	# v3: tracks got real elevation and start on the real timing line, so
	# sector splits and ghost laps from before no longer line up.
	if int(profile.get("schema", 1)) < 3:
		profile["best_sectors"] = {}
		profile["best_minis"] = {}
		var dir := DirAccess.open("user://ghosts")
		if dir != null:
			for f in dir.get_files():
				dir.remove(f)
	profile["schema"] = SCHEMA_VERSION


## Personal best time (s) for sector k (0..2), or -1.
func get_best_sector(key: String, k: int) -> float:
	var arr: Array = data["best_sectors"].get(key, [-1, -1, -1])
	return float(arr[k]) / 1000.0 if int(arr[k]) > 0 else -1.0


## Records a sector time; returns true if it's a new personal best.
func submit_sector(key: String, k: int, seconds: float) -> bool:
	if not data["best_sectors"].has(key):
		data["best_sectors"][key] = [-1, -1, -1]
	var arr: Array = data["best_sectors"][key]
	var ms := int(round(seconds * 1000.0))
	if int(arr[k]) <= 0 or ms < int(arr[k]):
		arr[k] = ms
		return true
	return false


## Personal best time (s) for minisector m, or -1.
func get_best_mini(key: String, m: int) -> float:
	var arr: Array = data["best_minis"].get(key, [])
	if m >= arr.size():
		return -1.0
	return float(arr[m]) / 1000.0 if int(arr[m]) > 0 else -1.0


## Records a minisector time; returns true if it's a new personal best.
func submit_mini(key: String, m: int, seconds: float) -> bool:
	if not data["best_minis"].has(key):
		data["best_minis"][key] = []
	var arr: Array = data["best_minis"][key]
	while arr.size() <= m:
		arr.append(-1)
	var ms := int(round(seconds * 1000.0))
	if int(arr[m]) <= 0 or ms < int(arr[m]):
		arr[m] = ms
		return true
	return false


## Ideal lap: the sum of your best minisectors (-1 until every one is set).
func ideal_lap(key: String, count: int) -> float:
	var arr: Array = data["best_minis"].get(key, [])
	if arr.size() < count:
		return -1.0
	var total := 0
	for i in count:
		if int(arr[i]) <= 0:
			return -1.0
		total += int(arr[i])
	return total / 1000.0


## Strength of an assist setting: 0 off, 0.5 moderate, 1 full.
func assist_level(key: String) -> float:
	var v: Variant = get_setting(key)
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	match String(v):
		"full":
			return 1.0
		"moderate":
			return 0.5
	return 0.0


## Overlays saved values onto defaults so new fields added in later
## versions get sensible defaults instead of breaking old saves.
func _merge(base: Dictionary, over: Dictionary) -> void:
	for key in over:
		if base.has(key) and typeof(base[key]) == TYPE_DICTIONARY and typeof(over[key]) == TYPE_DICTIONARY:
			_merge(base[key], over[key])
		else:
			base[key] = over[key]
