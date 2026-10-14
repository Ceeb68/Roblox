extends Node3D
class_name DLSimBike

## A native SI-unit, five-body motorcycle with a separately moving rider.
## Contact geometry and suspension end stops are resolved by Godot/Jolt; tire
## loads observe solved wheel momentum on the free suspension axis, with
## corrected native estimates at singularities and mechanical end stops. Rider support and posture use finite
## paired forces/torques. Coefficients are engineering approximations, not a
## replication of any commercial motorcycle simulator.
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
const RIDER_ORIGIN := Vector3(0.0, 0.54, 0.09)
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
var rider_body: RigidBody3D
var _rider_force := Vector3.ZERO
var _rider_torque := Vector3.ZERO
var _rider_reference_transform := Transform3D(Basis.IDENTITY, RIDER_ORIGIN)
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
var _body_twist: float = 0.0
var _standing: float = 0.0
var _rider_pitch_rate: float = 0.0
var _rider_roll_rate: float = 0.0
var _rider_yaw_rate: float = 0.0
var _last_air_velocity := Vector3.ZERO
var _air_time: float = 0.0
var _last_rear_slide: bool = false
var _crash_elapsed: float = 0.0
var crashed: bool = false
var crash_reason: String = ""
var _built: bool = false
var _reset_pending: bool = false
## The optional virtual human uses finite handlebar grip and ground-informed
## fore/aft rider articulation. Steering and body reactions are physical;
## there is no world-up torque, pose overwrite or airborne attitude feedback.
var riding_mode: String = "virtual_rider"
var _rider_steering_torque: float = 0.0
var _rider_target_lean: float = 0.0
var _steering_target: float = 0.0
var _first_person: bool = false
var _steering_integral: float = 0.0
var _rider_heading := Vector3.FORWARD
var _rider_line_origin := Vector3.ZERO
var _heading_correction: float = 0.0
var _line_capture_pending: bool = false
var _line_settle_time: float = 0.0
var _line_from_player_turn: bool = false
var _line_ground_seen: bool = false
var _landing_line_pending: bool = false
var _landing_line_active: bool = false
var _landing_line_elapsed: float = 0.0
var _bank_intent: float = 0.0
var _slip_feedforward: float = 0.0
var _front_support: float = 0.0
var _rear_support: float = 0.0
var _rear_slide_duration: float = 0.0
var _rear_regrip_duration: float = 0.0
var _tire_loss_context: String = ""
var _forward_acceleration: float = 0.0
var _last_velocity_sample := Vector3.ZERO
var _velocity_sample_valid: bool = false
var _automatic_body_forward: float = 0.0
var _mechanical_trail: float = 0.0

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
	chassis = _new_body("Chassis", float(config.ChassisMass), Vector3.ZERO)
	chassis.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	chassis.center_of_mass = Vector3(0, -0.11, 0.04)
	chassis.inertia = Vector3(15.8, 10.8, 2.6)
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
	rider_body = _new_body("PhysicalRider", float(config.RiderMass), RIDER_ORIGIN)
	rider_body.inertia = Vector3(float(config.Rider.PitchInertia), float(config.Rider.RollInertia), float(config.Rider.RollInertia))
	rider_body.physics_material_override = guard_material
	_rider_collision.position = Vector3.ZERO
	rider_body.add_child(_rider_collision)
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
	for body_a in [chassis, fork, front_wheel, rear_wheel, rider_body]:
		for body_b in [chassis, fork, front_wheel, rear_wheel, rider_body]:
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
	_build_rider_joint()
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
	_body_twist = 0.0
	_standing = 0
	_rider_pitch_rate = 0
	_rider_roll_rate = 0
	_rider_yaw_rate = 0.0
	_rider_force = Vector3.ZERO
	_rider_torque = Vector3.ZERO
	_rider_reference_transform = Transform3D(Basis.IDENTITY, RIDER_ORIGIN)
	_air_time = 0
	_last_air_velocity = Vector3.ZERO
	_last_rear_slide = false
	_steering_integral = 0.0
	_heading_correction = 0.0
	_line_capture_pending = false
	_line_settle_time = 0.0
	_line_from_player_turn = false
	_line_ground_seen = false
	_landing_line_pending = false
	_landing_line_active = false
	_landing_line_elapsed = 0.0
	_bank_intent = 0.0
	_slip_feedforward = 0.0
	_front_support = 0.0
	_rear_support = 0.0
	_rear_slide_duration = 0.0
	_rear_regrip_duration = 0.0
	_tire_loss_context = ""
	_forward_acceleration = 0.0
	_last_velocity_sample = Vector3.ZERO
	_velocity_sample_valid = false
	_automatic_body_forward = 0.0
	_mechanical_trail = 0.0
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
	var bodies: Array[RigidBody3D] = [chassis, fork, front_wheel, rear_wheel, rider_body]
	var positions: Array[Vector3] = [Vector3.ZERO, HEAD, FRONT_AXLE, REAR_AXLE, RIDER_ORIGIN]
	for i in range(bodies.size()):
		bodies[i].call("queue_reset", spawn * Transform3D(Basis.IDENTITY, positions[i]))
	front_wheel.clear_contact()
	rear_wheel.clear_contact()
	_update_feet()
	_apply_rider_pose(true)
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
	_bank_intent = 0.0
	_slip_feedforward = 0.0
	_automatic_body_forward = 0.0
	_line_capture_pending = false
	_line_settle_time = 0.0
	_line_from_player_turn = false
	_landing_line_pending = false
	_landing_line_active = false
	_landing_line_elapsed = 0.0
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
	_apply_steering(active, dt)
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
	wheel.record_axial_loading(axis, -force, compression, float(settings.Travel))
	wheel.apply_central_force(-force)
	parent_body.apply_force(force, parent_offset)

