extends SceneTree
## Native controllability observations use the actual controller endpoint map.
## A rolling/airborne initial state is seeded once; all later motion comes
## from the separate rigid bodies, contacts and finite rider actuators.
## Run with -- --baseline to compare the saved v0.4 implementation. Baseline
## mode records observations, while production mode checks useful response.
## --mirror repeats the ground stick grid in the opposite direction.

const ProductionBike = preload("res://scripts/bike_controller.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
const HZ := 240.0
var cfg: Dictionary
var bike_script: Script
var world: Node3D
var bike: Node3D
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var baseline := false

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _check(condition: bool, label: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("CONTROLLABILITY FAIL: " + failures[-1])

func _heading() -> float:
	var forward: Vector3 = -bike.chassis.global_basis.z
	return atan2(forward.x, forward.z)

func _fixture(speed: float, standing: bool, airborne := false) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await _tick()
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.position.y = -0.25
	ground.set_meta("physics_surface", "dirt")
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	ground.physics_material_override = material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 0.5, 1000.0)
	collision.shape = shape
	ground.add_child(collision)
	world.add_child(ground)
	bike = bike_script.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0, 0.82, 0)))
	bike.set_controls({"clutch": 1.0, "footDown": true, "standing": standing})
	for _i: int in range(482):
		await _tick()
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		if airborne:
			body.global_position += Vector3(0, 50, 0)
		body.linear_velocity = Vector3(0, 0, -speed)
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * speed / float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * speed / float(cfg.RearRadius)
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	if airborne:
		# Contacts belong to the old floor pose. Applying an old patch force
		# through a 50 m stale lever arm would fabricate an endo in the fixture.
		bike.front_wheel.clear_contact()
		bike.rear_wheel.clear_contact()
	bike.set_controls({"clutch": 1.0, "footDown": false, "standing": standing})
	await _tick()

