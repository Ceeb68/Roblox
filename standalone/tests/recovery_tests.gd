extends SceneTree
## Main-scene recovery checks use the real Jolt bodies and crash detector.
## The only fixture pose changes happen before each induced native fall.

const HZ: float = 240.0
const PAD_ORIGIN := Vector3(0.0, 0.0, 250.0)
var game: Node3D
var failures: Array[String] = []
var checks: int = 0
var saved_files: Dictionary = {}
var neutral_pelvis := Vector3.ZERO
var neutral_head_rotation := Vector3.ZERO
var neutral_frame_com := Vector3.ZERO
var neutral_frame_inertia := Vector3.ZERO
var neutral_rider_inertia := Vector3.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		var message := label + (": " + detail if not detail.is_empty() else "")
		failures.append(message)
		push_error("RECOVERY FAIL: " + message)

func _tick() -> void:
	await physics_frame
	await process_frame

func _ticks(count: int) -> void:
	for _frame: int in range(count):
		await _tick()

func _release_actions() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("mx_"):
			Input.action_release(action)

func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	return event

func _button(device: int, index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = true
	return event

func _add_pad() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "RecoveryNativeHardpack"
	floor_body.position = PAD_ORIGIN + Vector3(0.0, -0.15, 0.0)
	floor_body.set_meta("physics_surface", "hardpack")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	floor_body.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30.0, 0.3, 40.0)
	collision.shape = shape
	floor_body.add_child(collision)
	game.add_child(floor_body)

func _place_fall_fixture(offset: Vector3 = Vector3.ZERO) -> void:
	# All five bodies begin in a physically plausible tilted assembly, then
	# the native solver determines whether, when and how it falls and crashes.
	var spawn := Transform3D(Basis(Vector3.FORWARD, deg_to_rad(76.0)),
		PAD_ORIGIN + offset + Vector3(0.0, 0.80, 0.0))
	var bodies: Array[RigidBody3D] = [game.bike.chassis, game.bike.fork,
		game.bike.front_wheel, game.bike.rear_wheel, game.bike.rider_body]
	var positions: Array[Vector3] = [Vector3.ZERO, game.bike.HEAD,
		game.bike.FRONT_AXLE, game.bike.REAR_AXLE, Vector3(0.0, 0.54, 0.09)]
	for index: int in range(bodies.size()):
		bodies[index].global_transform = spawn * Transform3D(Basis.IDENTITY, positions[index])
		bodies[index].linear_velocity = Vector3(0.4, -0.8, 0.1)
		bodies[index].angular_velocity = Vector3(0.0, 0.0, -0.4)
	game.rider_input.foot_down = false
	game.bike.set_controls(game.rider_input.packet())

func _wait_for_crash() -> bool:
	for _frame: int in range(360):
		await _tick()
		if bool(game.bike.get_telemetry().get("crashed", false)):
			return true
	return false

