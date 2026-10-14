extends SceneTree
## An isolated native five-body bench, not a riding fixture. Bodies remain
## unfrozen under Jolt. Gravity/ground/engine/drag are excluded so paired rider
## and suspension interactions can be assessed without unknown external work.
## The canonical coherent wheel-aligned fixture keeps the 2% raw angular and
## 1% work/energy bounds. --counter-rotation runs the harder coherent cancelling
## momentum fixture with those SAME guards; its known native failure remains
## reproducible. See VALIDATION.md for the measured limitation and old fixture.
const Bike = preload("res://scripts/bike_controller.gd")
var bike: Node3D
var bodies: Array[RigidBody3D] = []
var cfg: Dictionary
var checks := 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []
var counter_rotation := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + detail if not detail.is_empty() else ""))
		push_error("RIDER DYNAMICS FAIL: " + failures[-1])

func _tick() -> void:
	await physics_frame
	await process_frame

func _new_bike(hz: int, basis: Basis = Basis.IDENTITY, clear_joints: bool = false) -> void:
	if is_instance_valid(bike):
		bike.queue_free()
		await _tick()
	Engine.physics_ticks_per_second = hz
	bike = Bike.new()
	bike.configure(cfg)
	root.add_child(bike)
	bike.set_physics_process(false)
	bike.reset_bike(Transform3D(basis, Vector3.ZERO))
	# The complete shipped virtual rider includes finite local handlebar grip.
	# Omitting that actuator lets an undamped spinning fork hit dissipative
	# native stops, invalidating a work budget that omits constraint impacts.
	bike.set_riding_mode("virtual_rider")
	bodies.assign([bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel, bike.rider_body])
	for body: RigidBody3D in bodies:
		body.gravity_scale = 0.0
		body.collision_mask = 0
	if clear_joints:
		for joint: Joint3D in bike._joints:
			PhysicsServer3D.joint_clear(joint.get_rid())
	await _tick()
	await _tick()

func _center() -> Vector3:
	var center := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in bodies:
		center += (body.global_transform * body.center_of_mass) * body.mass
		mass += body.mass
	return center / mass

func _spin(body: RigidBody3D) -> Vector3:
	var local_omega := body.global_basis.inverse() * body.angular_velocity
	return body.global_basis * (body.inertia * local_omega)

func _momentum() -> Array[Vector3]:
	var linear := Vector3.ZERO
	var angular := Vector3.ZERO
	var center := _center()
	for body: RigidBody3D in bodies:
		var p := body.mass * body.linear_velocity
		linear += p
		angular += _spin(body) + (body.global_transform * body.center_of_mass - center).cross(p)
	return [linear, angular]

func _relative_energy() -> float:
	var velocity := _momentum()[0] / 187.0
	var result := 0.0
	for body: RigidBody3D in bodies:
		var local_omega := body.global_basis.inverse() * body.angular_velocity
		result += 0.5 * body.mass * (body.linear_velocity - velocity).length_squared()
		result += 0.5 * local_omega.dot(body.inertia * local_omega)
	return result

func _applied_wrenches() -> Array[Dictionary]:
	# Read the production controller's actual applied forces. Work uses
	# COM-force + COM-torque, with each wrench held over this native step.
	var rider_force: Vector3 = bike._rider_force
	var rider_torque: Vector3 = bike._rider_torque
	var lever: Vector3 = bike.rider_body.global_position - bike.chassis.global_transform * bike.chassis.center_of_mass
	var result: Array[Dictionary] = [
		{"body": bike.rider_body, "force": rider_force, "torque": rider_torque},
		{"body": bike.chassis, "force": -rider_force, "torque": lever.cross(-rider_force) - rider_torque}]
	for front: bool in [true, false]:
		var wheel: RigidBody3D = bike.front_wheel if front else bike.rear_wheel
		var parent: RigidBody3D = bike.fork if front else bike.chassis
		var state: Dictionary = bike.front_suspension_state if front else bike.rear_suspension_state
		var caster := float(cfg.Steering.Caster) if front else 0.0
		var force := (parent.global_basis * Vector3(0, cos(caster), sin(caster))) * float(state.force)
		var hub_lever := wheel.global_position - parent.global_transform * parent.center_of_mass
		result.append({"body": wheel, "force": -force, "torque": Vector3.ZERO})
		result.append({"body": parent, "force": force, "torque": hub_lever.cross(force)})
	var steering_axis: Vector3 = bike.chassis.global_basis * Vector3(0, cos(float(cfg.Steering.Caster)), sin(float(cfg.Steering.Caster)))
	var steering_torque: Vector3 = steering_axis * float(bike._rider_steering_torque)
	result.append({"body": bike.fork, "force": Vector3.ZERO, "torque": steering_torque})
	result.append({"body": bike.chassis, "force": Vector3.ZERO, "torque": -steering_torque})
	return result