func _ground_case(speed: float, raw_stick: float, standing: bool, raw_body := 0.0, feet := false, rider_lean := 0.0) -> Dictionary:
	await _fixture(speed, standing)
	var mapping: RefCounted = Bindings.new(false)
	var request := signf(raw_stick) * float(mapping.axis_strength(absf(raw_stick), mapping.bindings.steer_right))
	var body_request := signf(raw_body) * float(mapping.axis_strength(absf(raw_body), mapping.bindings.body_right))
	var label := "%.0fm/s %s stick%.2f body%.2f lean%.2f%s" % [speed, "stand" if standing else "sit", raw_stick, raw_body, rider_lean, " default feet" if feet else ""]
	var direction := signf(raw_stick)
	var heading_start := _heading()
	var first_bank_response := INF
	var turn_heading := 0.0
	var total_heading := 0.0
	var previous_heading := heading_start
	var mean_bank := 0.0
	var mean_target := 0.0
	var mean_speed := 0.0
	var mean_yaw_rate := 0.0
	var mean_com_offset := 0.0
	var mean_bar_angle := 0.0
	var mean_samples := 0
	var max_bank := 0.0
	var max_opposite_release := 0.0
	var max_budget_excess := 0.0
	var max_unsupported_force := 0.0
	var max_torque := 0.0
	var first_bar_direction := 0.0
	var countersteer_ticks := 0
	var initial_pitch := float(bike.get_telemetry().pitch)
	var samples: Array[Dictionary] = []
	var ticks := 0
	var automatic_input: RefCounted = RiderInput.new() if feet and not baseline else null
	for i: int in range(1080):
		var time := float(i) / HZ
		var ramp := clampf((time - 0.25) / 0.3, 0.0, 1.0) if time < 3.0 else clampf((3.3 - time) / 0.3, 0.0, 1.0)
		var packet := {"steer": request * ramp, "bodySide": body_request * ramp,
			"lean": rider_lean * ramp, "bodyForward": 0.0, "clutch": 1.0, "footDown": feet, "standing": standing}
		if automatic_input != null:
			automatic_input.steer = request * ramp
			automatic_input.body_side = body_request * ramp
			automatic_input.lean = rider_lean * ramp
			automatic_input.standing = standing
			automatic_input.update_auto_feet(1.0 / HZ, bike.get_telemetry())
			packet = automatic_input.packet()
		bike.set_controls(packet)
		await _tick()
		ticks += 1
		var t: Dictionary = bike.get_telemetry()
		var heading := _heading()
		var delta_heading := wrapf(heading - previous_heading, -PI, PI)
		previous_heading = heading
		total_heading += delta_heading
		if time >= 0.25 and time < 3.0:
			turn_heading += delta_heading
		if time >= 0.25 and float(t.roll) * direction > deg_to_rad(3.0) and first_bank_response == INF:
			first_bank_response = time - 0.25
		if time >= 2.0 and time < 3.0:
			mean_bank += float(t.roll)
			mean_target += float(t.riderTargetLean)
			mean_speed += float(t.speedMps)
			mean_yaw_rate += float(t.headingRate)
			mean_com_offset += bike.chassis.to_local(bike._sprung_com()).x
			mean_bar_angle += float(t.steerAngle)
			mean_samples += 1
		if time >= 0.25 and time < 0.75:
			if float(t.steerAngle) * direction < -deg_to_rad(0.25):
				countersteer_ticks += 1
			if i == 143:
				first_bar_direction = float(t.steerAngle)
		if time >= 3.3:
			max_opposite_release = maxf(max_opposite_release, -direction * float(t.roll))
		max_bank = maxf(max_bank, absf(float(t.roll)))
		max_torque = maxf(max_torque, absf(float(t.riderSteeringTorque)))
		for wheel_result: Array in [[bike.front_wheel, bike._front_result], [bike.rear_wheel, bike._rear_result]]:
			var wheel: RigidBody3D = wheel_result[0]
			var force: Dictionary = wheel_result[1]
			# Tire scalars use 64-bit GDScript floats. A Vector2 would round
			# saturated kilonewton forces to 32-bit before checking their budget.
			var force_x := float(force.longitudinalForce)
			var force_y := float(force.lateralForce)
			var tangential := sqrt(force_x * force_x + force_y * force_y)
			max_budget_excess = maxf(max_budget_excess, tangential - float(force.grip) * float(wheel.normal_load))
			if not wheel.contact or wheel.normal_load <= 0.0:
				max_unsupported_force = maxf(max_unsupported_force, tangential)
		if i % 120 == 119:
			samples.append({"time": time, "roll": t.roll, "pitch": t.pitch, "target": t.riderTargetLean,
				"speed": t.speedMps, "headingRate": t.headingRate, "barAngle": t.steerAngle,
				"bodyCOM": bike.chassis.to_local(bike._sprung_com()).x,
				"frontSlip": t.frontSlipAngle, "rearSlip": t.rearSlipAngle,
				"frontLoad": t.frontLoad, "rearLoad": t.rearLoad, "feet": t.footDown})
		if bool(t.crashed):
			break
	var count := maxf(1.0, mean_samples)
	mean_bank /= count
	mean_target /= count
	mean_speed /= count
	mean_yaw_rate /= count
	mean_com_offset /= count
	mean_bar_angle /= count
	var final: Dictionary = bike.get_telemetry()
	var result := {"label": label, "speed": speed, "rawStick": raw_stick, "mappedStick": request,
		"rawBody": raw_body, "riderLean": rider_lean, "standing": standing, "defaultFeet": feet, "ticks": ticks,
		"meanBank": mean_bank, "meanTarget": mean_target, "meanSpeed": mean_speed,
		"meanYawRate": mean_yaw_rate, "meanCOM": mean_com_offset, "meanBarAngle": mean_bar_angle,
		"turnHeading": turn_heading, "totalHeading": total_heading, "response": first_bank_response,
		"maxBank": max_bank, "oppositeRelease": max_opposite_release,
		"maxTorque": max_torque, "budgetExcess": max_budget_excess, "unsupportedForce": max_unsupported_force,
		"countersteerTicks": countersteer_ticks, "firstBarAngle": first_bar_direction,
		"initialPitch": initial_pitch, "crashed": final.crashed, "crashReason": final.crashReason,
		"samples": samples}
	results.append(result)
	print("CONTROL %s mapped%.3f: bank %.1f target %.1f yaw %.2fdeg/s turn %.1fdeg response %.2fs counter%d crash %s" % [label, request,
		rad_to_deg(mean_bank), rad_to_deg(mean_target), rad_to_deg(mean_yaw_rate), rad_to_deg(turn_heading), first_bank_response,
		countersteer_ticks, str(final.crashReason) if bool(final.crashed) else "none"])
	if not baseline:
		_check(not bool(final.crashed) and ticks == 1080, label + " completes an ordinary partial-stick maneuver", str(final.crashReason))
		_check(mean_bank * direction > deg_to_rad(2.0), label + " reaches a visible bank")
		_check(mean_yaw_rate * direction > deg_to_rad(1.0), label + " turns in the requested direction at useful speed")
		_check(first_bank_response < 1.0, label + " produces visible bank within one second from a partial stick", str(first_bank_response))
		_check(countersteer_ticks > 0, label + " physically countersteers during turn entry")
		_check(max_opposite_release < deg_to_rad(4.0), label + " releases without unwanted opposite bank")
		_check(max_torque <= float(cfg.VirtualRider.MaxTorque) + 0.001, label + " keeps finite handlebar muscle torque")
		_check(max_budget_excess < 0.00001 and max_unsupported_force < 0.000001, label + " respects actual loaded contact traction")
		if feet:
			_check(not bool(final.footDown), label + " automatically places feet on pegs while moving")
			_check(bike._feet.all(func(foot: CollisionShape3D) -> bool: return foot.disabled), label + " disables actual ground foot collisions while riding")
	return result

