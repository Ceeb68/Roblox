extends SceneTree
## Round-trip completed-physics-frame data through the real CSV writer/reader.
## No GUI layout snapshots and no substituted physics or input calculations.
const Recorder = preload("res://scripts/telemetry_recorder.gd")
const Bike = preload("res://scripts/bike_controller.gd")

class CrashFrameProbe:
	extends Bike
	var crash_at_step_end := false
	var observed_drive_packet: Dictionary = {}
	func _apply_drivetrain(input: Dictionary, dt: float) -> void:
		observed_drive_packet = input.duplicate()
		super._apply_drivetrain(input, dt)
	func _detect_crash(dt: float) -> void:
		super._detect_crash(dt)
		if crash_at_step_end:
			crash_at_step_end = false
			# Exercise the real crash transition at its normal end-of-update
			# phase. Crash severity/contact geometry has its own native suite.
			_crash("Telemetry completed-step crash probe")

class PostStepObserver:
	extends Node
	signal completed
	func _physics_process(_dt: float) -> void:
		completed.emit()

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("TELEMETRY FAIL: " + label)

func _as_map(fields: PackedStringArray, row: PackedStringArray) -> Dictionary:
	var values := {}
	for index in range(mini(fields.size(), row.size())):
		values[fields[index]] = row[index]
	return values

