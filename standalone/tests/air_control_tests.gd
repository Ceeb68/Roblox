extends SceneTree
## Actual native free-flight maneuvers through the shipped controller. One
## coherent rolling state is seeded, then only ordinary player inputs change.
## These isolate angular handling; real jump/landing acceptance is separate.
const Bike = preload("res://scripts/bike_controller.gd")
const Air = preload("res://physics/air_control.gd")
const Track = preload("res://scripts/track_builder.gd")
var cfg: Dictionary
var bike: Node3D
var checks := 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _tick() -> void:
	# Each control/sample advances exactly one native step, including when the
	# engine runs480Hz inside a240fps headless process. Waiting for an idle
	# process frame here would silently double every480Hz command duration.
	await physics_frame

func _check(condition: bool, message: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + detail if not detail.is_empty() else ""))
		push_error("AIR CONTROL FAIL: " + failures[-1])

func _bodies() -> Array:
	return [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body]

func _heading() -> float:
	var forward: Vector3 = -bike.chassis.global_basis.z
	return atan2(forward.x, -forward.z)

func _angles() -> Vector3:
	var t: Dictionary = bike.get_telemetry()
	return Vector3(float(t.pitch), _heading(), float(t.roll))

func _fixture(hz: int, strength := 1.0, mode := "virtual_rider") -> void:
	if is_instance_valid(bike):
		bike.queue_free()
		await process_frame
	Engine.physics_ticks_per_second = hz
	var setup := cfg.duplicate(true)
	if not setup.has("AirControl"):
		setup.AirControl = {}
	setup.AirControl.Strength = strength
	bike = Bike.new()
	bike.configure(setup)
	root.add_child(bike)
	bike.set_riding_mode(mode)
	bike.reset_bike(Transform3D(Basis.IDENTITY, Vector3(0, 100, 0)))
	for body: RigidBody3D in _bodies():
		body.gravity_scale = 0.0
		body.collision_mask = 0
	bike.set_controls({"clutch": 1.0, "footDown": false, "standing": true,
		"throttle": 0.0, "bodyForward": 0.0, "bodySide": 0.0, "lean": 0.0, "steer": 0.0})
	for _i: int in range(hz * 2):
		await _tick()
	for body: RigidBody3D in _bodies():
		body.linear_velocity = Vector3(0, 0, -20)
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * 20.0 / float(cfg.FrontRadius)
	bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * 20.0 / float(cfg.RearRadius)
	bike.front_wheel.invalidate_load_history()
	bike.rear_wheel.invalidate_load_history()
	bike.front_wheel.clear_contact()
	bike.rear_wheel.clear_contact()
	await _tick()