func _apply_steering(input: Dictionary, dt: float) -> void:
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
		# Either patch can support the bike over bumps; losing the rear patch
		# must not remove steering authority from a still-loaded front tire.
		# Bars remain a real bearing with equal/opposite torques. With neither
		# tire supported, the roll feedback is completely inactive.
		var grounded := front_wheel.contact or rear_wheel.contact
		if grounded and front_wheel.normal_load + rear_wheel.normal_load > 100.0:
			_line_ground_seen = true
		if not grounded and _line_ground_seen and _air_time >= float(riding.get("AirLinePerceptionTime", 0.2)):
			# A sustained jump ends the old ground line reference. A brief bump
			# does not erase the human's chosen line each time a patch unloads.
			# In flight the rider has no balance/heading actuator. Capture a
			# fresh actual travel line once loaded contact returns, then acquire
			# it gradually through finite handlebars as the landing settles.
			_line_capture_pending = true
			_line_settle_time = 0.0
			_line_from_player_turn = true
			_landing_line_pending = true
			_landing_line_active = false
			_landing_line_elapsed = 0.0
			# The old corrective bank is also a ground-line intent, not an
			# airborne pose request. Do not revive it at first contact while the
			# rider is catching an otherwise clean, upright landing.
			_bank_intent = 0.0
			_steering_integral = 0.0
		var forward_speed := maxf(0.0, chassis.linear_velocity.dot(-chassis.global_basis.z))
		var blend := smoothstep(0.6, 2.2, forward_speed) if grounded else 0.0
		var contact_rate := 1.0 / maxf(float(riding.get("ContactPerceptionTime", 1.0 / 12.0)), 0.01)
		# Tire grip already falls with the actual normal load. A lightly loaded
		# but supported front patch still needs the rider's finite bar strength
		# to catch roll; blending toward straight-air grip at 100–250 N removes
		# corrective steering precisely during a landing's suspension rebound.
		var front_authority := smoothstep(0.0, float(riding.get("FrontContactConfidenceLoad", 80.0)), front_wheel.normal_load) if front_wheel.contact else 0.0
		var rear_authority := smoothstep(60.0, 300.0, rear_wheel.normal_load) if rear_wheel.contact else 0.0
		_front_support = move_toward(_front_support, front_authority, dt * contact_rate)
		_rear_support = move_toward(_rear_support, rear_authority, dt * contact_rate)
		var relative := chassis.global_basis.inverse() * fork.global_basis
		var angle := atan2(relative.x.z, relative.x.x)
		var lean := _angles().x
		var lean_rate := _bank_rate()
		var speed_squared := maxf(forward_speed * forward_speed, 2.0)
		var wheelbase := float(config.Wheelbase)
		var contact_height := chassis.global_position.y - float(config.FrontRadius) - 0.35
		if front_wheel.contact and rear_wheel.contact:
			contact_height = (front_wheel.contact_position.y + rear_wheel.contact_position.y) * 0.5
		elif front_wheel.contact:
			contact_height = front_wheel.contact_position.y
		elif rear_wheel.contact:
			contact_height = rear_wheel.contact_position.y
		var height := maxf(0.4, _sprung_com().y - contact_height)
		var max_angle := float(config.Steering.MaxAngle)
		var low_speed_lean := atan(speed_squared * tan(max_angle * 0.85) / (9.81 * wheelbase))
		var front_surface: Dictionary = config.Surfaces.get(front_wheel.surface, config.Surfaces.dirt)
		var rear_surface: Dictionary = config.Surfaces.get(rear_wheel.surface, config.Surfaces.dirt)
		var grip_lean := minf(deg_to_rad(36.0), atan(minf(float(front_surface.Grip), float(rear_surface.Grip)) * 0.85))
		var available_lean := minf(minf(deg_to_rad(49.0), grip_lean), low_speed_lean)
		var requested_bank := clampf(float(input.steer) + float(input.lean) * 0.9, -1.0, 1.0) * available_lean
		_heading_correction = 0.0
		var forward := -chassis.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		if _landing_line_pending and grounded and front_wheel.normal_load + rear_wheel.normal_load > 100.0:
			var landing_direction := chassis.linear_velocity
			landing_direction.y = 0.0
			_rider_heading = landing_direction.normalized() if landing_direction.length_squared() > 2.25 else forward
			_rider_line_origin = chassis.global_position
			_landing_line_pending = false
			_landing_line_active = true
			_landing_line_elapsed = 0.0
			_line_capture_pending = false
			_line_settle_time = 0.0
		if _landing_line_active and grounded:
			_landing_line_elapsed = minf(_landing_line_elapsed + dt, 2.0)
		if absf(float(input.steer)) + absf(float(input.lean)) > 0.025:
			_landing_line_pending = false
			_landing_line_active = false
			_landing_line_elapsed = 0.0
			_rider_heading = forward
			_rider_line_origin = chassis.global_position
			_line_capture_pending = true
			_line_settle_time = 0.0
			_line_from_player_turn = true
		elif _line_capture_pending:
			# Let a released stick return the bike upright before capturing its
			# next line. Capturing the still-turning tangent immediately asks the
			# rider to undo the natural finishing arc with an opposite bank.
			# This changes only a human intent/reference, never the body motion.
			_rider_heading = forward
			_rider_line_origin = chassis.global_position
			if grounded and absf(lean) < deg_to_rad(2.0) and absf(lean_rate) < 0.12 and absf(_heading_rate()) < 0.06:
				_line_settle_time += dt
			else:
				_line_settle_time = 0.0
			if _line_settle_time >= float(riding.get("LineSettleTime", 0.35)):
				_line_capture_pending = false
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
			heading_error -= atan(lateral_error / maxf(6.0, forward_speed * float(riding.get("LineLookaheadTime", 1.5))))
			var yaw_rate := _heading_rate()
			var heading_frequency := lerpf(float(riding.get("SeatedHeadingFrequency", 3.0)), float(riding.get("StandingHeadingFrequency", 3.0)), _standing)
			if _line_from_player_turn:
				# A freshly chosen turn exit has a less certain line than the
				# straight launch reference. Follow it with a longer lookahead,
				# below the rider's roll bandwidth, rather than trying to correct
				# tire relaxation/side-slip with another immediate opposite turn.
				heading_frequency = lerpf(float(riding.get("TurnExitHeadingFrequency", 1.2)), float(riding.get("StandingTurnExitHeadingFrequency", 0.65)), _standing)
			_heading_correction = clampf(atan(forward_speed * (heading_error * heading_frequency - yaw_rate * float(riding.get("HeadingDamping", 0.8))) / 9.81),
				-deg_to_rad(12.0), deg_to_rad(12.0))
			if _landing_line_active:
				# Hold the touchdown reference fixed. Waiting indefinitely for a
				# perfectly quiet bank while moving the reference each tick lets a
				# mild landing wobble gradually redefine an unintended corner.
				var acquire_delay := float(riding.get("LandingLineDelay", 0.25))
				_heading_correction *= smoothstep(acquire_delay, acquire_delay + float(riding.get("LandingLineResponse", 0.5)), _landing_line_elapsed)
			requested_bank += _heading_correction
		# Human intent changes continuously. A stick reversal, a surface seam,
		# or a braking-speed change must not demand a one-frame 72-degree bank
		# reversal. This filters the rider's request, never the actual bike pose.
		if grounded:
			var intent_change := (requested_bank - _bank_intent) * (1.0 - exp(-dt / float(riding.get("IntentResponse", 0.16))))
			_bank_intent += clampf(intent_change, -float(riding.get("MaxLeanRate", 1.4)) * dt, float(riding.get("MaxLeanRate", 1.4)) * dt)
			_rider_target_lean = clampf(_bank_intent, -deg_to_rad(36.0), deg_to_rad(36.0))
		# Seated and standing compliance have different roll modes. Schedule
		# the virtual human's feedback with the actual posture, without changing
		# available grip, bearing strength or the bike's physical attitude.
		var frequency := lerpf(float(riding.get("LowFrequency", 3.0)), lerpf(float(riding.get("SeatedRollFrequency", 6.4)), float(riding.get("RollFrequency", 3.4)), _standing), smoothstep(2.0, 7.0, forward_speed))
		frequency = lerpf(frequency, float(riding.get("HighSpeedFrequency", 3.4)), smoothstep(15.0, 28.0, forward_speed))
		var factor := height * wheelbase / speed_squared
		# Roll equilibrium includes rider COM displaced from the frame centre.
		var com_camber := atan2(chassis.to_local(_sprung_com()).x, height)
		var equilibrium := 9.81 * wheelbase * tan(clampf(lean + com_camber, -1.1, 1.1)) / speed_squared
		_steering_target = clampf(equilibrium + factor * (frequency * frequency *
			(lean - _rider_target_lean) + 2.0 * float(riding.get("RollDamping", 1.2)) * frequency * lean_rate), -max_angle, max_angle)
		# Finite tire slip makes geometric steer understeer; the human rider
		# feels this and adds bar travel, without adding grip or chassis torque.
		var slip_compensation := clampf(float(rear_tire_state.get("slipAngle", 0.0)) -
			float(front_tire_state.get("slipAngle", 0.0)), -0.22, 0.22)
		# The kinematic slip estimate is meaningful with two loaded patches.
		# Brief unloading/sliding is not an instruction to jerk the bars across
		# their stops. Keep finite perception latency in this feed-forward path;
		# immediate roll/rate feedback above remains unfiltered.
		var slip_reliability := minf(_front_support, _rear_support)
		if bool(_front_result.get("sliding", false)):
			slip_reliability *= 0.35
		_slip_feedforward += (slip_compensation * slip_reliability - _slip_feedforward) * (1.0 - exp(-dt / float(riding.get("SlipResponse", 0.10))))
		_steering_target = clampf(_steering_target + _slip_feedforward, -max_angle, max_angle)
		# A front-only nose-heavy contact can rotate the caster through zero
		# and reverse mechanical trail. Increase finite hand grip there, but
		# keep roll-catching input: forcing bars back to centre removes tire
		# leverage and can gyroscopically roll the bike deeper into the fall.
		var brace := 0.0
		if front_wheel.contact and not rear_wheel.contact:
			var normal := front_wheel.contact_normal
			var axis_normal := axis.dot(normal)
			if absf(axis_normal) > 0.15:
				var stem := chassis.global_transform * HEAD
				var intersection := stem - axis * ((stem - front_wheel.contact_position).dot(normal) / axis_normal)
				var patch_forward := -chassis.global_basis.z
				patch_forward -= normal * patch_forward.dot(normal)
				_mechanical_trail = (intersection - front_wheel.contact_position).dot(patch_forward.normalized())
				brace = 1.0 - smoothstep(-0.025, 0.035, _mechanical_trail)
		else:
			_mechanical_trail = float(config.Steering.Trail)
		if front_wheel.contact and blend > 0.1 and not bool(_front_result.get("sliding", false)):
			_steering_integral = clampf(_steering_integral + (_steering_target - angle) * dt, -0.025, 0.025)
		else:
			_steering_integral = move_toward(_steering_integral, 0.0, dt * 0.1)
		var bar_speed := maxf(1.0, float(riding.get("BarSpeedReference", 12.0)))
		var bandwidth := clampf(speed_squared / (bar_speed * bar_speed), 1.0, float(riding.get("MaxBarBandwidth", 6.0)))
		var bar_damping := lerpf(float(riding.get("BarDamping", 18.0)), float(riding.get("HighSpeedBarDamping", 18.0)), smoothstep(10.0, 17.0, forward_speed))
		var handlebar_torque := clampf(-(_steering_target - angle) * float(riding.get("BarStiffness", 600.0)) * bandwidth * lerpf(1.0, float(riding.get("ImpactGripScale", 1.5)), brace) - rate * bar_damping * sqrt(bandwidth) - _steering_integral * float(riding.get("BarIntegral", 300.0)) * bandwidth,
			-float(riding.get("MaxTorque", 45.0)), float(riding.get("MaxTorque", 45.0)))
		# At walking pace use deliberate steering while feet carry balance.
		var walking_angle := float(input.steer) * max_angle * 0.65
		var walking_torque := clampf(-(walking_angle - angle) * 36.0 - rate * 5.0,
			-float(config.Steering.InputTorque), float(config.Steering.InputTorque))
		scalar = lerpf(walking_torque, handlebar_torque, blend)
		# A geometric touch with zero normal force supplies no brush traction.
		# Balance authority must match the same CURRENT load the tire uses;
		# perceived contact history cannot drive bicycle curvature through an
		# unloaded wheel. Hand grip itself is retained at full finite strength.
		var loaded_balance := front_authority * _front_support
		# In flight the player exchanges the spinning front wheel's angular
		# momentum through actual bar travel, alongside independent torso twist.
		# Partial bar travel keeps the coupled whip/reversal controllable; this
		# is an input range, not a chassis attitude or angular-velocity limit.
		var air_travel := float(riding.get("AirBarTravel", 0.5)) if not grounded else 0.5
		var grip_angle := float(input.steer) * max_angle * air_travel
		var grip_torque := clampf(-(grip_angle - angle) * float(riding.get("AirBarStiffness", 600.0)) - rate * float(riding.get("AirBarDamping", 25.0)),
			-float(riding.get("MaxTorque", 45.0)), float(riding.get("MaxTorque", 45.0)))
		scalar = lerpf(grip_torque, scalar, loaded_balance)
		_steering_target = lerpf(grip_angle, _steering_target, loaded_balance)
		if front_authority <= 0.0:
			_steering_integral = 0.0
		if not grounded:
			_slip_feedforward = 0.0
		# In flight and rear-only support this local servo senses only fork
		# angle/rate, not world attitude or the landing. Steering/gyroscopic
		# reactions can create a whip; releasing the stick relaxes straight.
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
	# Record exactly the tangential forces applied this step; the completed
	# native step distinguishes support from spring/brush forces next tick.
	wheel.record_tire_loading(Vector3.ZERO)
	var normal := wheel.contact_normal
	var axle := wheel.global_basis.x.normalized()
	var forward := normal.cross(axle)
	# Tire sidewalls still have native collision at a 90-degree fall. Rolling
	# direction is undefined there, so omit brush forces instead of inventing
	# a normal support or heading. No contact itself is removed.
	var usable_contact := wheel.contact and forward.length_squared() > 0.000001
	forward = forward.normalized()
	var right := forward.cross(normal).normalized()
	# The native rounded shoulder supplies the actual contact lever. The same
	# lever must transport tread speed and produce tire torque; using nominal
	# upright radius for one while applying force at another creates spurious
	# longitudinal slip during a bank or a deeply compressed terrain contact.
	var effective_radius := axle.cross(wheel.contact_position - wheel.global_position).dot(forward) if usable_contact else radius
	usable_contact = usable_contact and effective_radius > 0.001
	var non_spin_omega := wheel.angular_velocity - axle * wheel.angular_velocity.dot(axle)
	var hub_velocity := wheel.linear_velocity + non_spin_omega.cross(
		wheel.contact_position - wheel.global_position) - wheel.ground_velocity
	# Contact transport includes non-spin roll/yaw motion. Only axial tread
	# spin is supplied separately, so contact slip is neither lost nor doubled.
	var input := {"normalLoad": wheel.normal_load, "contact": usable_contact,
		"longitudinalVelocity": hub_velocity.dot(forward),
		"lateralVelocity": hub_velocity.dot(right),
		"wheelOmega": wheel.angular_velocity.dot(-axle), "radius": effective_radius,
		"camber": asin(clampf(-axle.dot(normal), -1.0, 1.0))}
	var surface: Dictionary = config.Surfaces.get(wheel.surface, config.Surfaces.dirt)
	var tire_settings: Dictionary = config.Tire
	if wheel == rear_wheel and config.Tire.has("RearCamberStiffness"):
		# The wider rear knobby may have a different physical camber response;
		# both axles still consume their own unchanged combined grip budget.
		tire_settings = config.Tire.duplicate()
		tire_settings.CamberStiffness = float(config.Tire.RearCamberStiffness)
	var result: Dictionary = Tire.step(state, input, dt, tire_settings, surface)
	result.effectiveRadius = effective_radius
	if usable_contact and wheel.normal_load > 0.0:
		var force := forward * float(result.longitudinalForce) + right * float(result.lateralForce)
		wheel.record_tire_loading(force)
		wheel.apply_force(force, wheel.contact_position - wheel.global_position)
		# Contact application already creates Fx*r torque. Rolling loss alone
		# is separate; applying contactTorque here would count tire torque twice.
		wheel.apply_torque(-axle * float(result.rollingTorque))
	return result

