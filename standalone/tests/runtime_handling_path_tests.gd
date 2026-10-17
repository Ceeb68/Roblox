extends SceneTree
## End-to-end parameter A/B/A through the real main scene, keyboard polling,
## parked handling menu, finite handlebars and native tire forces. No riding
## motorcycle control packets, velocities or orientations are injected by this fixture.
## Only the ordinary from-rest reset starts each repeat at the same location.
const HZ := 240
const SPAWN := Vector3(0.0, 0.82, -500.0)
const USER_FILES: Array[String] = ["user://preferences.cfg", "user://controller_bindings.cfg", "user://handling.cfg"]
const Tire = preload("res://physics/tire.gd")

class PostStepObserver:
	extends Node
	signal completed
	func _physics_process(_dt: float) -> void:
		completed.emit()

var game: Node3D
var poststep: Node
var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var saved_files: Dictionary = {}
var original_config: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + detail if not detail.is_empty() else ""))
		push_error("RUNTIME HANDLING PATH FAIL: " + failures[-1])

func _release_actions() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("mx_"):
			Input.action_release(action)

func _key(keycode: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)

func _heading() -> float:
	var forward: Vector3 = -game.bike.chassis.global_basis.z
	return atan2(forward.x, -forward.z)

func _effective_configuration(config: Dictionary) -> Dictionary:
	# The real menu materializes per-axleGripScale=1 that startup inherits
	# from the shared tire. Compare the resolved physical coefficients rather
	# than treating that equivalent representation as an un-restored change.
	var resolved := config.duplicate(true)
	resolved.Tire.Front = Tire.axle_settings(config.Tire, "Front")
	resolved.Tire.Rear = Tire.axle_settings(config.Tire, "Rear")
	return resolved

func _same_coefficients(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		# SpinBox decimal steps may differ by machine-rounding bits. This is
		# far below a supported tuning step, not a riding acceptance tolerance.
		return absf(float(a) - float(b)) <= 0.000000001 * maxf(1.0, maxf(absf(float(a)), absf(float(b))))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same_coefficients(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _same_coefficients(a[i], b[i]):
				return false
		return true
	return a == b

func _add_native_pad() -> void:
	var body := StaticBody3D.new()
	body.name = "RuntimeHandlingPathNativeHardpack"
	body.position = Vector3(0.0, -0.15, -650.0)
	body.set_meta("physics_surface", "hardpack")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	body.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 0.3, 1000.0)
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)

func _prepare() -> void:
	_release_actions()
	game.bike.reset_bike(Transform3D(Basis.IDENTITY, SPAWN), true)
	game.rider_input.reset_for_recovery()
	game.was_crashed = false
	game.start_session()
	for _i in range(HZ):
		await poststep.completed
	_check(game._handling_available(), "Actual main scene reaches a parked state eligible for handling changes")

func _apply_through_menu(sensitivity: float) -> void:
	game._open_handling_setup()
	_check(game.modal_kind == "handling", "The real parked handling menu opens")
	(game.handling_fields["VirtualRider.SteeringSensitivity"] as SpinBox).value = sensitivity
	game._apply_handling()
	_check(game.modal_kind.is_empty() and is_equal_approx(float(game.bike.config.VirtualRider.SteeringSensitivity), sensitivity),
		"Apply and ride reaches the active bike configuration", str(game.bike.config.VirtualRider.SteeringSensitivity))
	var saved := ConfigFile.new()
	var status := saved.load("user://handling.cfg")
	var values: Dictionary = saved.get_value("handling", "values", {}) if status == OK else {}
	_check(status == OK and is_equal_approx(float(values.get("VirtualRider", {}).get("SteeringSensitivity", -1.0)), sensitivity),
		"The real menu persists the temporary setting in this isolated runtime")

