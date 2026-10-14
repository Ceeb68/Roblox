extends RefCounted
## Keyboard and one selected controller. No force or orientation correction here.
const ControllerBindings = preload("res://scripts/controller_bindings.gd")
var controller_bindings: RefCounted = ControllerBindings.new()
var throttle: float = 0.0
var front_brake: float = 0.0
var rear_brake: float = 0.0
var clutch: float = 1.0
var steer: float = 0.0
var lean: float = 0.0
var body_forward: float = 0.0
var body_side: float = 0.0
var standing: bool = false
var foot_down: bool = true
var controller_id: int = -1
var controller_active: bool = false
var _blocked_keys: Dictionary = {}
var _blocked_pad: Dictionary = {}

func _init() -> void:
	Input.joy_connection_changed.connect(_controller_connection_changed)
	var keys: Dictionary = {"throttle": KEY_W, "front_brake": KEY_SPACE, "rear_brake": KEY_S,
		"clutch_pull": KEY_V, "clutch_release": KEY_B, "clutch_quick": KEY_SHIFT,
		"steer_left": KEY_A, "steer_right": KEY_D, "lean_left": KEY_Z, "lean_right": KEY_X,
		"body_forward": KEY_I, "body_back": KEY_K, "body_left": KEY_J, "body_right": KEY_L,
		"downshift": KEY_Q, "upshift": KEY_E, "stand": KEY_C, "feet": KEY_F, "recover": KEY_R,
		"engine": KEY_T, "help": KEY_H, "setup": KEY_U, "pause": KEY_ESCAPE, "camera": KEY_M}
	for action: String in keys:
		var name_action: String = "mx_" + action
		if not InputMap.has_action(name_action):
			InputMap.add_action(name_action)
		# Remove legacy global joy events; only the selected device may drive.
		for existing: InputEvent in InputMap.action_get_events(name_action):
			if existing is InputEventJoypadButton or existing is InputEventJoypadMotion:
				InputMap.action_erase_event(name_action, existing)
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = int(keys[action])
		if not InputMap.action_has_event(name_action, event):
			InputMap.action_add_event(name_action, event)
	var pads: Array[int] = Input.get_connected_joypads()
	if not pads.is_empty():
		controller_id = pads[0]

func select_controller(device: int) -> void:
	release_controls()
	controller_bindings.reset_edges()
	controller_id = device
	controller_active = device >= 0

func note_event(event: InputEvent) -> void:
	# Release/recenter rearms only that input; held controls remain blocked.
	for action: StringName in _blocked_keys.keys():
		if event.is_action_released(action):
			_blocked_keys.erase(action)
	if event.device == controller_id:
		for action: String in _blocked_pad.keys():
			var binding: Dictionary = controller_bindings.bindings.get(action, {})
			if event is InputEventJoypadButton and str(binding.get("kind", "")) == "button":
				if (event as InputEventJoypadButton).button_index == int(binding.index) and not event.is_pressed():
					_blocked_pad.erase(action)
			elif event is InputEventJoypadMotion and str(binding.get("kind", "")) == "axis":
				var motion := event as InputEventJoypadMotion
				if motion.axis == int(binding.index) and float(controller_bindings.axis_strength(motion.axis_value, binding)) <= 0.05:
					_blocked_pad.erase(action)
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		if controller_id < 0:
			controller_id = event.device
		if event.device != controller_id:
			return
		if event is InputEventJoypadButton or absf((event as InputEventJoypadMotion).axis_value) > 0.18:
			controller_active = true
	elif event is InputEventKey and event.is_pressed():
		controller_active = false

func command(event: InputEvent) -> String:
	if event is InputEventKey and (event as InputEventKey).echo:
		return ""
	var action: String = ""
	if event is InputEventKey:
		for candidate: String in ["upshift", "downshift", "stand", "feet", "recover", "engine", "help", "setup", "pause", "camera"]:
			if event.is_action_pressed("mx_" + candidate):
				action = candidate
				break
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		action = str(controller_bindings.action_for_event(event, controller_id))
	if (event is InputEventKey and _blocked_keys.has("mx_" + action)) or ((event is InputEventJoypadButton or event is InputEventJoypadMotion) and _blocked_pad.has(action)):
		return ""
	return action

