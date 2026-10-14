extends Node3D
class_name DLSimBike

## A native SI-unit, four-body motorcycle. Contact geometry and suspension
## end stops are resolved by Godot/Jolt; tire normal loads use Jolt estimates. This is a prototype with explicit engineering
## coefficients, not a replication of any commercial motorcycle simulator.
const Drive = preload("res://physics/drivetrain.gd")
const Tire = preload("res://physics/tire.gd")
const Suspension = preload("res://physics/suspension.gd")
const Wheel = preload("res://scripts/wheel_body.gd")
const RiderVisual = preload("res://scripts/rider_visual.gd")
const BikeVisual = preload("res://scripts/bike_visual.gd")

class NativeBody:
	extends RigidBody3D
	const Gyro = preload("res://physics/gyroscope.gd")
	var _recovery_pose: Variant = null
	func queue_reset(pose: Transform3D) -> void:
		global_transform = pose
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = false
		_recovery_pose = pose
	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if _recovery_pose != null:
			state.transform = _recovery_pose
			state.linear_velocity = Vector3.ZERO
			state.angular_velocity = Vector3.ZERO
			_recovery_pose = null
			return
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
var _rider_visual: RiderVisual
var _bike_visual: BikeVisual
var _rider_collision: CollisionShape3D
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
## Optional virtual human rider actuates only the finite steering bearing.
## Rider intent uses body lean and a chosen line, actuated through bars only.
## There is no direct attitude/yaw force, transform overwrite or midair correction.
var riding_mode: String = "virtual_rider"
var _rider_steering_torque: float = 0.0
var _rider_target_lean: float = 0.0
var _steering_target: float = 0.0
var _first_person: bool = false
var _steering_integral: float = 0.0
var _rider_heading := Vector3.FORWARD
var _rider_line_origin := Vector3.ZERO
var _heading_correction: float = 0.0

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
	# Jolt's analytic cylinder has a real convex shoulder, not a faceted
	# polygon. With collision_margin_fraction=0.9 the round shoulder follows
	# a lean continuously; the outer wheel radius/width remain SI dimensions.
	var tire_volume := CylinderShape3D.new()
	tire_volume.radius = radius
	tire_volume.height = width
	tire_volume.margin = width * 0.45
	collision.shape = tire_volume
	collision.rotation.z = PI * 0.5
	wheel.add_child(collision)

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
	_last_air_velocity = Vector3.ZERO
	_last_rear_slide = false
	_steering_integral = 0.0
	_heading_correction = 0.0
	_rider_steering_torque = 0.0
	_rider_target_lean = 0.0
	_steering_target = 0.0
	crashed = false
	crash_reason = ""
	_crash_elapsed = 0
	controls = _neutral_controls()

func reset_bike(spawn: Transform3D, force_recovery: bool = false) -> bool:
	if not _built or not spawn.origin.is_finite() or not spawn.basis.is_finite() or absf(spawn.basis.determinant()) < 0.000001:
		return false
	if crashed and not force_recovery and _crash_elapsed < float(config.Crash.RecoveryDelay):
		return false
	_reset_models()
	_rider_heading = -spawn.basis.z
	_rider_line_origin = spawn.origin
	# Spawning/remounting is the sole pose reset path. Riding and the crash
	# itself remain native motion; automatic recovery starts after its delay.
	var bodies: Array[RigidBody3D] = [chassis, fork, front_wheel, rear_wheel]
	var positions: Array[Vector3] = [Vector3.ZERO, HEAD, FRONT_AXLE, REAR_AXLE]
	for i in range(bodies.size()):
		bodies[i].call("queue_reset", spawn * Transform3D(Basis.IDENTITY, positions[i]))
	front_wheel.clear_contact()
	rear_wheel.clear_contact()
	_update_feet()
	_apply_rider_pose()
	_update_visuals()
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

