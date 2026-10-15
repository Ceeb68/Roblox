extends SceneTree
## Acceptance J: matched real takeoffs compare neutral, leaned and scrubbed
## riding. The whole five-body COM trajectory establishes a functional scrub;
## lowering the visual rider or forcing the bike down in flight cannot pass.
const Bike = preload("res://scripts/bike_controller.gd")
const Track = preload("res://scripts/track_builder.gd")
const HZ := 240.0
var world: Node3D
var bike: Node3D
var cfg: Dictionary
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var turn_entry_z := 170.0
var turn_amount := 0.65

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("SCRUB TAKEOFF FAIL: " + failures[-1])

func _assembly() -> Dictionary:
	var center := Vector3.ZERO
	var velocity := Vector3.ZERO
	var drag := Vector3.ZERO
	var mass := 0.0
	var sprung_mass: float = bike.chassis.mass + bike.rider_body.mass
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		mass += body.mass
		center += (body.global_transform * body.center_of_mass) * body.mass
		velocity += body.linear_velocity * body.mass
		if body == bike.chassis or body == bike.rider_body:
			drag -= body.linear_velocity * body.linear_velocity.length() * 0.31 * body.mass / sprung_mass
	return {"center": center / mass, "velocity": velocity / mass, "drag": drag, "mass": mass}

func _fixture(speed: float) -> void:
	if is_instance_valid(bike):
		bike.queue_free()
		await _tick()
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(Transform3D(Basis(Vector3.UP, PI), Vector3(46, 0.95, 145)))
	for i in range(480):
		if i in [120, 160, 200]:
			bike.shift_gear(1)
		bike.set_controls({"clutch": 1.0, "standing": true, "footDown": true})
		await _tick()
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		body.linear_velocity = Vector3(0, 0, speed)
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * speed / float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * speed / float(cfg.RearRadius)
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	bike.drive_state.engineOmega = speed / float(cfg.RearRadius) * float(cfg.Drive.PrimaryRatio) * float(cfg.Drive.FinalRatio) * float(cfg.Drive.GearRatios[2])
	bike.set_controls({"clutch": 1.0, "standing": true, "footDown": false})
	await _tick()