func _ride(label: String, sensitivity: float) -> Dictionary:
	await _prepare()
	_apply_through_menu(sensitivity)
	var configuration: Dictionary = game.bike.config.duplicate(true)
	var start: Vector3 = game.bike.chassis.global_position
	var initial_heading := _heading()
	var recoveries: int = game.recovery_count
	_key(KEY_E)
	await poststep.completed
	_check(int(game.bike.get_telemetry().gear) == 1, label + " selects first through the actual keyboard event dispatcher")
	var start_frame := Engine.get_physics_frames()
	Input.action_press("mx_throttle")
	Input.action_press("mx_clutch_release")
	var max_speed := 0.0
	var peak_bank := 0.0
	var peak_target := 0.0
	var peak_bar_torque := 0.0
	var peak_front_force := 0.0
	var peak_rear_force := 0.0
	var peak_steer_input := 0.0
	var mean_bank := 0.0
	var mean_target := 0.0
	var mean_front_force := 0.0
	var mean_steer_angle := 0.0
	var mean_samples := 0
	var loaded_turn_samples := 0
	var crash_seen := false
	var samples: Array[Dictionary] = []
	for i in range(HZ * 9):
		if i == roundi(5.6 * HZ):
			Input.action_release("mx_throttle")
			Input.action_release("mx_clutch_release")
			Input.action_press("mx_clutch_quick")
		if i == HZ * 6:
			Input.action_press("mx_steer_right")
		if i == roundi(7.5 * HZ):
			Input.action_release("mx_steer_right")
		await poststep.completed
		var t: Dictionary = game.bike.get_telemetry()
		var time := float(i + 1) / HZ
		max_speed = maxf(max_speed, float(t.speedMps))
		crash_seen = crash_seen or bool(t.crashed)
		if time >= 6.0 and time <= 7.5:
			peak_bank = maxf(peak_bank, float(t.roll))
			peak_target = maxf(peak_target, float(t.riderTargetLean))
			peak_bar_torque = maxf(peak_bar_torque, absf(float(t.riderSteeringTorque)))
			peak_front_force = maxf(peak_front_force, absf(float(t.frontLateralForce)))
			peak_rear_force = maxf(peak_rear_force, absf(float(t.rearLateralForce)))
			peak_steer_input = maxf(peak_steer_input, float(game.bike.applied_controls.steer))
			loaded_turn_samples += int(float(t.frontLoad) > 100.0 and float(t.rearLoad) > 100.0)
		if time >= 6.7 and time <= 7.4:
			mean_bank += float(t.roll)
			mean_target += float(t.riderTargetLean)
			mean_front_force += absf(float(t.frontLateralForce))
			mean_steer_angle += absf(float(t.steerAngle))
			mean_samples += 1
		if i % 12 == 0:
			samples.append({"time": time, "position": str(game.bike.chassis.global_position),
				"speedMps": t.speedMps, "gear": t.gear, "rpm": t.rpm, "stalled": t.stalled, "bankDegrees": rad_to_deg(float(t.roll)),
				"targetBankDegrees": rad_to_deg(float(t.riderTargetLean)), "headingDegrees": rad_to_deg(wrapf(_heading() - initial_heading, -PI, PI)),
				"nativeSteerDegrees": rad_to_deg(float(t.steerAngle)), "pairedBarTorqueNm": t.riderSteeringTorque,
				"frontLateralForceN": t.frontLateralForce, "rearLateralForceN": t.rearLateralForce,
				"frontLoadN": t.frontLoad, "rearLoadN": t.rearLoad, "appliedControls": game.bike.applied_controls.duplicate()})
	var displacement: Vector3 = game.bike.chassis.global_position - start
	var result := {"label": label, "sensitivity": sensitivity, "configurationHash": JSON.stringify(configuration).sha256_text(),
		"runtimeReceipt": game.get_runtime_receipt() if game.has_method("get_runtime_receipt") else {},
		"physicsFrames": Engine.get_physics_frames() - start_frame, "maxSpeedMps": max_speed,
		"peakBankDegrees": rad_to_deg(peak_bank), "peakTargetDegrees": rad_to_deg(peak_target),
		"meanBankDegrees": rad_to_deg(mean_bank / maxi(mean_samples, 1)),
		"meanTargetDegrees": rad_to_deg(mean_target / maxi(mean_samples, 1)),
		"peakPairedBarTorqueNm": peak_bar_torque, "peakFrontLateralForceN": peak_front_force, "peakRearLateralForceN": peak_rear_force,
		"meanFrontLateralForceN": mean_front_force / maxi(mean_samples, 1), "meanNativeSteerDegrees": rad_to_deg(mean_steer_angle / maxi(mean_samples, 1)),
		"appliedSteerPeak": peak_steer_input, "loadedTurnSamples": loaded_turn_samples,
		"finalHeadingDegrees": rad_to_deg(wrapf(_heading() - initial_heading, -PI, PI)),
		"lateralTravelM": displacement.x, "forwardTravelM": -displacement.z,
		"crashSeen": crash_seen, "recoveries": game.recovery_count - recoveries, "samples": samples}
	_check(int(result.physicsFrames) == HZ * 9, label + " observes exactly2160 completed native main-scene updates")
	_check(not crash_seen and int(result.recoveries) == 0, label + " rides the comparison without crash or automatic recovery")
	_check(max_speed > 8.0 and float(result.forwardTravelM) > 30.0 and peak_steer_input > 0.99,
		label + " actual throttle/clutch/steering inputs produce useful native movement")
	_check(loaded_turn_samples > HZ and peak_bar_torque > 10.0 and peak_front_force > 100.0 and peak_rear_force > 100.0,
		label + " real paired handlebars and independent loaded tire forces generate the corner")
	var printable := result.duplicate()
	printable.erase("samples")
	print("RUNTIME HANDLING PATH ", JSON.stringify(printable))
	cases.append(result)
	_release_actions()
	return result

