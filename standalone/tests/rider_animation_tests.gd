extends SceneTree
## Exercise the production articulated rig with actual boot/hand IK endpoints.
## This is a presentation bench, not a claim about motorcycle rideability.
const Rider = preload("res://scripts/rider_visual.gd")

var checks := 0
var failures: Array[String] = []
var frame: Node3D
var fork: Node3D
var visual: Node3D
const PEG_LEFT := Vector3(-0.245, -0.101, 0.087)
const PEG_RIGHT := Vector3(0.245, -0.101, 0.087)

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("RIDER ANIMATION FAIL: " + message)

func _state(bank: float = 0.0, dt: float = 1.0 / 240.0,
		reset: bool = false, grounded: bool = true, speed: float = 8.0) -> Dictionary:
	return {"bank": bank, "speed": speed, "grounded": grounded,
		"dt": dt, "pose_reset": reset, "steer_angle": 0.0}

func _pose(bank: float = 0.0, stand: float = 0.0, feet: bool = false,
		dt: float = 1.0 / 240.0, reset: bool = false,
		grounded: bool = true, speed: float = 8.0) -> void:
	visual.update_pose(0.0, 0.0, 0.0, stand, feet,
		_state(bank, dt, reset, grounded, speed))

func _advance(seconds: float, bank: float, stand: float = 0.0,
		feet: bool = false, grounded: bool = true, speed: float = 8.0,
		hz: int = 240) -> void:
	for index in range(roundi(seconds * hz)):
		_pose(bank, stand, feet, 1.0 / hz, false, grounded, speed)

func _anatomical_legs() -> bool:
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var hip: Vector3 = visual._pelvis.position + Vector3(side * 0.124, -0.005, 0.0)
		var ankle: Vector3 = visual._boots[index].position + Vector3(0.0, 0.022, 0.014)
		var knee: Vector3 = visual._knees[index].position
		if absf(hip.distance_to(knee) - 0.480) > 0.001:
			return false
		if absf(knee.distance_to(ankle) - 0.475) > 0.001:
			return false
	return true

