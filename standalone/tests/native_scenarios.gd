extends SceneTree
## Integration checks for the actual Godot/Jolt simulation, in SI units.
## Run with tools/godot.sh --headless --fixed-fps 240
## --script res://tests/native_scenarios.gd. These checks measure native bodies;
## they do not establish that human cornering/jump handling feels convincing.

const BIKE_PATH := "res://scripts/bike_controller.gd"
const CONFIG_PATH := "res://config/bike_250f.json"
const HZ := 240.0

var failures: Array[String] = []
var checks: int = 0
var world: Node3D
var floor_body: StaticBody3D
var bike: Node3D
var cfg: Dictionary
var bike_script: Script

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, details: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + details if not details.is_empty() else ""))
		push_error("NATIVE FAIL: " + failures[-1])

func _finite_vector(value: Vector3) -> bool:
	return value.is_finite()

func _next_tick() -> void:
	# physics_frame is emitted before native integration. process_frame observes
	# the completed frame, including RigidBody3D contact reports.
	await physics_frame
	await process_frame

func _advance(seconds: float) -> void:
	for _tick: int in range(maxi(1, roundi(seconds * HZ))):
		await _next_tick()

func _static_box(name_value: String, position_value: Vector3, size: Vector3, surface: String = "hardpack", angle: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_value
	body.position = position_value
	body.rotation.x = angle
	body.set_meta("physics_surface", surface)
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = 0.0
	body.physics_material_override = material
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func _new_bike(position_value: Vector3 = Vector3(0.0, 0.82, 0.0), basis_value: Basis = Basis.IDENTITY) -> void:
	if is_instance_valid(bike):
		bike.queue_free()
		await _next_tick()
	bike = bike_script.new()
	bike.name = "NativeTestBike"
	bike.configure(cfg.duplicate(true))
	# These are isolated mechanical benches. Turn off the selectable virtual
	# rider so a steering feedback loop cannot mask the dynamics under test.
	bike.set_riding_mode("direct")
	world.add_child(bike)
	bike.reset_bike(Transform3D(basis_value, position_value))
	bike.set_controls({"clutch": 1.0, "footDown": true})
	await _next_tick()

func _native_bodies(node: Node) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	if node is RigidBody3D:
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_native_bodies(child))
	return result

func _native_joints(node: Node) -> Array[Joint3D]:
	var result: Array[Joint3D] = []
	if node is Joint3D:
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_native_joints(child))
	return result

func _wheel_has_native_volume(wheel: RigidBody3D, minimum_radius: float) -> bool:
	for child: Node in wheel.get_children():
		if not child is CollisionShape3D or child.disabled:
			continue
		if child.shape is CylinderShape3D:
			return child.shape.radius >= minimum_radius and child.shape.height > 0.05
	return false

func _omega(wheel: RigidBody3D) -> float:
	return wheel.angular_velocity.dot(wheel.global_basis.x)

func _set_native_motion(velocity: Vector3, front_omega: float = 0.0, rear_omega: float = 0.0) -> void:
	for body: RigidBody3D in _native_bodies(bike):
		body.linear_velocity = velocity
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
	bike.front_wheel.angular_velocity = bike.front_wheel.global_basis.x * front_omega
	bike.rear_wheel.angular_velocity = bike.rear_wheel.global_basis.x * rear_omega

func _set_pitched_bearing_motion(parent_rate: float, front_rate: float, rear_rate: float) -> void:
	# Give constrained body centres the translation of a common rigid rotation;
	# only the permitted tire bearing DOFs receive different angular rates.
	var axis: Vector3 = bike.chassis.global_basis.x.normalized()
	var reference_com: Vector3 = bike.chassis.global_transform * bike.chassis.center_of_mass
	for body: RigidBody3D in _native_bodies(bike):
		var com: Vector3 = body.global_transform * body.center_of_mass
		body.angular_velocity = axis * parent_rate
		body.linear_velocity = (axis * parent_rate).cross(com - reference_com)
		body.sleeping = false
	bike.front_wheel.angular_velocity = bike.front_wheel.global_basis.x * front_rate
	bike.rear_wheel.angular_velocity = bike.rear_wheel.global_basis.x * rear_rate