func _update_rider(input: Dictionary, dt: float) -> void:
	var rider: Dictionary = config.Rider
	var step_size := float(rider.MoveRate) * dt
	var body_request := float(input.bodyForward)
	if riding_mode == "virtual_rider" and not crashed:
		if absf(body_request) >= 0.98:
			# Full deliberate posture has complete manual authority.
			_automatic_body_forward = 0.0
		elif front_wheel.contact or rear_wheel.contact:
			var reflex_target := 0.0
			if front_wheel.contact and chassis.linear_velocity.length() > 2.0:
				var nose_to_ground := asin(clampf((-chassis.global_basis.z).dot(front_wheel.contact_normal), -1.0, 1.0))
				var nose_rate := chassis.angular_velocity.dot(chassis.global_basis.x)
				var nose_load := smoothstep(deg_to_rad(4.0), deg_to_rad(22.0), -(nose_to_ground + nose_rate * 0.06))
				var front_share := front_wheel.normal_load / maxf(front_wheel.normal_load + rear_wheel.normal_load, 1.0)
				var front_compression := float(front_suspension_state.get("compression", 0.0)) / float(config.Suspension.Front.Travel)
				var impact_brace := smoothstep(0.50, 0.90, front_compression) * smoothstep(0.55, 0.85, front_share)
				reflex_target = -maxf(nose_load * 0.45, impact_brace * 0.35) * lerpf(0.45, 1.0, _standing)
			# A seated human leans forward under acceleration before the front
			# unloads into a wheelie. Move the actual torso through the same finite
			# leg/hip support, keeping full manual body endpoints authoritative.
			if rear_wheel.contact and rear_wheel.normal_load > 100.0 and chassis.linear_velocity.length() > 2.0:
				var nose_up := asin(clampf((-chassis.global_basis.z).dot(rear_wheel.contact_normal), -1.0, 1.0))
				var pitch_rate := chassis.angular_velocity.dot(chassis.global_basis.x)
				var accelerating := smoothstep(2.0, 5.0, _forward_acceleration)
				var front_share := front_wheel.normal_load / maxf(front_wheel.normal_load + rear_wheel.normal_load, 1.0)
				var unloading := 1.0 - smoothstep(0.08, 0.40, front_share)
				var lifting := smoothstep(deg_to_rad(2.0), deg_to_rad(10.0), nose_up + pitch_rate * 0.10)
				var forward_brace := accelerating * maxf(unloading, lifting) * float(config.VirtualRider.get("AccelerationBodyBrace", 0.65))
				reflex_target = maxf(reflex_target, forward_brace) if forward_brace > 0.0 else reflex_target
			_automatic_body_forward = move_toward(_automatic_body_forward, reflex_target, dt * 2.0)
		# Choosing a modest body position does not make the rider rigid to
		# every impact. A small terrain-bracing offset uses the remaining pose
		# travel; authority fades quadratically toward fully manual endpoints.
		# Keep the last ground-informed reflex in unsupported flight. Only a
		# deliberate player input can request a new body position in the air.
		var reflex_authority := (1.0 - absf(body_request)) ** 2
		body_request = clampf(body_request + _automatic_body_forward * reflex_authority, -1.0, 1.0)
	else:
		_automatic_body_forward = 0.0
	# The reflex only changes a bounded real rider articulation; it applies
	# no independent chassis pitch torque and receives no airborne feedback.
	var pitch_motion := _advance_rider_axis(_body_forward, body_request,
		_rider_pitch_rate, float(rider.MaxPitch), float(rider.MoveRate),
		float(rider.PitchInertia), float(rider.MaxReactionTorque), dt)
	var roll_motion := _advance_rider_axis(_body_lean, float(input.lean),
		_rider_roll_rate, float(rider.MaxRoll), float(rider.MoveRate),
		float(rider.RollInertia), float(rider.MaxReactionTorque), dt)
	# In unsupported flight the player can twist the bike beneath the torso
	# through their legs as well as move sideways. This is a bounded HUMAN
	# body-relative pose, sensed by the existing finite paired posture servo.
	# It applies no external yaw force and has no world/landing angle target.
	var twist_request := float(input.bodySide) if not front_wheel.contact and not rear_wheel.contact else 0.0
	var yaw_motion := _advance_rider_axis(_body_twist, twist_request,
		_rider_yaw_rate, float(rider.get("MaxYaw", deg_to_rad(30.0))), float(rider.MoveRate),
		float(rider.get("YawInertia", rider.RollInertia)), float(rider.MaxReactionTorque), dt)
	_body_forward = pitch_motion.x
	_body_lean = roll_motion.x
	_body_twist = yaw_motion.x
	_body_side = move_toward(_body_side, float(input.bodySide), step_size)
	_standing = move_toward(_standing, 1.0 if input.standing else 0.0, step_size)
	# These rates describe a bounded body-relative muscle target. The native
	# rider mass supplies the actual inertial reaction through paired support.
	_rider_pitch_rate = pitch_motion.y
	_rider_roll_rate = roll_motion.y
	_rider_yaw_rate = yaw_motion.y
	if _velocity_sample_valid:
		var acceleration := (chassis.linear_velocity - _last_velocity_sample).dot(-chassis.global_basis.z) / maxf(dt, 0.0001)
		_forward_acceleration += (clampf(acceleration, -10.0, 10.0) - _forward_acceleration) * (1.0 - exp(-dt / 0.12))
	_last_velocity_sample = chassis.linear_velocity
	_velocity_sample_valid = true
	_apply_rider_pose()

