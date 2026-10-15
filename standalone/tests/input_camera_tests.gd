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
	check(bindings.describe("scrub") == "X / Square" and "scrub" in bindings.ACTIONS
		and "hold" in str(bindings.LABELS.scrub), "scrub has a customizable continuous Xbox X default")
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
	_scrub_migration_regressions()
	bindings.reset_defaults()
	check(bindings.describe("throttle") == "RT / R2 +" and is_equal_approx(float(bindings.deadzone), 0.14), "reset restores controller layout and deadzone")
	check(not "feet" in bindings.ACTIONS and not bindings.bindings.has("feet"), "automatic feet removes the manual feet action from controller bindings")
	bindings.assign("upshift", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": -1}, true)
	bindings.assign("downshift", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": 1}, true)
	check(bindings.action_for_event(joy_axis(7, JOY_AXIS_LEFT_Y, -1.0), 4).is_empty(), "unselected device cannot shift")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, -1.0), 4) == "upshift", "discrete command can bind axis")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, -0.9), 4).is_empty(), "held shift axis emits only one command")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, 1.0), 4) == "downshift", "opposite axis command fires after crossing")
	check(bindings.action_for_event(joy_axis(4, JOY_AXIS_LEFT_Y, -1.0), 4) == "upshift", "return crossing re-arms command without resting frame")
	var rider: RefCounted = RiderInput.new()
	check(not InputMap.has_action("mx_feet"), "automatic feet removes the legacy keyboard feet action")
	_scrub_input_regressions(rider)
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
	await _chase_input_regressions(game)
	_rider_twist_visual_regressions(game)
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
	# Camera probes intentionally displaced one body while paused. Restore
	# a complete stationary mount before checking support/recovery semantics.
	game.bike.reset_bike(game.track.spawn, true)
	game.rider_input.reset_for_recovery()
	game.rider_input.standing = true
	game.rider_input.clutch = 0.0
	game.rider_input.update_auto_feet(1.0 / 240.0, game.bike.get_telemetry())
	check(game.rider_input.standing and game.rider_input.foot_down and not bool(game.rider_input.packet().standing),
		"standing preference retains automatic seated ground support before a stationary recovery")
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