func _wrench_power(wrenches: Array[Dictionary]) -> float:
	var result := 0.0
	for wrench: Dictionary in wrenches:
		var body: RigidBody3D = wrench.body
		result += Vector3(wrench.force).dot(body.linear_velocity) + Vector3(wrench.torque).dot(body.angular_velocity)
	return result

func _force_pair_case(basis: Basis) -> void:
	await _new_bike(240, basis, true)
	await physics_frame
	var human: RigidBody3D = bike.rider_body
	var frame: RigidBody3D = bike.chassis
	var initial := _momentum()
	var initial_human_spin := _spin(human)
	var initial_frame_spin := _spin(frame)
	var initial_human_velocity := human.linear_velocity
	var initial_frame_velocity := frame.linear_velocity
	var common_point := human.global_position
	var frame_center := frame.global_transform * frame.center_of_mass
	bike._apply_rider_support(Vector3(0.07, 0.62, -0.05))
	var force: Vector3 = bike._rider_force
	var torque: Vector3 = bike._rider_torque
	var expected_frame_torque := (common_point - frame_center).cross(-force) - torque
	await physics_frame
	await physics_frame
	await process_frame
	var dt := 1.0 / 240.0
	_check(force.length() > 100.0 and force.length() <= float(cfg.RiderSupport.MaxForce) + 0.01, "Native support applies finite nontrivial force")
	_check(((human.linear_velocity - initial_human_velocity) * human.mass - force * dt).length() < 0.003, "Actual rider momentum receives the support force")
	_check(((frame.linear_velocity - initial_frame_velocity) * frame.mass + force * dt).length() < 0.003, "Actual frame momentum receives the opposite support force")
	_check((_spin(human) - initial_human_spin - torque * dt).length() < 0.005, "Native torso spin receives the paired posture torque")
	_check((_spin(frame) - initial_frame_spin - expected_frame_torque * dt).length() < 0.005, "Native frame spin receives force at the same world point and opposite posture torque")
	_check((_momentum()[0] - initial[0]).length() < 0.003 and (_momentum()[1] - initial[1]).length() < 0.008, "Actual common-point pair introduces no significant internal couple")

