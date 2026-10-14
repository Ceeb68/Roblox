extends SceneTree
const Bindings = preload("res://scripts/controller_bindings.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func joy_button(device: int, index: int) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = true
	return event

func joy_axis(device: int, index: int, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = device
	event.axis = index
	event.axis_value = value
	return event

func _run() -> void:
	var saved_files: Dictionary = {}
	for config_path: String in ["user://preferences.cfg", "user://controller_bindings.cfg"]:
		if FileAccess.file_exists(config_path):
			saved_files[config_path] = FileAccess.get_file_as_bytes(config_path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	var bindings: RefCounted = Bindings.new(false)
	check(bindings.describe("camera") == "B / Circle", "camera has accessible default button")
	check(bindings.axis_strength(0.08, bindings.bindings.steer_right) == 0.0, "stick drift stays inside deadzone")
	check(is_equal_approx(float(bindings.axis_strength(-1.0, bindings.bindings.steer_left)), 1.0), "left directional axis has full range")
	check(bindings.axis_strength(-1.0, bindings.bindings.steer_right) == 0.0, "axis opposite direction does not actuate")
	var duplicate: Dictionary = bindings.bindings.camera.duplicate()
	check(bindings.assign("upshift", duplicate) == ["camera"], "duplicate button rejected with conflict target")
	check(bindings.describe("upshift") == "D-pad up", "rejected capture preserves original binding")
	check(bindings.assign("upshift", duplicate, true).is_empty() and bindings.bindings.camera.is_empty(), "explicit replacement unbinds conflicting action")
	check(bindings.assign("throttle", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": -1}).is_empty(), "analog action remaps to another axis")
	var motion: InputEventJoypadMotion = joy_axis(4, JOY_AXIS_LEFT_Y, -0.9)
	Input.parse_input_event(motion)
	check(float(bindings.axis_strength(motion.axis_value, bindings.bindings.throttle)) > 0.8, "remapped analog axis has progressive input range")
	check(bindings.strength("throttle", 5) == 0.0, "another device cannot supply selected throttle")
	check(bindings.assign("rear_brake", {"kind": "axis", "index": JOY_AXIS_TRIGGER_LEFT, "direction": -1}).is_empty(), "brake can bind an analog axis direction")
	var inverse_trigger: Dictionary = {"kind": "axis", "index": JOY_AXIS_TRIGGER_RIGHT, "direction": -1}
	check(is_equal_approx(float(bindings.axis_strength(0.0, inverse_trigger)), 1.0) and float(bindings.axis_strength(1.0, inverse_trigger)) == 0.0, "trigger inversion reverses its 0..1 range")
	check(bindings.assign("clutch", {"kind": "button", "index": 999, "direction": 1}) == ["invalid"], "invalid hardware index rejected")
	check(bindings.capture(joy_axis(4, JOY_AXIS_RIGHT_X, 0.4)).is_empty(), "capture ignores small accidental axis motion")
	check(bindings.capture(joy_axis(4, JOY_AXIS_RIGHT_X, -0.9)).direction == -1, "capture preserves chosen direction")
	bindings.deadzone = 0.22
	var path: String = "user://controller_regression.cfg"
	check(bindings.save_file(path) == OK, "custom mapping saves locally")
	var reload: RefCounted = Bindings.new(false)
	check(reload.load_file(path) == OK and reload.bindings.throttle == bindings.bindings.throttle and is_equal_approx(float(reload.deadzone), 0.22), "binding and deadzone survive reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	bindings.reset_defaults()
	check(bindings.describe("throttle") == "RT / R2 +" and is_equal_approx(float(bindings.deadzone), 0.14), "reset restores controller layout and deadzone")
	bindings.assign("upshift", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": -1}, true)
	bindings.assign("downshift", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": 1}, true)
	check(bindings.action_for_event(joy_axis(7, JOY_AXIS_LEFT_Y, -1.0), 4).is_empty(), "unselected device cannot shift")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, -1.0), 4) == "upshift", "discrete command can bind axis")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, -0.9), 4).is_empty(), "held shift axis emits only one command")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, 1.0), 4) == "downshift", "opposite axis command fires after crossing")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, -1.0), 4) == "upshift", "return crossing re-arms command without resting frame")
	var rider: RefCounted = RiderInput.new()
	rider.controller_bindings = bindings
	rider.select_controller(4)
	rider.note_event(joy_button(7, JOY_BUTTON_A))
	check(rider.controller_id == 4 and rider.command(joy_button(7, JOY_BUTTON_A)).is_empty(), "secondary controller cannot take over or toggle posture")
	rider.throttle = 1.0
	rider.clutch = 0.0
	var safe: Dictionary = rider.tick(0.1, true)
	check(safe.throttle == 0.0 and safe.clutch == 1.0 and not rider.controller_active, "disconnected controller safely releases drivetrain")
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var game: Node3D = packed.instantiate() as Node3D
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.modal_kind == "welcome" and game.riding_mode == "virtual_rider", "first boot presents lean control default")
	check(game.orbit_distance < 5.0 and game.third_person_fov <= 60.0, "chase framing makes bike larger")
	game.start_session()
	paused = true # Camera and input tests hold the world still; no handling assertions here.
	game.set_camera_mode("first_person", false)
	var eye_before: Transform3D = game.camera_target_transform()
	check(eye_before.origin.distance_to(game.bike.chassis.global_position) < 1.6 and eye_before.origin.y > game.bike.chassis.global_position.y + 0.6, "helmet camera lives at rider eye height")
	var before_body: Transform3D = game.bike.chassis.global_transform
	game._update_camera(0.05)
	check(game.bike.chassis.global_transform.is_equal_approx(before_body), "camera follow never changes motorcycle transform")
	check(game.camera_hint_panel.offset_top > 0.0 and game.status_panel.offset_top > 0.0, "helmet HUD leaves bars and gloves unobstructed")
	game.bike.chassis.global_position += Vector3(3.0, 0.3, -2.0)
	var eye_after: Transform3D = game.camera_target_transform()
	check((eye_after.origin - eye_before.origin).distance_to(Vector3(3.0, 0.3, -2.0)) < 0.001, "helmet anchor follows actual body translation")
	game._update_camera(0.05)
	check(game.camera.global_position.distance_to(eye_after.origin) < 0.001, "camera remains anchored instead of clipping through torso")
	game.set_camera_mode("third_person", false)
	check(game.camera_mode == "third_person" and game.camera.fov == game.third_person_fov, "camera toggle restores chase field of view")
	game.rider_input.select_controller(4)
	game.rider_input.controller_bindings.assign("upshift", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": -1}, true)
	game.rider_input.controller_bindings.assign("downshift", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": 1}, true)
	check(game.bike.get_telemetry().gear == 0, "discrete command fixture starts in neutral")
	game._input(joy_axis(4, JOY_AXIS_LEFT_Y, -1.0))
	check(game.bike.get_telemetry().gear == 1, "remapped axis actually shifts through game input dispatcher")
	game._input(joy_axis(4, JOY_AXIS_LEFT_Y, -0.9))
	check(game.bike.get_telemetry().gear == 1, "held remapped axis does not repeat shifts")
	paused = false
	for frame: int in range(24):
		await physics_frame
	paused = true
	game.rider_input.select_controller(4)
	game._input(joy_axis(4, JOY_AXIS_LEFT_Y, 1.0))
	check(game.bike.get_telemetry().gear == 0, "opposite remapped axis downshifts through game dispatcher")
	game._show_modal("bindings")
	game._invert_controller_axis("steer_left")
	check(game.rider_input.controller_bindings.bindings.steer_left.direction == 1 and game.rider_input.controller_bindings.bindings.steer_right.direction == -1, "axis inversion swaps both steering halves")
	game.rider_input.controller_bindings.reset_defaults()
	game.rider_input.controller_bindings.save_file()
	game._show_modal("settings")
	check(game.modal_kind == "settings", "settings renders riding mode and camera controls")
	game._resume()
	var camera_key: InputEventKey = InputEventKey.new()
	camera_key.physical_keycode = KEY_M
	camera_key.pressed = true
	game._input(camera_key)
	check(game.camera_mode == "first_person", "keyboard M toggles actual game camera")
	game.rider_input.foot_down = false
	game.rider_input.standing = true
	game.rider_input.clutch = 0.0
	game.bike.set_controls(game.rider_input.packet())
	var recover_key: InputEventKey = InputEventKey.new()
	recover_key.physical_keycode = KEY_R
	recover_key.pressed = true
	game._input(recover_key)
	check(game.rider_input.foot_down and not game.rider_input.standing and game.rider_input.clutch == 1.0, "R remount plants feet, seats rider and pulls clutch")
	check(game.bike.get_telemetry().gear == 0, "R remount resets drivetrain to neutral")
	paused = false
	for frame: int in range(240):
		await physics_frame
	var remounted: Dictionary = game.bike.get_telemetry()
	check(bool(remounted.get("footDown", false)) and not bool(remounted.get("standing", true)), "remount support persists through live game input ticks")
	check(not bool(remounted.get("crashed", true)) and game.bike.chassis.global_basis.y.dot(Vector3.UP) > 0.98 and game.bike.chassis.linear_velocity.length() < 0.3, "remounted bike remains stationary and upright for one native second")
	game.queue_free()
	for config_path: String in ["user://preferences.cfg", "user://controller_bindings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
		if saved_files.has(config_path):
			var restored: FileAccess = FileAccess.open(config_path, FileAccess.WRITE)
			restored.store_buffer(saved_files[config_path])
	paused = false
	await process_frame
	print("Input / camera regression: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