func _apply_rider_pose(pose_reset: bool = false) -> void:
	var rider: Dictionary = config.Rider
	var rider_position := Vector3(
		_body_side * float(rider.SideTravel) + sin(_body_lean * float(rider.MaxRoll)) * 0.26,
		0.54 + _standing * float(rider.StandingHeight),
		0.09 - _body_forward * float(rider.ForeAftTravel))
	# The frame inertia/COM are constant. A fifth physical body carries the
	# mass, so internal movement exchanges momentum through real paired forces.
	var rider_rotation := Vector3(-_body_forward * float(rider.MaxPitch), _body_twist * float(rider.get("MaxYaw", deg_to_rad(30.0))),
		-_body_lean * float(rider.MaxRoll))
	_rider_reference_transform = Transform3D(Basis.from_euler(rider_rotation), rider_position)
	if not pose_reset:
		_apply_rider_support(rider_position)
	var suspension_compression := 0.5 * (float(front_suspension_state.get("compression", 0.0)) / float(config.Suspension.Front.Travel) +
		float(rear_suspension_state.get("compression", 0.0)) / float(config.Suspension.Rear.Travel))
	_rider_visual.update_pose(_body_forward, _body_side, _body_lean, _standing,
		bool(controls.footDown) and not crashed, {"suspension_compression": clampf(suspension_compression, 0.0, 1.0),
		"forward_acceleration": _forward_acceleration, "speed": chassis.linear_velocity.length(),
		"grounded": front_wheel.contact or rear_wheel.contact, "dt": get_physics_process_delta_time(), "pose_reset": pose_reset,
		"rider_yaw_target": _body_twist * float(rider.get("MaxYaw", deg_to_rad(30.0))),
		"rider_transform": chassis.global_transform.affine_inverse() * rider_body.global_transform,
		"rider_reference_transform": _rider_reference_transform})

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