func _coupled_case(hz: int, active: bool) -> Dictionary:
	await _new_bike(hz)
	await physics_frame
	var total_mass := 0.0
	var rigid_center := _center()
	var rigid_velocity := Vector3(2, 1, -5)
	var rigid_rotation := Vector3(0.3 if counter_rotation else -0.3, 0.15, 0.08)
	for body: RigidBody3D in bodies:
		# A rotating assembly's hubs must have the transport velocity of
		# their actual COM offsets. Equal translations with nonzero common
		# rotation violate its native bearing/slider velocities at startup.
		var body_center := body.global_transform * body.center_of_mass
		body.linear_velocity = rigid_velocity + rigid_rotation.cross(body_center - rigid_center)
		body.angular_velocity = rigid_rotation
		total_mass += body.mass
	var rigid_momentum := _momentum()[1]
	# Independent spin is relative to the machine and follows each real axle.
	bike.front_wheel.angular_velocity -= bike.front_wheel.global_basis.x * 20.0
	bike.rear_wheel.angular_velocity -= bike.rear_wheel.global_basis.x * 20.0
	var axle_momentum: Vector3 = _momentum()[1] - rigid_momentum
	if not active:
		# Free flight has no leg weight preload. Excite actual relative motion
		# once so the passive damping bench has energy to dissipate, instead
		# of depending on that former unsupported preload to start moving.
		# All machine bodies share the balancing velocity, preserving their
		# native joint compatibility and total linear momentum.
		var rider_excitation := Vector3(0.0, 0.25, 0.0)
		bike.rider_body.linear_velocity += rider_excitation
		var machine_reaction: Vector3 = rider_excitation * float(bike.rider_body.mass) / (total_mass - float(bike.rider_body.mass))
		for body: RigidBody3D in [bike.chassis, bike.fork, bike.front_wheel, bike.rear_wheel]:
			body.linear_velocity -= machine_reaction
	var initial := _momentum()
	# Report cancellation sensitivity in a COM-relative, frame-independent
	# activity scale. The strict angular GUARD still uses raw net momentum.
	var excitation_momentum: Vector3 = initial[1] - rigid_momentum - axle_momentum
	var momentum_budget := rigid_momentum.length() + axle_momentum.length() + excitation_momentum.length()
	var initial_center := _center()
	var initial_relative: Vector3 = bike.chassis.to_local(bike.rider_body.global_position)
	var fixed_com: Vector3 = bike.chassis.center_of_mass
	var fixed_inertia: Vector3 = bike.chassis.inertia
	var initial_energy := _relative_energy()
	var peak_linear := 0.0
	var peak_angular := 0.0
	var peak_angular_absolute := 0.0
	var peak_transport := 0.0
	var peak_relative_motion := 0.0
	var peak_force := 0.0
	var peak_torque := 0.0
	var peak_bar_torque := 0.0
	var peak_bar_angle := 0.0
	var peak_air_feedback := 0.0
	var work := 0.0
	var damping_work := 0.0
	for i: int in range(hz * 3):
		var dt := 1.0 / hz
		var input := {"bodyForward": 0.5 if i < hz * 3 / 2 else -0.5, "bodySide": 0.4 if i < hz * 3 / 2 else -0.4, "lean": 0.3, "standing": true, "footDown": false}
		if not active:
			input = {"bodyForward": 0.0, "bodySide": 0.0, "lean": 0.0, "standing": false, "footDown": false}
		# Advance the real unsupported-air perception while the normal game
		# callback is disabled to exclude engine, gravity and aerodynamic work.
		bike._detect_crash(dt)
		bike.set_controls(input)
		bike._update_rider(bike.controls, dt)
		var offset: Vector3 = bike.rider_body.global_position - bike.chassis.global_transform * bike.chassis.center_of_mass
		var frame_velocity: Vector3 = bike.chassis.linear_velocity + bike.chassis.angular_velocity.cross(offset)
		var local_rate: Vector3 = bike.chassis.global_basis.inverse() * (bike.rider_body.linear_velocity - frame_velocity)
		var damping := Vector3(float(cfg.RiderSupport.SideDamping), float(cfg.RiderSupport.VerticalDamping), float(cfg.RiderSupport.ForeDamping))
		var relative_omega: Vector3 = bike.rider_body.angular_velocity - bike.chassis.angular_velocity
		var local_relative_omega: Vector3 = bike.chassis.global_basis.inverse() * relative_omega
		var posture_damping := Vector3(float(cfg.RiderSupport.PostureDamping),
			float(cfg.RiderSupport.get("YawPostureDamping", 25.0)), float(cfg.RiderSupport.PostureDamping))
		# Yaw is a separately tuned torso mode. Resolve angular speed in the
		# bike frame so this diagnostic accounts for the actual damping law.
		damping_work -= (local_rate.dot(damping * local_rate) + local_relative_omega.dot(posture_damping * local_relative_omega)) * dt
		bike._apply_suspension(bike.front_wheel, bike.fork, Bike.FRONT_AXLE - Bike.HEAD, true, dt)
		bike._apply_suspension(bike.rear_wheel, bike.chassis, Bike.REAR_AXLE, false, dt)
		bike._apply_steering(bike.controls, dt)
		var wrenches := _applied_wrenches()
		var power_before := _wrench_power(wrenches)
		peak_force = maxf(peak_force, bike._rider_force.length())
		peak_torque = maxf(peak_torque, bike._rider_torque.length())
		peak_bar_torque = maxf(peak_bar_torque, absf(float(bike._rider_steering_torque)))
		var axis: Vector3 = bike.chassis.global_basis * Vector3(0, cos(float(cfg.Steering.Caster)), sin(float(cfg.Steering.Caster)))
		var frame_right: Vector3 = bike.chassis.global_basis.x
		var fork_right: Vector3 = bike.fork.global_basis.x
		peak_bar_angle = maxf(peak_bar_angle, absf(atan2(axis.dot(frame_right.cross(fork_right)), frame_right.dot(fork_right))))
		peak_air_feedback = maxf(peak_air_feedback, absf(float(bike._rider_target_lean)) + absf(float(bike._heading_correction)))
		# Consume every physics signal, including both 480-Hz steps within a
		# 240-fps renderer frame; a process-frame wait would skip force steps.
		await physics_frame
		work += (power_before + _wrench_power(wrenches)) * dt * 0.5
		var now := _momentum()
		peak_linear = maxf(peak_linear, now[0].distance_to(initial[0]) / initial[0].length())
		peak_angular = maxf(peak_angular, now[1].distance_to(initial[1]) / initial[1].length())
		peak_angular_absolute = maxf(peak_angular_absolute, now[1].distance_to(initial[1]))
		peak_transport = maxf(peak_transport, _center().distance_to(initial_center + initial[0] / total_mass * float(i + 1) / hz))
		peak_relative_motion = maxf(peak_relative_motion, bike.chassis.to_local(bike.rider_body.global_position).distance_to(initial_relative))
	var result := {"hz": hz, "active": active, "counterRotation": counter_rotation, "rigidRotation": rigid_rotation,
		"initialAngularNms": initial[1], "initialAngularMagnitudeNms": initial[1].length(),
		"momentumBudgetNms": momentum_budget, "angularConditionNumber": momentum_budget / initial[1].length(),
		"peakAngularAbsoluteNms": peak_angular_absolute, "peakAngularBudgetRelative": peak_angular_absolute / momentum_budget,
		"mass": total_mass, "peakLinearRelative": peak_linear, "peakAngularRelative": peak_angular,
		"peakTransportM": peak_transport, "relativeMotionM": peak_relative_motion, "peakForceN": peak_force,
		"peakTorqueNm": peak_torque, "peakBarTorqueNm": peak_bar_torque, "peakBarAngleRad": peak_bar_angle,
		"peakAirFeedback": peak_air_feedback, "initialKineticJ": initial_energy, "finalKineticJ": _relative_energy(),
		"appliedWorkJ": work, "dampingWorkJ": damping_work, "workResidualJ": _relative_energy() - initial_energy - work}
	_check(absf(total_mass - 187.0) < 0.001, "Five native masses total 187 kg")
	_check(bike.chassis.center_of_mass == fixed_com and bike.chassis.inertia == fixed_inertia, "Articulation preserves the frame's fixed COM and inertia")
	_check(peak_linear < 0.0001 and peak_transport < 0.001, "Internal movement transports total COM without an external force", JSON.stringify(result))
	_check(peak_angular < 0.02, "Coupled native angular drift stays within the new documented 2% engineering bound", JSON.stringify(result))
	_check(peak_force <= float(cfg.RiderSupport.MaxForce) + 0.02 and peak_torque <= float(cfg.Rider.MaxReactionTorque) + 0.02, "Native muscle force and posture torque remain physically bounded")
	_check(peak_bar_torque <= float(cfg.VirtualRider.MaxTorque) + 0.02 and peak_bar_angle < float(cfg.Steering.MaxAngle) - 0.001
		and peak_air_feedback < 0.000001, "Unsupported handlebar grip is finite, local and avoids dissipative steering stops", JSON.stringify(result))
	_check(damping_work <= 0.0 and absf(float(result.workResidualJ)) < initial_energy * 0.01, "Internal actuator work accounts for energy to within 1%; relative damping dissipates energy", JSON.stringify(result))
	if active:
		_check(peak_relative_motion > 0.10 and bike._standing > 0.99, "Standing and body commands move the real torso relative to the frame")
	reports.append(result)
	print("RIDER DYNAMICS ", JSON.stringify(result))
	return result

func _run() -> void:
	counter_rotation = "--counter-rotation" in OS.get_cmdline_user_args()
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
	for basis: Basis in [Basis.IDENTITY, Basis.from_euler(Vector3(0.25, 0.4, -0.3)), Basis.from_euler(Vector3(-0.4, -0.6, 0.2))]:
		await _force_pair_case(basis)
	var active_240 := await _coupled_case(240, true)
	var active_480 := await _coupled_case(480, true)
	_check(float(active_480.peakAngularRelative) < float(active_240.peakAngularRelative) * 0.8, "Halving the native time step reduces coupled angular-momentum drift")
	var relaxed := await _coupled_case(240, false)
	_check(float(relaxed.dampingWorkJ) < -1.0 and float(relaxed.finalKineticJ) < float(relaxed.initialKineticJ) and float(relaxed.appliedWorkJ) < 0.0, "Relaxed finite support dissipates relative kinetic energy without a commanded body movement")
	var report := FileAccess.open("res://build/rider-dynamics-report-%d.json" % OS.get_process_id(), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "counterRotation": counter_rotation,
		"config": cfg, "cases": reports, "controllerHash": String(bike.get_script().source_code).sha256_text()}, "\t"))
	report.close()
	print("Rider dynamics native checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