func _native_mechanical_energy() -> float:
	var result := 0.0
	for body: RigidBody3D in _native_bodies(bike):
		var local_omega: Vector3 = body.global_basis.inverse() * body.angular_velocity
		var inertia: Vector3 = body.inertia
		var rotation_energy: float = 0.5 * (inertia.x * local_omega.x ** 2 + inertia.y * local_omega.y ** 2 + inertia.z * local_omega.z ** 2)
		var com: Vector3 = body.global_transform * body.center_of_mass
		result += 0.5 * body.mass * body.linear_velocity.length_squared() + rotation_energy + body.mass * 9.81 * com.y
	return result

func _test_structure_and_settle() -> void:
	await _new_bike()
	var bodies := _native_bodies(bike)
	var total_mass := 0.0
	for body: RigidBody3D in bodies:
		total_mass += body.mass
		_check(not body.freeze, "Rigid bodies run native integration", str(body.name))
	_check(bodies.size() == 4, "Four native chassis/fork/wheel bodies", str(bodies.size()))
	_check(absf(total_mass - 187.0) < 0.01, "Physical bike+rider mass is 187 kg", str(total_mass))
	_check(_native_joints(bike).size() >= 3, "Native constraints connect all four bodies")
	_check(_wheel_has_native_volume(bike.front_wheel, 0.34), "Front tire has a full native collision volume")
	_check(_wheel_has_native_volume(bike.rear_wheel, 0.33), "Rear tire has a full native collision volume")
	await _advance(3.0)
	var telemetry: Dictionary = bike.get_telemetry()
	_check(bool(telemetry.frontContact) and bool(telemetry.rearContact), "Both tires physically contact a flat floor", str(telemetry))
	_check(float(telemetry.frontLoad) > 200.0 and float(telemetry.rearLoad) > 200.0, "Both native contacts carry the stationary bike", "%s / %s N" % [telemetry.frontLoad, telemetry.rearLoad])
	_check(bike.chassis.linear_velocity.length() < 0.8, "Manual feet-down stationary settle", str(bike.chassis.linear_velocity))
	_check(float(telemetry.frontCompression) >= -0.015 and float(telemetry.frontCompression) <= 0.315, "Native front suspension stays within 300 mm travel", str(telemetry.frontCompression))
	_check(float(telemetry.rearCompression) >= -0.015 and float(telemetry.rearCompression) <= 0.315, "Native rear suspension stays within 300 mm travel", str(telemetry.rearCompression))
	print("NATIVE settle: mass=%.1f kg, front/rear load=%.1f/%.1f N, travel=%.3f/%.3f m" % [total_mass, telemetry.frontLoad, telemetry.rearLoad, telemetry.frontCompression, telemetry.rearCompression])

func _test_neutral_and_clutch() -> void:
	await _new_bike()
	await _advance(1.0)
	var start_rpm: float = bike.get_telemetry().rpm
	bike.set_controls({"throttle": 0.7, "clutch": 0.0, "footDown": true})
	await _advance(1.2)
	var neutral: Dictionary = bike.get_telemetry()
	_check(int(neutral.gear) == 0 and float(neutral.rpm) > start_rpm + 1000.0, "Neutral throttle revs the crank")
	_check(absf(_omega(bike.rear_wheel)) < 3.0, "Neutral does not motor the native rear wheel", str(_omega(bike.rear_wheel)))
	await _new_bike()
	await _advance(1.0)
	var clutch_start_rpm: float = bike.get_telemetry().rpm
	_check(bike.shift_gear(1), "Manual clutch-pulled shift selects first gear")
	bike.set_controls({"throttle": 0.7, "clutch": 1.0, "footDown": true})
	await _advance(1.2)
	var isolated: Dictionary = bike.get_telemetry()
	_check(int(isolated.gear) == 1 and float(isolated.rpm) > clutch_start_rpm + 1000.0, "First gear with pulled clutch allows free revving", "start=%.0f end=%.0f RPM" % [clutch_start_rpm, isolated.rpm])
	_check(absf(_omega(bike.rear_wheel)) < 3.0, "Pulled clutch isolates the actual rear rotor", str(_omega(bike.rear_wheel)))
	print("NATIVE neutral/clutch: RPM=%.0f/%.0f, isolated native rotor=%.3f rad/s" % [neutral.rpm, isolated.rpm, _omega(bike.rear_wheel)])