func set_riding_mode(mode: String) -> bool:
	if mode not in ["virtual_rider", "direct"]:
		return false
	riding_mode = mode
	_steering_integral = 0.0
	if _built:
		_rider_heading = -chassis.global_basis.z
		_rider_line_origin = chassis.global_position
	return true

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
	var damping := float(config.Steering.Damping)
	var riding: Dictionary = config.get("VirtualRider", {})
	var scalar := -float(input.steer) * float(config.Steering.InputTorque) - rate * damping
	_rider_target_lean = 0.0
	_heading_correction = 0.0
	_steering_target = 0.0
	if riding_mode == "virtual_rider" and not crashed:
		# A real rider steers into a developing fall and countersteers to start
		# a requested lean. The optional virtual human closes that sensor/motor
		# loop through the handlebars, with finite strength and steering stops.
		# Feedback is grounded only: no landing/pitch correction in the air.
		var grounded := front_wheel.contact and rear_wheel.contact
		var forward_speed := maxf(0.0, chassis.linear_velocity.dot(-chassis.global_basis.z))
		var blend := smoothstep(0.6, 2.2, forward_speed) if grounded else 0.0
		var relative := chassis.global_basis.inverse() * fork.global_basis
		var angle := atan2(relative.x.z, relative.x.x)
		var lean := _angles().x
		var lean_rate := chassis.angular_velocity.dot(-chassis.global_basis.z)
		var speed_squared := maxf(forward_speed * forward_speed, 2.0)
		var wheelbase := float(config.Wheelbase)
		var height := maxf(0.4, (chassis.global_transform * chassis.center_of_mass).y -
			(front_wheel.contact_position.y + rear_wheel.contact_position.y) * 0.5)
		var max_angle := float(config.Steering.MaxAngle)
		var low_speed_lean := atan(speed_squared * tan(max_angle * 0.85) / (9.81 * wheelbase))
		var front_surface: Dictionary = config.Surfaces.get(front_wheel.surface, config.Surfaces.dirt)
		var rear_surface: Dictionary = config.Surfaces.get(rear_wheel.surface, config.Surfaces.dirt)
		var grip_lean := minf(deg_to_rad(36.0), atan(minf(float(front_surface.Grip), float(rear_surface.Grip)) * 0.85))
		var available_lean := minf(minf(deg_to_rad(49.0), grip_lean), low_speed_lean)
		_rider_target_lean = clampf(float(input.steer) + float(input.lean) * 0.9, -1.0, 1.0) * available_lean
		_heading_correction = 0.0
		var forward := -chassis.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		if absf(float(input.steer)) + absf(float(input.lean)) > 0.025:
			_rider_heading = forward
			_rider_line_origin = chassis.global_position
		elif grounded and forward_speed > 1.5 and bool(riding.get("MaintainHeading", true)):
			var reference := _rider_heading
			reference.y = 0.0
			reference = reference.normalized()
			var heading_error := atan2(reference.cross(forward).y, reference.dot(forward))
			# Releasing directional input asks the virtual human to hold the
			# chosen line. Looking ahead corrects drift through the same finite
			# bars; there is no rail, yaw force or position constraint.
			var right := reference.cross(Vector3.UP).normalized()
			var lateral_error := (chassis.global_position - _rider_line_origin).dot(right)
			heading_error -= atan(lateral_error / maxf(6.0, forward_speed * 1.5))
			var yaw_rate := -chassis.angular_velocity.dot(Vector3.UP)
			_heading_correction = clampf(atan(forward_speed * (heading_error * 3.0 - yaw_rate * 0.8) / 9.81),
				-deg_to_rad(12.0), deg_to_rad(12.0))
			_rider_target_lean += _heading_correction
		var frequency := lerpf(float(riding.get("LowFrequency", 3.0)), float(riding.get("RollFrequency", 3.4)), smoothstep(2.0, 7.0, forward_speed))
		var factor := height * wheelbase / speed_squared
		# Roll equilibrium includes rider COM displaced from the frame centre.
		var com_camber := atan2(chassis.center_of_mass.x, height)
		var equilibrium := 9.81 * wheelbase * tan(clampf(lean + com_camber, -1.1, 1.1)) / speed_squared
		_steering_target = clampf(equilibrium + factor * (frequency * frequency *
			(lean - _rider_target_lean) + 2.0 * float(riding.get("RollDamping", 1.2)) * frequency * lean_rate), -max_angle, max_angle)
		# Finite tire slip makes geometric steer understeer; the human rider
		# feels this and adds bar travel, without adding grip or chassis torque.
		var slip_compensation := clampf(float(rear_tire_state.get("slipAngle", 0.0)) -
			float(front_tire_state.get("slipAngle", 0.0)), -0.22, 0.22)
		_steering_target = clampf(_steering_target + slip_compensation, -max_angle, max_angle)
		if grounded and blend > 0.1:
			_steering_integral = clampf(_steering_integral + (_steering_target - angle) * get_physics_process_delta_time(), -0.025, 0.025)
		else:
			_steering_integral = 0.0
		var bandwidth := maxf(1.0, speed_squared / 144.0)
		var handlebar_torque := clampf(-(_steering_target - angle) * float(riding.get("BarStiffness", 600.0)) * bandwidth - rate * float(riding.get("BarDamping", 18.0)) * sqrt(bandwidth) - _steering_integral * float(riding.get("BarIntegral", 300.0)) * bandwidth,
			-float(riding.get("MaxTorque", 45.0)), float(riding.get("MaxTorque", 45.0)))
		# At walking pace use deliberate steering while feet carry balance.
		var walking_angle := float(input.steer) * max_angle * 0.65
		var walking_torque := clampf(-(walking_angle - angle) * 36.0 - rate * 5.0,
			-float(config.Steering.InputTorque), float(config.Steering.InputTorque))
		scalar = lerpf(walking_torque, handlebar_torque, blend)
		if not grounded:
			_steering_integral = 0.0
			scalar = -float(input.steer) * float(config.Steering.InputTorque) - rate * damping
	_rider_steering_torque = scalar
	var torque := axis * scalar
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
	var non_spin_omega := wheel.angular_velocity - axle * wheel.angular_velocity.dot(axle)
	var hub_velocity := wheel.linear_velocity + non_spin_omega.cross(
		wheel.contact_position - wheel.global_position) - wheel.ground_velocity
	# Contact transport includes non-spin roll/yaw motion. Only axial tread
	# spin is supplied separately, so contact slip is neither lost nor doubled.
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
	_apply_rider_pose()