func _run() -> void:
	frame = Node3D.new()
	root.add_child(frame)
	fork = Node3D.new()
	frame.add_child(fork)
	fork.position = Vector3(0.0, 0.36, -0.29)
	visual = Rider.new()
	frame.add_child(visual)
	visual.configure(frame, fork)
	_pose(0.0, 0.0, false, 1.0 / 240.0, true)
	_check(visual._boots[0].position.distance_to(PEG_LEFT) < 0.00001
		and visual._boots[1].position.distance_to(PEG_RIGHT) < 0.00001,
		"neutral boots are anchored to both real pegs")
	for direction: float in [-1.0, 1.0]:
		_pose(0.0, 0.0, false, 1.0 / 240.0, true)
		var natural := true
		var max_step := 0.0
		var previous: Vector3 = visual._boots[0 if direction < 0.0 else 1].position
		for index in range(180):
			_pose(direction * 0.4)
			var actual: Vector3 = visual._boots[0 if direction < 0.0 else 1].position
			max_step = maxf(max_step, actual.distance_to(previous))
			previous = actual
			natural = natural and _anatomical_legs()
		var inside: Node3D = visual._boots[0 if direction < 0.0 else 1]
		var outside: Node3D = visual._boots[1 if direction < 0.0 else 0]
		_check(inside.position.z < -0.30 and absf(inside.position.x) > 0.40,
			"inside boot extends forward and away from the motorcycle during %s corner" % direction)
		_check(outside.position.distance_to(PEG_RIGHT if direction < 0.0 else PEG_LEFT) < 0.00001,
			"outside boot remains anchored to its peg during %s corner" % direction)
		_check(natural, "leg bones retain anatomical lengths throughout corner extension %s" % direction)
		_check(max_step < 0.015, "corner extension has no per-tick boot teleport %s" % direction)
	# Reverse while the first leg is still moving outward. The exact spring
	# retains velocity instead of restarting a new clip at an arbitrary pose.
	_pose(0.0, 0.0, false, 1.0 / 240.0, true)
	_advance(0.12, -0.4)
	var before: Dictionary = visual.get_animation_state()
	var left_before: Vector3 = visual._boots[0].position
	_pose(0.4, 0.0, false, 0.0)
	var switched: Dictionary = visual.get_animation_state()
	_check(absf(float(switched.corner) - float(before.corner)) < 0.000001
		and absf(float(switched.corner_rate) - float(before.corner_rate)) < 0.000001,
		"changing a corner target preserves pose and velocity at the interruption instant")
	_pose(0.4)
	var after: Dictionary = visual.get_animation_state()
	_check(absf(float(after.corner) - float(before.corner)) < 0.03
		and float(after.corner_rate) < 0.0,
		"mid-extension reversal decelerates the moving leg before returning it")
	_check(visual._boots[0].position.distance_to(left_before) < 0.015,
		"interrupting corner animation does not snap the moving boot")
	var reversal_natural := true
	var never_two_extended := true
	for index in range(240):
		_pose(0.4)
		reversal_natural = reversal_natural and _anatomical_legs()
		never_two_extended = never_two_extended and not (
			visual._boots[0].position.z < 0.03 and visual._boots[1].position.z < 0.03)
	_check(reversal_natural and never_two_extended,
		"reversal keeps anatomical legs and never extends both cornering boots")
	_check(visual._boots[0].position.distance_to(PEG_LEFT) < 0.00001
		and visual._boots[1].position.z < -0.30,
		"right turn completes naturally after interrupted left extension")
	_advance(0.8, 0.0)
	_check(visual._boots[0].position.distance_to(PEG_LEFT) < 0.0001
		and visual._boots[1].position.distance_to(PEG_RIGHT) < 0.0001,
		"corner exit returns both boots to the pegs")
	# Countersteering must not select the outside foot once the bike is banked.
	var opposite_bars := _state(0.30, 1.0 / 240.0, true)
	opposite_bars.steer_angle = -0.5
	visual.update_pose(0.0, 0.0, 0.0, 0.0, false, opposite_bars)
	_check(float(visual.get_animation_state().corner) > 0.5,
		"actual bank retains the inside leg despite opposite countersteering bars")
	_advance(0.8, 0.4, 0.0, false, false)
	_check(absf(float(visual.get_animation_state().corner)) < 0.0001,
		"unsupported airborne phase retracts cornering leg instead of playing a whip clip")
	_pose(0.4, 0.0, false, 1.0 / 240.0, true, true, 30.0)
	_check(absf(float(visual.get_animation_state().corner)) < 0.00001,
		"fast sweeping corners retain both boots on the pegs")
	_pose(0.4, 0.0, false, 1.0 / 240.0, true, true, 0.5)
	_check(absf(float(visual.get_animation_state().corner)) < 0.00001,
		"near-stop leg support remains owned by automatic planted-foot state")
	_pose(0.4, 0.0, false, 1.0 / 240.0, true)
	var max_support_step := 0.0
	var support_natural := true
	for index in range(240):
		var previous: Vector3 = visual._boots[1].position
		_pose(0.0, 1.0, true)
		max_support_step = maxf(max_support_step, previous.distance_to(visual._boots[1].position))
		support_natural = support_natural and _anatomical_legs()
	_check(max_support_step < 0.025 and support_natural,
		"corner-to-planted support transition remains smooth with anatomical reach")
	_check(absf(visual._boots[1].position.y + 0.635) < 0.0001
		and visual._pelvis.position.y < 0.35,
		"automatic support fully plants boots and seats the rider despite standing preference")
	var support_hip: Vector3 = visual._pelvis.position
	_pose(0.0, 1.0, false)
	_check(visual._pelvis.position.distance_to(support_hip) < 0.003,
		"lifting feet with standing preference begins without pelvis teleport")
	_advance(0.8, 0.0, 1.0)
	_check(visual._pelvis.position.y > 0.69 and _anatomical_legs(),
		"standing settles to the attack stance with boots supported and natural leg lengths")
	# Reset bypasses transitional momentum; ordinary direction changes do not.
	_pose(-0.4, 1.0, false, 1.0 / 240.0, true)
	_advance(0.1, -0.4, 0.0)
	_pose(0.0, 0.0, true, 1.0 / 240.0, true)
	var reset_state: Dictionary = visual.get_animation_state()
	_check(absf(float(reset_state.corner)) + absf(float(reset_state.corner_rate))
		+ absf(float(reset_state.standing)) + absf(float(reset_state.standing_rate))
		+ absf(float(reset_state.support_rate)) < 0.00001
		and visual._boots[0].position.distance_to(Vector3(-0.34, -0.635, 0.02)) < 0.00001,
		"remount clears animation momentum and restores planted pose immediately")
	var rate_samples: Array[Vector3] = []
	for hz: int in [30, 60, 120, 240]:
		_pose(0.0, 0.0, false, 1.0 / hz, true)
		_advance(0.1, -0.4, 0.0, false, true, 8.0, hz)
		_advance(0.2, 0.4, 0.0, false, true, 8.0, hz)
		rate_samples.append(visual._boots[1].position)
	var rate_consistent := true
	for sample: Vector3 in rate_samples:
		rate_consistent = rate_consistent and sample.distance_to(rate_samples[-1]) < 0.00002
	_check(rate_consistent, "interrupted pose integration agrees at 30, 60, 120, and 240 Hz")
	var settings_visual: Node3D = Rider.new()
	frame.add_child(settings_visual)
	settings_visual.configure(frame, fork, {"CornerTransitionTime": 0.5, "LegOutForwardTravel": 0.25})
	settings_visual.update_pose(0.0, 0.0, 0.0, 0.0, false, _state(0.0, 0.0, true))
	for index in range(24):
		settings_visual.update_pose(0.0, 0.0, 0.0, 0.0, false, _state(0.4))
	_check(float(settings_visual.get_animation_state().corner) < 0.1,
		"constructor tuning controls the real transition response")
	for index in range(720):
		settings_visual.update_pose(0.0, 0.0, 0.0, 0.0, false, _state(0.4))
	_check(absf(settings_visual._boots[1].position.z - (PEG_RIGHT.z - 0.25)) < 0.001,
		"constructor tuning controls real boot extension in metres")
	var tuning_state: Dictionary = settings_visual.get_animation_state()
	settings_visual.set_animation_settings({"CornerTransitionTime": 0.18, "unknown": 99.0})
	_check(settings_visual.get_animation_state() == tuning_state
		and not settings_visual._animation_settings.has("unknown"),
		"live tuning preserves interruption state and accepts only supported coefficients")
	settings_visual.free()
	_scrub_crouch_regressions()
	# Native human yaw remains authoritative in both third/first person.
	var center := Vector3(0.0, 0.54, 0.09)
	var physical_state := _state(0.0, 1.0 / 240.0, true, false)
	physical_state.rider_transform = Transform3D(Basis(Vector3.UP, 0.32), center)
	physical_state.rider_reference_transform = Transform3D(Basis(Vector3.UP, 0.4), center)
	physical_state.rider_yaw_target = 0.4
	visual.update_pose(0.0, 0.0, 0.0, 0.0, false, physical_state)
	_check(absf(visual._head.rotation.y - 0.32) < 0.0001,
		"helmet follows actual physical rider yaw during airborne motion")
	visual.set_first_person(true)
	_check(not visual._head.visible and visual._forearms[0].visible
		and visual.get_camera_transform().origin.is_finite(),
		"first-person keeps physical eye anchor and visible forearms while hiding helmet")
	visual.set_first_person(false)
	_check(visual._head.visible and visual._torso.visible,
		"returning to third person restores helmet and torso")
	frame.free()
	print("Rider animation checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _scrub_crouch_regressions() -> void:
	for sample: Array in [[0.0, 0.08], [1.0, 0.16], [0.0, 0.28], [1.0, 0.28]]:
		var posture := float(sample[0])
		var center := Vector3(0.0, 0.54 + posture * 0.22, 0.09 - posture * 0.10)
		var baseline := Transform3D(Basis.IDENTITY, center)
		var crouch := float(sample[1])
		var reference := baseline
		reference.origin.y -= crouch
		var state := _state(0.0, 1.0 / 240.0, true)
		state.rider_transform = baseline
		state.rider_reference_transform = baseline
		visual.update_pose(0.0, 0.0, 0.0, posture, false, state)
		var original_hip: Vector3 = visual._pelvis.position
		var original_head: Vector3 = visual._head.position
		# Phase one changes the physical request while actual native motion has
		# not occurred. Rendering must not anticipate it or move in reverse.
		state.scrub_crouch = crouch
		state.rider_reference_transform = reference
		visual.update_pose(0.0, 0.0, 0.0, posture, false, state)
		_check(visual._pelvis.position.distance_to(original_hip) < 0.0001
			and visual._head.position.distance_to(original_head) < 0.0001,
			"%.2fm scrub target alone does not invent inverse visual movement at posture %.0f" % [crouch, posture])
		# Phase two moves the real torso to the requested crouch. The rider
		# follows that real movement while hands and boots retain bike contacts.
		state.rider_transform = reference
		visual.update_pose(0.0, 0.0, 0.0, posture, false, state)
		if posture > 0.5:
			_check(absf(original_hip.y - visual._pelvis.position.y - crouch) < 0.0001
				and original_head.y - visual._head.position.y > 0.12,
				"standing scrub follows actual native hip and torso crouch")
		else:
			_check(absf(visual._pelvis.position.y - original_hip.y) < 0.0001
				and visual._head.position.y < original_head.y - 0.01,
				"seated scrub hinges the torso while keeping the pelvis above the saddle")
		var contacts_anchored := true
		for index in range(2):
			var side := -1.0 if index == 0 else 1.0
			var hand: Vector3 = frame.global_transform.affine_inverse() * (
				fork.global_transform * Vector3(side * 0.355, 0.14, -0.025))
			contacts_anchored = contacts_anchored and visual._gloves[index].position.distance_to(hand) < 0.0001
			contacts_anchored = contacts_anchored and visual._boots[index].position.distance_to(PEG_LEFT if index == 0 else PEG_RIGHT) < 0.0001
		_check(contacts_anchored and _anatomical_legs(),
			"actual scrub crouch retains glove/boot contacts and human leg lengths at posture %.0f" % posture)
		state.grounded = false
		state.bank = -0.4
		state.pose_reset = false
		for index in range(240):
			visual.update_pose(0.0, 0.0, 0.0, posture, false, state)
		_check(absf(float(visual.get_animation_state().corner)) < 0.0001
			and visual._boots[0].position.distance_to(PEG_LEFT) < 0.0001,
			"airborne held scrub crouch keeps the cornering legs retracted at posture %.0f" % posture)