func _test_suspension_tuning() -> void:
	await _new_bike()
	bike.tune_setup({"Front": {"SpringRate": 9000.0}, "Rear": {"SpringRate": 10000.0}})
	await _advance(2.0)
	var soft: Dictionary = bike.get_telemetry()
	var soft_front_offset: float = bike.chassis.to_local(bike.front_wheel.global_position).y
	var soft_rear_offset: float = bike.chassis.to_local(bike.rear_wheel.global_position).y
	bike.tune_setup({"Front": {"SpringRate": 36000.0}, "Rear": {"SpringRate": 38000.0}})
	await _advance(2.0)
	var firm: Dictionary = bike.get_telemetry()
	var firm_front_offset: float = bike.chassis.to_local(bike.front_wheel.global_position).y
	var firm_rear_offset: float = bike.chassis.to_local(bike.rear_wheel.global_position).y
	# Physical feet also carry load in this stationary bench. Require 5 mm of
	# measured sag change rather than assuming all rider weight is on tires.
	_check(float(soft.frontCompression) > float(firm.frontCompression) + 0.005, "Front spring tuning changes actual static sag", "soft=%.3f firm=%.3f m" % [soft.frontCompression, firm.frontCompression])
	_check(float(soft.rearCompression) > float(firm.rearCompression) + 0.005, "Rear spring tuning changes actual static sag", "soft=%.3f firm=%.3f m" % [soft.rearCompression, firm.rearCompression])
	_check(soft_front_offset > firm_front_offset + 0.005 and soft_rear_offset > firm_rear_offset + 0.005, "Tuning moves physical wheel bodies relative to chassis", "front delta=%.3f rear delta=%.3f m" % [soft_front_offset - firm_front_offset, soft_rear_offset - firm_rear_offset])
	print("NATIVE spring tuning: front sag=%.3f/%.3f m, rear sag=%.3f/%.3f m" % [soft.frontCompression, firm.frontCompression, soft.rearCompression, firm.rearCompression])

func _test_power_and_brakes() -> void:
	await _new_bike()
	await _advance(1.0)
	bike.shift_gear(1)
	bike.set_controls({"throttle": 0.5, "clutch": 1.0, "footDown": true})
	await _advance(0.25)
	var origin: Vector3 = bike.chassis.global_position
	for index: int in range(180):
		var engagement: float = minf(1.0, float(index) / 110.0)
		bike.set_controls({"throttle": 0.5, "clutch": 1.0 - engagement, "footDown": index < 95})
		await _next_tick()
	var powered: Dictionary = bike.get_telemetry()
	var forward_distance: float = origin.z - bike.chassis.global_position.z
	_check(forward_distance > 0.2, "Geared clutch engagement accelerates the actual chassis forward", "%.3f m, velocity %s" % [forward_distance, bike.chassis.linear_velocity])
	_check(_omega(bike.rear_wheel) < -1.0, "Drivetrain turns the actual rear native wheel", str(_omega(bike.rear_wheel)))
	_check(_finite_vector(bike.chassis.linear_velocity), "Power application leaves finite native velocity")
	print("NATIVE launch: displacement=%.3f m, speed=%.3f m/s, rear omega=%.3f rad/s, slip=%.3f" % [forward_distance, bike.chassis.linear_velocity.length(), _omega(bike.rear_wheel), powered.rearSlip])
	# Airborne rotor benches isolate the two brakes without ground loads or tire
	# model assumptions. All bodies still integrate native gravity and joints.
	await _new_bike(Vector3(0.0, 12.0, 0.0))
	_set_native_motion(Vector3.ZERO, -24.0, -24.0)
	bike.set_controls({"frontBrake": 1.0, "rearBrake": 0.0, "clutch": 1.0, "footDown": false})
	await _advance(0.09)
	var front_braked: float = absf(_omega(bike.front_wheel))
	var rear_unbraked: float = absf(_omega(bike.rear_wheel))
	_check(front_braked < 5.0 and rear_unbraked > 15.0, "Front brake acts only on the actual front rotor", "front=%.2f rear=%.2f" % [front_braked, rear_unbraked])
	await _new_bike(Vector3(0.0, 12.0, 0.0))
	_set_native_motion(Vector3.ZERO, -24.0, -24.0)
	bike.set_controls({"frontBrake": 0.0, "rearBrake": 1.0, "clutch": 1.0, "footDown": false})
	await _advance(0.14)
	var front_unbraked: float = absf(_omega(bike.front_wheel))
	var rear_braked: float = absf(_omega(bike.rear_wheel))
	_check(front_unbraked > 15.0 and rear_braked < 5.0, "Rear brake acts only on the actual rear rotor", "front=%.2f rear=%.2f" % [front_unbraked, rear_braked])