func _module_guards() -> void:
	await _fixture(240)
	var task: RefCounted = Air.new()
	var frame := {"bodies": _bodies(), "basis": bike.chassis.global_basis,
		"omega": Vector3(10, -8, 12), "velocity": Vector3(0, 0, -20),
		"grounded": false, "enabled": true, "bodyReference": 0.3}
	var controls := {"bodyForward": 1.0, "bodySide": 1.0, "steer": 1.0, "lean": 0.4}
	var before: Array = []
	for body: RigidBody3D in _bodies():
		before.append([body.global_transform, body.linear_velocity, body.angular_velocity])
	var result: Dictionary
	for _i in range(120):
		result = task.update(frame, controls, 1.0 / 240.0, {})
	var unchanged := true
	for i: int in range(_bodies().size()):
		var body: RigidBody3D = _bodies()[i]
		unchanged = unchanged and body.global_transform == before[i][0] \
			and body.linear_velocity == before[i][1] and body.angular_velocity == before[i][2]
	_check(unchanged, "Air task only returns a force request and never mutates native poses or velocities")
	_check(float(result.powerWatts) >= -float(Air.DEFAULTS.MaxDissipationPower) - 0.001 \
		and float(result.powerWatts) <= float(Air.DEFAULTS.MaxPower) + 0.001,
		"Air assistance has an explicit positive and dissipative power budget")
	var local_torque: Vector3 = result.localTorque
	_check(absf(local_torque.x) <= float(Air.DEFAULTS.MaxPitchTorque) + 0.001 \
		and absf(local_torque.y) <= float(Air.DEFAULTS.MaxYawTorque) + 0.001 \
		and absf(local_torque.z) <= float(Air.DEFAULTS.MaxRollTorque) + 0.001 \
		and local_torque.length() <= float(Air.DEFAULTS.MaxTotalTorque) + 0.001,
		"Air assistance respects every axis and combined torque budget")
	_check(float(result.barRequest) == -1.0 and float(result.bodySideRequest) == -1.0 \
		and float(result.twistRequest) == -1.0 and float(result.riderLeanRequest) < 0.0,
		"One virtual air task gives handlebars and rider coherent counterstroke directions")
	frame.grounded = true
	result = task.update(frame, controls, 1.0 / 240.0, {})
	_check(Vector3(result.torque) == Vector3.ZERO and not bool(result.active),
		"Loaded tire contact immediately removes external air torque")
	frame.grounded = false
	result = task.update(frame, controls, 1.0 / 240.0, {"Strength": 0.0})
	_check(Vector3(result.torque) == Vector3.ZERO and float(result.blend) == 0.0,
		"Zero assistance preserves the original local muscle task and native airborne dynamics")
	frame.enabled = false
	result = task.update(frame, controls, 1.0 / 240.0, {})
	_check(Vector3(result.torque) == Vector3.ZERO and float(result.blend) == 0.0,
		"Direct/crashed mode bypasses both air assistance and virtual counterstroke remapping")
	# An isotropic test inertia removes native pose differences: rotating the
	# complete observation must only rotate its torque. A hidden world-up or
	# stored-heading target would break this independent frame-covariance check.
	var first: RefCounted = Air.new()
	var rotated: RefCounted = Air.new()
	var rotation := Basis.from_euler(Vector3(0.45, -0.72, 0.38))
	var base_frame := {"bodies": [], "basis": Basis.IDENTITY, "omega": Vector3(0.2, -0.1, 0.3),
		"velocity": Vector3(0, 0, -20), "grounded": false, "enabled": true}
	var rotated_frame := {"bodies": [], "basis": rotation, "omega": rotation * base_frame.omega,
		"velocity": rotation * base_frame.velocity, "grounded": false, "enabled": true}
	var base_result: Dictionary
	var rotated_result: Dictionary
	for _i in range(120):
		base_result = first.update(base_frame, controls, 1.0 / 240.0, {})
		rotated_result = rotated.update(rotated_frame, controls, 1.0 / 240.0, {})
	_check(Vector3(rotated_result.torque).distance_to(rotation * Vector3(base_result.torque)) < 0.0001,
		"Air assistance has no hidden world-up or original-heading correction")