func _bank_rate() -> float:
	# The sensed bank uses a world-gravity projection. Its derivative is not
	# simply local roll velocity during a pitched/yawed whoop or jump. Using
	# a different angle's rate feeds gyroscopic yaw into the wrong damping
	# command just as a wheel lands. Differentiate the actual sensor vectors.
	var right := chassis.global_basis.x
	var up := chassis.global_basis.y
	var omega := chassis.angular_velocity
	var a := -right.y
	var b := up.y
	var denominator := a * a + b * b
	if denominator < 0.03:
		# Bank has no useful gravity projection at a vertical wheelie. Keep a
		# finite local measurement; the controller cannot invent roll authority.
		return clampf(omega.dot(-chassis.global_basis.z), -15.0, 15.0)
	var da := -omega.cross(right).y
	var db := omega.cross(up).y
	return clampf((b * da - a * db) / denominator, -15.0, 15.0)

func _heading_rate() -> float:
	# Heading is the flattened forward vector, so its derivative must also
	# include pitch/roll coupling instead of treating world-Y spin as heading.
	var forward := -chassis.global_basis.z
	var derivative := chassis.angular_velocity.cross(forward)
	var denominator := forward.x * forward.x + forward.z * forward.z
	if denominator < 0.03:
		return clampf(-chassis.angular_velocity.y, -10.0, 10.0)
	return clampf(-(forward.z * derivative.x - forward.x * derivative.z) / denominator, -10.0, 10.0)