func _test_stall_and_starter() -> void:
	await _new_bike()
	await _advance(1.0)
	bike.shift_gear(1)
	bike.set_controls({"clutch": 0.0, "throttle": 0.0, "frontBrake": 1.0, "rearBrake": 1.0, "footDown": true})
	await _advance(1.0)
	var stopped: Dictionary = bike.get_telemetry()
	_check(bool(stopped.stalled), "Braked first-gear clutch engagement can stall the engine", "RPM=%.1f" % stopped.rpm)
	_check(not bike.start_engine(), "Starter refuses engaged in-gear clutch")
	bike.set_controls({"clutch": 1.0, "frontBrake": 1.0, "rearBrake": 1.0, "footDown": true})
	_check(bike.start_engine(), "Explicit starter works with pulled clutch")
	await _advance(0.15)
	_check(not bool(bike.get_telemetry().stalled) and float(bike.get_telemetry().rpm) > 1000.0, "Starter restores a running crank without resetting bike position")

func _test_native_rotor_speed_budget() -> void:
	await _new_bike(Vector3(0.0, 12.0, 0.0))
	bike.set_controls({"clutch": 1.0, "footDown": false})
	_set_native_motion(Vector3.ZERO, -100.0, -100.0)
	await _advance(0.08)
	var front_speed: float = absf(_omega(bike.front_wheel))
	var rear_speed: float = absf(_omega(bike.rear_wheel))
	_check(front_speed > 95.0 and rear_speed > 95.0, "Native engine preserves 100 rad/s tire rotation above the Jolt default cap", "front=%.3f rear=%.3f rad/s" % [front_speed, rear_speed])
	print("NATIVE unrestricted rotor speed: front=%.3f rear=%.3f rad/s" % [front_speed, rear_speed])

func _test_moving_parent_brake_passivity() -> void:
	# A wheel rotating +1 rad/s in the world still rotates -4 rad/s relative
	# to a +5 rad/s parent. A brake must speed up that wheel and slow its parent;
	# applying an absolute-world-speed brake would do work in the wrong direction.
	for front: bool in [true, false]:
		await _new_bike(Vector3(0.0, 12.0, 0.0))
		bike.set_controls({"clutch": 1.0, "footDown": false})
		await _advance(0.25)
		_set_pitched_bearing_motion(5.0, 1.0 if front else 5.0, 5.0 if front else 1.0)
		# Runtime body setters and the direct native integration callback are
		# synchronized across a physics boundary before taking the initial sample.
		await _advance(2.0 / HZ)
		var wheel: RigidBody3D = bike.front_wheel if front else bike.rear_wheel
		var parent: RigidBody3D = bike.fork if front else bike.chassis
		var axis: Vector3 = wheel.global_basis.x.normalized()
		var initial_wheel: float = wheel.angular_velocity.dot(axis)
		var initial_parent: float = parent.angular_velocity.dot(axis)
		var initial_relative: float = initial_wheel - initial_parent
		var initial_energy: float = _native_mechanical_energy()
		bike.set_controls({"clutch": 1.0, "footDown": false, "frontBrake": 1.0 if front else 0.0, "rearBrake": 0.0 if front else 1.0})
		await _advance(4.0 / HZ)
		var final_wheel: float = wheel.angular_velocity.dot(axis)
		var final_parent: float = parent.angular_velocity.dot(axis)
		var final_relative: float = final_wheel - final_parent
		var final_energy: float = _native_mechanical_energy()
		var label := "Front" if front else "Rear"
		_check(final_wheel > initial_wheel + 0.05, "%s brake opposes bearing speed when world-wheel speed has opposite sign" % label, "wheel %.3f -> %.3f, parent %.3f -> %.3f" % [initial_wheel, final_wheel, initial_parent, final_parent])
		_check(absf(final_relative) < absf(initial_relative) - 0.05 and final_relative * initial_relative >= -0.02, "%s brake reduces relative wheel-parent spin without overshoot" % label, "relative %.3f -> %.3f rad/s" % [initial_relative, final_relative])
		_check(final_energy < initial_energy - 0.05, "%s brake dissipates native mechanical energy with moving parent" % label, "delta %.5f J" % [final_energy - initial_energy])
		print("NATIVE %s moving-parent brake: wheel %.3f -> %.3f, bearing %.3f -> %.3f, native energy delta %.5f J" % [label.to_lower(), initial_wheel, final_wheel, initial_relative, final_relative, final_energy - initial_energy])