func _maneuver(hz: int, axis: String, direction: float) -> Dictionary:
	await _fixture(hz)
	var initial := _angles()
	var thrown := Vector3.ZERO
	var recovered := Vector3.ZERO
	var peak_yaw := 0.0
	var peak_bank := 0.0
	var peak_torque := 0.0
	var budget_excess := 0.0
	var power_excess := 0.0
	var unsupported_tire_force := 0.0
	var opposite_command_seen := false
	var air_observations := 0
	var finite := true
	var settings: Dictionary = bike.config.get("AirControl", {})
	var throw_steps := roundi(0.55 * hz)
	var return_steps := roundi(0.55 * hz)
	var native_start := Engine.get_physics_frames()
	for i: int in range(roundi(1.5 * hz)):
		var command := direction if i < throw_steps else (-direction if i < throw_steps + return_steps else 0.0)
		var packet := {"clutch": 1.0, "footDown": false, "standing": true,
			"steer": 0.0, "bodySide": 0.0, "bodyForward": 0.0, "lean": 0.0, "throttle": 0.0}
		if axis == "whip":
			packet.steer = command
			packet.bodySide = command
		else:
			packet[axis] = command
		opposite_command_seen = opposite_command_seen or command * direction < 0.0
		bike.set_controls(packet)
		await _tick()
		var angle := _angles() - initial
		angle.y = wrapf(angle.y, -PI, PI)
		peak_yaw = maxf(peak_yaw, absf(angle.y))
		peak_bank = maxf(peak_bank, absf(angle.z))
		if i == throw_steps - 1:
			thrown = angle
		recovered = angle
		var output: Dictionary = bike._air_result
		var local_torque: Vector3 = output.get("localTorque", Vector3.ZERO)
		peak_torque = maxf(peak_torque, local_torque.length())
		budget_excess = maxf(budget_excess, absf(local_torque.x) - float(settings.get("MaxPitchTorque", Air.DEFAULTS.MaxPitchTorque)))
		budget_excess = maxf(budget_excess, absf(local_torque.y) - float(settings.get("MaxYawTorque", Air.DEFAULTS.MaxYawTorque)))
		budget_excess = maxf(budget_excess, absf(local_torque.z) - float(settings.get("MaxRollTorque", Air.DEFAULTS.MaxRollTorque)))
		budget_excess = maxf(budget_excess, local_torque.length() - float(settings.get("MaxTotalTorque", Air.DEFAULTS.MaxTotalTorque)))
		var power := float(output.get("powerWatts", 0.0))
		power_excess = maxf(power_excess, power - float(settings.get("MaxPower", Air.DEFAULTS.MaxPower)))
		power_excess = maxf(power_excess, -power - float(settings.get("MaxDissipationPower", Air.DEFAULTS.MaxDissipationPower)))
		air_observations += int(bool(output.get("active", false)))
		for result: Dictionary in [bike._front_result, bike._rear_result]:
			unsupported_tire_force = maxf(unsupported_tire_force,
				Vector2(float(result.longitudinalForce), float(result.lateralForce)).length())
		for body: RigidBody3D in _bodies():
			finite = finite and body.global_transform.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
	var label := "%s %+.0f at %dHz" % [axis, direction, hz]
	_check(Engine.get_physics_frames() - native_start == roundi(1.5 * hz),
		label + " controls and observations cover exactly1.5 native seconds independently of render rate")
	_check(finite and not bike.crashed and air_observations > hz,
		label + " remains a finite five-body native flight")
	_check(budget_excess < 0.001 and power_excess < 0.001 and peak_torque > 10.0,
		label + " uses useful assistance inside its declared torque/power budgets")
	_check(unsupported_tire_force < 0.000001, label + " never invents airborne tire force")
	if axis == "bodyForward":
		_check(thrown.x * direction < -deg_to_rad(12.0), label + " produces prompt useful signed pitch control", str(thrown))
		_check(opposite_command_seen and absf(recovered.x) < absf(thrown.x) * 0.8,
			label + " counter-input reduces the initial pitch excursion", str(recovered))
	elif axis == "steer":
		_check(thrown.z * direction > deg_to_rad(18.0), label + " produces useful signed airborne roll", str(thrown))
		_check(opposite_command_seen and absf(recovered.z) < deg_to_rad(10.0),
			label + " counter-input returns bank near a usable landing attitude", str(recovered))
	elif axis == "bodySide":
		_check(thrown.y * direction > deg_to_rad(18.0), label + " produces useful signed airborne yaw", str(thrown))
		_check(opposite_command_seen and absf(recovered.y) < deg_to_rad(8.0),
			label + " counter-input returns yaw close to the original travel line", str(recovered))
	else:
		_check(peak_yaw > deg_to_rad(30.0) and peak_bank > deg_to_rad(18.0),
			label + " throws a visible physical whip with both yaw and bank", str(thrown))
		_check(opposite_command_seen and absf(recovered.y) < deg_to_rad(8.0) and absf(recovered.z) < deg_to_rad(10.0),
			label + " deliberate counter-input returns the whip without a heading or upright target", str(recovered))
	var report := {"axis": axis, "direction": direction, "hz": hz,
		"thrownDegrees": str(thrown * 180.0 / PI), "recoveredDegrees": str(recovered * 180.0 / PI),
		"peakYawDegrees": rad_to_deg(peak_yaw), "peakBankDegrees": rad_to_deg(peak_bank),
		"peakTorqueNm": peak_torque, "budgetExcessNm": budget_excess, "powerExcessW": power_excess}
	reports.append(report)
	print("AIR MANEUVER ", JSON.stringify(report))
	return {"throw": thrown, "return": recovered}

func _native_bypass() -> void:
	for mode: String in ["virtual_rider", "direct"]:
		await _fixture(240, 0.0 if mode == "virtual_rider" else 1.0, mode)
		var peak := 0.0
		var blend := 0.0
		for _i in range(180):
			bike.set_controls({"clutch": 1.0, "footDown": false, "standing": true, "bodySide": 1.0, "steer": 1.0})
			await _tick()
			peak = maxf(peak, Vector3(bike._air_result.get("torque", Vector3.ZERO)).length())
			blend = maxf(blend, float(bike._air_result.get("blend", 0.0)))
		_check(peak == 0.0 and blend == 0.0, mode + " bypasses the external air task when requested")

