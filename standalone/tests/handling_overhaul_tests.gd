extends SceneTree
## Native handling acceptance A–F. Except the from-rest launch, fixtures seed
## coherent rolling speed once. Every later movement follows actual controls,
## five-body dynamics, native contacts and independent production tire forces.
## Thresholds are design acceptance goals, not measured commercial-game data.
const Bike = preload("res://scripts/bike_controller.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
var HZ := 240.0
var cfg: Dictionary
var world: Node3D
var bike: Node3D
var rider: RefCounted
var results: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("OVERHAUL HANDLING FAIL: " + failures[-1])

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _fixture(speed: float, gear: int, standing := false) -> void:
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
	var box := BoxShape3D.new()
	box.size = Vector3(1000.0, 0.5, 1000.0)
	collision.shape = box
	ground.add_child(collision)
	world.add_child(ground)
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0, 0.82, 0)))
	rider = RiderInput.new()
	rider.standing = standing
	var last_preparation_shift := -1.0
	for i in range(roundi(2.0 * HZ)):
		var elapsed := float(i) / HZ
		if elapsed > 0.5 and elapsed - last_preparation_shift > 0.15 and int(bike.get_telemetry().gear) < gear:
			bike.shift_gear(1)
			last_preparation_shift = elapsed
		bike.set_controls({"clutch": 1.0, "footDown": true, "standing": standing})
		await _tick()
	if speed > 0.0:
		for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
			body.linear_velocity = Vector3(0, 0, -speed)
			body.angular_velocity = Vector3.ZERO
			body.sleeping = false
		bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * speed / float(cfg.FrontRadius)
		bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * speed / float(cfg.RearRadius)
		bike.front_wheel.invalidate_load_history()
		bike.rear_wheel.invalidate_load_history()
		if gear > 0:
			bike.drive_state.engineOmega = speed / float(cfg.RearRadius) * float(cfg.Drive.PrimaryRatio) * float(cfg.Drive.FinalRatio) * float(cfg.Drive.GearRatios[gear - 1])
		bike.set_controls({"clutch": 1.0, "footDown": false, "standing": standing})
		await _tick()

func _heading() -> float:
	var forward: Vector3 = -bike.chassis.global_basis.z
	return atan2(forward.x, forward.z)