func _run() -> void:
	var path := "user://telemetry-tests/roundtrip-%d.csv" % OS.get_process_id()
	var absolute := ProjectSettings.globalize_path(path)
	var recorder := Recorder.new()
	check(not recorder.active() and not recorder.capture(1, 0.1, {}, {}), "Inactive capture does not create a recording")
	check(recorder.start(path) == OK and recorder.active(), "Recording creates its output directory and file")
	check(recorder.start(path) == ERR_ALREADY_IN_USE and recorder.active(), "Starting twice preserves an active session")
	var reason := "Front washout, rider says \"recover\""
	var observation := {"speedMps": 14.125, "groundSpeedMps": 13.5, "roll": -0.25,
		"frontContact": true, "rearContact": false, "frontLoad": 1234.56789, "rearLoad": 0.0,
		"frontSlip": -0.02, "frontSlipAngle": 0.08, "frontCompression": 0.19,
		"frontLongitudinalForce": 321.25, "frontLateralForce": -216.5, "frontCapacityX": 950.0,
		"pitchRate": -0.6, "yawRate": 0.2, "rollRate": 1.4,
		"groundAssistTorque": Vector3(1.25, -2.5, 3.75),
		"airAssistTorque": Vector3.ZERO, "riderPostureTorque": Vector3(-5, 4, -3),
		"frontSurface": "sand", "crashed": false, "crashReason": reason,
		"crashObservation": {"supportBank": -0.1, "supportPitch": 0.2, "loadedSupport": true,
			"impactSpeed": 6.2, "landingTilt": 0.3, "sideSpeed": 1.4}}
	var controls := {"throttle": 0.72, "frontBrake": 0.3, "rearBrake": 0.1, "clutch": 0.25,
		"steer": -0.4, "bodySide": 0.8, "standing": true, "footDown": false}
	check(recorder.capture(241, 0.1, observation, controls), "A complete actual-value snapshot writes successfully")
	observation.crashed = true
	observation.crashReason = "Landing impact"
	check(recorder.capture(242, 0.2, observation, controls), "Crash observations flush without ending the recording")
	check(recorder.rows == 2, "One capture writes one physics frame")
	check(recorder.stop() == absolute and not recorder.active(), "Stopping closes and returns the concrete CSV path")
	var file := FileAccess.open(path, FileAccess.READ)
	var fields := file.get_csv_line()
	var first_row := file.get_csv_line()
	var second_row := file.get_csv_line()
	check(fields == Recorder.header() and first_row.size() == fields.size() and second_row.size() == fields.size(),
		"CSV header and every frame retain the complete stable unit-labelled schema")
	var first := _as_map(fields, first_row)
	var second := _as_map(fields, second_row)
	check(first.physics_frame == "241" and second.physics_frame == "242" and is_equal_approx(float(second.time_s), 0.3),
		"Native frame identity and elapsed simulation time round-trip independently of render frames")
	check(is_equal_approx(float(first.physics_dt_s), 0.1) and is_equal_approx(float(second.physics_dt_s), 0.2),
		"Recorded timestep preserves variable-step observations")
	check(is_equal_approx(float(first.front_load_n), 1234.56789) and is_equal_approx(float(first.front_lateral_force_n), -216.5)
		and is_equal_approx(float(first.front_longitudinal_capacity_n), 950.0), "Actual load, signed force and independent capacity values survive CSV")
	check(is_equal_approx(float(first.pitch_rate_radps), -0.6) and is_equal_approx(float(first.roll_rate_radps), 1.4)
		and is_equal_approx(float(first.ground_assist_nm_y), -2.5), "Local angular rates and world torque components preserve sign and units")
	check(first.front_contact == "1" and first.rear_contact == "0" and first.input_standing == "1"
		and first.input_foot_down == "0" and second.crashed == "1", "Contact, posture and crash flags round-trip unambiguously")
	check(is_equal_approx(float(first.input_steer), -0.4) and is_equal_approx(float(first.input_throttle), 0.72)
		and is_equal_approx(float(first.input_clutch), 0.25), "Applied input samples remain associated with their completed frame")
	check(first.crash_reason == reason and first.front_surface == "sand" and second.crash_reason == "Landing impact",
		"CSV escapes commas and quoted crash text and preserves surface identity")
	check(is_equal_approx(float(first.support_bank_rad), -0.1) and is_equal_approx(float(first.support_pitch_rad), 0.2)
		and first.loaded_support == "1" and is_equal_approx(float(first.last_landing_impact_mps), 6.2)
		and is_equal_approx(float(first.last_landing_tilt_rad), 0.3) and is_equal_approx(float(first.last_landing_side_mps), 1.4),
		"Terrain-relative crash balance, impact, sideways speed and landing tilt survive recording")
	file.close()
	check(not recorder.capture(243, 0.1, {}, {}), "Stopped capture cannot append to a closed file")
	check(recorder.start(path) == OK and recorder.rows == 0, "A new recording resets its frame count")
	recorder.capture(1000, 0.01, {}, {})
	recorder.stop()
	file = FileAccess.open(path, FileAccess.READ)
	fields = file.get_csv_line()
	var restarted := _as_map(fields, file.get_csv_line())
	check(restarted.physics_frame == "1000" and is_equal_approx(float(restarted.time_s), 0.01)
		and is_equal_approx(float(restarted.input_clutch), 1.0) and restarted.input_foot_down == "1", "Restart resets simulation time and uses safe missing-field defaults")
	check(restarted.last_landing_impact_mps.is_empty() and restarted.last_landing_tilt_rad.is_empty(),
		"Absent landing observations remain empty rather than fabricating zero-impact landings")
	file.close()
	DirAccess.remove_absolute(absolute)
	await _main_game_capture()
	await _crash_step_capture()
	print("Physics telemetry recorder: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _debug_key(game: Node3D, key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	game._input(event)

func _main_game_capture() -> void:
	var game: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var poststep := PostStepObserver.new()
	poststep.process_physics_priority = 10
	poststep.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(poststep)
	await process_frame
	await process_frame
	game.start_session()
	check(not game.physics_panel.visible and not game.physics_recorder.active(), "Live main game starts with diagnostics and recording disabled")
	game.rider_input.controller_active = true
	_debug_key(game, KEY_F8)
	check(game.physics_panel.visible and game.rider_input.controller_active, "Telemetry key preserves selected controller input ownership")
	game.rider_input.controller_active = false
	for _i in range(240):
		await poststep.completed
	_debug_key(game, KEY_F9)
	check(game.physics_recorder.active(), "The actual game's F9 dispatcher starts a real CSV recording")
	var path: String = game.physics_recorder.path
	for _i in range(32):
		await poststep.completed
	# Stop in the32nd completed native node callback, without another render
	# boundary advancing an extra physics update before this observation.
	_debug_key(game, KEY_F9)
	check(not game.physics_recorder.active() and str(game.get("notification")).contains(path), "The actual F9 stop closes the file and tells the player its path")
	var csv := FileAccess.open(path, FileAccess.READ)
	var fields := csv.get_csv_line()
	var count := 0
	var previous_frame := -1
	var consecutive := true
	var observed_real_load := false
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() != fields.size():
			continue
		var observation := _as_map(fields, row)
		var frame := int(observation.physics_frame)
		consecutive = consecutive and (previous_frame < 0 or frame == previous_frame + 1)
		previous_frame = frame
		observed_real_load = observed_real_load or float(observation.front_load_n) > 1.0 or float(observation.rear_load_n) > 1.0
		count += 1
	csv.close()
	if count != 32 or not consecutive:
		print("Live recording observation: ", count, " rows; consecutive=", consecutive)
	check(count == 32 and consecutive, "Live recording captures each of 32 native frames once through the actual main loop")
	check(observed_real_load, "Live CSV contains real native tire support rather than only placeholder defaults")
	DirAccess.remove_absolute(path)
	_debug_key(game, KEY_F9)
	var exit_path: String = game.physics_recorder.path
	game.queue_free()
	poststep.queue_free()
	await process_frame
	var closed := FileAccess.open(exit_path, FileAccess.READ)
	check(closed != null and closed.get_csv_line() == Recorder.header(), "Exiting the main game flushes and closes an active recording")
	closed.close()
	DirAccess.remove_absolute(exit_path)
	paused = false

func _crash_step_capture() -> void:
	Engine.physics_ticks_per_second = 240
	var bike := CrashFrameProbe.new()
	check(bike.applied_controls == Bike._neutral_controls(),
		"A newly constructed bike starts with an independent neutral applied-input observation")
	bike.configure(JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json")))
	root.add_child(bike)
	var poststep := PostStepObserver.new()
	poststep.process_physics_priority = 10
	root.add_child(poststep)
	var spawn := Transform3D(Basis.IDENTITY, Vector3(0, 100, 0))
	bike.reset_bike(spawn)
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.gravity_scale = 0.0
		body.collision_mask = 0
	await poststep.completed
	await poststep.completed
	var requested := {"throttle": 1.0, "clutch": 0.0, "steer": 0.5, "lean": -0.4,
		"bodyForward": 0.3, "bodySide": -0.6, "footDown": false, "standing": true}
	bike.set_controls(requested)
	check(bike.applied_controls.throttle == 0.0 and bike.applied_controls.clutch == 1.0,
		"Polling a new request does not overwrite the previous completed-step observation")
	var recorder := Recorder.new()
	var path := "user://telemetry-tests/crash-steps-%d.csv" % OS.get_process_id()
	check(recorder.start(path) == OK, "Crash-phase recording creates a real CSV")
	bike.crash_at_step_end = true
	await poststep.completed
	check(bike.crashed and bike.controls.throttle == 1.0 and bike.controls.clutch == 0.0,
		"The crash-triggering step retains the player's requested throttle and clutch")
	check(bike.applied_controls.throttle == 1.0 and bike.applied_controls.clutch == 0.0 \
		and bike.applied_controls == bike.observed_drive_packet,
		"A crash detected after force application preserves that step's actual pre-crash drivetrain packet")
	check(recorder.capture(Engine.get_physics_frames(), 1.0 / 240.0, bike.get_telemetry(), bike.applied_controls),
		"The crash-triggering completed step records its actual input packet")
	await poststep.completed
	check(bike.controls.throttle == 1.0 and bike.controls.clutch == 0.0,
		"Crash gating preserves requested input independently of its effective force packet")
	check(bike.applied_controls == bike.observed_drive_packet and bike.applied_controls.throttle == 0.0 \
		and bike.applied_controls.clutch == 1.0 and bike.applied_controls.steer == 0.0 \
		and bike.applied_controls.lean == 0.0 and bike.applied_controls.bodyForward == 0.0 and bike.applied_controls.bodySide == 0.0,
		"The following crashed step observes the actual zero-drive, open-clutch and neutral-body force packet")
	check(recorder.capture(Engine.get_physics_frames(), 1.0 / 240.0, bike.get_telemetry(), bike.applied_controls),
		"The following crashed step records sanitized force inputs instead of the still-held request")
	check(bike.reset_bike(spawn, true) and bike.applied_controls == Bike._neutral_controls(),
		"Recovery immediately clears the applied observation to neutral without replaying pre-crash inputs")
	bike.set_controls(requested)
	check(bike.applied_controls == Bike._neutral_controls(),
		"A new post-recovery request cannot retroactively alter the neutral reset observation")
	check(recorder.capture(Engine.get_physics_frames(), 1.0 / 240.0, bike.get_telemetry(), bike.applied_controls),
		"Recovery records an actual neutral input observation")
	recorder.stop()
	var file := FileAccess.open(path, FileAccess.READ)
	var fields := file.get_csv_line()
	var trigger := _as_map(fields, file.get_csv_line())
	var crashed_step := _as_map(fields, file.get_csv_line())
	var recovery := _as_map(fields, file.get_csv_line())
	check(trigger.crashed == "1" and float(trigger.input_throttle) == 1.0 and float(trigger.input_clutch) == 0.0 \
		and crashed_step.crashed == "1" and float(crashed_step.input_throttle) == 0.0 and float(crashed_step.input_clutch) == 1.0,
		"CSV distinguishes the crash-triggering packet from the next step's automatic crash gate")
	check(recovery.crashed == "0" and float(recovery.input_throttle) == 0.0 and float(recovery.input_clutch) == 1.0 \
		and recovery.input_foot_down == "1" and recovery.input_standing == "0",
		"CSV recovery row reflects reset neutral, seated posture and planted support")
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	bike.queue_free()
	poststep.queue_free()
	await process_frame