func _real_jump_whips() -> void:
	# This fixture uses the actual shipped triangle track, normal gravity,
	# finite suspension, third gear and a real clutch release. Only its initial
	# 24m/s rolling approach is seeded. The scripted PILOT below reads ordinary
	# attitude/rate observations to finish a maneuver as a player would; the
	# shipped air-control task never receives a heading or landing target.
	if is_instance_valid(bike):
		bike.queue_free()
		await process_frame
	Engine.physics_ticks_per_second = 240
	var world := Node3D.new()
	root.add_child(world)
	Track.build(world)
	for direction: float in [1.0, -1.0]:
		if is_instance_valid(bike):
			bike.queue_free()
			await process_frame
		bike = Bike.new()
		bike.configure(cfg.duplicate(true))
		world.add_child(bike)
		bike.reset_bike(Transform3D(Basis(Vector3.UP, PI), Vector3(46, 0.95, 145)))
		bike.set_controls({"clutch": 1.0, "footDown": true, "standing": true})
		var shifts := 0
		for i: int in range(482):
			if i in [242, 266, 290]:
				shifts += int(bike.shift_gear(1))
			bike.set_controls({"throttle": 0.8 if i >= 242 else 0.0,
				"clutch": 1.0, "footDown": true, "standing": true})
			await _tick()
		for body: RigidBody3D in _bodies():
			body.linear_velocity = Vector3(0, 0, 24)
			body.angular_velocity = Vector3.ZERO
			body.sleeping = false
		bike.front_wheel.angular_velocity = -bike.front_wheel.global_basis.x * 24.0 / float(cfg.FrontRadius)
		bike.rear_wheel.angular_velocity = -bike.rear_wheel.global_basis.x * 24.0 / float(cfg.RearRadius)
		bike.front_wheel.invalidate_load_history()
		bike.rear_wheel.invalidate_load_history()
		var flight_start := -1.0
		var flight_heading := 0.0
		var flight_end := -1.0
		var peak_yaw := 0.0
		var peak_bank := 0.0
		var landing: Dictionary = {}
		var both_loaded_after := false
		var clearance := INF
		var torque_excess := 0.0
		var peak_air_torque := 0.0
		var front_travel := 0.0
		var rear_travel := 0.0
		var samples: Array[Dictionary] = []
		for i: int in range(2400):
			var time := float(i) / 240.0
			var state: Dictionary = bike.get_telemetry()
			var bank := float(state.roll)
			var heading := wrapf(_heading() - flight_heading, -PI, PI)
			var packet := {"throttle": 0.5, "clutch": maxf(0.0, 1.0 - time / 0.75),
				"footDown": false, "standing": true, "bodyForward": 0.0, "bodySide": 0.0, "steer": 0.0}
			if flight_start >= 0.0 and flight_end < 0.0:
				var flight := time - flight_start
				packet.bodyForward = clampf((float(state.pitch) - deg_to_rad(-3.0)) * 1.5
					+ bike.chassis.angular_velocity.dot(bike.chassis.global_basis.x) * 0.25, -0.7, 0.7)
				if flight > 0.05 and flight < 0.5:
					packet.steer = direction
					packet.bodySide = direction
				elif flight >= 0.5 and flight < 0.95:
					packet.steer = -direction
					packet.bodySide = -direction
				elif flight >= 0.95:
					packet.steer = clampf(-bank * 1.8 - float(state.bankRate) * 0.28, -0.7, 0.7)
					packet.bodySide = clampf(-heading * 2.0 - float(state.headingRate) * 0.3, -0.7, 0.7)
			bike.set_controls(packet)
			await _tick()
			state = bike.get_telemetry()
			var position: Vector3 = bike.chassis.global_position
			var supported: bool = (bike.front_wheel.contact and bike.front_wheel.normal_load > 0.0) \
				or (bike.rear_wheel.contact and bike.rear_wheel.normal_load > 0.0)
			if flight_start < 0.0 and position.z > 186.0 and position.y > 4.5 and not supported:
				flight_start = time
				flight_heading = _heading()
			if flight_start >= 0.0:
				var actual_heading := wrapf(_heading() - flight_heading, -PI, PI)
				if flight_end < 0.0:
					peak_yaw = maxf(peak_yaw, absf(actual_heading))
					peak_bank = maxf(peak_bank, absf(float(state.roll)))
					if time - flight_start > 0.2 and supported:
						flight_end = time
						landing = {"time": time, "airtime": time - flight_start,
							"yaw": actual_heading, "bank": float(state.roll), "pitch": float(state.pitch),
							"speed": state.speedMps, "frontLoad": state.frontLoad, "rearLoad": state.rearLoad}
				if flight_end >= 0.0 and float(state.frontLoad) > 100.0 and float(state.rearLoad) > 100.0:
					both_loaded_after = true
				if i % 24 == 0:
					samples.append({"time": time, "position": str(position), "yaw": rad_to_deg(actual_heading),
						"bank": rad_to_deg(float(state.roll)), "pitch": rad_to_deg(float(state.pitch)),
						"frontLoad": state.frontLoad, "rearLoad": state.rearLoad, "input": packet.duplicate()})
			var local_torque: Vector3 = bike._air_result.get("localTorque", Vector3.ZERO)
			var settings: Dictionary = bike.config.get("AirControl", {})
			torque_excess = maxf(torque_excess, local_torque.length() - float(settings.get("MaxTotalTorque", Air.DEFAULTS.MaxTotalTorque)))
			# The returned output belongs to the contacts observed at the start
			# of that native step, rather than the following contact callback.
			if bool(bike._air_result.get("active", false)):
				peak_air_torque = maxf(peak_air_torque, local_torque.length())
			front_travel = maxf(front_travel, float(state.frontCompression))
			rear_travel = maxf(rear_travel, float(state.rearCompression))
			var half_width := Track._ribbon_road_half_width({"center": Vector2(46.0, position.z)})
			clearance = minf(clearance, half_width + float(Track.SHOULDER_WIDTH) - absf(position.x - 46.0))
			if bike.crashed or position.z > 265.0:
				break
		var label := "Actual big-tabletop whip %+.0f" % direction
		_check(shifts == 3 and int(bike.get_telemetry().gear) == 3, label + " uses real third gear and clutch engagement")
		_check(flight_end > flight_start and flight_start >= 0.0 and float(landing.get("airtime", 0.0)) > 1.0,
			label + " leaves the actual jump face and returns through positively loaded native contact")
		_check(peak_yaw > deg_to_rad(30.0) and peak_bank > deg_to_rad(12.0),
			label + " creates a substantial physical sideways whip", "yaw %.2f bank %.2f" % [rad_to_deg(peak_yaw), rad_to_deg(peak_bank)])
		_check(not landing.is_empty() and absf(float(landing.yaw)) < deg_to_rad(8.0) \
			and absf(float(landing.bank)) < deg_to_rad(10.0),
			label + " player counter-input prepares a nearly straight landing", str(landing))
		_check(both_loaded_after and not bike.crashed and bike.chassis.global_position.z > 265.0,
			label + " restores both tire loads and rides through the landing runout", str(bike.crash_reason))
		_check(clearance > 0.45 and front_travel < float(cfg.Suspension.Front.Travel) + 0.04 \
			and rear_travel < float(cfg.Suspension.Rear.Travel) + 0.04,
			label + " remains inside the prepared track and real suspension travel")
		_check(torque_excess < 0.001 and peak_air_torque > 10.0,
			label + " uses the same declared finite air assistance rather than a jump-only actuator")
		var report := {"axis": "real-track-whip", "direction": direction, "hz": 240,
			"peakYawDegrees": rad_to_deg(peak_yaw), "peakBankDegrees": rad_to_deg(peak_bank),
			"landing": landing, "finalPosition": str(bike.chassis.global_position),
			"crashed": bike.crashed, "reason": bike.crash_reason, "samples": samples}
		reports.append(report)
		print("REAL TRACK WHIP ", JSON.stringify({"direction": direction, "peakYaw": rad_to_deg(peak_yaw),
			"peakBank": rad_to_deg(peak_bank), "landing": landing, "finalPosition": report.finalPosition,
			"crashed": bike.crashed, "reason": bike.crash_reason}))
	world.queue_free()
	await process_frame

func _run() -> void:
	var config_source := FileAccess.get_file_as_string("res://config/bike_250f.json")
	cfg = JSON.parse_string(config_source)
	await _module_guards()
	var observations: Dictionary = {}
	for hz: int in [240, 480]:
		for axis: String in ["bodyForward", "bodySide", "steer", "whip"]:
			for direction: float in [-1.0, 1.0]:
				var result := await _maneuver(hz, axis, direction)
				var key := "%s/%s" % [axis, direction]
				if hz == 240:
					observations[key] = result
				else:
					var earlier: Dictionary = observations[key]
					_check(Vector3(result.throw).distance_to(earlier.throw) < deg_to_rad(4.0) \
						and Vector3(result.return).distance_to(earlier.return) < deg_to_rad(6.0),
						key + " converges across 240 and 480 native physics updates")
	await _native_bypass()
	await _real_jump_whips()
	var controller_script: Script = Bike
	var air_script: Script = Air
	var file := FileAccess.open("res://build/air-control-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": reports,
		"controllerHash": controller_script.get_source_code().sha256_text(), "airHash": air_script.get_source_code().sha256_text(),
		"configHash": config_source.sha256_text()}, "\t"))
	file.close()
	print("Air control: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(bike):
		bike.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
