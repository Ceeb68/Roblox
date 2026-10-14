extends SceneTree
## Native analog control regressions: imperfect turn entry, neutral release,
## direction reversal, moderate braking, and active airborne whip/unwhip.
## Fixtures initialize rolling motion once. No body is locked, continuously
## repositioned, velocity-clamped or given an upright/landing force.

const Bike = preload("res://scripts/bike_controller.gd")
const HZ := 240.0
var cfg: Dictionary
var world: Node3D
var bike: Node3D
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + detail if not detail.is_empty() else ""))
		push_error("RIDEABILITY FAIL: " + failures[-1])

func _tick() -> void:
	await physics_frame
	await process_frame

func _fixture(speed: float, surface: String, standing: bool) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _tick()
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.position.y = -0.25
	ground.set_meta("physics_surface", surface)
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	ground.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(600.0, 0.5, 600.0)
	collision.shape = shape
	ground.add_child(collision)
	world.add_child(ground)
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.82, 0.0)))
	bike.set_controls({"clutch": 1.0, "footDown": true, "standing": standing})
	# Let the chosen posture settle as an actual compliant body before the
	# fixture starts. Standing in mid-air would add an unrelated pitch impulse.
	for _i: int in range(482):
		await _tick()
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.linear_velocity = Vector3(0.0, 0.0, -speed)
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * speed / float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * speed / float(cfg.RearRadius)
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	bike.set_controls({"clutch": 1.0, "footDown": false, "standing": standing})

func _prepare_powered_gear(gear: int, standing: bool) -> void:
	_check(bike.shift_gear(1), "Powered analog ride selects first with the real clutch pulled")
	for i: int in range(240):
		if gear == 2 and i == 24:
			_check(bike.shift_gear(1), "Powered analog ride selects second after the real shift delay")
		bike.set_controls({"clutch": 1.0, "throttle": 0.6, "footDown": false, "standing": standing})
		await _tick()
	_check(int(bike.get_telemetry().gear) == gear, "Powered analog fixture verifies its actual manual gear")

func _heading() -> float:
	var forward: Vector3 = -bike.chassis.global_basis.z
	return atan2(forward.x, forward.z)

func _analog_request(time: float, amount: float) -> float:
	if time >= 0.5 and time < 1.25:
		return amount * (time - 0.5) / 0.75
	if time >= 1.25 and time < 3.0:
		return amount
	if time >= 3.0 and time < 3.5:
		return amount * (1.0 - (time - 3.0) / 0.5)
	if time >= 5.0 and time < 5.75:
		return -amount * (time - 5.0) / 0.75
	if time >= 5.75 and time < 7.0:
		return -amount
	if time >= 7.0 and time < 7.5:
		return -amount * (1.0 - (time - 7.0) / 0.5)
	return 0.0

