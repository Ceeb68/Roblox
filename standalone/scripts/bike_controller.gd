extends Node3D
class_name DLSimBike

## A native SI-unit, four-body motorcycle. Every contact and suspension end
## stop is resolved by Godot/Jolt. This is a prototype with explicit engineering
## coefficients, not a replication of any commercial motorcycle simulator.
const Drive = preload("res://physics/drivetrain.gd")
const Tire = preload("res://physics/tire.gd")
const Suspension = preload("res://physics/suspension.gd")
const Wheel = preload("res://scripts/wheel_body.gd")

class NativeBody:
	extends RigidBody3D
	const Gyro = preload("res://physics/gyroscope.gd")
	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		Gyro.integrate(state)
const FRONT_AXLE := Vector3(0.0, -0.44, -0.74)
const REAR_AXLE := Vector3(0.0, -0.44, 0.74)
const HEAD := Vector3(0.0, 0.36, -0.265)
const CONTROL_RANGES := {
	"throttle": Vector2(0, 1), "frontBrake": Vector2(0, 1),
	"rearBrake": Vector2(0, 1), "clutch": Vector2(0, 1),
	"steer": Vector2(-1, 1), "lean": Vector2(-1, 1),
	"bodyForward": Vector2(-1, 1), "bodySide": Vector2(-1, 1)
}
const TUNE_RANGES := {
	"SpringRate": Vector2(8000, 40000), "Compression": Vector2(300, 5000),
	"Rebound": Vector2(300, 6000), "Preload": Vector2(0, 0.035)
}

var config: Dictionary = {}
var chassis: RigidBody3D
var front_wheel: Wheel
var rear_wheel: Wheel
var fork: RigidBody3D
var controls: Dictionary = _neutral_controls()
var drive_state: Dictionary = {}
var front_tire_state: Dictionary = {}
var rear_tire_state: Dictionary = {}
var front_suspension_state: Dictionary = {}
var rear_suspension_state: Dictionary = {}
var _front_result: Dictionary = {}
var _rear_result: Dictionary = {}
var _drive_result: Dictionary = {}
var _joints: Array[Joint3D] = []
var _feet: Array[CollisionShape3D] = []
var _foot_visuals: Array[MeshInstance3D] = []
var _rider_visual: Node3D
var _rider_collision: CollisionShape3D
var _front_rods: Array[MeshInstance3D] = []
var _swingarm: Array[MeshInstance3D] = []
var _body_forward: float = 0.0
var _body_side: float = 0.0
var _body_lean: float = 0.0
var _standing: float = 0.0
var _rider_pitch_rate: float = 0.0
var _rider_roll_rate: float = 0.0
var _last_air_velocity := Vector3.ZERO
var _air_time: float = 0.0
var _last_rear_slide: bool = false
var _crash_elapsed: float = 0.0
var crashed: bool = false
var crash_reason: String = ""
var _built: bool = false
var _reset_pending: bool = false

static func _neutral_controls() -> Dictionary:
	return {"throttle": 0.0, "frontBrake": 0.0, "rearBrake": 0.0,
		"clutch": 1.0, "steer": 0.0, "lean": 0.0, "bodyForward": 0.0,
		"bodySide": 0.0, "standing": false, "footDown": true}

func configure(values: Dictionary) -> void:
	if _built:
		return
	config = values.duplicate(true)
	if is_inside_tree():
		_build_bike()

func _ready() -> void:
	if config.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json"))
		if parsed is Dictionary:
			config = parsed
	if not _built:
		_build_bike()

func _new_body(body_name: String, body_mass: float, local_origin: Vector3) -> RigidBody3D:
	var body := NativeBody.new()
	body.name = body_name
	body.mass = body_mass
	body.position = local_origin
	body.can_sleep = false
	body.continuous_cd = true
	body.max_contacts_reported = 16
	body.contact_monitor = true
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.collision_layer = 2
	body.collision_mask = 1
	add_child(body)
	return body