func apply_command(action: String) -> void:
	if action == "stand":
		standing = not standing
	elif action == "feet":
		foot_down = not foot_down

func tick(delta: float, enabled: bool) -> Dictionary:
	if controller_active and not controller_id in Input.get_connected_joypads():
		controller_id = -1
		controller_active = false
		release_controls()
		return packet()
	if not enabled:
		release_controls()
		return packet()
	if controller_active:
		throttle = _pad_strength("throttle")
		front_brake = _pad_strength("front_brake")
		rear_brake = move_toward(rear_brake, _pad_strength("rear_brake"), delta * 5.0)
		var lever: float = _pad_strength("clutch")
		var binding: Dictionary = controller_bindings.bindings.get("clutch", {})
		clutch = lever if str(binding.get("kind", "")) == "axis" else move_toward(clutch, lever, delta * (12.0 if lever > clutch else (1.0 / 0.6)))
		steer = _controller_pair("steer_left", "steer_right")
		lean = _controller_pair("lean_left", "lean_right")
		body_forward = _controller_pair("body_back", "body_forward")
		body_side = _controller_pair("body_left", "body_right")
	else:
		throttle = move_toward(throttle, 1.0 if _key_down("mx_throttle") else 0.0, delta * (1.25 if _key_down("mx_throttle") else 5.0))
		front_brake = move_toward(front_brake, 1.0 if _key_down("mx_front_brake") else 0.0, delta * (2.5 if _key_down("mx_front_brake") else 7.0))
		rear_brake = move_toward(rear_brake, 1.0 if _key_down("mx_rear_brake") else 0.0, delta * 4.0)
		if _key_down("mx_clutch_quick"):
			clutch = 1.0
		elif _key_down("mx_clutch_pull"):
			clutch = move_toward(clutch, 1.0, delta * 3.0)
		elif _key_down("mx_clutch_release"):
			clutch = move_toward(clutch, 0.0, delta * 0.625)
		steer = move_toward(steer, _key_axis("mx_steer_left", "mx_steer_right"), delta * 3.5)
		lean = move_toward(lean, _key_axis("mx_lean_left", "mx_lean_right"), delta * 3.0)
		body_forward = move_toward(body_forward, _key_axis("mx_body_back", "mx_body_forward"), delta * 3.0)
		body_side = move_toward(body_side, _key_axis("mx_body_left", "mx_body_right"), delta * 3.0)
	return packet()

func _controller_pair(negative: String, positive: String) -> float:
	return _pad_strength(positive) - _pad_strength(negative)

func release_controls() -> void:
	throttle = 0.0
	front_brake = 0.0
	rear_brake = 0.0
	clutch = 1.0
	steer = 0.0
	lean = 0.0
	body_forward = 0.0
	body_side = 0.0

func packet() -> Dictionary:
	return {"throttle": throttle, "frontBrake": front_brake, "rearBrake": rear_brake,
		"clutch": clutch, "steer": steer, "lean": lean, "bodyForward": body_forward,
		"bodySide": body_side, "standing": standing, "footDown": foot_down}

func _controller_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == controller_id:
		controller_id = -1
		controller_active = false
		controller_bindings.reset_edges()
		release_controls()
	elif connected and controller_id < 0:
		controller_id = device
		controller_active = false

func reset_for_recovery() -> void:
	release_controls()
	standing = false
	foot_down = true
	_blocked_keys.clear()
	_blocked_pad.clear()
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("mx_") and Input.is_action_pressed(action):
			_blocked_keys[action] = true
	if controller_id >= 0:
		for action: String in controller_bindings.ACTIONS:
			if float(controller_bindings.strength(action, controller_id)) > 0.05:
				_blocked_pad[action] = true
	controller_bindings.reset_edges()

func _key_down(action: StringName) -> bool:
	var pressed := Input.is_action_pressed(action)
	if _blocked_keys.has(action):
		if pressed:
			return false
		_blocked_keys.erase(action)
	return pressed

func _key_axis(negative: StringName, positive: StringName) -> float:
	return float(_key_down(positive)) - float(_key_down(negative))

func _pad_strength(action: String) -> float:
	var value: float = float(controller_bindings.strength(action, controller_id))
	if _blocked_pad.has(action):
		if value > 0.05:
			return 0.0
		_blocked_pad.erase(action)
	return value
