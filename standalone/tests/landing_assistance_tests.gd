extends SceneTree
## Observe the production aid during actual native wheel impacts. This class
## adds instrumentation only: the production callback applies its torque once.
class ObservedBike:
	extends "res://scripts/bike_controller.gd"
	var aid_observations: Array[Dictionary] = []
	func _apply_landing_assistance(input: Dictionary, dt: float) -> void:
		var prior_air := _loaded_air_time
		super._apply_landing_assistance(input, dt)
		aid_observations.append({"frame": Engine.get_physics_frames(),
			"supported": _has_support(), "frontContact": front_wheel.contact,
			"rearContact": rear_wheel.contact, "frontLoad": front_wheel.normal_load,
			"rearLoad": rear_wheel.normal_load, "frontNative": front_wheel.native_contact_count,
			"rearNative": rear_wheel.native_contact_count,
			"priorAir": prior_air, "remaining": _landing_assist_remaining,
			"dt": dt,
			"torque": _landing_assist_torque,
			"localTorque": chassis.global_basis.transposed() * _landing_assist_torque,
			"bank": _angles().x, "bankRate": _bank_rate(),
			"pitchRate": chassis.angular_velocity.dot(chassis.global_basis.x),
			"leanRateTarget": _lean_rate_target, "bodyForward": float(input.bodyForward),
			"mode": riding_mode, "crashed": crashed})

var cfg: Dictionary
var world: Node3D
var bike: ObservedBike
var checks := 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []
const HZ := 240.0

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	# One native update per observation, independent of render/process frames.
	await physics_frame

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("LANDING ASSIST FAIL: " + failures[-1])

func _fixture(pitch: float, bank: float, strength := 1.0, landing_strength := 1.0,
		mode := "virtual_rider", body_forward := 0.0, steer := 0.0, pitch_stiffness := -1.0) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await process_frame
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
	shape.size = Vector3(1000, 0.5, 1000)
	collision.shape = shape
	ground.add_child(collision)
	world.add_child(ground)
	var setup := cfg.duplicate(true)
	setup.Assistance.Strength = strength
	setup.Assistance.LandingStrength = landing_strength
	setup.Assistance.LowSpeedStrength = 0.0
	setup.AirControl.Strength = 0.0
	if pitch_stiffness >= 0.0:
		setup.Assistance.LandingPitchStiffness = pitch_stiffness
	bike = ObservedBike.new()
	bike.configure(setup)
	world.add_child(bike)
	bike.set_riding_mode(mode)
	var basis := Basis.from_euler(Vector3(pitch, 0, -bank))
	bike.reset_bike(Transform3D(basis, Vector3(0, 2.0, 0)))
	bike.set_controls({"throttle": 0.0, "clutch": 1.0, "footDown": false,
		"standing": false, "steer": steer, "bodyForward": body_forward})
	# Commit the reset before seeding one coherent initial flight velocity.
	await _tick()
	await _tick()
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.linear_velocity = Vector3(0, 0, -8)
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * 8.0 / float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * 8.0 / float(cfg.RearRadius)
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	bike.aid_observations.clear()