func _build_bike() -> void:
	if config.is_empty():
		push_error("250F config could not be loaded")
		return
	var mass_total: float = float(config.ChassisMass) + float(config.RiderMass)
	chassis = _new_body("ChassisAndRider", mass_total, Vector3.ZERO)
	chassis.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	chassis.center_of_mass = Vector3(0, 0.14, 0)
	chassis.inertia = Vector3(39.0, 29.0, 14.0)
	var guard_material := PhysicsMaterial.new()
	guard_material.friction = 0.45
	guard_material.bounce = 0.04
	chassis.physics_material_override = guard_material
	_box_collision(chassis, Vector3(0.27, 0.31, 0.61), Vector3(0, -0.09, 0.08))
	_box_collision(chassis, Vector3(0.32, 0.12, 0.81), Vector3(0, 0.20, 0.12))
	_rider_collision = CollisionShape3D.new()
	var rider_capsule := CapsuleShape3D.new()
	rider_capsule.radius = 0.14
	rider_capsule.height = 0.78
	_rider_collision.shape = rider_capsule
	_rider_collision.position = Vector3(0, 0.54, 0.09)
	chassis.add_child(_rider_collision)
	for side in [-1.0, 1.0]:
		var foot := CollisionShape3D.new()
		var foot_shape := CapsuleShape3D.new()
		foot_shape.radius = 0.05
		foot_shape.height = 0.28
		foot.shape = foot_shape
		foot.position = Vector3(side * 0.34, -0.62, 0.03)
		chassis.add_child(foot)
		_feet.append(foot)
		_foot_visuals.append(_box_mesh(chassis, Vector3(0.12, 0.20, 0.22), foot.position,
			Color(0.09, 0.10, 0.12)))
	fork = _new_body("SteeringFork", float(config.Unsprung.ForkMass), HEAD)
	fork.inertia = Vector3(0.15, 0.12, 0.06)
	# A tiny stem guard gives the body an explicit collision/mass geometry.
	_box_collision(fork, Vector3(0.12, 0.10, 0.12), Vector3.ZERO)
	front_wheel = _make_wheel("FrontWheel", float(config.FrontRadius), 0.085,
		float(config.Unsprung.FrontMass), float(config.FrontInertia), FRONT_AXLE)
	rear_wheel = _make_wheel("RearWheel", float(config.RearRadius), 0.115,
		float(config.Unsprung.RearMass), float(config.RearInertia), REAR_AXLE)
	for body_a in [chassis, fork, front_wheel, rear_wheel]:
		for body_b in [chassis, fork, front_wheel, rear_wheel]:
			if body_a != body_b:
				body_a.add_collision_exception_with(body_b)
	var caster: float = float(config.Steering.Caster)
	var fork_axis := Vector3(0, cos(caster), sin(caster))
	var fork_frame := Basis(Vector3.RIGHT, fork_axis, Vector3.RIGHT.cross(fork_axis))
	var steering := HingeJoint3D.new()
	steering.name = "SteeringBearing"
	steering.position = HEAD
	# A Godot hinge rotates about joint-local Z. Mechanical lock stops only;
	# there is no angle-target steering motor or world-up alignment.
	steering.basis = Basis(Vector3.RIGHT, fork_axis.cross(Vector3.RIGHT), fork_axis)
	add_child(steering)
	steering.node_a = steering.get_path_to(chassis)
	steering.node_b = steering.get_path_to(fork)
	steering.exclude_nodes_from_collision = true
	steering.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	steering.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -float(config.Steering.MaxAngle))
	steering.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, float(config.Steering.MaxAngle))
	steering.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
	_joints.append(steering)
	_add_suspension_joint("FrontForkSlider", fork, front_wheel, FRONT_AXLE,
		fork_frame, float(config.Suspension.Front.Travel))
	_add_suspension_joint("RearShockSlider", chassis, rear_wheel, REAR_AXLE,
		Basis.IDENTITY, float(config.Suspension.Rear.Travel))
	_build_visuals()
	_built = true
	_reset_models()

func _add_suspension_joint(joint_name: String, parent_body: RigidBody3D,
		wheel: RigidBody3D, origin: Vector3, frame: Basis, travel: float) -> void:
	var joint := Generic6DOFJoint3D.new()
	joint.name = joint_name
	joint.position = origin
	joint.basis = frame
	add_child(joint)
	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(wheel)
	joint.exclude_nodes_from_collision = true
	for axis in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis, true)
		joint.set("linear_limit_%s/lower_distance" % axis, 0.0)
		joint.set("linear_limit_%s/upper_distance" % axis, travel if axis == "y" else 0.0)
		joint.set("angular_limit_%s/enabled" % axis, axis != "x")
		joint.set("angular_limit_%s/lower_angle" % axis, 0.0)
		joint.set("angular_limit_%s/upper_angle" % axis, 0.0)
		joint.set("angular_motor_%s/enabled" % axis, false)
		joint.set("linear_motor_%s/enabled" % axis, false)
		joint.set("linear_spring_%s/enabled" % axis, false)
		joint.set("angular_spring_%s/enabled" % axis, false)
	_joints.append(joint)

