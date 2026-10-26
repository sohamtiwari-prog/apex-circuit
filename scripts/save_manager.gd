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
const SCHEMA_VERSION := 2

signal saved

var data: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	data = _load()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save()


func default_profile() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"settings": {
			"control_mode": "tilt",       # "tilt" or "buttons"
			"auto_accelerate": false,
			"invert_tilt": false,
			"tilt_sensitivity": 1.0,
			"camera": 0,
			"traction_control": true,
			"abs": true,
			"car": "gp26",
			"team": 0,
			"track": "silvermoor",
		},
		"best_laps": {},                  # "track|car" -> milliseconds
		"stats": {
			"laps": 0,
			"distance_m": 0.0,
		},
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
	profile["schema"] = SCHEMA_VERSION


## Overlays saved values onto defaults so new fields added in later
## versions get sensible defaults instead of breaking old saves.
func _merge(base: Dictionary, over: Dictionary) -> void:
	for key in over:
		if base.has(key) and typeof(base[key]) == TYPE_DICTIONARY and typeof(over[key]) == TYPE_DICTIONARY:
			_merge(base[key], over[key])
		else:
			base[key] = over[key]