func _detect_crash(dt: float) -> void:
	# A fallen bike can rest entirely on the chassis/rider, with both tires
	# clear of the ground. Such a fall must still start the recovery timer.
	var grounded := front_wheel.contact or rear_wheel.contact or chassis.get_contact_count() > 0 or fork.get_contact_count() > 0 or rider_body.get_contact_count() > 0
	var angles := _angles()
	var speed := chassis.linear_velocity.length()
	var rear_sliding := bool(_rear_result.get("sliding", false))
	if rear_sliding and absf(float(_rear_result.get("slipAngle", 0.0))) > 0.16:
		_rear_slide_duration += dt
		_rear_regrip_duration = 0.0
	elif _rear_slide_duration > 0.08:
		_rear_regrip_duration += dt
		if _rear_regrip_duration > 0.25:
			_rear_slide_duration = 0.0
			_rear_regrip_duration = 0.0
	else:
		_rear_slide_duration = 0.0
	_tire_loss_context = ""
	if speed > 4.0 and bool(_front_result.get("sliding", false)) and absf(float(_front_result.get("slipAngle", 0))) > 0.36:
		_tire_loss_context = "Front-wheel washout"
	elif _rear_slide_duration > 0.08 and _rear_regrip_duration > 0.02 and absf(chassis.angular_velocity.dot(-chassis.global_basis.z)) > 3.5:
		_tire_loss_context = "Rear grip recovery / high-side"
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
			_crash(_tire_loss_context if not _tire_loss_context.is_empty() else "Loss of balance / low-side")
		elif angles.y > float(config.Crash.LoopPitch) and not front_wheel.contact:
			_crash("Wheelie loop-out")
		# Grip loss and re-grip are physical events, not an automatic dismount.
		# Let the human countersteer and the tires recover until the actual
		# attitude/impact is unsafe. Otherwise a one-frame brush saturation
		# switches off the very rider feedback needed to catch a small slide.
	_last_rear_slide = rear_sliding
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
		"frontLoadMethod": front_wheel.load_method, "rearLoadMethod": rear_wheel.load_method,
		"frontNormal": front_wheel.contact_normal, "rearNormal": rear_wheel.contact_normal,
		"frontOmega": front_wheel.angular_velocity.dot(-front_wheel.global_basis.x),
		"rearOmega": rear_wheel.angular_velocity.dot(-rear_wheel.global_basis.x),
		"steerAngle": atan2(relative.x.z, relative.x.x),
		"roll": angles.x, "pitch": angles.y, "standing": bool(controls.standing),
		"bankRate": _bank_rate(),
		"headingRate": _heading_rate(),
		"ridingMode": riding_mode, "riderSteeringTorque": _rider_steering_torque,
		"riderTargetLean": _rider_target_lean, "steeringTarget": _steering_target,
		"headingCorrection": _heading_correction,
		"lineCapturePending": _line_capture_pending,
		"frontSupport": _front_support, "rearSupport": _rear_support,
		"slipFeedforward": _slip_feedforward, "tireLossContext": _tire_loss_context,
		"automaticBodyForward": _automatic_body_forward, "mechanicalTrail": _mechanical_trail,
		"riderTwist": _body_twist * float(config.Rider.get("MaxYaw", deg_to_rad(30.0))),
		"riderTransform": chassis.global_transform.affine_inverse() * rider_body.global_transform,
		"riderReferenceTransform": _rider_reference_transform,
		"riderSupportForce": _rider_force, "riderPostureTorque": _rider_torque,
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