func _make_wheel(wheel_name: String, radius: float, width: float,
		wheel_mass: float, spin_inertia: float, origin: Vector3) -> Wheel:
	var wheel := Wheel.new() as Wheel
	wheel.name = wheel_name
	wheel.mass = wheel_mass
	wheel.position = origin
	wheel.inertia = Vector3(spin_inertia, spin_inertia * 0.53, spin_inertia * 0.53)
	wheel.can_sleep = false
	wheel.continuous_cd = true
	wheel.max_contacts_reported = 16
	wheel.contact_monitor = true
	wheel.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	wheel.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	wheel.linear_damp = 0
	wheel.angular_damp = 0
	wheel.collision_layer = 2
	wheel.collision_mask = 1
	var rubber := PhysicsMaterial.new()
	rubber.friction = 0.0 # Tangential grip is supplied once by the brush model.
	rubber.bounce = 0.01
	rubber.rough = false
	wheel.physics_material_override = rubber
	add_child(wheel)
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = width
	collision.shape = cylinder
	collision.rotation.z = PI * 0.5
	wheel.add_child(collision)
	var tire_mesh := _cylinder_mesh(wheel, radius, width, Color(0.055, 0.06, 0.07))
	tire_mesh.rotation.z = PI * 0.5
	var rim := _cylinder_mesh(wheel, radius * 0.77, width * 1.04, Color(0.28, 0.32, 0.37))
	rim.rotation.z = PI * 0.5
	var inner := _cylinder_mesh(wheel, radius * 0.70, width * 1.06, Color(0.08, 0.10, 0.12))
	inner.rotation.z = PI * 0.5
	var hub := _cylinder_mesh(wheel, 0.062, width * 1.18, Color(0.75, 0.78, 0.82))
	hub.rotation.z = PI * 0.5
	for n in range(12):
		var angle := TAU * n / 12.0
		for side in [-1, 1]:
			var spoke := _cylinder_mesh(wheel, 0.006, 0.3, Color(0.57, 0.61, 0.67))
			_set_segment(spoke, Vector3(side * width * 0.55, 0, 0),
				Vector3(side * width * 0.55, cos(angle) * radius * 0.73, sin(angle) * radius * 0.73))
	return wheel

func _reset_models() -> void:
	drive_state = Drive.new_state(config.Drive)
	front_tire_state = Tire.new_state()
	rear_tire_state = Tire.new_state()
	front_suspension_state = Suspension.new_state()
	rear_suspension_state = Suspension.new_state()
	_front_result = {}
	_rear_result = {}
	_drive_result = {}
	_body_forward = 0
	_body_side = 0
	_body_lean = 0
	_standing = 0
	_rider_pitch_rate = 0
	_rider_roll_rate = 0
	_air_time = 0
	_last_rear_slide = false
	crashed = false
	crash_reason = ""
	_crash_elapsed = 0
	controls = _neutral_controls()

func reset_bike(spawn: Transform3D) -> bool:
	if not _built or (crashed and _crash_elapsed < float(config.Crash.RecoveryDelay)):
		return false
	_reset_models()
	# Explicit rider recovery/spawn is the sole transform/velocity reset path.
	# Normal riding and crashes never replace native motion with target poses.
	var bodies: Array[RigidBody3D] = [chassis, fork, front_wheel, rear_wheel]
	var positions: Array[Vector3] = [Vector3.ZERO, HEAD, FRONT_AXLE, REAR_AXLE]
	for i in range(bodies.size()):
		bodies[i].global_transform = spawn * Transform3D(Basis.IDENTITY, positions[i])
		bodies[i].linear_velocity = Vector3.ZERO
		bodies[i].angular_velocity = Vector3.ZERO
		bodies[i].sleeping = false
	front_wheel.clear_contact()
	rear_wheel.clear_contact()
	_update_feet()
	_reset_pending = true
	return true

func set_controls(packet: Dictionary) -> void:
	for axis in CONTROL_RANGES:
		if packet.has(axis):
			var value = packet[axis]
			if (value is float or value is int) and is_finite(float(value)):
				var limits: Vector2 = CONTROL_RANGES[axis]
				controls[axis] = clampf(float(value), limits.x, limits.y)
	for key in ["standing", "footDown"]:
		if packet.get(key) is bool:
			controls[key] = packet[key]
	if _built:
		_update_feet()

func shift_gear(delta: int) -> bool:
	return _built and not crashed and Drive.shift(drive_state, delta, controls, config.Drive)