func _test_native_steering_gyro() -> void:
	var measured_roll_rates: Array[float] = []
	var measured_steer_angles: Array[float] = []
	for front_spin: float in [0.0, -100.0]:
		await _new_bike(Vector3(0.0, 12.0, 0.0))
		bike.set_controls({"clutch": 1.0, "footDown": false})
		await _advance(0.15)
		_set_native_motion(Vector3.ZERO, front_spin, 0.0)
		bike.set_controls({"clutch": 1.0, "footDown": false, "steer": 0.5})
		await _advance(0.25)
		measured_roll_rates.append(bike.chassis.angular_velocity.dot(bike.chassis.global_basis.z))
		measured_steer_angles.append(float(bike.get_telemetry().steerAngle))
	_check(absf(measured_steer_angles[0]) > 0.01, "Steering torque moves actual native fork bearing")
	_check(absf(measured_roll_rates[1] - measured_roll_rates[0]) > 0.05, "Actual spinning front tire changes chassis roll through steering gyroscopic coupling", "no spin=%.4f spin=%.4f rad/s" % [measured_roll_rates[0], measured_roll_rates[1]])
	print("NATIVE steering/gyro: zero/spinning front roll rates=%.4f/%.4f rad/s, steering angles=%.4f/%.4f rad" % [measured_roll_rates[0], measured_roll_rates[1], measured_steer_angles[0], measured_steer_angles[1]])

func _test_surfaces() -> void:
	await _new_bike()
	await _advance(1.0)
	var hardpack: Dictionary = bike.get_telemetry()
	floor_body.set_meta("physics_surface", "mud")
	await _advance(0.2)
	var mud: Dictionary = bike.get_telemetry()
	_check(hardpack.frontSurface == "hardpack" and hardpack.rearSurface == "hardpack", "Native contact collider supplies hardpack surface tag")
	_check(mud.frontSurface == "mud" and mud.rearSurface == "mud", "Both native wheels detect changed ground material")
	_check(float(mud.frontGrip) < float(hardpack.frontGrip) * 0.65 and float(mud.rearGrip) < float(hardpack.rearGrip) * 0.65, "Mud reduces independent front/rear grip", "hardpack=%.3f/%.3f mud=%.3f/%.3f" % [hardpack.frontGrip, hardpack.rearGrip, mud.frontGrip, mud.rearGrip])
	floor_body.set_meta("physics_surface", "hardpack")