func _run() -> void:
	Engine.physics_ticks_per_second = HZ
	for path: String in USER_FILES:
		if FileAccess.file_exists(path):
			saved_files[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	poststep = PostStepObserver.new()
	poststep.process_physics_priority = 10
	poststep.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(poststep)
	await process_frame
	await process_frame
	_add_native_pad()
	original_config = game.bike.config.duplicate(true)
	_check(game.get_script().resource_path == "res://scripts/game.gd" and game.bike.get_script().resource_path == "res://scripts/bike_controller.gd",
		"The actual main scene loads the shipped game and motorcycle controller")
	_check(game.bike.riding_mode == "virtual_rider", "The actual main scene uses virtual-rider lean control")
	await _prepare()
	var before_zero: Dictionary = game.bike.config.duplicate(true)
	_check(not game.bike.apply_handling_setup({"VirtualRider": {"SteeringSensitivity": 0.0}}) and game.bike.config == before_zero,
		"A zero sensitivity is safely rejected by the real parked parameter allowlist without changing the bike")
	_apply_through_menu(1.0)
	_check(_same_coefficients(_effective_configuration(original_config), _effective_configuration(game.bike.config)),
		"Initial menu application only materializes equivalent inherited tire defaults")
	var baseline := await _ride("baseline", 1.0)
	var changed := await _ride("temporary-half-sensitivity", 0.5)
	var restored := await _ride("restored", 1.0)
	_check(float(baseline.meanTargetDegrees) - float(changed.meanTargetDegrees) > 8.0,
		"The temporary menu setting materially changes the active physical lean request")
	_check(float(baseline.meanBankDegrees) - float(changed.meanBankDegrees) > 6.0,
		"The active native motorcycle follows a materially different bank under the same keyboard input")
	var trajectory_change := Vector2(float(baseline.lateralTravelM) - float(changed.lateralTravelM),
		float(baseline.forwardTravelM) - float(changed.forwardTravelM)).length()
	_check(absf(float(baseline.finalHeadingDegrees) - float(changed.finalHeadingDegrees)) > 8.0 and trajectory_change > 2.0,
		"The active main-scene trajectory visibly changes, beyond a cosmetic target or HUD value")
	_check(baseline.configurationHash == restored.configurationHash,
		"Restoring the menu value restores the complete effective bike configuration")
	_check(absf(float(baseline.meanBankDegrees) - float(restored.meanBankDegrees)) < 1.0 \
		and absf(float(baseline.finalHeadingDegrees) - float(restored.finalHeadingDegrees)) < 2.0,
		"Restoring the setting restores repeatable native bank and turning behavior")
	await _prepare()
	_apply_through_menu(1.0)
	_check(_same_coefficients(_effective_configuration(game.bike.config), _effective_configuration(original_config)),
		"The temporary experiment leaves every original effective physical coefficient restored")
	var report := {"checks": checks, "failures": failures, "cases": cases,
		"originalConfiguration": original_config, "restoredConfiguration": game.bike.config,
		"gameScript": game.get_script().resource_path, "bikeScript": game.bike.get_script().resource_path,
		"controllerHash": game.bike.get_script().get_source_code().sha256_text(),
		"gameHash": game.get_script().get_source_code().sha256_text(),
		"sourceConfigHash": FileAccess.get_file_as_string("res://config/bike_250f.json").sha256_text(),
		"restoredConfigurationHash": JSON.stringify(game.bike.config).sha256_text()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var output := FileAccess.open("res://build/runtime-handling-path-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	_release_actions()
	game.queue_free()
	poststep.queue_free()
	await process_frame
	paused = false
	for path: String in USER_FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if saved_files.has(path):
			var restore := FileAccess.open(path, FileAccess.WRITE)
			restore.store_buffer(saved_files[path])
			restore.close()
	print("Runtime handling path: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