func start_engine() -> bool:
	return _built and not crashed and Drive.start(drive_state, controls, config.Drive)

func tune_setup(changes: Dictionary) -> bool:
	if not _built or chassis.linear_velocity.length() >= 1.0:
		return false
	var next_setup: Dictionary = config.Suspension.duplicate(true)
	var count := 0
	for axle in changes:
		if axle not in ["Front", "Rear"] or not changes[axle] is Dictionary:
			return false
		for key in changes[axle]:
			var value = changes[axle][key]
			if not TUNE_RANGES.has(key) or not (value is int or value is float) or not is_finite(float(value)):
				return false
			var limits: Vector2 = TUNE_RANGES[key]
			next_setup[axle][key] = clampf(float(value), limits.x, limits.y)
			count += 1
	if count == 0:
		return false
	config.Suspension = next_setup
	return true

func _physics_process(dt: float) -> void:
	if not _built:
		return
	if _reset_pending:
		_reset_pending = false
		return # Solver contact cache from the previous spawn is not reusable.
	if crashed:
		_crash_elapsed += dt
	var active := controls.duplicate()
	if crashed:
		active.throttle = 0.0
		active.clutch = 1.0
		active.steer = 0.0
		active.lean = 0.0
		active.bodyForward = 0.0
		active.bodySide = 0.0
	_update_rider(active, dt)
	_apply_suspension(front_wheel, fork, FRONT_AXLE - HEAD, true, dt)
	_apply_suspension(rear_wheel, chassis, REAR_AXLE, false, dt)
	_apply_steering(active)
	_apply_drivetrain(active, dt)
	_front_result = _apply_tire(front_wheel, front_tire_state, float(config.FrontRadius), dt)
	_rear_result = _apply_tire(rear_wheel, rear_tire_state, float(config.RearRadius), dt)
	# Physical quadratic drag; no artificial lateral/angular damping on bike.
	var velocity := chassis.linear_velocity
	chassis.apply_central_force(-velocity * velocity.length() * 0.31)
	_detect_crash(dt)
	_update_visuals()

func _apply_suspension(wheel: Wheel, parent_body: RigidBody3D,
		full_droop: Vector3, is_front: bool, dt: float) -> void:
	var caster: float = float(config.Steering.Caster) if is_front else 0.0
	var axis := parent_body.global_basis * Vector3(0, cos(caster), sin(caster))
	var droop_position := parent_body.global_transform * full_droop
	var displacement := wheel.global_position - droop_position
	var compression := displacement.dot(axis)
	var parent_offset := wheel.global_position - parent_body.global_position
	var parent_velocity := parent_body.linear_velocity + parent_body.angular_velocity.cross(
		wheel.global_position - (parent_body.global_transform * parent_body.center_of_mass))
	var rate := (wheel.linear_velocity - parent_velocity).dot(axis)
	var settings: Dictionary = config.Suspension.Front if is_front else config.Suspension.Rear
	var state: Dictionary = front_suspension_state if is_front else rear_suspension_state
	var output: Dictionary = Suspension.step_articulated(state, compression, rate, dt, settings)
	var force := axis * float(output.force)
	# The compressed strut pushes wheel down, frame up. Equal-and-opposite
	# forces at the hub preserve total linear/angular momentum in the air.
	wheel.apply_central_force(-force)
	parent_body.apply_force(force, parent_offset)

func _apply_steering(input: Dictionary) -> void:
	var axis := chassis.global_basis * Vector3(0, cos(float(config.Steering.Caster)), sin(float(config.Steering.Caster)))
	var rate := (fork.angular_velocity - chassis.angular_velocity).dot(axis)
	var torque := axis * (-float(input.steer) * float(config.Steering.InputTorque)
		- rate * float(config.Steering.Damping))
	fork.apply_torque(torque)
	chassis.apply_torque(-torque)

