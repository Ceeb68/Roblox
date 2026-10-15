extends RefCounted
## Device-specific controller routing. Keyboard bindings stay in InputMap.
const FILE_PATH: String = "user://controller_bindings.cfg"
const ACTIONS: Array[String] = ["throttle", "front_brake", "rear_brake", "clutch",
	"steer_left", "steer_right", "lean_left", "lean_right", "body_forward", "body_back",
	"body_left", "body_right", "upshift", "downshift", "stand", "recover",
	"engine", "camera", "help", "setup", "pause", "scrub"]
const LABELS: Dictionary = {"throttle": "Throttle", "front_brake": "Front brake", "rear_brake": "Rear brake",
	"clutch": "Clutch lever", "steer_left": "Bike lean / bars left", "steer_right": "Bike lean / bars right",
	"lean_left": "Rider lean left", "lean_right": "Rider lean right", "body_forward": "Rider forward",
	"body_back": "Rider backward", "body_left": "Rider left", "body_right": "Rider right",
	"upshift": "Shift up", "downshift": "Shift down", "stand": "Stand / sit",
	"recover": "Recover", "engine": "Engine start", "camera": "Camera mode", "help": "Controls",
	"setup": "Suspension setup", "pause": "Pause", "scrub": "Scrub (hold / analog)"}
var bindings: Dictionary = {}
var deadzone: float = 0.14
var trigger_deadzone: float = 0.03
var _axis_latches: Dictionary = {}

func _init(load_saved: bool = true) -> void:
	reset_defaults()
	if load_saved:
		load_file()

func _axis(index: int, direction: int) -> Dictionary:
	return {"kind": "axis", "index": index, "direction": direction}

func _button(index: int) -> Dictionary:
	return {"kind": "button", "index": index, "direction": 1}

func reset_defaults() -> void:
	bindings = {"throttle": _axis(JOY_AXIS_TRIGGER_RIGHT, 1), "front_brake": _axis(JOY_AXIS_TRIGGER_LEFT, 1),
		"rear_brake": _button(JOY_BUTTON_RIGHT_SHOULDER), "clutch": _button(JOY_BUTTON_LEFT_SHOULDER),
		"steer_left": _axis(JOY_AXIS_LEFT_X, -1), "steer_right": _axis(JOY_AXIS_LEFT_X, 1),
		"lean_left": _button(JOY_BUTTON_DPAD_LEFT), "lean_right": _button(JOY_BUTTON_DPAD_RIGHT),
		"body_forward": _axis(JOY_AXIS_RIGHT_Y, -1), "body_back": _axis(JOY_AXIS_RIGHT_Y, 1),
		"body_left": _axis(JOY_AXIS_RIGHT_X, -1), "body_right": _axis(JOY_AXIS_RIGHT_X, 1),
		"upshift": _button(JOY_BUTTON_DPAD_UP), "downshift": _button(JOY_BUTTON_DPAD_DOWN),
		"stand": _button(JOY_BUTTON_A), "recover": _button(JOY_BUTTON_Y),
		"engine": _button(JOY_BUTTON_LEFT_STICK), "camera": _button(JOY_BUTTON_B),
		"help": _button(JOY_BUTTON_RIGHT_STICK), "setup": {}, "pause": _button(JOY_BUTTON_START),
		"scrub": _button(JOY_BUTTON_X)}
	deadzone = 0.14
	trigger_deadzone = 0.03
	_axis_latches.clear()

func is_valid(binding: Dictionary) -> bool:
	if binding.is_empty():
		return true
	var kind: String = str(binding.get("kind", ""))
	var index: int = int(binding.get("index", -1))
	if kind == "axis":
		return index >= 0 and index < JOY_AXIS_MAX and int(binding.get("direction", 0)) in [-1, 1]
	return kind == "button" and index >= 0 and index < JOY_BUTTON_MAX

