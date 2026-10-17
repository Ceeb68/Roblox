extends SceneTree
## Real launches and abrupt analog transitions. No rolling state is seeded;
## automatic boots, the manual clutch, drivetrain, rider and Jolt contacts all
## remain active from the stationary mount through both corner exits.
const Bike = preload("res://scripts/bike_controller.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
const HZ := 240.0
var world: Node3D
var bike: Node3D
var cfg: Dictionary
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame

func _check(value: bool, label: String, detail: String = "") -> void:
	checks += 1
	if not value:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("STEERING TRANSITION FAIL: " + failures[-1])

func _fixture() -> void:
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
	shape.size = Vector3(2000.0, 0.5, 2000.0)
	collision.shape = shape
	ground.add_child(collision)
	world.add_child(ground)
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.82, 0.0)))

func _case(direction: float, amount: float, standing: bool) -> void:
	await _fixture()
	var input: RefCounted = RiderInput.new()
	input.standing = standing
	for i: int in range(480):
		input.update_auto_feet(1.0 / HZ, bike.get_telemetry())
		bike.set_controls(input.packet())
		await _tick()
	_check(bike.shift_gear(1), "Stationary transition fixture selects first with its real clutch pulled")
	var label := "%s %s %.2f" % ["left" if direction < 0.0 else "right", "standing" if standing else "seated", amount]
	var max_bank := 0.0
	var response := INF
	var first_mean := 0.0
	var reverse_mean := 0.0
	var first_samples := 0
	var reverse_samples := 0
	var neutral_opposite := 0.0
	var final_bank_sum := 0.0
	var final_rate_max := 0.0
	var final_samples := 0
	var max_torque := 0.0
	var first_distance := 0.0
	var completed := 0
	var start: Vector3 = bike.chassis.global_position
	var samples: Array[Dictionary] = []
	for i: int in range(3840):
		var time := float(i) / HZ
		input.steer = direction * amount if time >= 3.0 and time < 6.0 else (-direction * amount if time >= 9.0 and time < 12.0 else 0.0)
		input.throttle = minf(time * 0.5, 0.5)
		input.clutch = maxf(1.0 - time / 0.7, 0.0)
		input.update_auto_feet(1.0 / HZ, bike.get_telemetry())
		bike.set_controls(input.packet())
		await _tick()
		completed += 1
		var state: Dictionary = bike.get_telemetry()
		var bank := float(state.roll)
		max_bank = maxf(max_bank, absf(bank))
		max_torque = maxf(max_torque, absf(float(state.riderSteeringTorque)))
		if time >= 3.0 and time < 6.0 and response == INF and bank * direction > deg_to_rad(3.0):
			response = time - 3.0
		if time >= 4.5 and time < 6.0:
			first_mean += bank * direction
			first_samples += 1
		if time >= 10.5 and time < 12.0:
			reverse_mean -= bank * direction
			reverse_samples += 1
		if time >= 7.5 and time < 9.0:
			neutral_opposite = maxf(neutral_opposite, -bank * direction)
		if time >= 15.0:
			final_bank_sum += absf(bank)
			final_rate_max = maxf(final_rate_max, absf(float(state.bankRate)))
			final_samples += 1
		if i == 719:
			first_distance = start.distance_to(bike.chassis.global_position)
		if i % 120 == 119:
			samples.append({"s": time, "speed": state.speedMps, "bank": bank,
				"bankRate": state.bankRate, "target": state.riderTargetLean,
				"bar": state.steerAngle, "barTarget": state.steeringTarget,
				"headingRequest": state.headingCorrection, "torque": state.riderSteeringTorque,
				"frontLoad": state.frontLoad, "rearLoad": state.rearLoad,
				"feet": state.footDown, "position": str(bike.chassis.global_position)})
		if bool(state.crashed):
			break
	var final: Dictionary = bike.get_telemetry()
	var mean_final := final_bank_sum / maxf(final_samples, 1)
	var record := {"case": label, "completed": completed, "response": response,
		"firstBank": first_mean / maxf(first_samples, 1), "reverseBank": reverse_mean / maxf(reverse_samples, 1),
		"finalMeanAbsBank": mean_final, "finalMaxBankRate": final_rate_max,
		"neutralOpposite": neutral_opposite, "maxBank": max_bank, "maxTorque": max_torque,
		"firstDistance": first_distance, "crash": final.crashReason, "samples": samples}
	results.append(record)
	print("STEERING TRANSITION %s: response%.3fs, banks%.2f/%.2fdeg, final%.2fdeg rate%.3f, crash%s" % [label,
		response, rad_to_deg(float(record.firstBank)), rad_to_deg(float(record.reverseBank)), rad_to_deg(mean_final), final_rate_max, final.crashReason])
	_check(completed == 3840 and not bool(final.crashed), label + " rides both actual corners and exits without recovery", str(final.crashReason))
	_check(first_distance > 4.0 and not bool(final.footDown), label + " launches through real drive and automatic foot retraction")
	_check(response < 0.65, label + " responds to an abrupt analog turn within 650 ms", str(response))
	_check(float(record.firstBank) > deg_to_rad(5.0) and float(record.reverseBank) > deg_to_rad(5.0), label + " holds both requested bank directions")
	_check(neutral_opposite < deg_to_rad(4.0), label + " releases without a forced opposite corner", str(rad_to_deg(neutral_opposite)))
	_check(mean_final < deg_to_rad(2.0), label + " settles to a predictable neutral bank", str(rad_to_deg(mean_final)))
	_check(final_rate_max < 0.12, label + " neutral reference does not hunt through rapid roll corrections", str(final_rate_max))
	_check(max_bank < deg_to_rad(55.0), label + " avoids an excessive bank from moderate steering")
	_check(max_torque <= 45.001, label + " uses finite handlebar torque instead of a pose constraint", str(max_torque))

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	for posture: bool in [false, true]:
		for direction: float in [-1.0, 1.0]:
			for amount: float in [0.25, 0.65]:
				await _case(direction, amount, posture)
	DirAccess.make_dir_recursive_absolute("res://build/v7-steering")
	var output := FileAccess.open("res://build/v7-steering/transitions-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "results": results,
		"controllerHash": String(bike.get_script().source_code).sha256_text(), "config": cfg}, "\t"))
	print("Native steering transition checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