func _apply_drivetrain(input: Dictionary, dt: float) -> void:
	var rear_axis := rear_wheel.global_basis.x.normalized()
	# Shaft speeds are bearing-relative. Absolute wheel spin belongs only in
	# the tire contact calculation; body pitch must not become gearbox RPM.
	var measured := (rear_wheel.angular_velocity - chassis.angular_velocity).dot(-rear_axis)
	var rear_effective_inertia := _bearing_inertia(rear_wheel, chassis, rear_axis)
	drive_state.rearOmega = measured
	var drive_config: Dictionary = config.Drive.duplicate()
	drive_config.RearInertia = rear_effective_inertia
	_drive_result = Drive.step(drive_state, input, 0.0, dt, drive_config)
	var wheel_impulse := -rear_axis * rear_effective_inertia * (float(_drive_result.rearOmega) - measured)
	rear_wheel.apply_torque_impulse(wheel_impulse)
	chassis.apply_torque_impulse(-wheel_impulse)
	# Virtual engine crank is coupled to chassis, wheels have native inertia.
	# engineOnlyReaction excludes the already-paired real rear-wheel impulse.
	chassis.apply_torque(chassis.global_basis.x * float(_drive_result.engineOnlyReaction))
	var engine_h := -chassis.global_basis.x * float(config.Drive.EngineInertia) * float(drive_state.engineOmega)
	chassis.apply_torque(-chassis.angular_velocity.cross(engine_h))
	var front_axis := front_wheel.global_basis.x.normalized()
	var front_omega := (front_wheel.angular_velocity - fork.angular_velocity).dot(-front_axis)
	# Pairing a finite Coulomb impulse changes both bearing bodies. The
	# combined inverse inertia prevents reversal or energy addition when the
	# wheel and fork already pitch together, including airborne braking.
	var front_effective_inertia := _bearing_inertia(front_wheel, fork, front_axis)
	var brake_impulse := minf(absf(front_omega) * front_effective_inertia,
		float(input.frontBrake) * float(config.Drive.FrontBrakeTorque) * dt)
	var impulse := front_axis * signf(front_omega) * brake_impulse
	front_wheel.apply_torque_impulse(impulse)
	fork.apply_torque_impulse(-impulse)

func _bearing_inertia(wheel: RigidBody3D, parent_body: RigidBody3D, axis: Vector3) -> float:
	var inverse_sum := axis.dot(wheel.get_inverse_inertia_tensor() * axis)
	inverse_sum += axis.dot(parent_body.get_inverse_inertia_tensor() * axis)
	return 1.0 / maxf(inverse_sum, 0.000001)

func _apply_tire(wheel: Wheel, state: Dictionary, radius: float, dt: float) -> Dictionary:
	var normal := wheel.contact_normal
	var axle := wheel.global_basis.x.normalized()
	var forward := normal.cross(axle)
	# Tire sidewalls still have native collision at a 90-degree fall. Rolling
	# direction is undefined there, so omit brush forces instead of inventing
	# a normal support or heading. No contact itself is removed.
	var usable_contact := wheel.contact and forward.length_squared() > 0.000001
	forward = forward.normalized()
	var right := forward.cross(normal).normalized()
	var hub_velocity := wheel.linear_velocity - wheel.ground_velocity
	# Translational hub transport, not tread speed (spin is separate input).
	var input := {"normalLoad": wheel.normal_load, "contact": usable_contact,
		"longitudinalVelocity": hub_velocity.dot(forward),
		"lateralVelocity": hub_velocity.dot(right),
		"wheelOmega": wheel.angular_velocity.dot(-axle), "radius": radius,
		"camber": asin(clampf(-axle.dot(normal), -1.0, 1.0))}
	var surface: Dictionary = config.Surfaces.get(wheel.surface, config.Surfaces.dirt)
	var result: Dictionary = Tire.step(state, input, dt, config.Tire, surface)
	if usable_contact and wheel.normal_load > 0.0:
		var force := forward * float(result.longitudinalForce) + right * float(result.lateralForce)
		wheel.apply_force(force, wheel.contact_position - wheel.global_position)
		# Contact application already creates Fx*r torque. Rolling loss alone
		# is separate; applying contactTorque here would count tire torque twice.
		wheel.apply_torque(-axle * float(result.rollingTorque))
	return result