func _test_native_wheelspin() -> void:
	floor_body.set_meta("physics_surface", "mud")
	await _new_bike()
	await _advance(1.0)
	bike.shift_gear(1)
	bike.set_controls({"throttle": 1.0, "clutch": 1.0, "footDown": true})
	await _advance(1.0)
	var maximum_slip := 0.0
	var maximum_tread_difference := 0.0
	var supported_ticks := 0
	for index: int in range(180):
		bike.set_controls({"throttle": 1.0, "clutch": maxf(0.0, 1.0 - float(index) / 100.0), "footDown": index < 120})
		await _next_tick()
		var state: Dictionary = bike.get_telemetry()
		if bool(state.rearContact) and float(state.rearLoad) > 100.0:
			supported_ticks += 1
			maximum_slip = maxf(maximum_slip, absf(float(state.rearSlip)))
			var tread_speed: float = -_omega(bike.rear_wheel) * float(cfg.RearRadius)
			var hub_speed: float = bike.rear_wheel.linear_velocity.dot(-bike.chassis.global_basis.z)
			maximum_tread_difference = maxf(maximum_tread_difference, tread_speed - hub_speed)
	_check(supported_ticks > 30, "Wheelspin test keeps the actual rear tire volume under load")
	_check(maximum_slip > 0.15 and maximum_tread_difference > 0.75, "Mud traction allows actual native rear wheelspin", "slip=%.3f tread-hub=%.3f m/s" % [maximum_slip, maximum_tread_difference])
	print("NATIVE mud wheelspin: slip=%.3f, native tread-hub difference=%.3f m/s" % [maximum_slip, maximum_tread_difference])
	floor_body.set_meta("physics_surface", "hardpack")

func _test_balance_crash_and_vertical_contact() -> void:
	await _new_bike(Vector3(0.0, 0.82, 0.0), Basis(Vector3.FORWARD, deg_to_rad(16.0)))
	bike.set_controls({"clutch": 1.0, "footDown": false})
	var initial_roll: float = absf(float(bike.get_telemetry().roll))
	await _advance(1.5)
	var fallen: Dictionary = bike.get_telemetry()
	_check(absf(float(fallen.roll)) > maxf(0.8, initial_roll + 0.35), "Unassisted tilted bike falls under actual gravity", "initial=%.3f final=%.3f" % [initial_roll, fallen.roll])
	_check(bool(fallen.crashed), "Physical loss of balance records a crash", str(fallen.crashReason))
	var remaining: float = fallen.recoveryRemaining
	await _advance(0.5)
	_check(float(bike.get_telemetry().recoveryRemaining) < remaining, "Crash recovery delay advances in simulation time")
	# Unlike a ray-from-axle model, a sideways native wheel volume still collides.
	# Place the rear wheel just above the floor; the chassis may land alongside
	# it, but wheel volume/contact remains an independently observable fact.
	var rear_first_pose := Basis(Vector3.RIGHT, deg_to_rad(25.0)) * Basis(Vector3.FORWARD, deg_to_rad(87.0))
	await _new_bike(Vector3(0.0, 0.55, 0.0), rear_first_pose)
	bike.set_controls({"clutch": 1.0, "footDown": false})
	var observed_native_contact := false
	var observed_model_contact := false
	var smallest_up_dot := 1.0
	for _tick: int in range(120):
		await _next_tick()
		if bike.rear_wheel.get_contact_count() > 0:
			observed_native_contact = true
			observed_model_contact = observed_model_contact or bool(bike.get_telemetry().rearContact)
			smallest_up_dot = minf(smallest_up_dot, absf(bike.chassis.global_basis.y.dot(Vector3.UP)))
	_check(observed_native_contact, "Near-horizontal axle uses native rear-wheel volume collision")
	_check(observed_model_contact and smallest_up_dot < 0.2, "Contact model retains native rear contact at near-vertical lean", "up dot=%.3f" % smallest_up_dot)
	_check(_finite_vector(bike.chassis.global_position) and bike.chassis.global_position.y > -0.3, "Sideways native collision prevents falling through floor")
	print("NATIVE balance/contact: fall roll=%.3f rad, crash=%s, sideways contact up-dot=%.3f" % [fallen.roll, fallen.crashReason, smallest_up_dot])