func _analog_case(speed: float, amount: float, surface: String, standing: bool,
		gear: int = 0, brake: String = "") -> void:
	await _fixture(speed, surface, standing)
	if gear > 0:
		await _prepare_powered_gear(gear, standing)
	var label := "%s %.0fm/s %s %.2f %s%s" % [surface, speed,
		"standing" if standing else "seated", amount,
		"coast" if gear == 0 else "gear%d" % gear, " " + brake if not brake.is_empty() else ""]
	var direction := signf(amount)
	var first_turn_heading := 0.0
	var reverse_heading := 0.0
	var first_turn_bank := 0.0
	var reverse_bank := 0.0
	var first_neutral_opposite_bank := 0.0
	var neutral_final_bank := 0.0
	var max_bank := 0.0
	var max_torque := 0.0
	var max_front_slip := 0.0
	var max_rear_slip := 0.0
	var max_budget_excess := 0.0
	var max_unsupported_force := 0.0
	var first_response := INF
	var entry_bank := 0.0
	var native_contact_ticks := 0
	var completed_ticks := 0
	var previous_heading := _heading()
	var origin: Vector3 = bike.chassis.global_position
	var first_turn_samples := 0
	var reverse_samples := 0
	var final_samples := 0
	var samples: Array[Dictionary] = []
	for i: int in range(2160):
		var time := float(i) / HZ
		var request := _analog_request(time, amount)
		var throttle := clampf(0.45 + (speed - bike.chassis.linear_velocity.length()) * 0.15, 0.1, 0.7) if gear > 0 else 0.0
		var packet := {"steer": request, "lean": 0.0, "clutch": maxf(0.0, 1.0 - time / 0.75) if gear > 0 else 1.0,
			"throttle": throttle, "footDown": false, "standing": standing,
			"frontBrake": 0.0, "rearBrake": 0.0, "bodyForward": 0.0, "bodySide": 0.0}
		# An imperfect brief brake application while holding a modest bank.
		# This is a lever input and real weight transfer, not a velocity change.
		if time >= 2.0 and time < 2.35:
			if brake == "front_brake":
				packet.frontBrake = 0.18
			elif brake == "rear_brake":
				packet.rearBrake = 0.25
		bike.set_controls(packet)
		await _tick()
		completed_ticks += 1
		var t: Dictionary = bike.get_telemetry()
		var bank := float(t.roll)
		if i == 120:
			entry_bank = bank
		var heading := _heading()
		var heading_change := wrapf(heading - previous_heading, -PI, PI)
		previous_heading = heading
		if time >= 1.5 and time < 3.0:
			first_turn_heading += heading_change
			first_turn_bank += bank
			first_turn_samples += 1
		if time >= 6.0 and time < 7.0:
			reverse_heading += heading_change
			reverse_bank += bank
			reverse_samples += 1
		if time >= 3.5 and time < 5.0:
			first_neutral_opposite_bank = maxf(first_neutral_opposite_bank, -direction * bank)
		if time >= 8.5:
			neutral_final_bank += absf(bank)
			final_samples += 1
		if time >= 0.5 and (bank - entry_bank) * direction > deg_to_rad(3.0) and first_response == INF:
			first_response = time - 0.5
		max_bank = maxf(max_bank, absf(bank))
		max_torque = maxf(max_torque, absf(float(t.riderSteeringTorque)))
		max_front_slip = maxf(max_front_slip, absf(float(t.frontSlipAngle)))
		max_rear_slip = maxf(max_rear_slip, absf(float(t.rearSlipAngle)))
		native_contact_ticks += int(bool(t.frontContact) and bool(t.rearContact))
		for wheel_result: Array in [[bike.front_wheel, bike._front_result], [bike.rear_wheel, bike._rear_result]]:
			var wheel: RigidBody3D = wheel_result[0]
			var result: Dictionary = wheel_result[1]
			var tangential := Vector2(float(result.longitudinalForce), float(result.lateralForce)).length()
			var capacity := float(result.grip) * float(wheel.normal_load)
			max_budget_excess = maxf(max_budget_excess, tangential - capacity)
			if not wheel.contact or float(wheel.normal_load) <= 0.0:
				max_unsupported_force = maxf(max_unsupported_force, tangential)
		if i % 120 == 119:
			samples.append({"s": time, "request": request, "roll": bank, "target": t.riderTargetLean,
				"speed": t.speedMps, "headingRate": t.headingRate, "frontLoad": t.frontLoad,
				"rearLoad": t.rearLoad, "frontSlipAngle": t.frontSlipAngle, "rearSlipAngle": t.rearSlipAngle,
				"frontUtilization": bike._front_result.utilization, "rearUtilization": bike._rear_result.utilization,
				"barAngle": t.steerAngle, "torque": t.riderSteeringTorque})
		if bool(t.crashed):
			break
	first_turn_bank /= maxf(1.0, first_turn_samples)
	reverse_bank /= maxf(1.0, reverse_samples)
	neutral_final_bank /= maxf(1.0, final_samples)
	var final: Dictionary = bike.get_telemetry()
	var result := {"label": label, "duration": float(completed_ticks) / HZ,
		"firstTurnMeanBank": first_turn_bank, "reverseMeanBank": reverse_bank,
		"firstTurnHeading": first_turn_heading, "reverseHeading": reverse_heading,
		"neutralOppositeBank": first_neutral_opposite_bank, "finalMeanBank": neutral_final_bank,
		"responseSeconds": first_response, "maxBank": max_bank, "maxTorque": max_torque,
		"frontMaxSlipAngle": max_front_slip, "rearMaxSlipAngle": max_rear_slip,
		"maxBudgetExcess": max_budget_excess, "unsupportedForce": max_unsupported_force,
		"distance": origin.distance_to(bike.chassis.global_position), "nativeContactTicks": native_contact_ticks,
		"crashed": final.crashed, "crashReason": final.crashReason, "samples": samples}
	results.append(result)
	print("RIDEABILITY %s: response %.2fs, turn/reverse %.1f/%.1fdeg, neutral opposite %.1fdeg, final %.1fdeg, crash=%s" % [
		label, first_response, rad_to_deg(first_turn_bank), rad_to_deg(reverse_bank),
		rad_to_deg(first_neutral_opposite_bank), rad_to_deg(neutral_final_bank), final.crashReason if bool(final.crashed) else "none"])
	_check(not bool(final.crashed) and completed_ticks == 2160, label + " completes the imperfect analog maneuver", str(final.crashReason))
	_check(first_turn_bank * direction > deg_to_rad(2.0), label + " establishes an actual bank in the requested direction")
	_check(first_turn_heading * direction < -deg_to_rad(2.0), label + " makes a real first turn")
	_check(first_response < 1.5, label + " responds to the analog turn within 1.5 seconds", str(first_response))
	_check(first_neutral_opposite_bank < deg_to_rad(4.0), label + " neutral release avoids a large opposite-direction bank", "%.1f degrees" % rad_to_deg(first_neutral_opposite_bank))
	_check(reverse_bank * direction < -deg_to_rad(2.0) and reverse_heading * direction > deg_to_rad(1.0), label + " permits a deliberate opposite correction")
	_check(neutral_final_bank < deg_to_rad(10.0), label + " ends with a modest bank after controls return to neutral", "%.1f degrees" % rad_to_deg(neutral_final_bank))
	_check(max_bank < deg_to_rad(45.0), label + " does not develop an excessive bank from moderate inputs")
	_check(max_torque <= 45.001, label + " retains finite 45Nm handlebar actuation")
	_check(native_contact_ticks > 1800, label + " uses real two-tire ground contact")
	_check(max_budget_excess < 0.001 and max_unsupported_force < 0.000001, label + " shares one physical traction budget per patch")
	_check(bike.chassis.global_transform.is_finite() and bike.chassis.linear_velocity.is_finite(), label + " leaves finite native body state")