func _update_rider(input: Dictionary, dt: float) -> void:
	var rider: Dictionary = config.Rider
	var step_size := float(rider.MoveRate) * dt
	var pitch_motion := _advance_rider_axis(_body_forward, float(input.bodyForward),
		_rider_pitch_rate, float(rider.MaxPitch), float(rider.MoveRate),
		float(rider.PitchInertia), float(rider.MaxReactionTorque), dt)
	var roll_motion := _advance_rider_axis(_body_lean, float(input.lean),
		_rider_roll_rate, float(rider.MaxRoll), float(rider.MoveRate),
		float(rider.RollInertia), float(rider.MaxReactionTorque), dt)
	_body_forward = pitch_motion.x
	_body_lean = roll_motion.x
	_body_side = move_toward(_body_side, float(input.bodySide), step_size)
	_standing = move_toward(_standing, 1.0 if input.standing else 0.0, step_size)
	# Bound the rider's acceleration itself, preserving I*dOmega rather than
	# clipping a one-tick torque while instantly assigning full rider speed.
	# Positive forward/lean articulate about -X/-Z; bike reaction is +X/+Z.
	var pitch_reaction := float(rider.PitchInertia) * (pitch_motion.y - _rider_pitch_rate) / dt
	var roll_reaction := float(rider.RollInertia) * (roll_motion.y - _rider_roll_rate) / dt
	chassis.apply_torque(chassis.global_basis.x * pitch_reaction + chassis.global_basis.z * roll_reaction)
	_rider_pitch_rate = pitch_motion.y
	_rider_roll_rate = roll_motion.y
	var rider_position := Vector3(
		_body_side * float(rider.SideTravel) + sin(_body_lean * float(rider.MaxRoll)) * 0.26,
		0.54 + _standing * float(rider.StandingHeight),
		0.09 - _body_forward * float(rider.ForeAftTravel))
	# Custom COM follows a finite rider articulation, not an upright target.
	# Parallel-axis terms approximate the rigidly coupled rider's inertia.
	var bike_mass: float = float(config.ChassisMass)
	var rider_mass: float = float(config.RiderMass)
	var total := bike_mass + rider_mass
	var bike_center := Vector3(0, -0.11, 0.04)
	var next_com := (bike_center * bike_mass + rider_position * rider_mass) / total
	if chassis.center_of_mass.distance_squared_to(next_com) > 0.00000001:
		chassis.center_of_mass = next_com
	var separation := rider_position - bike_center
	var reduced := bike_mass * rider_mass / total
	var next_inertia := Vector3(21, 14, 5.8) + Vector3(
		separation.y * separation.y + separation.z * separation.z,
		separation.x * separation.x + separation.z * separation.z,
		separation.x * separation.x + separation.y * separation.y) * reduced
	if chassis.inertia.distance_squared_to(next_inertia) > 0.00000001:
		chassis.inertia = next_inertia
	_rider_visual.position = rider_position - Vector3(0, 0.54, 0.09)
	_rider_visual.rotation = Vector3(-_body_forward * float(rider.MaxPitch), 0,
		-_body_lean * float(rider.MaxRoll))
	if _rider_collision.position.distance_squared_to(rider_position) > 0.0000000001:
		_rider_collision.position = rider_position
	if _rider_collision.rotation.distance_squared_to(_rider_visual.rotation) > 0.0000000001:
		_rider_collision.rotation = _rider_visual.rotation

func _advance_rider_axis(current: float, target: float, old_rate: float,
		max_angle: float, move_rate: float, inertia: float, torque_limit: float,
		dt: float) -> Vector2:
	var angle_error := (target - current) * max_angle
	var acceleration := torque_limit / maxf(inertia, 0.001)
	# Brake to a stop over a finite articulation distance near the desired
	# rider pose. Rider input is a pose command; the motorcycle has no target.
	var desired_rate := signf(angle_error) * minf(move_rate * max_angle,
		sqrt(2.0 * acceleration * absf(angle_error)))
	var next_rate := move_toward(old_rate, desired_rate, acceleration * dt)
	var next_position := current + next_rate * dt / maxf(max_angle, 0.001)
	return Vector2(clampf(next_position, -1.0, 1.0), next_rate)

func _update_feet() -> void:
	var feet_down: bool = bool(controls.footDown) and not crashed
	for i in range(_feet.size()):
		if _feet[i].disabled == feet_down:
			_feet[i].set_deferred("disabled", not feet_down)
		_foot_visuals[i].visible = feet_down

func _angles() -> Vector2:
	var up := chassis.global_basis.y
	var right := chassis.global_basis.x
	var forward := -chassis.global_basis.z
	return Vector2(atan2(-right.y, up.y), asin(clampf(forward.y, -1.0, 1.0)))