func _test_airborne_dynamics() -> void:
	var tilt := Basis(Vector3.FORWARD, deg_to_rad(22.0))
	await _new_bike(Vector3(0.0, 12.0, 0.0), tilt)
	bike.set_controls({"clutch": 1.0, "footDown": false})
	_set_native_motion(Vector3(0.0, 2.0, -7.0))
	var start_y: float = bike.chassis.global_position.y
	var start_z: float = bike.chassis.global_position.z
	var start_roll: float = bike.get_telemetry().roll
	await _advance(0.5)
	var air: Dictionary = bike.get_telemetry()
	var expected_y: float = start_y + 2.0 * 0.5 - 0.5 * 9.81 * 0.5 * 0.5
	_check(not bool(air.frontContact) and not bool(air.rearContact), "Airborne wheels have no fabricated ground contact")
	_check(absf(bike.chassis.linear_velocity.y - (2.0 - 9.81 * 0.5)) < 0.5, "Native flight velocity follows gravity", str(bike.chassis.linear_velocity))
	_check(absf(bike.chassis.global_position.y - expected_y) < 0.25, "Native flight follows ballistic height", "expected %.3f actual %.3f" % [expected_y, bike.chassis.global_position.y])
	_check(absf(bike.chassis.global_position.z - (start_z - 3.5)) < 0.25, "Airborne forward velocity is not replaced by a target speed")
	_check(absf(float(air.roll) - start_roll) < 0.15, "Airborne neutral inputs preserve tilted attitude without automatic correction", "initial %.3f final %.3f" % [start_roll, air.roll])
	bike.set_controls({"clutch": 1.0, "footDown": false, "bodySide": 1.0, "bodyForward": 1.0, "standing": true, "lean": 0.6})
	await _advance(0.25)
	_check(bike.chassis.angular_velocity.length() > 0.05, "Rider motion creates actual airborne body angular velocity", str(bike.chassis.angular_velocity))
	_check(bool(bike.get_telemetry().standing), "Standing posture reaches the simulation state")
	print("NATIVE flight: initial roll=%.3f, neutral roll=%.3f, controlled angular velocity=%s" % [start_roll, air.roll, bike.chassis.angular_velocity])

func _test_native_ramp_and_landing() -> void:
	var ramp := _static_box("LaunchRamp", Vector3(0.0, 1.32, 0.0), Vector3(6.0, 0.25, 8.0), "hardpack", deg_to_rad(18.0))
	await _new_bike(Vector3(0.0, 0.82, 10.0))
	bike.set_controls({"clutch": 1.0, "footDown": false})
	_set_native_motion(Vector3(0.0, 0.0, -14.0), -14.0 / float(cfg.FrontRadius), -14.0 / float(cfg.RearRadius))
	var ramp_contact := false
	var flew := false
	var landed := false
	var air_ticks := 0
	var highest := 0.0
	var fastest_down := 0.0
	for _tick: int in range(960):
		await _next_tick()
		var state: Dictionary = bike.get_telemetry()
		var contact: bool = bool(state.frontContact) or bool(state.rearContact)
		var chassis_pos: Vector3 = bike.chassis.global_position
		highest = maxf(highest, chassis_pos.y)
		fastest_down = minf(fastest_down, bike.chassis.linear_velocity.y)
		if contact and chassis_pos.z < 4.0 and chassis_pos.y > 1.1:
			ramp_contact = true
		# Require the bike to clear the lip. Contact gaps while climbing a curved
		# tire onto a box edge are not the intended jump or landing here.
		if ramp_contact and not contact and chassis_pos.z < -4.5 and chassis_pos.y > 1.5:
			air_ticks += 1
			flew = flew or air_ticks >= 8
		if flew and contact and chassis_pos.z < -5.0 and bike.chassis.linear_velocity.y < 0.5:
			landed = true
			break
	_check(ramp_contact, "Actual tires climb the physical launch ramp")
	_check(flew and air_ticks >= 8 and highest > 2.0, "Native ramp launches the bike into measurable airtime", "height=%.3f m airtime>=%.3f s" % [highest, float(air_ticks) / HZ])
	_check(landed and fastest_down < -1.0, "Airborne bike returns to actual native landing contact", "landed=%s down=%.3f m/s" % [landed, fastest_down])
	_check(_finite_vector(bike.chassis.linear_velocity) and _finite_vector(bike.chassis.angular_velocity), "Native launch/landing velocities remain finite")
	print("NATIVE ramp: max height=%.3f m, airtime>=%.3f s, max descent=%.3f m/s, landed=%s" % [highest, float(air_ticks) / HZ, fastest_down, landed])
	ramp.queue_free()
	await _next_tick()

