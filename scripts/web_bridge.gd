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


## Opened from the iPhone's home screen (full screen), not in Safari.
static func is_standalone() -> bool:
	var w := _window()
	return w == null or bool(w.__apexStandalone)


static var _text_cb: JavaScriptObject
static var _text_field: LineEdit


## Typing in a browser: phones only raise their keyboard for a real text
## box, so a field opens one in a bar across the top of the page (above
## the keyboard, in landscape too). What you type goes into the field as
## you type; Done or Enter closes it.
static func edit_text(e: LineEdit) -> void:
	var w := _window()
	if w == null or w.__apexText == null:
		return
	_text_field = e
	_text_cb = JavaScriptBridge.create_callback(_on_text)
	w.__apexText.open(e.text, e.placeholder_text, e.max_length, _text_cb)
	# (Let go of the field: while a field has the focus the engine keeps
	# pulling the page's focus to its own hidden typing box.)
	e.release_focus.call_deferred()


static func _on_text(args: Array) -> void:
	var e := _text_field
	if e == null or not is_instance_valid(e):
		return
	var t := String(args[0])
	if e.max_length > 0:
		t = t.substr(0, e.max_length)
	if t != e.text:
		e.text = t
		e.caret_column = t.length()
		e.text_changed.emit(t)
	if bool(args[1]):
		e.release_focus()
		e.text_submitted.emit(t)
