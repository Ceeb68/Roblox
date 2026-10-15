extends SceneTree
## Acceptance M: a complete shipped-track lap driven by a reproducible bot.
## One ordinary spawn reset is the only pose/velocity initialization. The bot
## uses actual steer, body, throttle, brake, clutch and manual-shift packets.
## This validates one known control recipe; it is not human feel validation.
const Bike = preload("res://scripts/bike_controller.gd")
const RiderInput = preload("res://scripts/rider_input.gd")
const Track = preload("res://scripts/track_builder.gd")
const HZ := 240.0
var world: Node3D
var bike: Node3D
var rider: RefCounted
var rows: Array
var track: Dictionary
var samples: Array[Dictionary] = []
var gate_events: Array[Dictionary] = []
var gates_crossed: Array[int] = []
var checks := 0
var failures: Array[String] = []

func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (": " + detail if not detail.is_empty() else ""))
		push_error("LAP RIDE FAIL: " + failures[-1])

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	await physics_frame
	await process_frame

func _nearest_index(position: Vector2, old_index: int) -> int:
	var best := old_index
	var nearest := INF
	for offset in range(-4, 110):
		var index := posmod(old_index + offset, rows.size() - 1)
		var d := position.distance_squared_to(rows[index].center)
		if d < nearest:
			nearest = d
			best = index
	return best

func _lookahead(index: int, distance: float) -> Vector2:
	var location: Vector2 = rows[index].center
	var remaining := distance
	for offset in range(1, 160):
		var next: Vector2 = rows[posmod(index + offset, rows.size() - 1)].center
		var segment := location.distance_to(next)
		if segment >= remaining:
			return location.lerp(next, remaining / maxf(segment, 0.001))
		remaining -= segment
		location = next
	return location

func _cross_gates(from: Vector3, to: Vector3, time: float) -> void:
	for index in range(track.gates.size()):
		var gate: Dictionary = track.gates[index]
		var transform: Transform3D = gate.transform
		var a: Vector3 = transform.affine_inverse() * from
		var b: Vector3 = transform.affine_inverse() * to
		if a.z > 0.0 and b.z <= 0.0:
			var fraction := a.z / maxf(0.00001, a.z - b.z)
			var crossing := a.lerp(b, fraction)
			if absf(crossing.x) <= float(gate.width) * 0.5 and crossing.y >= -1.5 and crossing.y <= 5.0:
				gate_events.append({"time": time, "gate": index, "name": gate.name, "x": crossing.x, "y": crossing.y})
				if gates_crossed.is_empty() and index == 0:
					gates_crossed.append(index)
				elif not gates_crossed.is_empty() and index == posmod(gates_crossed[-1] + 1, track.gates.size()):
					gates_crossed.append(index)

func _target_speed(position: Vector3, curvature: float) -> float:
	var target := 15.0
	if absf(position.x - Track.WEST_X) < 12.0:
		if position.z < 13.0 and position.z > -43.0:
			target = 8.0
		elif position.z > 150.0 and position.z < 240.0:
			target = 11.0
	if absf(position.x - Track.EAST_X) < 12.0:
		if position.z < 30.0:
			target = 13.0
		elif position.z < 151.0:
			target = 19.0
		elif position.z < 220.0:
			target = 22.0
		else:
			target = 10.0
	# Lateral acceleration asks no more than 0.42 g on the sand/mud arcs.
	return minf(target, sqrt(4.1 / maxf(absf(curvature), 0.001)))

