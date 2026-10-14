extends SceneTree
const RiderInput = preload("res://scripts/rider_input.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
const Main = preload("res://scenes/main.tscn")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func state(speed: float, front: bool = true, rear: bool = true, crashed: bool = false) -> Dictionary:
	return {"speedMps": speed, "speed": speed * 3.6, "frontContact": front,
		"rearContact": rear, "frontLoad": 500.0 if front else 0.0,
		"rearLoad": 500.0 if rear else 0.0, "roll": 0.0, "bankRate": 0.0, "crashed": crashed}

func advance(input: RefCounted, seconds: float, observation: Dictionary) -> void:
	for step: int in range(int(round(seconds * 240.0))):
		input.update_auto_feet(1.0 / 240.0, observation)

func _run() -> void:
	var input: RefCounted = RiderInput.new()
	check(input.foot_down and not input.standing, "first mount is seated with supporting feet")
	advance(input, 0.7, state(0.0))
	check(input.foot_down, "stationary rider keeps physical feet support")
	input.throttle = 0.8
	input.clutch = 0.0
	advance(input, 0.5, state(0.0))
	check(input.foot_down, "throttle in neutral cannot retract supporting feet")
	var engaged := state(0.0)
	engaged.gear = 1
	input.clutch = 1.0
	advance(input, 0.5, engaged)
	check(input.foot_down, "selected gear with pulled clutch keeps boots supporting stopped bike")
	input.clutch = 0.5
	advance(input, 0.1, engaged)
	check(input.foot_down, "engaged drive must persist before rider lifts boots for launch")
	advance(input, 0.05, engaged)
	check(not input.foot_down, "deliberate clutch-engaged launch lifts boots before drag can trap bike")
	advance(input, 1.0, engaged)
	check(not input.foot_down, "continued launch intent cannot replant boots at low rolling speed")
	input.reset_for_recovery()
	engaged.stalled = true
	input.throttle = 0.8
	input.clutch = 0.0
	advance(input, 0.5, engaged)
	check(input.foot_down, "stalled engine cannot trigger automatic launch lift")
	input.release_controls()
	input.update_auto_feet(1.0 / 240.0, state(1.5))
	check(not input.foot_down and not bool(input.packet().footDown), "actual rolling speed raises feet into controller packet")
	advance(input, 0.8, state(0.95))
	check(not input.foot_down, "middle speed hysteresis does not redeploy riding boots")
	advance(input, 1.0, state(0.1, true, false))
	check(not input.foot_down, "front-only slow contact cannot plant boots during nose-heavy touchdown")
	advance(input, 1.0, state(0.1, false, true))
	check(not input.foot_down, "rear-only slow contact cannot plant boots during wheelie")
	advance(input, 0.4, state(0.0))
	check(not input.foot_down, "brief stop keeps boots on pegs before dwell completes")
	advance(input, 0.1, state(0.0))
	check(input.foot_down, "settled seated stop automatically restores ground support")
	input.update_auto_feet(1.0 / 240.0, state(1.5))
	advance(input, 0.3, state(0.0))
	input.update_auto_feet(1.0 / 240.0, state(0.9))
	advance(input, 0.3, state(0.0))
	check(not input.foot_down, "short stops separated by rolling cannot accumulate plant dwell")
	advance(input, 0.2, state(0.0))
	check(input.foot_down, "continuous stop can plant after interrupted dwell")
	advance(input, 0.05, state(0.0, false, false))
	check(input.foot_down, "brief contact-cache gap does not flicker supporting feet")
	advance(input, 0.05, state(0.0, false, false))
	check(not input.foot_down, "unsupported low-speed flight raises feet after contact confirmation")
	advance(input, 1.5, state(0.0, false, false))
	check(not input.foot_down, "zero-speed jump apex never deploys boots")
	advance(input, 0.5, state(0.0))
	check(input.foot_down, "true landing followed by stopped dwell restores support")
	input.standing = true
	input.update_auto_feet(1.0 / 240.0, state(0.0))
	check(input.foot_down and input.standing and not bool(input.packet().standing),
		"stationary support seats the rider while preserving preferred standing posture")
	input.update_auto_feet(1.0 / 240.0, state(1.5))
	check(not input.foot_down and input.standing and bool(input.packet().standing),
		"rolling automatically lifts feet and restores the preferred standing posture")
	advance(input, 0.6, state(0.0))
	check(input.foot_down and input.standing and not bool(input.packet().standing),
		"a continuous stopped dwell plants feet even with standing preferred")
	_walking_dab_checks(input)
	input.standing = false
	advance(input, 0.6, state(0.0, true, true, true))
	check(not input.foot_down, "crashed bike cannot be supported by automatically planted feet")
	input.reset_for_recovery()
	check(input.foot_down and not input.standing and input.clutch == 1.0
		and input._feet_stop_elapsed == 0.0 and input._feet_air_elapsed == 0.0 and not input._feet_ground_seen
		and input._feet_launch_elapsed == 0.0 and input._feet_dab_elapsed == 0.0 and not input._feet_dab_active,
		"recovery immediately seats rider, plants feet and clears auto-foot history")
	input.update_auto_feet(1.0 / 240.0, state(0.0, false, false))
	check(input.foot_down, "one stale recovery contact sample does not remove remount support")
	advance(input, 0.2, state(0.0, false, false))
	check(input.foot_down, "queued remount keeps support through bounded native contact-cache delay")
	advance(input, 0.2, state(0.0, false, false))
	check(not input.foot_down, "mount grace cannot support an indefinitely unsupported motorcycle")
	advance(input, 0.5, state(0.0))
	input.update_auto_feet(1.0 / 240.0, state(NAN))
	check(not input.foot_down, "invalid speed cannot enable invisible foot support")
	check(not InputMap.has_action("mx_feet"), "legacy F feet action is absent from keyboard input map")
	var bindings: RefCounted = Bindings.new(false)
	check(not "feet" in bindings.ACTIONS and not bindings.bindings.has("feet"), "feet is absent from customizable controller actions")
	var old := ConfigFile.new()
	old.set_value("bindings", "feet", {"kind": "button", "index": JOY_BUTTON_X, "direction": 1})
	var migration_path := "user://feet_migration_test.cfg"
	check(old.save(migration_path) == OK and bindings.load_file(migration_path) == OK
		and not bindings.bindings.has("feet"), "old saved manual foot mapping is ignored on load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(migration_path))
	var button := InputEventJoypadButton.new()
	button.device = 7
	button.button_index = JOY_BUTTON_X
	button.pressed = true
	check(bindings.action_for_event(button, 7).is_empty(), "unmapped Xbox X cannot toggle foot state")
	var game: Node3D = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.audio_enabled = false
	game._stop_engine_audio()
	paused = true
	_anatomy_checks(game)
	await _native_stop_checks(game)
	game.queue_free()
	paused = false
	await process_frame
	print("Automatic feet / riding posture: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _walking_dab_checks(input: RefCounted) -> void:
	input.standing = true
	input.update_auto_feet(1.0 / 240.0, state(3.0))
	var walking := state(1.4)
	walking.roll = deg_to_rad(12.0)
	walking.bankRate = -0.25
	advance(input, 0.15, walking)
	check(not input.foot_down, "recovering walking bank does not deploy supporting boots")
	walking.bankRate = 0.25
	advance(input, 0.025, walking)
	check(not input.foot_down, "one brief developing bank sample cannot plant boots")
	advance(input, 0.025, walking)
	check(input.foot_down and input._feet_dab_active and input.standing and not bool(input.packet().standing),
		"positively loaded walking fall triggers a physical dab and temporary seated support")
	walking.roll = deg_to_rad(6.0)
	walking.bankRate = -0.25
	advance(input, 0.1, walking)
	check(input.foot_down, "dab hysteresis allows the physical support to finish recovering")
	walking.roll = deg_to_rad(3.0)
	advance(input, 0.05, walking)
	check(not input.foot_down and not input._feet_dab_active and bool(input.packet().standing),
		"recovering bank lifts boots and restores preferred standing while moving")
	walking.roll = deg_to_rad(-12.0)
	walking.bankRate = -0.25
	advance(input, 0.05, walking)
	check(input.foot_down, "walking dab responds symmetrically to a developing left fall")
	walking.frontLoad = 0.0
	walking.rearLoad = 0.0
	advance(input, 0.15, walking)
	check(not input.foot_down, "geometry-only contact with zero actual tire load cannot trigger or hold a dab")
	walking.frontLoad = 500.0
	walking.rearLoad = 500.0
	advance(input, 0.05, walking)
	check(input.foot_down, "restored real ground support can permit a fresh walking dab")
	walking.frontContact = false
	walking.frontLoad = 0.0
	advance(input, 0.15, walking)
	check(not input.foot_down, "rear-only wheelie contact immediately removes walking boot support")
	walking.frontContact = true
	walking.frontLoad = 500.0
	advance(input, 0.05, walking)
	walking.rearContact = false
	walking.rearLoad = 0.0
	advance(input, 0.15, walking)
	check(not input.foot_down, "front-only nose-heavy touchdown cannot hold walking boot support")
	advance(input, 0.5, state(0.0, false, false))
	check(not input.foot_down, "slow unsupported air and apex cannot deploy a walking dab")
	walking = state(2.1)
	walking.roll = deg_to_rad(-12.0)
	walking.bankRate = -0.25
	advance(input, 0.2, walking)
	check(not input.foot_down, "riding speed prevents walking dabs even with developing bank")
	walking = state(1.4)
	walking.roll = deg_to_rad(7.0)
	walking.bankRate = 0.3
	advance(input, 0.2, walking)
	check(not input.foot_down, "small walking bank remains on pegs without unnecessary boot deployment")
	walking.roll = NAN
	advance(input, 0.2, walking)
	check(not input.foot_down, "invalid bank observations cannot enable a walking support reflex")
	walking.roll = deg_to_rad(12.0)
	advance(input, 0.05, walking)
	input.throttle = 0.8
	input.clutch = 0.0
	walking.gear = 1
	advance(input, 0.15, walking)
	check(not input.foot_down and not input._feet_dab_active and bool(input.packet().standing),
		"deliberate clutch-engaged launch retracts a dab and resumes standing preference")
	input.release_controls()

func _native_stop_checks(game: Node3D) -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("mx_"):
			Input.action_release(action)
	game.start_session()
	game.rider_input.standing = true
	for _i: int in range(600):
		await physics_frame
		await process_frame
	var stopped: Dictionary = game.bike.get_telemetry()
	check(game.rider_input.standing and bool(stopped.footDown) and not bool(stopped.standing),
		"live flat stop preserves standing preference while actually seated on supporting boots")
	var feet_enabled := true
	for foot: CollisionShape3D in game.bike._feet:
		feet_enabled = feet_enabled and not foot.disabled
	check(feet_enabled and game.bike.chassis.get_contact_count() > 0 and not bool(stopped.crashed)
		and float(stopped.speedMps) < 0.25 and game.bike.chassis.global_basis.y.dot(Vector3.UP) > 0.98,
		"flat stopped support comes from actual native boot contacts with an upright stationary bike")
	game.bike.shift_gear(1)
	Input.action_press("mx_throttle")
	Input.action_press("mx_clutch_release")
	for _i: int in range(720):
		await physics_frame
		await process_frame
	var moving: Dictionary = game.bike.get_telemetry()
	var feet_disabled := true
	for foot: CollisionShape3D in game.bike._feet:
		feet_disabled = feet_disabled and foot.disabled
	check(feet_disabled and not bool(moving.footDown) and bool(moving.standing) and game.rider_input.standing
		and float(game.bike._standing) > 0.75 and float(moving.speedMps) > 1.3 and not bool(moving.crashed),
		"live gear-and-clutch launch raises real boots and resumes preferred physical standing")
	Input.action_release("mx_throttle")
	Input.action_release("mx_clutch_release")
	Input.action_press("mx_clutch_quick")
	Input.action_press("mx_rear_brake")
	for _i: int in range(960):
		await physics_frame
		await process_frame
	var returned: Dictionary = game.bike.get_telemetry()
	print("NATIVE FOOT STOP ", JSON.stringify({"launchSpeed": moving.speedMps,
		"stopSpeed": returned.speedMps, "preferredStanding": game.rider_input.standing,
		"standing": returned.standing, "feet": returned.footDown, "crashed": returned.crashed,
		"recoveries": game.recovery_count, "nativeBootContacts": game.bike.chassis.get_contact_count()}))
	check(game.rider_input.standing and bool(returned.footDown) and not bool(returned.standing)
		and float(returned.speedMps) < 0.3 and not bool(returned.crashed) and game.bike.chassis.get_contact_count() > 0,
		"real braking back to a flat stop automatically restores seated native support without losing preference")
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("mx_"):
			Input.action_release(action)

func _anatomy_checks(game: Node3D) -> void:
	var visual: Node3D = game.bike._rider_visual
	var center := Vector3(0.0, 0.54, 0.09)
	var standing_hip_y := 0.0
	var sitting_hip_y := 0.0
	for posture: int in range(2):
		for body_sign: float in [-1.0, 0.0, 1.0]:
			var forward := body_sign * 0.35
			var side := body_sign * 0.30
			var body_lean := -body_sign * 0.40
			var yaw := body_sign * 0.25
			var target := Transform3D(Basis.from_euler(Vector3(-forward * 0.42, yaw, -body_lean * 0.48)),
				center + Vector3(side * 0.19, float(posture) * 0.2, -forward * 0.22))
			visual.update_pose(forward, side, body_lean, float(posture), false,
				{"rider_transform": target, "rider_reference_transform": target,
				"rider_yaw_target": yaw, "pose_reset": true})
			var grips_anchored := true
			var arms_natural := true
			var legs_natural := true
			var pegs_supported := true
			var elbow_relaxed := true
			for index: int in range(2):
				var sign_side := -1.0 if index == 0 else 1.0
				var grip: Vector3 = game.bike.chassis.global_transform.affine_inverse() * \
					(game.bike.fork.global_transform * Vector3(sign_side * 0.355, 0.140, -0.025))
				grips_anchored = grips_anchored and visual._gloves[index].position.distance_to(grip) < 0.0001
				arms_natural = arms_natural and absf(visual._upper_arms[index].scale.y - 0.303) < 0.001 \
					and absf(visual._forearms[index].scale.y - 0.289) < 0.001
				var hip_joint: Vector3 = visual._pelvis.position + Basis(Vector3.UP, yaw) * Vector3(sign_side * 0.124, -0.005, 0)
				var ankle: Vector3 = visual._boots[index].position + Vector3(0, 0.022, 0.014)
				legs_natural = legs_natural and absf(hip_joint.distance_to(visual._knees[index].position) - 0.480) < 0.001 \
					and absf(ankle.distance_to(visual._knees[index].position) - 0.475) < 0.001
				# Boot sole y=-0.13 is aligned to the actual bike-visual peg top.
				pegs_supported = pegs_supported and absf(visual._boots[index].position.y - 0.13 - (-0.231)) < 0.006
				elbow_relaxed = elbow_relaxed and visual._elbows[index].position.y < visual._head.position.y - 0.12
			check(grips_anchored, "riding/body shift keeps both gloves on real moving fork grips")
			check(arms_natural, "riding/body shift keeps both arms at human anatomical lengths")
			check(legs_natural, "riding/body shift preserves thigh and knee-to-ankle lengths")
			check(pegs_supported, "riding boots stay supported at the real peg tops")
			check(elbow_relaxed, "rider elbows stay comfortably below helmet")
			check(visual._head.basis.z.dot(Vector3.BACK) > 0.85, "helmet keeps forward riding gaze through input posture")
			if body_sign == 0.0:
				if posture == 0:
					sitting_hip_y = visual._pelvis.position.y
				else:
					standing_hip_y = visual._pelvis.position.y
	check(standing_hip_y - sitting_hip_y > 0.25, "standing posture opens legs instead of maintaining a seated squat")
	visual.update_pose(0.0, 0.0, 0.0, 0.0, true, {"pose_reset": true})
	var planted := true
	for boot: Node3D in visual._boots:
		planted = planted and absf(boot.position.y + 0.635) < 0.0001
	check(planted, "rest/recovery boots return to physical foot support position")