func _sprung_com() -> Vector3:
	# Balance senses the frame plus actual moving rider; wheels/fork remain
	# separate unsprung bodies supported through their native bearings.
	var frame_mass: float = float(config.ChassisMass)
	var human_mass: float = float(config.RiderMass)
	return ((chassis.global_transform * chassis.center_of_mass) * frame_mass + rider_body.global_position * human_mass) / (frame_mass + human_mass)

func _build_rider_joint() -> void:
	var joint := Generic6DOFJoint3D.new()
	joint.name = "RiderReachLimits"
	joint.position = RIDER_ORIGIN
	add_child(joint)
	joint.node_a = joint.get_path_to(chassis)
	joint.node_b = joint.get_path_to(rider_body)
	joint.exclude_nodes_from_collision = true
	for axis: String in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis, true)
		joint.set("linear_limit_%s/lower_distance" % axis, -0.40 if axis != "x" else -0.35)
		joint.set("linear_limit_%s/upper_distance" % axis, 0.45 if axis == "y" else 0.40)
		joint.set("angular_limit_%s/enabled" % axis, false)
		joint.set("angular_motor_%s/enabled" % axis, false)
		joint.set("linear_motor_%s/enabled" % axis, false)
		joint.set("linear_spring_%s/enabled" % axis, false)
		joint.set("angular_spring_%s/enabled" % axis, false)
	_joints.append(joint)