func _air_fixture() -> void:
	await _fixture(14.0, "dirt", true)
	# Translate all five existing physical bodies once, retaining their settled
	# posture, inertia and relative transforms. Then let native gravity act.
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.global_position += Vector3(0.0, 30.0, 0.0)
	bike.front_wheel.clear_contact()
	bike.rear_wheel.clear_contact()
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	# Contact caches commit at the next native step. This initial neutral tick
	# is not a pose/velocity override and makes the unsupported fixture explicit.
	bike.set_controls({"standing": true, "footDown": false, "clutch": 1.0})
	await _tick()

func _air_case(direction: float, body_only: bool = false) -> Dictionary:
	await _air_fixture()
	var origin: Vector3 = bike.chassis.global_position
	var start_bank: float = bike.get_telemetry().roll
	var start_heading := _heading()
	var peak_bank := 0.0
	var peak_heading := 0.0
	var bank_before_reverse := 0.0
	var rider_yaw_before_reverse := 0.0
	var max_torque := 0.0
	var contacts := 0
	var max_rider_torque := 0.0
	var automatic_target := 0.0
	var max_front_force := 0.0
	var samples: Array[Dictionary] = []
	for i: int in range(360):
		var time := float(i) / HZ
		var command := direction if time < 0.5 else (-direction if time < 1.0 else 0.0)
		bike.set_controls({"steer": 0.0 if body_only else command * 0.7,
			"lean": 0.0 if body_only else command * 0.6,
			"bodySide": command * 0.6 if body_only else command * 0.5,
			"clutch": 1.0, "standing": true, "footDown": false})
		await _tick()
		var t: Dictionary = bike.get_telemetry()
		var bank := float(t.roll) - start_bank
		var heading := wrapf(_heading() - start_heading, -PI, PI)
		peak_bank = maxf(peak_bank, absf(bank))
		peak_heading = maxf(peak_heading, absf(heading))
		max_torque = maxf(max_torque, absf(float(t.riderSteeringTorque)))
		max_rider_torque = maxf(max_rider_torque, (t.riderPostureTorque as Vector3).length())
		contacts += int(bool(t.frontContact) or bool(t.rearContact))
		automatic_target = maxf(automatic_target, absf(float(t.riderTargetLean)) + absf(float(t.headingCorrection)))
		max_front_force = maxf(max_front_force, Vector2(float(bike._front_result.longitudinalForce), float(bike._front_result.lateralForce)).length())
		if i == 119:
			bank_before_reverse = bank
			rider_yaw_before_reverse = (bike.chassis.global_basis.inverse() * bike.rider_body.global_basis).get_euler().y
		if i % 60 == 59:
			samples.append({"s": time, "roll": bank, "heading": heading, "pitch": t.pitch,
				"barAngle": t.steerAngle, "torque": t.riderSteeringTorque, "riderTransform": str(t.riderTransform)})
	var final: Dictionary = bike.get_telemetry()
	var final_bank := float(final.roll) - start_bank
	var final_heading := wrapf(_heading() - start_heading, -PI, PI)
	var result := {"label": ("air neutral" if direction == 0.0 else ("air left" if direction < 0.0 else "air right")) + (" body yaw" if body_only else ""),
		"direction": direction, "peakBank": peak_bank, "peakHeading": peak_heading,
		"bankBeforeReverse": bank_before_reverse, "finalBank": final_bank, "finalHeading": final_heading,
		"riderYawBeforeReverse": rider_yaw_before_reverse,
		"contacts": contacts, "automaticTarget": automatic_target, "frontForce": max_front_force,
		"maxTorque": max_torque, "verticalTravel": bike.chassis.global_position.y - origin.y,
		"maxRiderTorque": max_rider_torque,
		"crashed": final.crashed, "samples": samples}
	results.append(result)
	print("RIDEABILITY %s: bank peak %.1fdeg, yaw peak %.1fdeg, bank after reversal %.1fdeg" % [result.label, rad_to_deg(peak_bank), rad_to_deg(peak_heading), rad_to_deg(final_bank)])
	_check(contacts == 0 and max_front_force < 0.000001, String(result.label) + " remains fully unsupported without tire forces")
	_check(automatic_target < 0.000001, String(result.label) + " has no airborne balance or heading target")
	_check(max_torque <= 45.001, String(result.label) + " retains bounded physical handlebar torque")
	_check(max_rider_torque <= float(cfg.Rider.MaxReactionTorque) + 0.001, String(result.label) + " keeps torso articulation inside the physical muscle-torque budget")
	_check(float(result.verticalTravel) < -9.0 and not bool(final.crashed), String(result.label) + " follows native gravity while the rider stays mounted")
	_check(bike.chassis.global_transform.is_finite() and bike.rider_body.global_transform.is_finite(), String(result.label) + " preserves separate finite bike and rider bodies")
	if direction == 0.0:
		_check(peak_bank < deg_to_rad(2.0) and peak_heading < deg_to_rad(2.0), "Neutral airborne input invents no whip")
	elif body_only:
		_check(absf(rider_yaw_before_reverse) > deg_to_rad(6.0), String(result.label) + " twists the actual rider torso independently of steering and bike lean")
		_check(peak_heading > deg_to_rad(2.0), String(result.label) + " exchanges real yaw momentum with the chassis")
	else:
		_check(absf(bank_before_reverse) > deg_to_rad(5.0) and peak_heading > deg_to_rad(3.0), String(result.label) + " creates measurable native bank and yaw instead of a cosmetic animation")
		_check(absf(final_bank) < absf(bank_before_reverse) * 0.7, String(result.label) + " opposite rider input brings the whip back through actual dynamics")
	return result

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	# Both directions, multiple surfaces/speeds, and a separately moving rider
	# make symmetry, traction and release response observable beyond a held key.
	for speed: float in [4.0, 8.0, 12.0]:
		for direction: float in [-1.0, 1.0]:
			# A 4m/s coasting bike loses >2m/s across this nine-second maneuver;
			# use a real first-gear throttle rider to test steering AT slow pace,
			# rather than demand riding-speed bank from a nearly stopped bike.
			await _analog_case(speed, direction * 0.5, "hardpack", false, 1 if speed == 4.0 else 0)
	for direction: float in [-1.0, 1.0]:
		await _analog_case(8.0, direction * 0.25, "dirt", true)
		await _analog_case(8.0, direction * 0.5, "dirt", true, 2)
	await _analog_case(8.0, 0.4, "dirt", false, 2, "front_brake")
	await _analog_case(8.0, -0.4, "dirt", false, 2, "rear_brake")
	await _air_case(0.0)
	var left := await _air_case(-1.0)
	var right := await _air_case(1.0)
	_check(float(left.bankBeforeReverse) * float(right.bankBeforeReverse) < 0.0,
		"Opposite airborne commands produce opposite native bank")
	_check(absf(absf(float(left.bankBeforeReverse)) - absf(float(right.bankBeforeReverse))) < deg_to_rad(3.0),
		"Left and right airborne response are reasonably symmetric")
	var body_left := await _air_case(-1.0, true)
	var body_right := await _air_case(1.0, true)
	_check(float(body_left.riderYawBeforeReverse) * float(body_right.riderYawBeforeReverse) < 0.0,
		"Independent left and right hip movement twists the physical torso in opposite directions")
	_check(absf(absf(float(body_left.riderYawBeforeReverse)) - absf(float(body_right.riderYawBeforeReverse))) < deg_to_rad(3.0),
		"Independent airborne hip-yaw response is reasonably symmetric")
	var report := {"checks": checks, "failures": failures, "configuration": cfg,
		"controllerHash": String((load("res://scripts/bike_controller.gd") as Script).source_code).sha256_text(), "results": results}
	DirAccess.make_dir_recursive_absolute("res://build")
	var file := FileAccess.open("res://build/rideability-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Native analog/air rideability: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