func _native_case(label: String, pitch: float, bank: float, strength := 1.0,
		landing_strength := 1.0, mode := "virtual_rider", body_forward := 0.0, steer := 0.0,
		pitch_stiffness := -1.0) -> Dictionary:
	await _fixture(pitch, bank, strength, landing_strength, mode, body_forward, steer, pitch_stiffness)
	var duration := float(bike.config.Assistance.get("LandingTime", 0.65))
	for _i in range(roundi((duration + 1.3) * HZ)):
		await _tick()
	var first_loaded := -1
	var first_active := -1
	var last_active := -1
	var maximum_torque := 0.0
	var maximum_pitch := 0.0
	var maximum_roll := 0.0
	var positive_pitch_work_rate := 0.0
	var maximum_yaw := 0.0
	var unsupported_torque := 0.0
	var window_excess := 0.0
	var window_age_excess := 0
	var timer_rearm_without_flight := false
	var active_window_start := -1
	var window_count := 0
	var previous_remaining := 0.0
	var gap_timer_error := 0.0
	var continued_gap_frames := 0
	var endpoint_pitch := 0.0
	var wrong_roll_damping := 0.0
	var roll_task_samples := 0
	var real_front := false
	var real_rear := false
	var front_first := false
	var rear_first := false
	var finite := true
	var expired_supported := false
	for observation: Dictionary in bike.aid_observations:
		var torque: Vector3 = observation.localTorque
		positive_pitch_work_rate = maxf(positive_pitch_work_rate, torque.x * float(observation.pitchRate))
		finite = finite and torque.is_finite() and is_finite(float(observation.remaining))
		maximum_torque = maxf(maximum_torque, torque.length())
		maximum_pitch = maxf(maximum_pitch, absf(torque.x))
		maximum_roll = maxf(maximum_roll, absf(torque.z))
		maximum_yaw = maxf(maximum_yaw, absf(torque.y))
		window_excess = maxf(window_excess, float(observation.remaining) - duration)
		var actual_new_flight := bool(observation.supported) and float(observation.priorAir) \
			>= float(bike.config.Assistance.get("LandingMinFlight", 0.2))
		if actual_new_flight:
			active_window_start = int(observation.frame)
			window_count += 1
		if float(observation.remaining) > previous_remaining + 0.00001 and not actual_new_flight:
			timer_rearm_without_flight = true
		if not bool(observation.supported) and not bool(observation.crashed) \
			and str(observation.mode) == "virtual_rider" and previous_remaining > float(observation.dt):
			continued_gap_frames += 1
			gap_timer_error = maxf(gap_timer_error,
				absf(float(observation.remaining) - maxf(0.0, previous_remaining - float(observation.dt))))
		previous_remaining = float(observation.remaining)
		if not bool(observation.supported):
			unsupported_torque = maxf(unsupported_torque, torque.length())
		if bool(observation.frontContact) and float(observation.frontLoad) > 1.0 and int(observation.frontNative) > 0:
			real_front = true
		if bool(observation.rearContact) and float(observation.rearLoad) > 1.0 and int(observation.rearNative) > 0:
			real_rear = true
		if first_loaded < 0 and bool(observation.supported):
			first_loaded = int(observation.frame)
			front_first = float(observation.frontLoad) > 1.0 and float(observation.rearLoad) <= 1.0
			rear_first = float(observation.rearLoad) > 1.0 and float(observation.frontLoad) <= 1.0
		if torque.length() > 0.001:
			if first_active < 0:
				first_active = int(observation.frame)
			last_active = int(observation.frame)
			window_age_excess = maxi(window_age_excess,
				int(observation.frame) - active_window_start - roundi(duration * HZ))
			# Positive local-Z torque reduces positive bank rate. Its product
			# with the measured player-task rate error must dissipate that error.
			var rate_error := float(observation.bankRate) - float(observation.leanRateTarget)
			wrong_roll_damping = maxf(wrong_roll_damping, -torque.z * rate_error)
			if absf(float(observation.leanRateTarget)) > 0.15:
				roll_task_samples += 1
		if absf(float(observation.bodyForward)) >= 0.999:
			endpoint_pitch = maxf(endpoint_pitch, absf(torque.x))
		if first_loaded >= 0 and int(observation.frame) - first_loaded > roundi((duration + 0.2) * HZ) \
			and bool(observation.supported) and float(observation.remaining) <= 0.0 and torque.length() == 0.0:
			expired_supported = true
	var enabled := strength > 0.0 and landing_strength > 0.0 and mode == "virtual_rider"
	_check(first_loaded >= 0 and (real_front or real_rear), label + " reaches positively loaded actual native wheel contact")
	_check(finite and maximum_torque <= float(bike.config.Assistance.get("LandingMaxTorque", 100.0)) * strength * landing_strength + 0.001,
		label + " remains inside its finite strength-scaled torque budget", str(maximum_torque))
	_check(maximum_yaw < 0.0001 and unsupported_torque == 0.0,
		label + " adds no local yaw torque or unsupported force")
	_check(window_excess < 0.00001 and expired_supported,
		label + " finite landing window expires despite held rider input")
	_check(gap_timer_error < 0.00001,
		label + " an unsupported rebound keeps counting down its window without applying torque")
	_check(wrong_roll_damping < 0.0001,
		label + " damps roll-rate error relative to the active player task")
	if enabled:
		_check(first_active >= first_loaded and maximum_torque > 1.0,
			label + " activates useful assistance only after a real flight and loaded touchdown")
		_check(window_age_excess <= 1 and not timer_rearm_without_flight,
			label + " held steering cannot prolong a window without a new sustained native flight")
	else:
		_check(maximum_torque == 0.0, label + " explicitly bypasses optional landing assistance")
	if absf(body_forward) >= 0.999:
		_check(endpoint_pitch < 0.0001, label + " full manual fore/aft input bypasses pitch correction")
	elif enabled and float(bike.config.Assistance.get("LandingPitchStiffness", 0.0)) > 0.0 and absf(pitch) > deg_to_rad(10.0):
		_check(maximum_pitch > 5.0, label + " actually exercises the terrain-relative pitch catch")
	if enabled and float(bike.config.Assistance.get("LandingPitchStiffness", 0.0)) == 0.0:
		_check(positive_pitch_work_rate < 0.0001,
			label + " default pitch damping dissipates rotation instead of seeking an upright pose", str(positive_pitch_work_rate))
	var report := {"label": label, "firstLoadedFrame": first_loaded, "firstActiveFrame": first_active,
		"lastActiveFrame": last_active, "peakTorqueNm": maximum_torque,
		"peakPitchTorqueNm": maximum_pitch, "peakRollTorqueNm": maximum_roll,
		"positivePitchWorkRateWatts": positive_pitch_work_rate,
		"pitchStiffness": float(bike.config.Assistance.get("LandingPitchStiffness", 0.0)),
		"frontObserved": real_front, "rearObserved": real_rear, "frontFirst": front_first,
		"rearFirst": rear_first, "rollTaskSamples": roll_task_samples,
		"windows": window_count, "continuedGapFrames": continued_gap_frames,
		"expiredSupported": expired_supported, "crashed": bike.crashed}
	reports.append(report)
	print("LANDING AID ", JSON.stringify(report))
	return report