func _assert_reset(label: String, just_integrated: bool = false) -> void:
	var telemetry: Dictionary = game.bike.get_telemetry()
	var bodies: Array[RigidBody3D] = [game.bike.chassis, game.bike.fork,
		game.bike.front_wheel, game.bike.rear_wheel, game.bike.rider_body]
	var upright := true
	var stationary := true
	for body: RigidBody3D in bodies:
		upright = upright and body.global_basis.y.dot(Vector3.UP) > 0.999
		var velocity_tolerance := 0.12 if just_integrated else 0.001
		stationary = stationary and body.linear_velocity.length() < velocity_tolerance and body.angular_velocity.length() < velocity_tolerance
	_check(upright and stationary, label + " restores every native body upright and stationary")
	_check(not bool(telemetry.get("crashed", true)) and int(telemetry.get("gear", -1)) == 0
		and not bool(telemetry.get("stalled", true)) and float(telemetry.get("rpm", 0.0)) > 2100.0,
		label + " clears crash and restarts in neutral at idle")
	_check(game.rider_input.foot_down and not game.rider_input.standing
		and is_equal_approx(float(game.rider_input.clutch), 1.0),
		label + " remounts seated with both feet down and clutch pulled")
	var rider_collision: CollisionShape3D = game.bike._rider_collision
	var rider_body: RigidBody3D = game.bike.rider_body
	_check(rider_collision.get_parent() == rider_body and rider_collision.position.length() < 0.0001
		and rider_collision.rotation.length() < 0.0001,
		label + " immediately restores the physical rider capsule")
	_check(game.bike.chassis.center_of_mass.distance_to(neutral_frame_com) < 0.0001
		and game.bike.chassis.to_local(rider_body.global_position).distance_to(Vector3(0.0, 0.54, 0.09)) < 0.001,
		label + " immediately restores the real rider COM and fixed frame COM")
	_check(game.bike.chassis.inertia.distance_to(neutral_frame_inertia) < 0.0001
		and rider_body.inertia.distance_to(neutral_rider_inertia) < 0.0001,
		label + " preserves separate frame and rider inertias")
	var rider_visual: Node3D = game.bike._rider_visual
	_check(rider_visual._pelvis.position.distance_to(neutral_pelvis) < 0.0001
		and rider_visual._head.rotation.distance_to(neutral_head_rotation) < 0.0001,
		label + " immediately restores the seated visible rider")
	_check(absf(float(game.bike._body_forward)) + absf(float(game.bike._body_side))
		+ absf(float(game.bike._body_lean)) + absf(float(game.bike._standing))
		+ absf(float(game.bike._body_twist)) + absf(float(game.bike._rider_yaw_rate))
		+ absf(float(game.bike._rider_pitch_rate)) + absf(float(game.bike._rider_roll_rate)) < 0.0001,
		label + " removes old posture and articulation momentum")
	_check(absf(float(game.bike._rider_target_lean)) + absf(float(game.bike._steering_target))
		+ absf(float(game.bike._heading_correction)) + absf(float(game.bike._steering_integral)) < 0.0001
		and not game.bike._line_capture_pending and not game.bike._line_from_player_turn
		and absf(float(game.bike._line_settle_time)) < 0.0001
		and not game.bike._landing_line_pending and not game.bike._landing_line_active
		and absf(float(game.bike._landing_line_elapsed)) < 0.0001,
		label + " removes old cornering and steering state")
	_check(not game.lap_active and game.next_gate == 0,
		label + " clears the interrupted lap and checkpoint progress")

func _wait_for_recovery() -> float:
	for _frame: int in range(300):
		var previous_age: float = float(game.bike._crash_elapsed)
		await _tick()
		if not bool(game.bike.get_telemetry().get("crashed", true)):
			return previous_age + 1.0 / HZ
	return -1.0