func _detect_crash(dt: float) -> void:
	var grounded := front_wheel.contact or rear_wheel.contact
	var angles := _angles()
	var speed := chassis.linear_velocity.length()
	if not grounded:
		_air_time += dt
		_last_air_velocity = chassis.linear_velocity
	else:
		if not crashed and _air_time > 0.10:
			var normal := front_wheel.contact_normal if front_wheel.contact else rear_wheel.contact_normal
			var impact_speed := maxf(0, -_last_air_velocity.dot(normal))
			var landing_tilt := acos(clampf(chassis.global_basis.y.dot(normal), -1, 1))
			var side_speed := absf(_last_air_velocity.dot(chassis.global_basis.x))
			if landing_tilt > float(config.Crash.LandingAngle) and impact_speed > float(config.Crash.LandingSpeed):
				_crash("Poor landing: impact angle")
			elif side_speed > float(config.Crash.SideLandingSpeed) and impact_speed > 3.0:
				_crash("Sideways landing")
		_air_time = 0
	if not crashed and grounded:
		if absf(angles.x) > float(config.Crash.GroundRoll):
			_crash("Loss of balance / low-side")
		elif angles.y > float(config.Crash.LoopPitch) and not front_wheel.contact:
			_crash("Wheelie loop-out")
		elif speed > 4.0 and bool(_front_result.get("sliding", false)) and absf(float(_front_result.get("slipAngle", 0))) > 0.36:
			_crash("Front-wheel washout")
		elif _last_rear_slide and not bool(_rear_result.get("sliding", false)) and absf(chassis.angular_velocity.dot(-chassis.global_basis.z)) > 3.5 and absf(angles.x) > 0.45:
			_crash("Rear grip recovery / high-side")
	_last_rear_slide = bool(_rear_result.get("sliding", false))
	# A flipped body remains a native collision body in the air and on ground.
	if not crashed and chassis.global_basis.y.y < -0.3 and grounded:
		_crash("Over-rotation")

func _crash(reason: String) -> void:
	crashed = true
	crash_reason = reason
	_crash_elapsed = 0
	_update_feet()

func get_telemetry() -> Dictionary:
	if not _built:
		return {}
	var angles := _angles()
	var relative := chassis.global_basis.inverse() * fork.global_basis
	var speed := chassis.linear_velocity.length()
	return {"speed": speed * 3.6, "speedMps": speed,
		"gear": int(drive_state.gear), "rpm": float(drive_state.engineOmega) * 30.0 / PI,
		"clutch": float(controls.clutch), "stalled": bool(drive_state.stalled),
		"frontCompression": float(front_suspension_state.get("compression", 0)),
		"rearCompression": float(rear_suspension_state.get("compression", 0)),
		"frontSlip": float(front_tire_state.get("slipRatio", 0)),
		"rearSlip": float(rear_tire_state.get("slipRatio", 0)),
		"frontSlipAngle": float(front_tire_state.get("slipAngle", 0)),
		"rearSlipAngle": float(rear_tire_state.get("slipAngle", 0)),
		"frontSurface": front_wheel.surface, "rearSurface": rear_wheel.surface,
		"frontGrip": float(_front_result.get("grip", 0)), "rearGrip": float(_rear_result.get("grip", 0)),
		"frontContact": front_wheel.contact, "rearContact": rear_wheel.contact,
		"frontLoad": front_wheel.normal_load, "rearLoad": rear_wheel.normal_load,
		"frontNormal": front_wheel.contact_normal, "rearNormal": rear_wheel.contact_normal,
		"frontOmega": front_wheel.angular_velocity.dot(-front_wheel.global_basis.x),
		"rearOmega": rear_wheel.angular_velocity.dot(-rear_wheel.global_basis.x),
		"steerAngle": atan2(relative.x.z, relative.x.x),
		"roll": angles.x, "pitch": angles.y, "standing": bool(controls.standing),
		"footDown": bool(controls.footDown), "crashed": crashed, "crashReason": crash_reason,
		"recoveryRemaining": maxf(0, float(config.Crash.RecoveryDelay) - _crash_elapsed) if crashed else 0.0}

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.65
	return result