func _recovery_lifecycle() -> void:
	await _fixture(deg_to_rad(12), deg_to_rad(8))
	var active := false
	for _i in range(360):
		await _tick()
		if bike._landing_assist_torque.length() > 1.0:
			active = true
			break
	_check(active, "Lifecycle fixture enters a real active native landing")
	bike._crash("Landing aid recovery fixture")
	_check(bike._landing_assist_torque == Vector3.ZERO and bike._landing_assist_remaining == 0.0 and bike._loaded_air_time == 0.0,
		"Crash immediately clears the landing wrench, timer and prior flight")
	for _i in range(30):
		await _tick()
	_check(bike._landing_assist_torque == Vector3.ZERO and bike._landing_assist_remaining == 0.0,
		"Crashed native motion cannot reactivate landing assistance")
	var recovered := bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0, 0.82, 0)), true)
	_check(recovered and bike._landing_assist_torque == Vector3.ZERO and bike._landing_assist_remaining == 0.0 \
		and bike._loaded_air_time == 0.0,
		"Forced recovery clears all prior landing state through the production reset path")
	var stale := false
	for _i in range(180):
		await _tick()
		stale = stale or bike._landing_assist_torque.length() > 0.0 or bike._landing_assist_remaining > 0.0
	_check(not stale, "A normal remount does not revive a stale pre-crash landing window")

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	var source := FileAccess.get_file_as_string("res://config/bike_250f.json")
	cfg = JSON.parse_string(source)
	var front := await _native_case("Nose-first drop", deg_to_rad(-12), deg_to_rad(6))
	var rear := await _native_case("Rear-first drop", deg_to_rad(12), deg_to_rad(-6))
	_check(bool(front.frontFirst) and bool(rear.rearFirst), "Opposite drop pitches exercise actual independent front/rear touchdown activation")
	var turning := await _native_case("Held voluntary bank", deg_to_rad(8), deg_to_rad(8), 1.0, 1.0, "virtual_rider", 0.0, 0.25)
	_check(int(turning.rollTaskSamples) > 0 and float(turning.peakRollTorqueNm) > 1.0,
		"Native landing actually corrects rate error around a nonzero player-requested lean task")
	await _native_case("Manual forward endpoint", deg_to_rad(-12), deg_to_rad(6), 1.0, 1.0, "virtual_rider", 1.0, 0.1)
	await _native_case("Manual backward endpoint", deg_to_rad(12), deg_to_rad(-6), 1.0, 1.0, "virtual_rider", -1.0, -0.1)
	await _native_case("Global assistance off", deg_to_rad(8), deg_to_rad(4), 0.0)
	await _native_case("Landing assistance off", deg_to_rad(-8), deg_to_rad(-4), 1.0, 0.0)
	await _native_case("Combined partial strengths", deg_to_rad(20), deg_to_rad(16), 0.5, 0.5)
	await _native_case("Optional arcade pitch spring", deg_to_rad(20), deg_to_rad(6),
		1.0, 1.0, "virtual_rider", 0.0, 0.0, 200.0)
	await _native_case("Direct mode", deg_to_rad(8), deg_to_rad(4), 1.0, 1.0, "direct")
	var native_gap_samples := 0
	for report: Dictionary in reports:
		native_gap_samples += int(report.continuedGapFrames)
	_check(native_gap_samples > 0, "Native impacts actually exercise unsupported rebound-window continuity")
	await _recovery_lifecycle()
	var controller_script: Script = (bike.get_script() as Script).get_base_script()
	var file := FileAccess.open("res://build/landing-assistance-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures,
		"configHash": source.sha256_text(), "controllerHash": controller_script.get_source_code().sha256_text(),
		"cases": reports}, "\t"))
	file.close()
	print("Landing assistance: %d checks, %d failures" % [checks, failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