func conflicts(action: String, binding: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if binding.is_empty():
		return found
	for other: String in ACTIONS:
		if other == action:
			continue
		var existing: Dictionary = bindings.get(other, {})
		if not existing.is_empty() and str(existing.kind) == str(binding.kind) and int(existing.index) == int(binding.index):
			if str(binding.kind) == "button" or int(existing.direction) == int(binding.direction):
				found.append(other)
	return found

func assign(action: String, binding: Dictionary, replace_conflicts: bool = false) -> Array[String]:
	if not action in ACTIONS or not is_valid(binding):
		return ["invalid"]
	var found: Array[String] = conflicts(action, binding)
	if not found.is_empty() and not replace_conflicts:
		return found
	for other: String in found:
		bindings[other] = {}
	bindings[action] = binding.duplicate()
	_axis_latches.clear()
	return []

func invert(action: String) -> bool:
	var binding: Dictionary = (bindings.get(action, {}) as Dictionary).duplicate()
	if str(binding.get("kind", "")) != "axis":
		return false
	binding.direction = -int(binding.direction)
	if not assign(action, binding).is_empty():
		return false
	return true

func reset_edges() -> void:
	_axis_latches.clear()

func strength(action: String, device: int) -> float:
	if device < 0:
		return 0.0
	var binding: Dictionary = bindings.get(action, {})
	if binding.is_empty():
		return 0.0
	if str(binding.kind) == "button":
		return 1.0 if Input.is_joy_button_pressed(device, int(binding.index)) else 0.0
	return axis_strength(Input.get_joy_axis(device, int(binding.index)), binding)

func axis_strength(value: float, binding: Dictionary) -> float:
	var trigger: bool = int(binding.index) in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
	var zone: float = trigger_deadzone if trigger else deadzone
	var directed: float = value * float(binding.direction)
	# SDL triggers already span 0..1; inverse means pull/release reversal.
	if trigger and int(binding.direction) < 0:
		directed = 1.0 - value
	return clampf((directed - zone) / (1.0 - zone), 0.0, 1.0)

func action_for_event(event: InputEvent, device: int) -> String:
	if event.device != device or device < 0:
		return ""
	var pressed_action: String = ""
	for action: String in ACTIONS:
		var binding: Dictionary = bindings.get(action, {})
		if binding.is_empty():
			continue
		if event is InputEventJoypadButton and str(binding.kind) == "button":
			var button_event: InputEventJoypadButton = event as InputEventJoypadButton
			if button_event.button_index == int(binding.index) and button_event.pressed:
				pressed_action = action
		elif event is InputEventJoypadMotion and str(binding.kind) == "axis":
			var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
			if motion.axis != int(binding.index):
				continue
			var held: bool = axis_strength(motion.axis_value, binding) > 0.6
			var prior: bool = bool(_axis_latches.get(action, false))
			_axis_latches[action] = held
			if held and not prior:
				pressed_action = action
	return pressed_action

func capture(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton and event.is_pressed():
		return _button((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if absf(motion.axis_value) >= 0.7:
			return _axis(motion.axis, 1 if motion.axis_value > 0.0 else -1)
	return {}

func describe(action: String) -> String:
	var binding: Dictionary = bindings.get(action, {})
	if binding.is_empty():
		return "Unbound"
	if str(binding.kind) == "button":
		var names: Dictionary = {JOY_BUTTON_A: "A / Cross", JOY_BUTTON_B: "B / Circle", JOY_BUTTON_X: "X / Square",
			JOY_BUTTON_Y: "Y / Triangle", JOY_BUTTON_LEFT_SHOULDER: "LB / L1", JOY_BUTTON_RIGHT_SHOULDER: "RB / R1",
			JOY_BUTTON_LEFT_STICK: "Left stick click", JOY_BUTTON_RIGHT_STICK: "Right stick click",
			JOY_BUTTON_START: "Start / Options", JOY_BUTTON_BACK: "Back / Select", JOY_BUTTON_DPAD_LEFT: "D-pad left",
			JOY_BUTTON_DPAD_RIGHT: "D-pad right", JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down"}
		return str(names.get(int(binding.index), "Button %d" % int(binding.index)))
	var axes: Dictionary = {JOY_AXIS_LEFT_X: "Left stick X", JOY_AXIS_LEFT_Y: "Left stick Y", JOY_AXIS_RIGHT_X: "Right stick X",
		JOY_AXIS_RIGHT_Y: "Right stick Y", JOY_AXIS_TRIGGER_LEFT: "LT / L2", JOY_AXIS_TRIGGER_RIGHT: "RT / R2"}
	return "%s %s" % [str(axes.get(int(binding.index), "Axis %d" % int(binding.index))), "+" if int(binding.direction) > 0 else "−"]

func save_file(path: String = FILE_PATH) -> Error:
	var file: ConfigFile = ConfigFile.new()
	file.set_value("controller", "version", 2)
	file.set_value("controller", "deadzone", clampf(deadzone, 0.0, 0.5))
	file.set_value("controller", "trigger_deadzone", clampf(trigger_deadzone, 0.0, 0.3))
	for action: String in ACTIONS:
		file.set_value("bindings", action, bindings.get(action, {}))
	return file.save(path)

func load_file(path: String = FILE_PATH) -> Error:
	var file: ConfigFile = ConfigFile.new()
	var result: Error = file.load(path)
	if result != OK:
		return result
	deadzone = clampf(float(file.get_value("controller", "deadzone", 0.14)), 0.0, 0.5)
	trigger_deadzone = clampf(float(file.get_value("controller", "trigger_deadzone", 0.03)), 0.0, 0.3)
	var loaded: Dictionary = {}
	for action: String in ACTIONS:
		var value: Variant = file.get_value("bindings", action, bindings.get(action, {}))
		loaded[action] = value.duplicate() if value is Dictionary and is_valid(value as Dictionary) else bindings.get(action, {}).duplicate()
	bindings = loaded
	# Old layouts may already use X for a customized action. Add the new
	# default only when it is free; never overwrite a player's saved mapping.
	if not file.has_section_key("bindings", "scrub") \
			and not conflicts("scrub", bindings.scrub).is_empty():
		bindings.scrub = {}
	_axis_latches.clear()
	return OK