func _scrub_migration_regressions() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("controller", "version", 1)
	legacy.set_value("bindings", "camera", {"kind": "button", "index": JOY_BUTTON_X, "direction": 1})
	var legacy_path := "user://scrub_legacy_binding_test.cfg"
	var map: RefCounted = Bindings.new(false)
	check(legacy.save(legacy_path) == OK and map.load_file(legacy_path) == OK
		and map.describe("camera") == "X / Square" and map.bindings.scrub.is_empty(),
		"migration preserves a saved Xbox X mapping and leaves new scrub action unbound")
	legacy.set_value("bindings", "camera", {"kind": "button", "index": JOY_BUTTON_B, "direction": 1})
	map.reset_defaults()
	check(legacy.save(legacy_path) == OK and map.load_file(legacy_path) == OK
		and map.describe("scrub") == "X / Square", "old layout adds scrub default when Xbox X is free")
	map.assign("scrub", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": 1})
	check(map.save_file(legacy_path) == OK and map.load_file(legacy_path) == OK
		and map.bindings.scrub == {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": 1},
		"analog scrub remapping survives save and reload")
	map.assign("scrub", {})
	check(map.save_file(legacy_path) == OK and map.load_file(legacy_path) == OK
		and map.bindings.scrub.is_empty(), "explicitly unbound scrub remains unbound after reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))

func _scrub_input_regressions(rider: RefCounted) -> void:
	var keyboard_f := false
	for event: InputEvent in InputMap.action_get_events("mx_scrub"):
		keyboard_f = keyboard_f or (event is InputEventKey and event.physical_keycode == KEY_F)
	check(keyboard_f and not InputMap.has_action("mx_feet"),
		"F maps to continuous scrub while the manual foot action remains absent")
	rider.controller_active = false
	Input.action_press("mx_scrub")
	var held: Dictionary = rider.tick(1.0 / 240.0, true)
	check(float(held.scrub) == 1.0 and bool(held.footDown) and not bool(held.standing),
		"held keyboard scrub reaches the riding packet without changing feet or posture")
	check(float(rider.tick(1.0 / 240.0, false).scrub) == 0.0,
		"disabled riding releases scrub instead of leaving an armed gesture")
	rider.reset_for_recovery()
	check(float(rider.tick(1.0 / 240.0, true).scrub) == 0.0,
		"recovery blocks a held scrub key until it is released")
	Input.action_release("mx_scrub")
	rider.tick(1.0 / 240.0, true)
	Input.action_press("mx_scrub")
	check(float(rider.tick(1.0 / 240.0, true).scrub) == 1.0,
		"released and pressed scrub key rearms normally after recovery")
	Input.action_release("mx_scrub")
	rider.release_controls()
	var map: RefCounted = Bindings.new(false)
	rider.controller_bindings = map
	rider.select_controller(4)
	Input.parse_input_event(joy_button(4, JOY_BUTTON_X))
	Input.flush_buffered_events()
	check(is_equal_approx(float(rider._pad_strength("scrub")), 1.0)
		and rider.command(joy_button(4, JOY_BUTTON_X)).is_empty(),
		"selected Xbox X supplies continuous scrub strength without a one-shot command")
	var released := joy_button(4, JOY_BUTTON_X)
	released.pressed = false
	Input.parse_input_event(released)
	Input.parse_input_event(joy_button(7, JOY_BUTTON_X))
	Input.flush_buffered_events()
	check(float(rider._pad_strength("scrub")) == 0.0,
		"secondary controller cannot supply selected rider scrub")
	var other_released := joy_button(7, JOY_BUTTON_X)
	other_released.pressed = false
	Input.parse_input_event(other_released)
	map.assign("scrub", {"kind": "axis", "index": JOY_AXIS_LEFT_Y, "direction": 1})
	Input.parse_input_event(joy_axis(4, JOY_AXIS_LEFT_Y, 0.5))
	Input.flush_buffered_events()
	var partial: float = rider._pad_strength("scrub")
	check(partial > 0.4 and partial < 0.5,
		"remapped analog scrub supplies progressive strength through the existing deadzone")
	Input.parse_input_event(joy_axis(4, JOY_AXIS_LEFT_Y, 0.0))
	Input.flush_buffered_events()
	rider.scrub = 0.7
	rider.release_controls()
	check(float(rider.packet().scrub) == 0.0, "control release clears stored scrub axis")
	rider.controller_active = false

func _rider_twist_visual_regressions(game: Node3D) -> void:
	var visual: Node3D = game.bike._rider_visual
	var center := Vector3(0.0, 0.54, 0.09)
	# The camera-only test translates just the frame while the world is paused.
	# Assemble its grips at the normal local stem for this anatomical bench;
	# restore the paused fixture afterward without a native simulation step.
	var original_fork: Transform3D = game.bike.fork.global_transform
	game.bike.fork.global_transform = game.bike.chassis.global_transform * Transform3D(Basis.IDENTITY, game.bike.HEAD)
	for target: float in [-0.45, 0.45]:
		for actual: float in [0.0, target]:
			visual.update_pose(0.0, 0.0, 0.0, 0.0, false, {
				"rider_transform": Transform3D(Basis(Vector3.UP, actual), center),
				"rider_reference_transform": Transform3D(Basis(Vector3.UP, target), center),
				"rider_yaw_target": target})
			check(absf(atan2(visual._head.basis.z.x, visual._head.basis.z.z) - actual) < 0.0001,
				"helmet follows actual hip yaw, without cancelling it or preceding physical motion")
			check(absf(atan2(visual._pelvis.basis.z.x, visual._pelvis.basis.z.z) - actual) < 0.0001,
				"pelvis visibly follows the physical hip twist")
			var anchored := true
			var natural_reach := true
			for index: int in range(2):
				var side := -1.0 if index == 0 else 1.0
				var grip: Vector3 = game.bike.chassis.global_transform.affine_inverse() * \
					(game.bike.fork.global_transform * Vector3(side * 0.355, 0.140, -0.025))
				anchored = anchored and visual._gloves[index].position.distance_to(grip) < 0.0001
				natural_reach = natural_reach and absf(visual._upper_arms[index].scale.y - 0.303) < 0.001 \
					and absf(visual._forearms[index].scale.y - 0.289) < 0.001
			check(anchored, "hip twist preserves both gloves on the actual fork grips")
			check(natural_reach, "physical hip twist keeps the rider's arms at anatomical length")
	visual.update_pose(0.0, 0.0, 0.0, 0.0, true, {"pose_reset": true,
		"rider_transform": Transform3D(Basis.IDENTITY, center),
		"rider_reference_transform": Transform3D(Basis.IDENTITY, center), "rider_yaw_target": 0.0})
	check(absf(visual._head.rotation.y) < 0.0001 and absf(visual._pelvis.rotation.y) < 0.0001,
		"neutral visual remount immediately clears physical hip twist")
	game.bike.fork.global_transform = original_fork
	game.bike._apply_rider_pose(true)

func _chase_input_regressions(game: Node3D) -> void:
	var body: RigidBody3D = game.bike.chassis
	var rider: RigidBody3D = game.bike.rider_body
	var fork: RigidBody3D = game.bike.fork
	var original_body: Transform3D = body.global_transform
	var original_rider: Transform3D = rider.global_transform
	var original_fork: Transform3D = fork.global_transform
	game.orbit_yaw = 0.0
	game.camera_snap = true
	game._update_camera(0.05)
	var original_yaw: float = game.camera_yaw
	var original_distance: float = game.orbit_distance
	game.rider_input.select_controller(4)
	game.rider_input.controller_bindings.reset_defaults()
	check(game.rider_input.command(joy_button(4, JOY_BUTTON_X)).is_empty()
		and game.rider_input.controller_bindings.action_for_event(joy_button(4, JOY_BUTTON_X), 4) == "scrub",
		"Xbox X is a held scrub input and cannot toggle feet")
	var legacy_feet_key := InputEventKey.new()
	legacy_feet_key.physical_keycode = KEY_F
	legacy_feet_key.pressed = true
	check(game.rider_input.command(legacy_feet_key).is_empty()
		and legacy_feet_key.is_action_pressed("mx_scrub"), "F is a held scrub input and cannot toggle feet")
	var target: Vector3 = body.global_position + Vector3.UP * 0.65
	var unobstructed: Transform3D = game.camera_target_transform()
	check(unobstructed.origin.distance_to(target) > 4.0, "chase ray fixture begins clear of terrain")
	# Send actual native events through the viewport while physics is paused.
	# Neither selected nor secondary riding sticks have a camera-look binding.
	for device: int in [4, 7]:
		for axis: int in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			for amount: float in [-1.0, 1.0, 0.0]:
				Input.parse_input_event(joy_axis(device, axis, amount))
				Input.flush_buffered_events()
				if device == 4:
					var pair: Array = {JOY_AXIS_LEFT_X: ["steer_left", "steer_right"],
						JOY_AXIS_RIGHT_X: ["body_left", "body_right"],
						JOY_AXIS_RIGHT_Y: ["body_back", "body_forward"]}.get(axis, [])
					if not pair.is_empty():
						var mapped: float = game.rider_input._controller_pair(pair[0], pair[1])
						check(is_equal_approx(mapped, -amount if axis == JOY_AXIS_RIGHT_Y else amount),
							"Xbox stick %d value %.1f reaches riding control" % [axis, amount])
			check(is_zero_approx(float(game.orbit_yaw)) and is_equal_approx(float(game.orbit_height), 1.9)
				and is_equal_approx(float(game.orbit_distance), original_distance)
				and game.camera_target_transform().is_equal_approx(unobstructed),
				"device %d stick %d never changes chase orbit" % [device, axis])
	# These are legitimate physical rider positions within its .26 m travel.
	# The old query hit this capsule and collapsed from 4.7 m to ~.16 m.
	for offset: Vector3 in [Vector3(0.0, 0.54, 0.20), Vector3(0.0, 0.54, 0.35),
			Vector3(0.10, 0.54, 0.30), Vector3(-0.10, 0.76, 0.30)]:
		rider.global_transform = Transform3D(body.global_basis, body.global_transform * offset)
		await physics_frame
		check(game.camera_target_transform().is_equal_approx(unobstructed),
			"moving physical rider %s cannot occlude chase camera" % str(offset))
	# Steering/fork articulation must also remain independent of chase heading.
	rider.global_transform = original_rider
	fork.global_basis = Basis(Vector3.UP, 0.45)
	await physics_frame
	game.camera_snap = true
	game._update_camera(0.05)
	check(is_equal_approx(float(game.camera_yaw), original_yaw)
		and game.camera_target_transform().is_equal_approx(unobstructed), "fork angle never supplies chase heading")
	check(body.global_transform.is_equal_approx(original_body), "camera/input fixtures never alter chassis pose")
	# World occlusion stays active: ignoring the bike must not disable walls.
	var wall := StaticBody3D.new()
	wall.name = "CameraOcclusionRegression"
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 0.25)
	collision.shape = shape
	wall.add_child(collision)
	game.add_child(wall)
	wall.global_position = target.lerp(unobstructed.origin, 0.5)
	await physics_frame
	check(game.camera_target_transform().origin.distance_to(target) < 3.0, "world wall still pulls chase camera clear of obstruction")
	wall.queue_free()
	await physics_frame
	check(game.camera_target_transform().is_equal_approx(unobstructed), "removing world wall restores chase distance")
	# Explicit mouse orbit remains available while a controller is selected.
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(40.0, 10.0)
	game._input(mouse)
	check(is_zero_approx(float(game.orbit_yaw)), "free mouse movement cannot orbit chase camera")
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_RIGHT
	drag.pressed = true
	game._input(drag)
	game._input(mouse)
	check(is_equal_approx(float(game.orbit_yaw), -0.16) and is_equal_approx(float(game.orbit_height), 2.0), "right mouse intentionally orbits with controller selected")
	drag.pressed = false
	game._input(drag)
	game._input(mouse)
	check(not game.camera_dragging and is_equal_approx(float(game.orbit_yaw), -0.16), "releasing right mouse stops further orbit")
	game.orbit_yaw = 0.0
	game.orbit_height = 1.9
	rider.global_transform = original_rider
	fork.global_transform = original_fork
	game.rider_input.select_controller(4)
	game._input(joy_button(4, JOY_BUTTON_B))
	check(game.camera_mode == "first_person", "selected camera button still switches to helmet view")
	game._input(joy_button(7, JOY_BUTTON_B))
	check(game.camera_mode == "first_person", "secondary controller cannot switch camera")
	game._input(joy_button(4, JOY_BUTTON_B))
	check(game.camera_mode == "third_person", "selected camera button switches back to chase view")
