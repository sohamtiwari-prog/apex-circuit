class_name WebBridge
## The browser build (iPhone, iPad, laptops): what the phone app gets from
## Android, read from the page instead (web/shell.html).

static var _win: JavaScriptObject


static func is_web() -> bool:
	return OS.has_feature("web")


static func _window() -> JavaScriptObject:
	if _win == null and is_web():
		_win = JavaScriptBridge.get_interface("window")
	return _win


## Gravity in screen axes (as Input.get_accelerometer() on a phone).
static func accelerometer() -> Vector3:
	var w := _window()
	if w == null:
		return Input.get_accelerometer()
	var x: Variant = w.__apexAccX
	if x == null:
		return Vector3.ZERO
	return Vector3(float(x), float(w.__apexAccY), float(w.__apexAccZ))


## The phone's tilt sensor is reporting (always true in the app; in a
## browser only once the page has had motion events, and iOS has said yes).
static func has_tilt() -> bool:
	var w := _window()
	if w == null:
		return true
	return w.__apexAccX != null


## iPhone / iPad (in a browser).
static func is_ios() -> bool:
	var w := _window()
	return w != null and bool(w.__apexIOS)