func _case(label: String, speed: float, gear: int, steer: float, power: bool, brake: bool, standing := false) -> Dictionary:
	await _fixture(speed, gear, standing)
	var start: Vector3 = bike.chassis.global_position
	var last_position := start
	var last_heading := _heading()
	var total_heading := 0.0
	var distance := 0.0
	var max_bank := 0.0
	var first_bank := -1.0
	var entry_bank := 0.0
	var mean_bank := 0.0
	var mean_front_slip := 0.0
	var mean_rear_slip := 0.0
	var mean_sideslip := 0.0
	var mean_speed := 0.0
	var peak_front_utilization := 0.0
	var peak_rear_utilization := 0.0
	var max_rear_ratio := 0.0
	var peak_front_load_fraction := 0.0
	var baseline_load_fraction := 0.0
	var baseline_samples := 0
	var normal_samples := 0
	var samples: Array[Dictionary] = []
	var total_ticks := 0
	var successful_shifts := 0
	var shift_frames := -1
	var duration := 8.0 if speed == 0.0 else 5.0
	for i in range(roundi(duration * HZ)):
		var t := float(i) / HZ
		var before: Dictionary = bike.get_telemetry()
		if i == roundi(0.3 * HZ):
			entry_bank = float(before.roll)
		var request := steer * smoothstep(0.3, 0.55, t) * (1.0 - smoothstep(3.25, 3.5, t))
		var throttle := 0.0
		var clutch := 1.0
		if power:
			throttle = clampf(0.25 + (speed - float(before.speedMps)) * 0.12, 0.08, 0.65) if speed > 0.0 else 0.7
			if "exit" in label:
				throttle = lerpf(0.25, 1.0, smoothstep(2.0, 2.3, t))
			clutch = maxf(0.0, 1.0 - t / 0.7)
			if shift_frames >= 0:
				clutch = 1.0
				shift_frames += 1
				if shift_frames >= roundi(HZ / 12.0):
					if bike.shift_gear(1):
						successful_shifts += 1
					shift_frames = -1
			elif float(before.rpm) > 10500.0 and int(before.gear) < 4 and clutch < 0.1:
				shift_frames = 0
		rider.throttle = throttle
		rider.clutch = clutch
		rider.steer = request
		rider.front_brake = 0.38 * smoothstep(0.5, 0.8, t) if brake else 0.0
		rider.rear_brake = 0.18 * smoothstep(0.5, 0.8, t) if brake else 0.0
		rider.update_auto_feet(1.0 / HZ, before)
		bike.set_controls(rider.packet())
		await _tick()
		total_ticks += 1
		var state: Dictionary = bike.get_telemetry()
		var p: Vector3 = bike.chassis.global_position
		distance += p.distance_to(last_position)
		last_position = p
		var heading := _heading()
		total_heading += wrapf(heading - last_heading, -PI, PI)
		last_heading = heading
		max_bank = maxf(max_bank, absf(float(state.roll)))
		if first_bank < 0.0 and float(state.roll) * signf(steer) > deg_to_rad(5.0) and (float(state.roll) - entry_bank) * signf(steer) > deg_to_rad(5.0) and t >= 0.3:
			first_bank = t - 0.3
		var local_velocity: Vector3 = bike.chassis.global_basis.inverse() * bike.chassis.linear_velocity
		var sideslip := atan2(local_velocity.x, maxf(0.1, -local_velocity.z))
		var front_fraction := float(state.frontLoad) / maxf(1.0, float(state.frontLoad) + float(state.rearLoad))
		if t < 0.5:
			baseline_load_fraction += front_fraction
			baseline_samples += 1
		elif brake:
			peak_front_load_fraction = maxf(peak_front_load_fraction, front_fraction)
		peak_front_utilization = maxf(peak_front_utilization, float(bike._front_result.utilization))
		peak_rear_utilization = maxf(peak_rear_utilization, float(bike._rear_result.utilization))
		max_rear_ratio = maxf(max_rear_ratio, absf(float(state.rearSlip)))
		if t >= 1.5 and t < 3.25:
			mean_bank += float(state.roll)
			mean_front_slip += absf(float(state.frontSlipAngle))
			mean_rear_slip += absf(float(state.rearSlipAngle))
			mean_sideslip += absf(sideslip)
			mean_speed += float(state.speedMps)
			normal_samples += 1
		if i % maxi(1, roundi(HZ / 10.0)) == 0:
			samples.append({"t": t, "speed": state.speedMps, "rollDeg": rad_to_deg(float(state.roll)), "headingDeg": rad_to_deg(total_heading),
				"frontSlipDeg": rad_to_deg(float(state.frontSlipAngle)), "rearSlipDeg": rad_to_deg(float(state.rearSlipAngle)),
				"sideslipDeg": rad_to_deg(sideslip), "rearRatio": state.rearSlip, "frontUtil": bike._front_result.utilization,
				"rearUtil": bike._rear_result.utilization, "frontLoad": state.frontLoad, "rearLoad": state.rearLoad,
				"frontCompression": state.frontCompression, "rearCompression": state.rearCompression, "steer": request, "throttle": throttle})
		if bike.crashed:
			break
	var divisor := float(maxi(normal_samples, 1))
	var final: Dictionary = bike.get_telemetry()
	var observation := {"label": label, "elapsed": float(total_ticks) / HZ, "crashed": bike.crashed, "reason": bike.crash_reason,
		"distanceM": distance, "finalSpeed": final.speedMps, "headingDeg": rad_to_deg(total_heading), "first5DegBankSeconds": first_bank,
		"entryBankDeg": rad_to_deg(entry_bank), "meanBankDeg": rad_to_deg(mean_bank / divisor), "maxBankDeg": rad_to_deg(max_bank), "finalBankDeg": rad_to_deg(float(final.roll)),
		"meanFrontSlipDeg": rad_to_deg(mean_front_slip / divisor), "meanRearSlipDeg": rad_to_deg(mean_rear_slip / divisor),
		"meanSideslipDeg": rad_to_deg(mean_sideslip / divisor), "meanSpeed": mean_speed / divisor,
		"radiusM": distance / maxf(0.00001, absf(total_heading)), "peakFrontUtil": peak_front_utilization,
		"peakRearUtil": peak_rear_utilization, "maxRearSlipRatio": max_rear_ratio,
		"baselineFrontLoadFraction": baseline_load_fraction / float(maxi(1, baseline_samples)), "peakBrakingFrontLoadFraction": peak_front_load_fraction,
		"successfulShifts": successful_shifts, "samples": samples}
	results.append(observation)
	var printable := observation.duplicate()
	printable.erase("samples")
	print("OVERHAUL GROUND ", JSON.stringify(printable))
	return observation

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hz="):
			HZ = clampf(float(argument.trim_prefix("--hz=")), 120.0, 480.0)
	Engine.physics_ticks_per_second = int(HZ)
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	var source_hash := String((load("res://scripts/bike_controller.gd") as GDScript).source_code).sha256_text()
	var config_hash := FileAccess.get_file_as_string("res://config/bike_250f.json").sha256_text()
	var launch := await _case("A straight from rest", 0.0, 1, 0.0, true, false)
	_check(not bool(launch.crashed) and float(launch.finalSpeed) > 12.0 and float(launch.distanceM) > 40.0,
		"A: actual first-gear launch and clutch shifts accelerate to useful riding speed", str(launch))
	_check(absf(float(launch.headingDeg)) < 4.0 and float(launch.maxBankDeg) < 8.0,
		"A: normal acceleration tracks straight with less than 4 degree drift and 8 degree bank", "heading=%.2f bank=%.2f" % [launch.headingDeg, launch.maxBankDeg])
	for direction: float in [-1.0, 1.0]:
		var side := "left" if direction < 0.0 else "right"
		var normal := await _case("B normal corner " + side, 12.0, 3, 0.35 * direction, true, false)
		_check(not bool(normal.crashed) and float(normal.elapsed) >= 5.0, "B: " + side + " ordinary corner completes without a fall")
		_check(float(normal.first5DegBankSeconds) >= 0.0 and float(normal.first5DegBankSeconds) < 0.55,
			"B: " + side + " ordinary turn reaches 5 degree bank within 0.55 seconds of input onset", str(normal.first5DegBankSeconds))
		_check(float(normal.meanFrontSlipDeg) < 5.0 and float(normal.meanRearSlipDeg) < 5.0 and float(normal.meanSideslipDeg) < 4.0,
			"B: " + side + " ordinary corner uses planted independent tire grip instead of sustained drift")
		_check(float(normal.headingDeg) * direction < -25.0 and float(normal.meanBankDeg) * direction > 10.0,
			"B: " + side + " bank produces a useful physical trajectory change")
		_check(absf(float(normal.finalBankDeg)) < 4.0, "B: " + side + " released steering recovers below 4 degree bank")
		var tight := await _case("C tight corner " + side, 4.0, 1, 0.8 * direction, true, false)
		_check(not bool(tight.crashed) and float(tight.elapsed) >= 5.0 and float(tight.radiusM) < 8.0 and float(tight.meanSpeed) > 2.5,
			"C: " + side + " walking-speed corner stays mobile with less than 8 metre effective radius", "radius=%.2f speed=%.2f" % [tight.radiusM, tight.meanSpeed])
		_check(float(tight.maxBankDeg) < 35.0 and float(tight.meanFrontSlipDeg) < 6.0 and float(tight.meanRearSlipDeg) < 6.0,
			"C: " + side + " tight turn remains supported by the actual tire patches")
		var sweep := await _case("D fast sweep " + side, 20.0, 5, 0.25 * direction, true, false)
		_check(not bool(sweep.crashed) and float(sweep.elapsed) >= 5.0, "D: " + side + " fast sweep completes without washout")
		_check(float(sweep.first5DegBankSeconds) >= 0.0 and float(sweep.first5DegBankSeconds) < 0.65,
			"D: " + side + " fast sweep reaches 5 degree bank within 0.65 seconds", str(sweep.first5DegBankSeconds))
		_check(float(sweep.meanFrontSlipDeg) < 5.0 and float(sweep.meanRearSlipDeg) < 5.0 and float(sweep.meanSideslipDeg) < 4.0,
			"D: " + side + " high-speed front and rear grip remain planted")
		_check(float(sweep.headingDeg) * direction < -10.0 and absf(float(sweep.finalBankDeg)) < 4.0,
			"D: " + side + " high-speed trajectory turns and returns predictably toward neutral")
		var exit := await _case("E exit full throttle " + side, 12.0, 3, 0.45 * direction, true, false)
		_check(not bool(exit.crashed) and float(exit.finalSpeed) > 18.0,
			"E: " + side + " hard corner exit transfers actual drive torque without a fall")
		_check(float(exit.maxRearSlipRatio) > float(normal.maxRearSlipRatio) + 0.03 and float(exit.maxRearSlipRatio) < 0.8,
			"E: " + side + " excessive throttle causes bounded rear spin beyond ordinary corner slip")
		_check(float(exit.meanFrontSlipDeg) < 5.0 and float(exit.meanRearSlipDeg) < 6.0,
			"E: " + side + " a loaded rear slide does not wash out the front line")
	var braking := await _case("F progressive braking", 15.0, 0, 0.0, false, true)
	_check(not bool(braking.crashed) and float(braking.finalSpeed) < 7.0 and float(braking.maxBankDeg) < 8.0,
		"F: progressive independent brakes slow 15 m/s below 7 m/s while upright")
	_check(float(braking.peakBrakingFrontLoadFraction) - float(braking.baselineFrontLoadFraction) > 0.10,
		"F: real braking transfers at least ten percentage points of load toward the fork")
	var standing := await _case("B normal corner standing", 12.0, 3, 0.35, true, false, true)
	_check(not bool(standing.crashed) and float(standing.first5DegBankSeconds) >= 0.0 and float(standing.first5DegBankSeconds) < 0.55,
		"B: standing rider keeps the same ordinary turn response and completes the corner", str(standing.first5DegBankSeconds))
	_check(float(standing.meanFrontSlipDeg) < 5.0 and float(standing.meanRearSlipDeg) < 5.0 and absf(float(standing.finalBankDeg)) < 4.0,
		"B: actual standing rider corner remains planted and releases predictably")
	var output := FileAccess.open("res://build/handling-overhaul-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "physicsHz": HZ, "controllerHash": source_hash, "configHash": config_hash, "results": results}, "\t"))
	print("Overhaul handling acceptance: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