func _box_collision(body: RigidBody3D, size: Vector3, origin: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = origin
	body.add_child(collision)

func _box_mesh(parent_node: Node3D, size: Vector3, origin: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = origin
	visual.material_override = _material(color)
	parent_node.add_child(visual)
	return visual

func _cylinder_mesh(parent_node: Node3D, radius: float, height: float, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	visual.mesh = mesh
	visual.material_override = _material(color)
	parent_node.add_child(visual)
	return visual

func _set_segment(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	mesh.position = (a + b) * 0.5
	(mesh.mesh as CylinderMesh).height = maxf(delta.length(), 0.001)
	var up := delta.normalized()
	var tangent := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.95 else Vector3.FORWARD
	var right := tangent.cross(up).normalized()
	mesh.basis = Basis(right, up, right.cross(up)).orthonormalized()

func _build_visuals() -> void:
	var silver := Color(0.44, 0.49, 0.54)
	var dark := Color(0.075, 0.09, 0.115)
	var orange := Color(0.97, 0.26, 0.055)
	# A recognizable procedural MX chassis; all parts follow actual native
	# body transforms and strut travel rather than canned wheel/lean animation.
	for side in [-1.0, 1.0]:
		var x: float = side * 0.115
		for endpoints in [
			[Vector3(x, 0.31, -0.28), Vector3(x, -0.26, -0.22)],
			[Vector3(x, -0.26, -0.22), Vector3(x, -0.26, 0.28)],
			[Vector3(x, -0.26, 0.28), Vector3(x, 0.27, 0.14)],
			[Vector3(x, 0.27, 0.14), Vector3(x, 0.31, -0.28)],
			[Vector3(x, 0.24, 0.10), Vector3(x, 0.23, 0.59)]
		]:
			var tube := _cylinder_mesh(chassis, 0.018, 1.0, silver)
			_set_segment(tube, endpoints[0], endpoints[1])
		_swingarm.append(_cylinder_mesh(chassis, 0.026, 1.0, silver))
		_front_rods.append(_cylinder_mesh(fork, 0.022, 1.0, Color(0.78, 0.71, 0.49)))
	_box_mesh(chassis, Vector3(0.26, 0.22, 0.28), Vector3(0, -0.11, 0.05), silver)
	_box_mesh(chassis, Vector3(0.26, 0.10, 0.53), Vector3(0, 0.28, 0.24), dark)
	_box_mesh(chassis, Vector3(0.30, 0.21, 0.33), Vector3(0, 0.21, -0.12), orange)
	_box_mesh(chassis, Vector3(0.17, 0.045, 0.46), Vector3(0, 0.25, 0.64), orange)
	var front_fender := _box_mesh(fork, Vector3(0.16, 0.035, 0.48), Vector3(0, -0.16, -0.28), orange)
	front_fender.rotation.x = -0.08
	_box_mesh(fork, Vector3(0.25, 0.23, 0.04), Vector3(0, 0.03, -0.11), Color(0.94, 0.94, 0.87))
	var bar := _cylinder_mesh(fork, 0.012, 0.68, dark)
	bar.position = Vector3(0, 0.13, -0.015)
	bar.rotation.z = PI * 0.5
	var silencer := _cylinder_mesh(chassis, 0.055, 0.44, silver)
	silencer.position = Vector3(0.20, 0.16, 0.40)
	silencer.rotation.x = PI * 0.5
	_rider_visual = Node3D.new()
	_rider_visual.name = "RiderArticulation"
	chassis.add_child(_rider_visual)
	var jersey := _box_mesh(_rider_visual, Vector3(0.30, 0.36, 0.20), Vector3(0, 0.59, 0.09), Color(0.12, 0.26, 0.39))
	jersey.rotation.x = -0.20
	var helmet := MeshInstance3D.new()
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.13
	helmet_mesh.height = 0.25
	helmet.mesh = helmet_mesh
	helmet.position = Vector3(0, 0.89, -0.005)
	helmet.material_override = _material(Color(0.91, 0.91, 0.85))
	_rider_visual.add_child(helmet)
	_box_mesh(_rider_visual, Vector3(0.22, 0.055, 0.13), Vector3(0, 0.88, -0.115), dark)
	for side in [-1.0, 1.0]:
		var thigh := _cylinder_mesh(_rider_visual, 0.065, 0.34, dark)
		_set_segment(thigh, Vector3(side * 0.10, 0.43, 0.21), Vector3(side * 0.18, 0.09, 0.03))
		var calf := _cylinder_mesh(_rider_visual, 0.052, 0.32, dark)
		_set_segment(calf, Vector3(side * 0.18, 0.09, 0.03), Vector3(side * 0.21, -0.21, 0.13))
		var arm := _cylinder_mesh(_rider_visual, 0.047, 0.40, Color(0.12, 0.26, 0.39))
		_set_segment(arm, Vector3(side * 0.16, 0.71, 0.02), Vector3(side * 0.29, 0.48, -0.32))

func _update_visuals() -> void:
	var front_local := fork.global_transform.affine_inverse() * front_wheel.global_position
	var rear_local := chassis.global_transform.affine_inverse() * rear_wheel.global_position
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		_set_segment(_front_rods[i], Vector3(side * 0.055, 0.02, 0.0),
			front_local + Vector3(side * 0.055, 0, 0))
		_set_segment(_swingarm[i], Vector3(side * 0.11, -0.12, 0.17),
			rear_local + Vector3(side * 0.07, 0, 0))