func _apply_rider_pose() -> void:
	var rider: Dictionary = config.Rider
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
	_rider_visual.update_pose(_body_forward, _body_side, _body_lean, _standing,
		bool(controls.footDown) and not crashed)
	var rider_rotation := Vector3(-_body_forward * float(rider.MaxPitch), 0,
		-_body_lean * float(rider.MaxRoll))
	if _rider_collision.position.distance_squared_to(rider_position) > 0.0000000001:
		_rider_collision.position = rider_position
	if _rider_collision.rotation.distance_squared_to(rider_rotation) > 0.0000000001:
		_rider_collision.rotation = rider_rotation

func _advance_rider_axis(current: float, target: float, old_rate: float,
		max_angle: float, move_rate: float, inertia: float, torque_limit: float,
		dt: float) -> Vector2:
	var angle_error := (target - current) * max_angle
	var acceleration := torque_limit / maxf(inertia, 0.001)
	# A smooth pose servo avoids the old bang-bang braking law chattering
	# around a held pose and injecting alternating torso-reaction torques.
	# Acceleration stays bounded; the motorcycle has no upright pose target.
	var desired_rate := signf(angle_error) * minf(move_rate * max_angle,
		absf(angle_error) * 8.0)
	var next_rate := move_toward(old_rate, desired_rate, acceleration * dt)
	var next_position := current + next_rate * dt / maxf(max_angle, 0.001)
	return Vector2(clampf(next_position, -1.0, 1.0), next_rate)

func _update_feet() -> void:
	var feet_down: bool = bool(controls.footDown) and not crashed
	for i in range(_feet.size()):
		if _feet[i].disabled == feet_down:
			_feet[i].set_deferred("disabled", not feet_down)

func _angles() -> Vector2:
	var up := chassis.global_basis.y
	var right := chassis.global_basis.x
	var forward := -chassis.global_basis.z
	return Vector2(atan2(-right.y, up.y), asin(clampf(forward.y, -1.0, 1.0)))

func _detect_crash(dt: float) -> void:
	# A fallen bike can rest entirely on the chassis/rider, with both tires
	# clear of the ground. Such a fall must still start the recovery timer.
	var grounded := front_wheel.contact or rear_wheel.contact or chassis.get_contact_count() > 0 or fork.get_contact_count() > 0
	var angles := _angles()
	var speed := chassis.linear_velocity.length()
	if not grounded:
		_air_time += dt
		_last_air_velocity = chassis.linear_velocity
	else:
		if not crashed and _air_time > 0.10:
			var normal := front_wheel.contact_normal if front_wheel.contact else (rear_wheel.contact_normal if rear_wheel.contact else Vector3.UP)
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
		elif speed > 4.0 and absf(angles.x) > deg_to_rad(50.0) and bool(_front_result.get("sliding", false)) and absf(float(_front_result.get("slipAngle", 0))) > 0.36:
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
	_steering_integral = 0.0
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
		"ridingMode": riding_mode, "riderSteeringTorque": _rider_steering_torque,
		"riderTargetLean": _rider_target_lean, "steeringTarget": _steering_target,
		"headingCorrection": _heading_correction,
		"footDown": bool(controls.footDown), "crashed": crashed, "crashReason": crash_reason,
		"recoveryRemaining": maxf(0, float(config.Crash.RecoveryDelay) - _crash_elapsed) if crashed else 0.0}

func _box_collision(body: RigidBody3D, size: Vector3, origin: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = origin
	body.add_child(collision)

func _build_visuals() -> void:
	_rider_visual = RiderVisual.new()
	chassis.add_child(_rider_visual)
	_rider_visual.configure(chassis, fork)
	_bike_visual = BikeVisual.new()
	chassis.add_child(_bike_visual)
	_bike_visual.configure(chassis, fork, front_wheel, rear_wheel, config)

func _update_visuals() -> void:
	_bike_visual.update_geometry()

func get_rider_camera_transform() -> Transform3D:
	return _rider_visual.get_camera_transform() if _rider_visual != null else chassis.global_transform

func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if _rider_visual != null:
		_rider_visual.set_first_person(enabled)
