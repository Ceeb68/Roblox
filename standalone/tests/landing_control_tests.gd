extends SceneTree
## Powered from rest through both shipped tabletops, with a deliberate forward
## air input over the big jump. Only native reset initializes the bodies; every
## later movement comes from real controls, contacts and finite rider muscles.
const Bike = preload("res://scripts/bike_controller.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
const Track = preload("res://scripts/track_builder.gd")
const HZ := 240.0
var world: Node3D
var bike: Node3D
var rider: RefCounted
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("LANDING CONTROL FAIL: " + failures[-1])

func _release() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("mx_"):
			Input.action_release(action)

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	var prefer_standing := "--standing" in OS.get_cmdline_user_args()
	var throttle_chop := "--chop" in OS.get_cmdline_user_args()
	var source := FileAccess.get_file_as_string("res://config/bike_250f.json")
	var cfg: Dictionary = JSON.parse_string(source)
	world = Node3D.new()
	root.add_child(world)
	Track.build(world)
	rider = RiderInput.new()
	_release()
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis(Vector3.UP, PI), Vector3(46.0, 0.95, 35.0)))
	for _i: int in range(240):
		rider.tick(1.0 / HZ, true)
		rider.update_auto_feet(1.0 / HZ, bike.get_telemetry())
		bike.set_controls(rider.packet())
		await _tick()
	_check(bike.shift_gear(1), "Powered landing rider selects first gear with the real clutch pulled")
	Input.action_press("mx_throttle")
	Input.action_press("mx_clutch_release")
	var recipe: Dictionary = Track.EXTENSION_JUMPS[1]
	var height := float(recipe.height)
	var lip := float(recipe.start) + float(recipe.takeoff)
	var finish := lip + float(recipe.deck) + float(recipe.landing)
	var steady_limit := float(cfg.VirtualRider.MaxTorque)
	var catch_limit := float(cfg.VirtualRider.MaxLandingCatchTorque)
	var catch_duration := float(cfg.VirtualRider.LandingCatchTime)
	var shift_wait := -1
	var last_shift := -10000
	var successful_shifts := 0
	var rejected_shifts := 0
	var air_frames := 0
	var longest_air := 0
	var full_air_frames := 0
	var flight_start := -1.0
	var first_loaded_touchdown := -1.0
	var body_commanded := false
	var both_supported := false
	var feet_raised := false
	var big_catch_seen := false
	var catch_expired := false
	var ordinary_sample_seen := false
	var air_sample_seen := false
	var illegal_catch := 0
	var illegal_air := 0
	var max_torque_excess := 0.0
	var max_budget_excess := 0.0
	var max_grip_excess := 0.0
	var max_unsupported_force := 0.0
	var max_bank := 0.0
	var max_air_bank := 0.0
	var max_pitch := 0.0
	var min_pitch := 0.0
	var peak_height := 0.0
	var max_front_travel := 0.0
	var max_rear_travel := 0.0
	var min_corridor_clearance := INF
	var peak_torque := 0.0
	var peak_limit := 0.0
	var samples: Array[Dictionary] = []
	for i: int in range(6000):
		var time := float(i) / HZ
		var observation: Dictionary = bike.get_telemetry()
		if prefer_standing and float(observation.speedMps) > 6.0:
			rider.standing = true
		if shift_wait >= 0:
			shift_wait += 1
			if shift_wait == 20:
				if bike.shift_gear(1):
					successful_shifts += 1
				else:
					rejected_shifts += 1
				Input.action_release("mx_clutch_quick")
				shift_wait = -1
				last_shift = i
		elif float(observation.rpm) > 9500.0 and float(observation.clutch) < 0.05 \
				and int(observation.gear) < 3 and i - last_shift > 180:
			Input.action_press("mx_clutch_quick")
			shift_wait = 0
		rider.tick(1.0 / HZ, true)
		rider.update_auto_feet(1.0 / HZ, observation)
		var packet: Dictionary = rider.packet()
		if flight_start >= 0.0 and time - flight_start >= 0.1:
			packet.bodyForward = 0.35
			if throttle_chop and not body_commanded:
				# Real keyboard throttle release follows the shipped progressive
				# input response; clutch remains engaged and engine braking stays.
				Input.action_release("mx_throttle")
			body_commanded = true
		bike.set_controls(packet)
		await _tick()
		var state: Dictionary = bike.get_telemetry()
		var position: Vector3 = bike.chassis.global_position
		var unsupported := not bool(state.frontContact) and not bool(state.rearContact)
		full_air_frames = full_air_frames + 1 if unsupported else 0
		if position.z > lip - 2.0 and position.y > height and unsupported:
			air_frames += 1
			longest_air = maxi(longest_air, air_frames)
			if flight_start < 0.0 and air_frames >= 8:
				flight_start = time - float(air_frames - 1) / HZ
		else:
			air_frames = 0
		if flight_start >= 0.0 and time - flight_start > 0.2 and position.z > lip \
				and (float(state.frontLoad) > 0.0 or float(state.rearLoad) > 0.0) \
				and first_loaded_touchdown < 0.0:
			first_loaded_touchdown = time
		if first_loaded_touchdown >= 0.0 and float(state.frontLoad) > 100.0 and float(state.rearLoad) > 100.0:
			both_supported = true
		feet_raised = feet_raised or (float(state.speedMps) > 2.0 and not bool(state.footDown))
		var limit := float(state.activeTorqueLimit)
		var remaining := float(state.landingCatchRemaining)
		var torque := absf(float(state.riderSteeringTorque))
		peak_torque = maxf(peak_torque, torque)
		peak_limit = maxf(peak_limit, limit)
		max_torque_excess = maxf(max_torque_excess, torque - limit)
		if limit > steady_limit + 0.001:
			if not bool(state.frontContact) or float(state.frontLoad) <= 0.0 or remaining <= 0.0 \
					or remaining > catch_duration + 0.00001 or limit > catch_limit + 0.00001:
				illegal_catch += 1
			if first_loaded_touchdown >= 0.0:
				big_catch_seen = true
		else:
			ordinary_sample_seen = true
		if first_loaded_touchdown >= 0.0 and time - first_loaded_touchdown > catch_duration + 0.2 \
				and remaining <= 0.00001 and absf(limit - steady_limit) < 0.00001:
			catch_expired = true
		if unsupported:
			air_sample_seen = true
			max_air_bank = maxf(max_air_bank, absf(float(state.roll)))
			if absf(limit - steady_limit) > 0.00001 or torque > steady_limit + 0.00001:
				illegal_air += 1
			if float(full_air_frames) / HZ > 0.25 and \
					absf(float(state.riderTargetLean)) + absf(float(state.headingCorrection)) > 0.000001:
				illegal_air += 1
		for wheel_pair: Array in [[bike.front_wheel, bike._front_result], [bike.rear_wheel, bike._rear_result]]:
			var wheel: RigidBody3D = wheel_pair[0]
			var tire: Dictionary = wheel_pair[1]
			var force_x := float(tire.longitudinalForce)
			var force_y := float(tire.lateralForce)
			var magnitude := sqrt(force_x * force_x + force_y * force_y)
			max_budget_excess = maxf(max_budget_excess, magnitude - float(tire.grip) * wheel.normal_load)
			if wheel.normal_load > 0.0:
				var surface: Dictionary = cfg.Surfaces.get(wheel.surface, cfg.Surfaces.dirt)
				var expected_grip := float(surface.Grip) * clampf(
					(wheel.normal_load / float(cfg.Tire.ReferenceLoad)) ** -float(cfg.Tire.LoadSensitivity), 0.5, 1.5)
				max_grip_excess = maxf(max_grip_excess, float(tire.grip) - expected_grip)
			if not wheel.contact or wheel.normal_load <= 0.0:
				max_unsupported_force = maxf(max_unsupported_force, magnitude)
		max_bank = maxf(max_bank, absf(float(state.roll)))
		max_pitch = maxf(max_pitch, float(state.pitch))
		min_pitch = minf(min_pitch, float(state.pitch))
		peak_height = maxf(peak_height, position.y)
		max_front_travel = maxf(max_front_travel, float(state.frontCompression))
		max_rear_travel = maxf(max_rear_travel, float(state.rearCompression))
		var half_width := Track._ribbon_road_half_width({"center": Vector2(46.0, position.z)})
		min_corridor_clearance = minf(min_corridor_clearance,
			half_width + float(Track.SHOULDER_WIDTH) - absf(position.x - 46.0))
		if i % 24 == 0:
			samples.append({"time": time, "position": str(position), "roll": rad_to_deg(float(state.roll)),
				"pitch": rad_to_deg(float(state.pitch)), "frontLoad": state.frontLoad, "rearLoad": state.rearLoad,
				"torque": torque, "activeLimit": limit, "catchRemaining": remaining, "bodyInput": packet.bodyForward})
		if bike.crashed or position.z > finish + 15.0:
			break
	_release()
	var final: Dictionary = bike.get_telemetry()
	_check(successful_shifts == 2 and rejected_shifts == 0 and int(final.gear) == 3,
		"From-rest approach uses real first/second/third gears and timed clutch shifts")
	_check(feet_raised and not bool(final.footDown), "Powered approach automatically raises supporting feet without a feet action")
	_check(flight_start >= 0.0 and float(longest_air) / HZ > 0.5 and peak_height > height + 0.7,
		"Powered bike clears the actual big-jump lip into sustained native flight")
	_check(body_commanded, "Rider applies the deliberate 0.35 forward air control during the big jump")
	_check(first_loaded_touchdown >= 0.0 and both_supported, "Big-jump landing restores positive loads at both independent tires")
	_check(not bike.crashed and bike.chassis.global_position.z > finish + 14.0,
		"Powered touchdown reaches the landing runout without a crash or recovery", str(bike.crash_reason))
	_check(max_bank < deg_to_rad(45.0), "Ordinary powered jump and landing avoid an excessive uncontrolled bank", str(rad_to_deg(max_bank)))
	_check(min_corridor_clearance > 0.45, "Powered takeoff, touchdown and runout remain inside prepared track and shoulders", str(min_corridor_clearance))
	_check(max_front_travel < float(cfg.Suspension.Front.Travel) + 0.04 and max_rear_travel < float(cfg.Suspension.Rear.Travel) + 0.04,
		"Both native shocks remain within their actual mechanical travel")
	_check(max_torque_excess < 0.00001, "All real handlebar torque stays inside its currently active finite muscle budget")
	_check(big_catch_seen and illegal_catch == 0 and peak_limit <= catch_limit + 0.00001,
		"Extra landing muscle is brief and requires actual positively loaded front contact")
	_check(catch_expired and ordinary_sample_seen, "Landing effort expires back to the ordinary 45 Nm limit")
	_check(air_sample_seen and illegal_air == 0, "Full flight keeps ordinary finite hands and receives no world-bank or landing alignment")
	_check(max_budget_excess < 0.00001 and max_grip_excess < 0.00000001 and max_unsupported_force < 0.000001,
		"Landing catch never increases tire mu, loaded grip budget or unsupported tire forces")
	var finite := true
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		finite = finite and body.global_transform.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
	_check(finite, "Powered landing leaves all five independent native bodies finite")
	var report := {"checks": checks, "failures": failures,
		"standing": prefer_standing, "tactic": "chop" if throttle_chop else "held",
		"controllerHash": String(bike.get_script().source_code).sha256_text(), "configHash": source.sha256_text(),
		"maxBankDegrees": rad_to_deg(max_bank), "maxAirBankDegrees": rad_to_deg(max_air_bank),
		"minPitchDegrees": rad_to_deg(min_pitch), "maxPitchDegrees": rad_to_deg(max_pitch),
		"airSeconds": float(longest_air) / HZ, "firstLoadedTouchdown": first_loaded_touchdown,
		"peakTorqueNm": peak_torque, "peakLimitNm": peak_limit,
		"maxTireBudgetExcessN": max_budget_excess, "maxGripCoefficientExcess": max_grip_excess,
		"unsupportedTireForceN": max_unsupported_force,
		"minCorridorClearance": min_corridor_clearance, "finalPosition": str(bike.chassis.global_position),
		"crashed": bike.crashed, "reason": bike.crash_reason, "samples": samples}
	var output := FileAccess.open("res://build/landing-control-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("POWERED LANDING ", JSON.stringify({"standing": prefer_standing, "tactic": report.tactic,
		"bank": report.maxBankDegrees, "air": report.airSeconds,
		"torque": peak_torque, "limit": peak_limit, "position": report.finalPosition, "reason": bike.crash_reason}))
	print("Powered landing control: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