func _test_actual_track_contacts() -> void:
	# Exercise the shipped track builder and its collider metadata, not only
	# laboratory fixtures. Remove the flat floor so it cannot mask mesh faults.
	if is_instance_valid(bike):
		bike.queue_free()
	floor_body.queue_free()
	await _next_tick()
	var builder: Script = load("res://scripts/track_builder.gd")
	if builder == null or not builder.can_instantiate():
		_check(false, "Actual proving-ground builder compiles")
		return
	var track: Dictionary = builder.build(world)
	_check(track.has("spawn") and track.has("gates"), "Actual proving ground exposes playable spawn and race gates")
	var pads: Array = [
		{"surface": "hardpack", "position": Vector3(-7.0, 0.95, -11.0)},
		{"surface": "sand", "position": Vector3(7.0, 0.95, -11.0)},
		{"surface": "mud", "position": Vector3(-7.0, 0.95, 11.0)},
		{"surface": "loam", "position": Vector3(7.0, 0.95, 11.0)}]
	var actual_grips: Dictionary = {}
	for pad: Dictionary in pads:
		await _new_bike(pad.position)
		await _advance(1.5)
		var state: Dictionary = bike.get_telemetry()
		_check(bool(state.frontContact) and bool(state.rearContact), "Actual %s traction pad supports both native tires" % pad.surface)
		_check(state.frontSurface == pad.surface and state.rearSurface == pad.surface, "Actual %s pad reaches independent wheel contact model" % pad.surface, "%s / %s" % [state.frontSurface, state.rearSurface])
		_check(state.frontNormal.dot(Vector3.UP) > 0.7 and state.rearNormal.dot(Vector3.UP) > 0.7, "Actual %s pad supplies upward collision normals" % pad.surface)
		actual_grips[pad.surface] = Vector2(float(state.frontGrip), float(state.rearGrip))
	_check(actual_grips.mud.x < actual_grips.hardpack.x * 0.65 and actual_grips.mud.y < actual_grips.hardpack.y * 0.65, "Shipped track mud has lower actual grip than hardpack", str(actual_grips))
	print("NATIVE shipped proving-ground pad grips: ", actual_grips)

func _run() -> void:
	if not FileAccess.file_exists(BIKE_PATH) or not FileAccess.file_exists(CONFIG_PATH):
		push_error("Native test prerequisites are missing")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		push_error("Native test bike configuration is invalid")
		quit(2)
		return
	cfg = parsed
	bike_script = load(BIKE_PATH)
	if bike_script == null or not bike_script.can_instantiate():
		push_error("Native bike script or its dependencies failed to compile")
		quit(2)
		return
	Engine.physics_ticks_per_second = int(HZ)
	_check(ProjectSettings.get_setting("physics/3d/physics_engine", "") == "Jolt Physics", "Project selects native Jolt physics backend")
	_check(absf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 0.0)) - 9.81) < 0.001, "Project gravity uses meters and 9.81 m/s²")
	world = Node3D.new()
	world.name = "NativePhysicsScenarioWorld"
	root.add_child(world)
	floor_body = _static_box("HardpackFloor", Vector3(0.0, -0.15, 0.0), Vector3(80.0, 0.3, 240.0))
	await _test_structure_and_settle()
	await _test_suspension_tuning()
	await _test_neutral_and_clutch()
	await _test_power_and_brakes()
	await _test_stall_and_starter()
	await _test_native_rotor_speed_budget()
	await _test_moving_parent_brake_passivity()
	await _test_native_steering_gyro()
	await _test_surfaces()
	await _test_native_wheelspin()
	await _test_balance_crash_and_vertical_contact()
	await _test_airborne_dynamics()
	await _test_native_ramp_and_landing()
	await _test_actual_track_contacts()
	print("Native Jolt integration checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	if not failures.is_empty():
		for failure: String in failures:
			print("  FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)