func _air_case(raw_body: float, standing: bool) -> Dictionary:
	await _fixture(20.0, standing, true)
	var mapping: RefCounted = Bindings.new(false)
	# Forward is the negative half of right-stick Y. A positive forward
	# request therefore reads its real binding at a negative axis value.
	var request := signf(raw_body) * float(mapping.axis_strength(-absf(raw_body), mapping.bindings.body_forward))
	var start_pitch := float(bike.get_telemetry().pitch)
	var pitch_before_reverse := 0.0
	var max_pitch := 0.0
	var max_rider_torque := 0.0
	var unsupported_force := 0.0
	var max_auto_target := 0.0
	var contacts := 0
	var samples: Array[Dictionary] = []
	for i: int in range(300):
		var time := float(i) / HZ
		var command := request if time < 0.5 else (-request if time < 1.0 else 0.0)
		bike.set_controls({"bodyForward": command, "steer": 0.0, "lean": 0.0, "bodySide": 0.0,
			"clutch": 1.0, "footDown": false, "standing": standing})
		await _tick()
		var t: Dictionary = bike.get_telemetry()
		var pitch := float(t.pitch) - start_pitch
		if i == 119:
			pitch_before_reverse = pitch
		max_pitch = maxf(max_pitch, absf(pitch))
		max_rider_torque = maxf(max_rider_torque, (t.riderPostureTorque as Vector3).length())
		max_auto_target = maxf(max_auto_target, absf(float(t.riderTargetLean)) + absf(float(t.headingCorrection)))
		contacts += int(bool(t.frontContact) or bool(t.rearContact))
		for tire_result: Dictionary in [bike._front_result, bike._rear_result]:
			var force_x := float(tire_result.longitudinalForce)
			var force_y := float(tire_result.lateralForce)
			unsupported_force = maxf(unsupported_force, sqrt(force_x * force_x + force_y * force_y))
		if i % 30 == 29:
			samples.append({"time": time, "command": command, "pitch": pitch, "bodyTarget": bike._body_forward,
				"riderPitch": (bike.chassis.global_basis.inverse() * bike.rider_body.global_basis).get_euler().x,
				"riderZ": bike.chassis.to_local(bike.rider_body.global_position).z, "rate": bike.chassis.angular_velocity.dot(bike.chassis.global_basis.x)})
	var final_pitch := float(bike.get_telemetry().pitch) - start_pitch
	var result := {"label": "air %s body%.2f" % ["stand" if standing else "sit", raw_body], "standing": standing,
		"rawBody": raw_body, "mappedBody": request, "pitchBeforeReverse": pitch_before_reverse,
		"finalPitch": final_pitch, "maxPitch": max_pitch, "maxRiderTorque": max_rider_torque,
		"automaticTarget": max_auto_target, "contacts": contacts, "unsupportedForce": unsupported_force, "samples": samples}
	results.append(result)
	print("CONTROL %s mapped%.3f: pitch %.2fdeg after .5s, reversed %.2fdeg, peak%.2f" % [result.label, request,
		rad_to_deg(pitch_before_reverse), rad_to_deg(final_pitch), rad_to_deg(max_pitch)])
	if not baseline:
		_check(contacts == 0 and unsupported_force < 0.000001, String(result.label) + " remains unsupported without ground forces")
		_check(max_auto_target < 0.000001, String(result.label) + " receives no airborne balance or landing correction")
		_check(max_rider_torque <= float(cfg.Rider.MaxReactionTorque) + 0.001, String(result.label) + " stays inside physical rider torque limits")
		if raw_body == 0.0:
			_check(max_pitch < deg_to_rad(10.0), String(result.label) + " avoids a large uncommanded airborne endo")
		elif absf(raw_body) >= 0.75:
			_check(absf(pitch_before_reverse) >= deg_to_rad(4.0), String(result.label) + " produces visible physical pitch response within half a second")
	return result

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	baseline = "--baseline" in OS.get_cmdline_user_args()
	bike_script = load("res://build/controllability-v5/baseline_controller.gd") if baseline else ProductionBike
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://build/controllability-v5/baseline_config.json" if baseline else "res://config/bike_250f.json"))
	if not "--air-only" in OS.get_cmdline_user_args():
		var grid_direction := -1.0 if "--mirror" in OS.get_cmdline_user_args() else 1.0
		for speed: float in [8.0, 12.0, 16.0, 20.0]:
			for posture: bool in [false, true]:
				for stick: float in [0.25, 0.5, 0.75, 1.0]:
					await _ground_case(speed, stick * grid_direction, posture)
		for posture: bool in [false, true]:
			var neutral := await _ground_case(12.0, -0.5, posture)
			var counterbalanced := await _ground_case(12.0, -0.5, posture, 0.5)
			var inside := await _ground_case(12.0, -0.5, posture, -0.5)
			var leaned_outside := await _ground_case(12.0, -0.5, posture, 0.0, false, 0.5)
			print("COUNTERBALANCE %s actual framebank baseline/outside/inside %.2f/%.2f/%.2fdeg, bodyCOM %.4f/%.4f/%.4fm" % [
				"stand" if posture else "sit", rad_to_deg(float(neutral.meanBank)), rad_to_deg(float(counterbalanced.meanBank)),
				rad_to_deg(float(inside.meanBank)), float(neutral.meanCOM), float(counterbalanced.meanCOM), float(inside.meanCOM)])
			if not baseline:
				_check(float(counterbalanced.meanBank) < float(neutral.meanBank) - deg_to_rad(1.0), "Counterbalancing torso right allows the bike to bank further left")
				_check(float(counterbalanced.meanCOM) > float(neutral.meanCOM) + 0.02, "Counterbalance moves the actual physical rider COM right")
				_check(float(leaned_outside.meanBank) < float(neutral.meanBank) - deg_to_rad(1.0), "Independent torso roll right also permits counterbalancing a left bike bank")
				_check(float(leaned_outside.meanCOM) > float(neutral.meanCOM) + 0.015, "Torso roll moves actual combined COM instead of adding the same-direction bike bank command")
		await _ground_case(12.0, 0.5, false, 0.0, true)
		await _ground_case(12.0, 0.5, true, 0.0, true)
	if not "--ground-only" in OS.get_cmdline_user_args():
		for posture: bool in [false, true]:
			var neutral := await _air_case(0.0, posture)
			for partial: float in [0.25, 0.50]:
				var partial_forward := await _air_case(partial, posture)
				var partial_backward := await _air_case(-partial, posture)
				if not baseline:
					var response_minimum := deg_to_rad(1.0 if partial == 0.25 else 2.0)
					_check(float(partial_forward.pitchBeforeReverse) - float(neutral.pitchBeforeReverse) < -response_minimum, "Partial forward air input physically lowers the nose relative to neutral")
					_check(float(partial_backward.pitchBeforeReverse) - float(neutral.pitchBeforeReverse) > response_minimum, "Partial backward air input physically raises the nose relative to neutral")
			var forward := await _air_case(0.75, posture)
			var backward := await _air_case(-0.75, posture)
			await _air_case(1.0, posture)
			await _air_case(-1.0, posture)
			if not baseline:
				_check(float(forward.pitchBeforeReverse) - float(neutral.pitchBeforeReverse) < -deg_to_rad(4.0), "Forward air input physically lowers the nose relative to neutral")
				_check(float(backward.pitchBeforeReverse) - float(neutral.pitchBeforeReverse) > deg_to_rad(4.0), "Backward air input physically raises the nose relative to neutral")
	var report := {"baseline": baseline, "mirrored": "--mirror" in OS.get_cmdline_user_args(), "checks": checks, "failures": failures, "config": cfg,
		"controllerHash": bike_script.source_code.sha256_text(), "results": results}
	DirAccess.make_dir_recursive_absolute("res://build/controllability-v5")
	var file := FileAccess.open("res://build/controllability-v5/%s-%d.json" % ["baseline" if baseline else "current", OS.get_process_id()], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Native practical controllability: %d passed, %d failed%s" % [checks - failures.size(), failures.size(), " (baseline observations only)" if baseline else ""])
	quit(0 if failures.is_empty() else 1)