func _run() -> void:
	Engine.physics_ticks_per_second = int(HZ)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	world = Node3D.new()
	root.add_child(world)
	track = Track.build(world)
	rows = Track._main_rows()
	bike = Bike.new()
	bike.configure(cfg.duplicate(true))
	world.add_child(bike)
	bike.reset_bike(track.spawn)
	rider = RiderInput.new()
	for _i in range(240):
		bike.set_controls(rider.packet())
		await _tick()
	bike.shift_gear(1)
	var index := 16
	var shift_frames := -1
	var shift_direction := 1
	var last_shift := -1000
	var last_position: Vector3 = bike.chassis.global_position
	var max_error := 0.0
	var max_bank := 0.0
	var traveled := 0.0
	var ticks := 0
	var min_speed := INF
	var max_speed := 0.0
	var min_prepared_clearance := INF
	var progression_air := 0.0
	var big_air := 0.0
	var stall_elapsed := 0.0
	var stalls_seen := 0
	var shifts := 0
	var rejected_shifts := 0
	var air_elapsed := 0.0
	var ground_since_air := 1000.0
	var had_flight := false
	for i in range(38400):
		var time := float(i) / HZ
		var state: Dictionary = bike.get_telemetry()
		var position: Vector3 = bike.chassis.global_position
		var p2 := Vector2(position.x, position.z)
		index = _nearest_index(p2, index)
		var road_error: float = p2.distance_to(rows[index].center)
		max_error = maxf(max_error, road_error)
		var half_width := Track._ribbon_road_half_width(rows[index])
		min_prepared_clearance = minf(min_prepared_clearance, half_width + Track.SHOULDER_WIDTH - road_error)
		var speed := float(state.speedMps)
		var lookahead := clampf(speed * 2.3, 10.0, 30.0)
		var target := _lookahead(index, lookahead)
		var local_target: Vector3 = bike.chassis.global_basis.inverse() * Vector3(target.x - position.x, 0, target.y - position.z)
		var heading_error := atan2(local_target.x, -local_target.z)
		var curvature := 2.0 * sin(heading_error) / maxf(lookahead, 0.1)
		var speed_target := _target_speed(position, curvature)
		var bank := atan(speed * speed * curvature / 9.81)
		var surface: Dictionary = cfg.Surfaces.get(str(state.frontSurface), cfg.Surfaces.dirt)
		var lean_limit := minf(float(cfg.VirtualRider.MaxComfortLean), atan(float(surface.Grip) * float(cfg.VirtualRider.GripMargin)))
		var intent := clampf(bank / maxf(lean_limit, 0.1), -0.9, 0.9)
		var steer := signf(intent) * pow(absf(intent), 1.0 / float(cfg.VirtualRider.IntentExponent))
		rider.throttle = clampf(0.18 + (speed_target - speed) * 0.2, 0.0, 0.85)
		# Squeeze the real levers progressively while approaching a slower
		# section; the bot never edits wheel or chassis speed.
		rider.front_brake = move_toward(rider.front_brake, clampf((speed - speed_target) * 0.08, 0.0, 0.40), 0.8 / HZ)
		rider.rear_brake = move_toward(rider.rear_brake, clampf((speed - speed_target) * 0.035, 0.0, 0.18), 0.6 / HZ)
		rider.clutch = maxf(0.0, 1.0 - time / 0.8)
		rider.steer = steer
		rider.standing = speed > 6.0
		rider.body_forward = 0.0
		rider.body_side = 0.0
		var airborne := not bool(state.frontContact) and not bool(state.rearContact)
		if airborne:
			air_elapsed += 1.0 / HZ
			if position.z > 103.0 and position.z < 150.0 and absf(position.x - Track.EAST_X) < 9.5:
				progression_air = maxf(progression_air, air_elapsed)
			if position.z > 187.0 and position.z < 255.0 and absf(position.x - Track.EAST_X) < 9.5:
				big_air = maxf(big_air, air_elapsed)
			if air_elapsed > 0.1:
				had_flight = true
				ground_since_air = 0.0
			rider.body_forward = clampf(float(state.pitch) * 0.9, -0.55, 0.55)
			rider.throttle = 0.35
			# The observation rider actively corrects roll and yaw with real stick
			# inputs. These are not forces or in-game automatic alignment.
			rider.steer = clampf(-float(state.roll) * 1.5 - float(state.bankRate) * 0.4, -0.65, 0.65)
			var air_velocity: Vector3 = bike.chassis.global_basis.inverse() * bike.chassis.linear_velocity
			rider.body_side = clampf(atan2(air_velocity.x, maxf(1.0, -air_velocity.z)) * 0.9, -0.45, 0.45)
		else:
			air_elapsed = 0.0
			ground_since_air += 1.0 / HZ
			if had_flight and ground_since_air < 0.45:
				rider.body_forward = 0.35
				rider.throttle = minf(rider.throttle, 0.25)
				rider.steer *= smoothstep(0.0, 0.6, ground_since_air)
			if had_flight and ground_since_air < 1.0:
				# Finish suspension compression/rebound before requesting a deep
				# new bank while braking down the descending landing.
				rider.steer = clampf(rider.steer, -0.35, 0.35)
		if shift_frames >= 0:
			rider.clutch = 1.0
			shift_frames += 1
			if shift_frames == 20:
				if bike.shift_gear(shift_direction):
					shifts += 1
				else:
					rejected_shifts += 1
				shift_frames = -1
				last_shift = i
		elif i - last_shift > 120 and rider.clutch < 0.05 and float(state.frontLoad) > 100.0 and float(state.rearLoad) > 100.0:
			if float(state.rpm) > 10500.0 and int(state.gear) < 5:
				shift_direction = 1
				shift_frames = 0
			elif float(state.rpm) < 4800.0 and int(state.gear) > 1 and speed_target < speed:
				shift_direction = -1
				shift_frames = 0
		rider.update_auto_feet(1.0 / HZ, state)
		bike.set_controls(rider.packet())
		await _tick()
		ticks += 1
		var after: Vector3 = bike.chassis.global_position
		_cross_gates(last_position, after, time)
		traveled += after.distance_to(last_position)
		last_position = after
		max_bank = maxf(max_bank, absf(float(state.roll)))
		min_speed = minf(min_speed, speed)
		max_speed = maxf(max_speed, speed)
		if i % 48 == 0:
			samples.append({"time": time, "x": after.x, "y": after.y, "z": after.z, "roadError": road_error, "row": index,
				"speed": speed, "targetSpeed": speed_target, "bankDeg": rad_to_deg(float(state.roll)), "pitchDeg": rad_to_deg(float(state.pitch)),
				"steer": rider.steer, "pathSteerRequest": steer, "throttle": rider.throttle,
				"frontBrake": rider.front_brake, "rearBrake": rider.rear_brake, "gear": state.gear,
				"targetBankDeg": rad_to_deg(float(state.riderTargetLean)), "bankRate": state.bankRate,
				"barAngleDeg": rad_to_deg(float(state.steerAngle)), "barTorque": state.riderSteeringTorque,
				"torqueLimit": state.activeTorqueLimit, "catchRemaining": state.landingCatchRemaining,
				"frontSlipDeg": rad_to_deg(float(state.frontSlipAngle)), "rearSlipDeg": rad_to_deg(float(state.rearSlipAngle)),
				"frontLoad": state.frontLoad, "rearLoad": state.rearLoad, "frontContact": state.frontContact, "rearContact": state.rearContact})
		stall_elapsed = stall_elapsed + 1.0 / HZ if speed < 0.5 and time > 5.0 else 0.0
		if bool(state.stalled):
			stalls_seen += 1
		if bike.crashed or road_error > 18.0 or gates_crossed.size() >= 15 or stall_elapsed > 6.0:
			break
	_check(not bike.crashed, "M: complete-track driver avoids crashes or recovery", bike.crash_reason)
	_check(gates_crossed.size() >= 15 and gates_crossed[-1] == 0,
		"M: ordinary inputs cross all fourteen gates in order and return through START", str(gates_crossed))
	_check(traveled > 820.0, "M: full lap follows more than 820 metres of real native trajectory", str(traveled))
	_check(min_prepared_clearance > 0.15,
		"M: the lap remains inside the actual prepared road and graded shoulders", str(min_prepared_clearance))
	_check(progression_air > 0.5 and big_air > 0.5,
		"M: the lap includes sustained native flight over both large tabletops", "progression=%.2f big=%.2f" % [progression_air, big_air])
	_check(shifts >= 3 and rejected_shifts == 0, "M: real clutch shifts operate without forcing drivetrain state")
	_check(stall_elapsed < 6.0 and max_speed > 18.0,
		"M: the rider remains mobile and reaches useful jump approach speed")
	var finite := true
	for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]:
		finite = finite and body.global_transform.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
	_check(finite, "M: the full lap leaves all five independent rigid bodies finite")
	var report := {"checks": checks, "failures": failures, "sourceHash": String(bike.get_script().source_code).sha256_text(),
		"elapsed": float(ticks) / HZ, "crashed": bike.crashed, "reason": bike.crash_reason,
		"position": str(bike.chassis.global_position), "maxRoadError": max_error, "maxBankDeg": rad_to_deg(max_bank),
		"traveled": traveled, "minPreparedClearance": min_prepared_clearance, "progressionAirSeconds": progression_air, "bigAirSeconds": big_air, "shifts": shifts, "rejectedShifts": rejected_shifts, "stallSamples": stalls_seen, "gatesInOrder": gates_crossed, "gateEvents": gate_events, "maxSpeed": max_speed,
		"samples": samples}
	var output := FileAccess.open("res://build/lap-ride-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	report.erase("samples")
	print("OVERHAUL LAP ", JSON.stringify(report))
	print("Complete native lap: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