func _test_manual(label: String, controller: bool = false) -> void:
	game.rider_input.controller_active = false
	game.rider_input.standing = true
	game.lap_active = true
	game.lap_elapsed = 4.0
	game.next_gate = 2
	Input.action_press("mx_body_forward")
	Input.action_press("mx_body_right")
	Input.action_press("mx_lean_right")
	await _ticks(70)
	_place_fall_fixture(Vector3(2.0, 0.0, 1.0))
	var induced: bool = await _wait_for_crash()
	_check(induced, label + " fixture produces a genuine native crash")
	if not induced:
		return
	await _ticks(8)
	_check(float(game.bike._crash_elapsed) < 0.2, label + " is requested well before the automatic timer")
	var before_count: int = int(game.recovery_count)
	if controller:
		game.rider_input.select_controller(4)
		game._input(_button(4, JOY_BUTTON_BACK))
	else:
		game._input(_key(KEY_R))
	_check(int(game.recovery_count) == before_count + 1 and game.last_recovery_kind == "manual",
		label + " dispatches one immediate successful manual recovery")
	_assert_reset(label)
	_release_actions()
	await _ticks(120)
	_check(not bool(game.bike.get_telemetry().crashed) and game.bike.chassis.global_basis.y.dot(Vector3.UP) > 0.98,
		label + " leaves a natively supported upright remount")

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	for path: String in ["user://preferences.cfg", "user://controller_bindings.cfg"]:
		if FileAccess.file_exists(path):
			saved_files[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	game = scene.instantiate() as Node3D
	root.add_child(game)
	await process_frame
	# Capture a pristine neutral remount before the tests create shifted poses.
	# Recovery must restore this pose, independent of cosmetic mesh dimensions.
	game.bike.reset_bike(game.track.spawn, true)
	neutral_pelvis = game.bike._rider_visual._pelvis.position
	neutral_head_rotation = game.bike._rider_visual._head.rotation
	neutral_frame_com = game.bike.chassis.center_of_mass
	neutral_frame_inertia = game.bike.chassis.inertia
	neutral_rider_inertia = game.bike.rider_body.inertia
	_add_pad()
	game.start_session()
	game.bike.reset_bike(Transform3D(Basis.IDENTITY, PAD_ORIGIN + Vector3(0.0, 0.82, 0.0)))
	await _ticks(120)
	game.set_camera_mode("first_person", false)
	game.rider_input.controller_bindings.assign("recover", {"kind": "button", "index": JOY_BUTTON_BACK, "direction": 1}, true)
	var preserved_bindings: Dictionary = game.rider_input.controller_bindings.bindings.duplicate(true)
	game.rider_input.standing = true
	Input.action_press("mx_body_forward")
	Input.action_press("mx_body_right")
	Input.action_press("mx_lean_right")
	Input.action_press("mx_throttle")
	await _ticks(90)
	_check(float(game.bike._standing) > 0.4 and absf(float(game.bike._body_forward)) > 0.4,
		"Crash fixture starts with a live standing, shifted rider pose")
	game.lap_active = true
	game.lap_elapsed = 3.0
	_place_fall_fixture()
	var induced: bool = await _wait_for_crash()
	_check(induced, "Tilted assembly produces a real native-contact crash")
	if not induced:
		await _finish()
		return
	print("RECOVERY native crash: ", game.bike.get_telemetry().crashReason)
	await _tick() # Game observes the native crash on its following physics callback.
	_check(not game.lap_active, "Actual crash invalidates the current lap")
	var crash_origin: Vector3 = game.bike.chassis.global_position
	var initial_count: int = int(game.recovery_count)
	await _ticks(100)
	_check(bool(game.bike.get_telemetry().crashed) and int(game.recovery_count) == initial_count,
		"Automatic recovery does not right the motorcycle before one second")
	var paused_age: float = float(game.bike._crash_elapsed)
	var paused_pose: Transform3D = game.bike.chassis.global_transform
	game._show_modal("help")
	await _ticks(160)
	_check(paused and is_equal_approx(float(game.bike._crash_elapsed), paused_age)
		and game.bike.chassis.global_transform.is_equal_approx(paused_pose)
		and int(game.recovery_count) == initial_count,
		"Paused controls screen freezes crash timing and native pose")
	game._resume()
	var age_at_recovery: float = await _wait_for_recovery()
	_check(age_at_recovery >= 1.0 - 1.0 / HZ and age_at_recovery <= 1.0 + 3.0 / HZ,
		"Automatic recovery occurs at one second of unpaused crash physics", "%.6f s" % age_at_recovery)
	_check(int(game.recovery_count) == initial_count + 1 and game.last_recovery_kind == "automatic",
		"Automatic recovery runs exactly once for this crash")
	_assert_reset("Automatic recovery", true)
	_check(Vector2(game.bike.chassis.global_position.x, game.bike.chassis.global_position.z).distance_to(
		Vector2(crash_origin.x, crash_origin.z)) < 4.0
		and absf(game.bike.chassis.global_position.y - 0.82) < 0.2,
		"Automatic recovery uses nearby verified terrain instead of teleporting to START")
	_check(game.camera_mode == "first_person" and game.rider_input.controller_bindings.bindings == preserved_bindings,
		"Automatic recovery preserves camera mode and custom controller mapping")
	await _ticks(100)
	_check(float(game.rider_input.throttle) == 0.0 and float(game.rider_input.lean) == 0.0
		and float(game.rider_input.body_forward) == 0.0 and float(game.rider_input.body_side) == 0.0,
		"Controls held through a crash remain neutral until released")
	_check(not bool(game.bike.get_telemetry().crashed) and int(game.recovery_count) == initial_count + 1,
		"Held crash inputs do not immediately crash or repeatedly reset the remount")
	# Release only one held control: new inputs for it should work without
	# requiring every other held action to be released first.
	Input.action_release("mx_body_right")
	await _ticks(3)
	Input.action_press("mx_body_right")
	await _ticks(24)
	_check(float(game.rider_input.body_side) > 0.2 and float(game.rider_input.throttle) == 0.0
		and float(game.rider_input.lean) == 0.0,
		"Releasing and pressing one action re-arms it independently of other held controls")
	_release_actions()
	await _ticks(360)
	_check(not bool(game.bike.get_telemetry().crashed) and int(game.recovery_count) == initial_count + 1
		and game.bike.chassis.global_basis.y.dot(Vector3.UP) > 0.98
		and game.bike.chassis.linear_velocity.length() < 0.3,
		"Automatic remount stays upright and stationary for two further native seconds")
	await _test_manual("Keyboard R")
	await _test_manual("Remapped controller recovery", true)
	_check(game.camera_mode == "first_person" and game.rider_input.controller_bindings.bindings == preserved_bindings,
		"Manual recovery preserves camera mode and custom controller mapping")
	game.rider_input.controller_active = false
	game.bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(600.0, 3.0, 600.0)), true)
	var fallback_count: int = int(game.recovery_count)
	# Corrupt the fallback data rather than mocking the bike reset. The real
	# helper must propagate the real reset failure with no rider/UI side effects.
	var expected_spawn: Transform3D = game.track.spawn
	game.track.spawn = Transform3D(Basis.IDENTITY, Vector3(INF, 0.0, 0.0))
	game.rider_input.standing = true
	game.rider_input.foot_down = false
	game.rider_input.throttle = 0.4
	game.lap_active = true
	game.next_gate = 3
	var failure_packet: Dictionary = game.rider_input.packet().duplicate(true)
	var failure_pose: Transform3D = game.bike.chassis.global_transform
	var failed_helper: bool = not bool(game._recover())
	_check(failed_helper and game.rider_input.packet() == failure_packet
		and game.bike.chassis.global_transform.is_equal_approx(failure_pose)
		and int(game.recovery_count) == fallback_count and game.lap_active and game.next_gate == 3,
		"Game recovery propagates a genuine reset failure without partial rider or lap mutation")
	game.track.spawn = expected_spawn
	var fallback_ok: bool = bool(game._recover())
	_check(fallback_ok and int(game.recovery_count) == fallback_count + 1
		and game.bike.chassis.global_position.distance_to(expected_spawn.origin) < 0.001,
		"Missing terrain falls back to the validated starting spawn")
	_assert_reset("Missing-terrain recovery")
	# A malformed caller pose must be rejected before any reset side effect.
	var before_pose: Transform3D = game.bike.chassis.global_transform
	var before_com: Vector3 = game.bike.chassis.center_of_mass
	var before_controls: Dictionary = game.bike.controls.duplicate(true)
	var invalid_pose := Transform3D(Basis.IDENTITY, Vector3(INF, 0.0, 0.0))
	var rejected: bool = not bool(game.bike.reset_bike(invalid_pose, true))
	_check(rejected and game.bike.chassis.global_transform.is_equal_approx(before_pose)
		and game.bike.chassis.center_of_mass.is_equal_approx(before_com)
		and game.bike.controls == before_controls,
		"Failed malformed-pose reset returns false without partial native or rider mutation")
	# A later independent native fall must arm the automatic timer again.
	# Consume the preceding remount's queued native-body integration first;
	# it must not overwrite this scenario's deliberately tilted start pose.
	await _ticks(2)
	game.rider_input.controller_active = false
	_place_fall_fixture(Vector3(-3.0, 0.0, -1.0))
	induced = await _wait_for_crash()
	_check(induced, "A later fall independently produces another native crash")
	if induced:
		var repeated_count: int = int(game.recovery_count)
		age_at_recovery = await _wait_for_recovery()
		_check(age_at_recovery >= 1.0 - 1.0 / HZ and age_at_recovery <= 1.0 + 3.0 / HZ
			and int(game.recovery_count) == repeated_count + 1,
			"A later crash receives its own one-second automatic recovery")
	await _finish()

func _finish() -> void:
	_release_actions()
	paused = false
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	for path: String in ["user://preferences.cfg", "user://controller_bindings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if saved_files.has(path):
			var restored := FileAccess.open(path, FileAccess.WRITE)
			restored.store_buffer(saved_files[path])
	print("Recovery native checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