func _apply_rider_support(target: Vector3) -> void:
	var offset := rider_body.global_position - (chassis.global_transform * chassis.center_of_mass)
	var frame_velocity := chassis.linear_velocity + chassis.angular_velocity.cross(offset)
	var local_error := target - chassis.to_local(rider_body.global_position)
	var local_rate := chassis.global_basis.inverse() * (rider_body.linear_velocity - frame_velocity)
	var tune: Dictionary = config.get("RiderSupport", {})
	var stiffness := Vector3(float(tune.get("SideStiffness", 12000)), lerpf(float(tune.get("SeatedVertical", 20000)), float(tune.get("StandingVertical", 5000)), _standing), float(tune.get("ForeStiffness", 4000)))
	var damping := Vector3(float(tune.get("SideDamping", 1300)), float(tune.get("VerticalDamping", 350)), float(tune.get("ForeDamping", 200)))
	# Preload is along the bike's own leg direction, never world-up. This
	# preserves exactly paired internal forces even during free flight.
	var local_force := local_error * stiffness - local_rate * damping + Vector3(0, float(config.RiderMass) * 9.81, 0)
	var max_force := float(tune.get("MaxForce", 3500))
	local_force = local_force.limit_length(max_force)
	_rider_force = chassis.global_basis * local_force
	rider_body.apply_central_force(_rider_force)
	chassis.apply_force(-_rider_force, rider_body.global_position - chassis.global_position)
	var requested := _rider_reference_transform.basis
	var relative := chassis.global_basis.inverse() * rider_body.global_basis
	var error_rotation := (requested * relative.inverse()).get_rotation_quaternion()
	var angle := error_rotation.get_angle()
	if angle > PI:
		angle -= TAU
	var local_omega := chassis.global_basis.inverse() * (rider_body.angular_velocity - chassis.angular_velocity)
	var posture_stiffness := Vector3(float(tune.get("PostureStiffness", 180)), float(tune.get("YawPostureStiffness", 100)), float(tune.get("PostureStiffness", 180)))
	var posture_damping := Vector3(float(tune.get("PostureDamping", 12)), float(tune.get("YawPostureDamping", 25)), float(tune.get("PostureDamping", 12)))
	# Hip twist is a softer, more damped muscle mode than pitch/roll. A scalar
	# underdamped torso servo makes a new yaw degree of freedom ring against
	# spinning wheel gyroscopes, especially when the player reverses a whip.
	var torque_local := error_rotation.get_axis() * angle * posture_stiffness - local_omega * posture_damping
	_rider_torque = chassis.global_basis * torque_local.limit_length(float(config.Rider.MaxReactionTorque))
	rider_body.apply_torque(_rider_torque)
	chassis.apply_torque(-_rider_torque)
