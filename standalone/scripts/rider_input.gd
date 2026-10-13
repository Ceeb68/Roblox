extends RefCounted
## Physical controls only. This class never supplies stabilizing/landing assists.

var throttle: float = 0.0
var front_brake: float = 0.0
var rear_brake: float = 0.0
var clutch: float = 1.0 # 1 = lever pulled; 0 = fully engaged drivetrain.
var steer: float = 0.0
var lean: float = 0.0
var body_forward: float = 0.0
var body_side: float = 0.0
var standing: bool = false
var foot_down: bool = true
var controller_id: int = -1
var controller_active: bool = false

func _init() -> void:
	_bind("mx_throttle", KEY_W)
	_bind("mx_front_brake", KEY_SPACE)
	_bind("mx_rear_brake", KEY_S)
	_bind("mx_clutch_pull", KEY_V)
	_bind("mx_clutch_release", KEY_B)
	_bind("mx_clutch_quick", KEY_SHIFT)
	_bind("mx_steer_left", KEY_A)
	_bind("mx_steer_right", KEY_D)
	_bind("mx_lean_left", KEY_Z)
	_bind("mx_lean_right", KEY_X)
	_bind("mx_body_forward", KEY_I)
	_bind("mx_body_back", KEY_K)
	_bind("mx_body_left", KEY_J)
	_bind("mx_body_right", KEY_L)
	_bind("mx_downshift", KEY_Q, JOY_BUTTON_DPAD_DOWN)
	_bind("mx_upshift", KEY_E, JOY_BUTTON_DPAD_UP)
	_bind("mx_stand", KEY_C, JOY_BUTTON_A)
	_bind("mx_feet", KEY_F, JOY_BUTTON_X)
	_bind("mx_recover", KEY_R, JOY_BUTTON_Y)
	_bind("mx_engine", KEY_T, JOY_BUTTON_LEFT_STICK)
	_bind("mx_help", KEY_H, JOY_BUTTON_RIGHT_STICK)
	_bind("mx_setup", KEY_U)
	_bind("mx_pause", KEY_ESCAPE, JOY_BUTTON_START)
	_bind("mx_pad_rear_brake", 0, JOY_BUTTON_RIGHT_SHOULDER)
	_bind("mx_pad_clutch", 0, JOY_BUTTON_LEFT_SHOULDER)
	_bind("mx_pad_lean_left", 0, JOY_BUTTON_DPAD_LEFT)
	_bind("mx_pad_lean_right", 0, JOY_BUTTON_DPAD_RIGHT)
	var pads: Array[int] = Input.get_connected_joypads()
	if not pads.is_empty():
		controller_id = pads[0]

func _bind(action: StringName, key: int, pad_button: int = -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.12)
	if key != 0:
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = key
		if not InputMap.action_has_event(action, key_event):
			InputMap.action_add_event(action, key_event)
	if pad_button >= 0:
		var pad_event: InputEventJoypadButton = InputEventJoypadButton.new()
		pad_event.button_index = pad_button
		if not InputMap.action_has_event(action, pad_event):
			InputMap.action_add_event(action, pad_event)

func note_event(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if absf(motion.axis_value) > 0.18:
			controller_id = motion.device
			controller_active = true
	elif event is InputEventJoypadButton:
		controller_id = event.device
		controller_active = true
	elif event is InputEventKey and event.is_pressed():
		controller_active = false

func command(event: InputEvent) -> String:
	if event is InputEventKey and (event as InputEventKey).echo:
		return ""
	for action: String in ["upshift", "downshift", "stand", "feet", "recover", "engine"]:
		if event.is_action_pressed("mx_" + action):
			if action == "stand":
				standing = not standing
			elif action == "feet":
				foot_down = not foot_down
			return action
	return ""

func tick(delta: float, enabled: bool) -> Dictionary:
	if not enabled:
		release_controls()
		return packet()
	if controller_active and controller_id in Input.get_connected_joypads():
		# SDL/GameController mappings normalize the analog trigger values to 0..1.
		throttle = clampf(Input.get_joy_axis(controller_id, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
		front_brake = clampf(Input.get_joy_axis(controller_id, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)
		rear_brake = move_toward(rear_brake, 1.0 if Input.is_action_pressed("mx_pad_rear_brake") else 0.0, delta * 5.0)
		clutch = move_toward(clutch, 1.0 if Input.is_action_pressed("mx_pad_clutch") else 0.0, delta * (12.0 if Input.is_action_pressed("mx_pad_clutch") else (1.0 / 0.6)))
		steer = _deadzone(Input.get_joy_axis(controller_id, JOY_AXIS_LEFT_X))
		lean = Input.get_axis("mx_pad_lean_left", "mx_pad_lean_right")
		body_forward = -_deadzone(Input.get_joy_axis(controller_id, JOY_AXIS_RIGHT_Y))
		body_side = _deadzone(Input.get_joy_axis(controller_id, JOY_AXIS_RIGHT_X))
	else:
		throttle = move_toward(throttle, 1.0 if Input.is_action_pressed("mx_throttle") else 0.0, delta * (1.25 if Input.is_action_pressed("mx_throttle") else 5.0))
		front_brake = move_toward(front_brake, 1.0 if Input.is_action_pressed("mx_front_brake") else 0.0, delta * (2.5 if Input.is_action_pressed("mx_front_brake") else 7.0))
		rear_brake = move_toward(rear_brake, 1.0 if Input.is_action_pressed("mx_rear_brake") else 0.0, delta * 4.0)
		if Input.is_action_pressed("mx_clutch_quick"):
			clutch = 1.0
		elif Input.is_action_pressed("mx_clutch_pull"):
			clutch = move_toward(clutch, 1.0, delta * 3.0)
		elif Input.is_action_pressed("mx_clutch_release"):
			clutch = move_toward(clutch, 0.0, delta * 0.625)
		# The lever holds its position when V/B are released. No automatic clutch.
		steer = move_toward(steer, Input.get_axis("mx_steer_left", "mx_steer_right"), delta * 3.5)
		lean = move_toward(lean, Input.get_axis("mx_lean_left", "mx_lean_right"), delta * 3.0)
		body_forward = move_toward(body_forward, Input.get_axis("mx_body_back", "mx_body_forward"), delta * 3.0)
		body_side = move_toward(body_side, Input.get_axis("mx_body_left", "mx_body_right"), delta * 3.0)
	return packet()

func release_controls() -> void:
	throttle = 0.0
	front_brake = 0.0
	rear_brake = 0.0
	clutch = 1.0
	steer = 0.0
	lean = 0.0
	body_forward = 0.0
	body_side = 0.0
	# Posture and feet are physical rider decisions; menu/focus never change them.

func packet() -> Dictionary:
	return {"throttle": throttle, "frontBrake": front_brake, "rearBrake": rear_brake,
		"clutch": clutch, "steer": steer, "lean": lean, "bodyForward": body_forward,
		"bodySide": body_side, "standing": standing, "footDown": foot_down}

func _deadzone(value: float) -> float:
	return signf(value) * clampf((absf(value) - 0.12) / 0.88, 0.0, 1.0)