func _case(mode: String, direction: float, speed: float) -> Dictionary:
	await _fixture(speed)
	var source_hash := String(bike.get_script().source_code).sha256_text()
	var flight_start := -1.0
	var touchdown := -1.0
	var takeoff_com := Vector3.ZERO
	var takeoff_velocity := Vector3.ZERO
	var takeoff_bank := 0.0
	var takeoff_body_height := 0.0
	var takeoff_rider_relative_vy := 0.0
	var takeoff_frame_vy := 0.0
	var peak_com_height := -INF
	var unsupported_elapsed := 0.0
	var max_ballistic_error := 0.0
	var max_unsupported_tire_force := 0.0
	var max_unsupported_support_force := 0.0
	var max_ground_bank := 0.0
	var loaded_face_ticks := 0
	var airborne_ticks := 0
	var min_clearance := INF
	var face_normal_impulse := 0.0
	var samples: Array[Dictionary] = []
	var initial := _assembly()
	for i in range(2400):
		var time := float(i) / HZ
		var state: Dictionary = bike.get_telemetry()
		var position: Vector3 = bike.chassis.global_position
		var before := _assembly()
		var free := not bool(state.frontContact) and not bool(state.rearContact)
		var packet := {"standing": true, "footDown": false, "throttle": 0.5,
			"clutch": maxf(0.0, 1.0 - time / 0.75), "bodyForward": 0.0,
			"bodySide": 0.0, "lean": 0.0, "steer": 0.0, "scrub": 0.0}
		if flight_start < 0.0 and position.z >= turn_entry_z:
			packet.steer = direction * turn_amount if mode != "neutral" else 0.0
			packet.scrub = 1.0 if mode == "scrub" else 0.0
		if flight_start >= 0.0:
			# Identical player-style landing pilot in every case. Attitude torques
			# cannot fabricate a reduction in whole-assembly takeoff momentum.
			packet.bodyForward = clampf(float(state.pitch) * 0.9, -0.55, 0.55)
			packet.steer = clampf(-float(state.roll) * 1.5 - float(state.bankRate) * 0.4, -0.65, 0.65)
			var local_velocity: Vector3 = bike.chassis.global_basis.inverse() * bike.chassis.linear_velocity
			packet.bodySide = clampf(atan2(local_velocity.x, maxf(1.0, -local_velocity.z)) * 0.9, -0.45, 0.45)
			packet.throttle = 0.35
		bike.set_controls(packet)
		await _tick()
		var after := _assembly()
		var observed: Dictionary = bike.get_telemetry()
		var now_free := not bool(observed.frontContact) and not bool(observed.rearContact)
		unsupported_elapsed = unsupported_elapsed + 1.0 / HZ if now_free else 0.0
		if position.z >= 168.0 and position.z <= 189.0 and not free:
			loaded_face_ticks += 1
			max_ground_bank = maxf(max_ground_bank, absf(float(state.roll)))
			face_normal_impulse += (bike.front_wheel.contact_normal.y * float(state.frontLoad)
				+ bike.rear_wheel.contact_normal.y * float(state.rearLoad)) / HZ
		if flight_start < 0.0 and now_free and position.z > 187.0:
			flight_start = time
			takeoff_com = after.center
			takeoff_velocity = after.velocity
			takeoff_bank = float(observed.roll)
			takeoff_body_height = bike.chassis.to_local(bike.rider_body.global_transform * bike.rider_body.center_of_mass).y
			takeoff_rider_relative_vy = bike.rider_body.linear_velocity.y - bike.chassis.linear_velocity.y
			takeoff_frame_vy = bike.chassis.linear_velocity.y
		if flight_start >= 0.0 and touchdown < 0.0:
			peak_com_height = maxf(peak_com_height, (after.center as Vector3).y)
			if now_free:
				airborne_ticks += 1
			if time - flight_start > 0.15 and float(observed.frontLoad) + float(observed.rearLoad) > 50.0:
				touchdown = time
		if unsupported_elapsed > 0.08 and free and now_free:
			var expected: Vector3 = Vector3.DOWN * float(after.mass) * float(cfg.Gravity) + before.drag
			var measured: Vector3 = ((after.velocity as Vector3) - (before.velocity as Vector3)) * float(after.mass) * HZ
			max_ballistic_error = maxf(max_ballistic_error, (measured - expected).length())
			for result: Dictionary in [bike._front_result, bike._rear_result]:
				max_unsupported_tire_force = maxf(max_unsupported_tire_force,
					Vector2(float(result.longitudinalForce), float(result.lateralForce)).length())
			max_unsupported_support_force = maxf(max_unsupported_support_force, float(bike.front_wheel.normal_load) + float(bike.rear_wheel.normal_load))
		var now: Vector3 = bike.chassis.global_position
		min_clearance = minf(min_clearance, 9.5 - absf(now.x - 46.0))
		if i % 24 == 0:
			samples.append({"t": time, "x": now.x, "y": now.y, "z": now.z,
				"comY": (after.center as Vector3).y, "comVy": (after.velocity as Vector3).y,
				"pitchDeg": rad_to_deg(float(observed.pitch)), "bankDeg": rad_to_deg(float(observed.roll)),
				"riderHeight": bike.chassis.to_local(bike.rider_body.global_position).y,
				"scrubInput": packet.scrub, "frontLoad": observed.frontLoad, "rearLoad": observed.rearLoad})
		if bike.crashed or touchdown >= 0.0 or now.z > 265.0:
			break
	var result := {"mode": mode, "direction": direction, "speedSeed": speed, "sourceHash": source_hash,
		"configHash": JSON.stringify(cfg).sha256_text(), "scrubSettings": cfg.get("ScrubControl", {}).duplicate(true),
		"bankInput": turn_amount, "bankOnsetZ": turn_entry_z,
		"flightStart": flight_start, "touchdown": touchdown, "airTime": touchdown - flight_start,
		"takeoffY": takeoff_com.y, "takeoffVy": takeoff_velocity.y, "takeoffVz": takeoff_velocity.z,
		"takeoffBankDeg": rad_to_deg(takeoff_bank), "takeoffRiderHeight": takeoff_body_height,
		"takeoffRiderRelativeVy": takeoff_rider_relative_vy, "takeoffFrameVy": takeoff_frame_vy,
		"apexY": peak_com_height, "apexRise": peak_com_height - takeoff_com.y,
		"maxGroundBankDeg": rad_to_deg(max_ground_bank), "loadedFaceTicks": loaded_face_ticks,
		"airborneTicks": airborne_ticks, "minPreparedClearance": min_clearance,
		"maxBallisticResidualN": max_ballistic_error, "unsupportedTireForceN": max_unsupported_tire_force,
		"unsupportedLoadN": max_unsupported_support_force, "faceNormalImpulseNs": face_normal_impulse,
		"initialCOMY": (initial.center as Vector3).y, "crashed": bike.crashed, "reason": bike.crash_reason,
		"samples": samples}
	results.append(result)
	var printable := result.duplicate()
	printable.erase("samples")
	print("SCRUB TAKEOFF ", JSON.stringify(printable))
	return result

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	world = Node3D.new()
	root.add_child(world)
	Track.build(world)
	for direction: float in [-1.0, 1.0]:
		var neutral := await _case("neutral", direction, 24.0)
		var leaned := await _case("lean-only", direction, 24.0)
		var scrubbed := await _case("scrub", direction, 24.0)
		var side := "left" if direction < 0.0 else "right"
		for observation: Dictionary in [neutral, leaned, scrubbed]:
			var label := side + " " + str(observation.mode)
			_check(float(observation.flightStart) >= 0.0 and float(observation.airTime) > 0.5 and int(observation.loadedFaceTicks) > 50,
				label + " leaves the actual positively loaded jump face into sustained native flight")
			_check(float(observation.maxBallisticResidualN) < (float(cfg.BikeMass) + float(cfg.RiderMass)) * 9.81 * 0.02
				and float(observation.unsupportedTireForceN) < 0.000001 and float(observation.unsupportedLoadN) < 0.000001,
				label + " follows whole-assembly gravity and measured drag without an extra downward flight force", str(observation.maxBallisticResidualN))
			_check(not bool(observation.crashed) and float(observation.minPreparedClearance) > 0.15,
				label + " reaches loaded touchdown inside the prepared jump corridor", str(observation.reason))
		_check(absf(float(leaned.takeoffBankDeg)) > 12.0 and absf(float(scrubbed.takeoffBankDeg)) > 12.0,
			side + " scrub comparison actually leans the native motorcycle on the jump face")
		_check(float(scrubbed.takeoffRiderHeight) < float(leaned.takeoffRiderHeight) - 0.03,
			side + " scrub lowers the actual massive rider instead of only its rendered pose")
		_check(float(scrubbed.takeoffVy) < float(leaned.takeoffVy) * 0.96 and float(scrubbed.apexRise) < float(leaned.apexRise) * 0.93,
			side + " scrub reduces takeoff vertical momentum and ballistic rise beyond lean alone")
		_check(float(scrubbed.airTime) < float(leaned.airTime) * 0.97,
			side + " functional scrub reduces loaded-to-loaded airtime by at least three percent")
		_check(float(scrubbed.takeoffVz) >= float(leaned.takeoffVz) * 0.93,
			side + " trajectory reduction retains at least 93 percent of forward departure speed")
	var output := FileAccess.open("res://build/scrub-takeoff-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "results": results}, "\t"))
	print("Scrub native takeoffs: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
