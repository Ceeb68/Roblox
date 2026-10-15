extends SceneTree
## Exercise the actual main game's keyboard/input/controller path at 240 Hz
## while rendering at a different cadence. Run with --fixed-fps N and
## -- --render-hz=N (30, 60, 144 or 240). Await physics frames only during
## the launch, so low render rates cannot silently skip simulation samples.
## A native hardpack bench outside the circuit permits a straight 14 s run;
## the only reset/pose assignment is the initial stationary fixture spawn.

const PHYSICS_HZ := 240
const DURATION := 14.0
const SPAWN := Vector3(0.0, 0.82, -500.0)
var expected_render_hz := 240.0
var game: Node3D
var failures: Array[String] = []
var checks := 0
var saved_files: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + detail if not detail.is_empty() else ""))
		push_error("RENDER CADENCE FAIL: " + failures[-1])

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

func _add_launch_pad() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "RenderCadenceNativeHardpack"
	floor_body.position = Vector3(0.0, -0.15, -650.0)
	floor_body.set_meta("physics_surface", "hardpack")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	floor_body.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 0.3, 1000.0)
	collision.shape = shape
	floor_body.add_child(collision)
	game.add_child(floor_body)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--render-hz="):
			expected_render_hz = float(argument.trim_prefix("--render-hz="))
	Engine.physics_ticks_per_second = PHYSICS_HZ
	_check(expected_render_hz in [30.0, 60.0, 144.0, 240.0], "Render fixture uses a supported comparison cadence")
	var paths: Array[String] = ["user://preferences.cfg", "user://controller_bindings.cfg", "user://handling.cfg"]
	for path: String in paths:
		if FileAccess.file_exists(path):
			saved_files[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_release_actions()
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	_add_launch_pad()
	game.bike.reset_bike(Transform3D(Basis.IDENTITY, SPAWN), true)
	game.rider_input.reset_for_recovery()
	game.start_session()
	for tick in range(PHYSICS_HZ):
		await physics_frame
	_check(bool(game.bike.get_telemetry().footDown), "Normal main-game startup settles with automatic feet support")
	_key(KEY_E)
	await physics_frame
	_check(int(game.bike.get_telemetry().gear) == 1, "An actual keyboard event selects first through the game's input dispatcher")
	var origin: Vector3 = game.bike.chassis.global_position
	var origin_heading := atan2(-game.bike.chassis.global_basis.z.x, -game.bike.chassis.global_basis.z.z)
	var previous_physics_frames := Engine.get_physics_frames()
	var previous_process_frames := Engine.get_process_frames()
	var max_bank := 0.0
	var max_speed := 0.0
	var first_100_max_lateral := 0.0
	var first_100_heading := 0.0
	var first_100_reached := false
	var grounded_ticks := 0
	var crash_seen := false
	var lifted := false
	var samples: Array[Dictionary] = []
	Input.action_press("mx_throttle")
	Input.action_press("mx_clutch_release")
	for tick in range(roundi(DURATION * PHYSICS_HZ)):
		# Identical clutch and four-shift timing to the existing keyboard
		# playability protocol. Main game callbacks produce all riding inputs.
		if tick in [600, 1000, 1400, 1900]:
			Input.action_press("mx_clutch_quick")
		if tick in [620, 1020, 1420, 1920]:
			_key(KEY_E)
			Input.action_release("mx_clutch_quick")
		await physics_frame
		var state: Dictionary = game.bike.get_telemetry()
		max_bank = maxf(max_bank, absf(float(state.roll)))
		max_speed = maxf(max_speed, float(state.speedMps))
		grounded_ticks += int(bool(state.frontContact) or bool(state.rearContact))
		crash_seen = crash_seen or bool(state.crashed)
		lifted = lifted or not bool(state.footDown)
		if not first_100_reached:
			first_100_max_lateral = maxf(first_100_max_lateral, absf(game.bike.chassis.global_position.x - origin.x))
			if origin.z - game.bike.chassis.global_position.z >= 100.0:
				first_100_reached = true
				var heading := atan2(-game.bike.chassis.global_basis.z.x, -game.bike.chassis.global_basis.z.z)
				first_100_heading = absf(wrapf(heading - origin_heading, -PI, PI))
		if tick % PHYSICS_HZ == PHYSICS_HZ - 1:
			samples.append({"seconds": float(tick + 1) / PHYSICS_HZ, "speed": state.speedMps,
				"bankDeg": rad_to_deg(float(state.roll)), "position": str(game.bike.chassis.global_position),
				"gear": state.gear, "physicsFrames": Engine.get_physics_frames() - previous_physics_frames,
				"processFrames": Engine.get_process_frames() - previous_process_frames})
	var physics_frames := Engine.get_physics_frames() - previous_physics_frames
	var process_frames := Engine.get_process_frames() - previous_process_frames
	var final: Dictionary = game.bike.get_telemetry()
	var forward_distance: float = origin.z - game.bike.chassis.global_position.z
	var measured_render_hz := float(process_frames) / DURATION
	var ratio := float(physics_frames) / maxi(process_frames, 1)
	_check(physics_frames == roundi(DURATION * PHYSICS_HZ), "Launch observes every one of 3360 actual physics frames", str(physics_frames))
	_check(absf(measured_render_hz - expected_render_hz) < 1.0,
		"Measured process cadence matches the requested render rate", "%.3f Hz / %d frames" % [measured_render_hz, process_frames])
	_check(absf(ratio - float(PHYSICS_HZ) / expected_render_hz) < 0.03,
		"Native physics continues across multiple updates per render frame", "%.6f physics/render" % ratio)
	_check(not crash_seen and game.recovery_count == 0, "The actual main-game input path completes the launch without crash or hidden recovery")
	_check(int(final.gear) == 5, "Four genuine keyboard/clutch shifts reach fifth gear")
	_check(forward_distance > 120.0 and max_speed > 15.0, "The native bike makes useful progress at this render cadence")
	_check(max_bank < 0.4 and grounded_ticks > 2400, "The bike stays controlled through actual loaded tire contacts")
	_check(lifted and not bool(final.footDown), "Main-game automatic feet lift during the launch")
	_check(first_100_reached and first_100_max_lateral < 3.0, "Neutral launch remains inside the unchanged first-100m lane limit", "%.3f m" % first_100_max_lateral)
	_check(first_100_reached and first_100_heading < deg_to_rad(12.0), "Neutral launch stays within the existing heading limit")
	var report := {"expectedRenderHz": expected_render_hz, "measuredRenderHz": measured_render_hz,
		"physicsHz": PHYSICS_HZ, "physicsFrames": physics_frames, "processFrames": process_frames,
		"physicsPerRenderFrame": ratio, "first100MaxLateral": first_100_max_lateral,
		"first100HeadingDeg": rad_to_deg(first_100_heading), "maxBankDeg": rad_to_deg(max_bank),
		"maxSpeed": max_speed, "forwardDistance": forward_distance, "gear": final.gear,
		"crashSeen": crash_seen, "recoveries": game.recovery_count, "checks": checks, "failures": failures,
		"samples": samples}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var output := FileAccess.open("res://build/render-cadence-%d-%d.json" % [roundi(expected_render_hz), OS.get_process_id()], FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	var printable := report.duplicate()
	printable.erase("samples")
	print("RENDER CADENCE ", JSON.stringify(printable))
	_release_actions()
	game.queue_free()
	await process_frame
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if saved_files.has(path):
			var restored := FileAccess.open(path, FileAccess.WRITE)
			restored.store_buffer(saved_files[path])
			restored.close()
	print("Render cadence checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
