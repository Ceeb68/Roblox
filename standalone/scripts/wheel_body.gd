extends RigidBody3D
class_name DLWheelBody

const Gyro = preload("res://physics/gyroscope.gd")

## Native wheel contact reporting. Despite the historical name, Godot's
## get_contact_local_position() returns WORLD coordinates (4.6 API).
## Geometry comes from native world contacts. Godot4.6 Jolt reports an
## estimated five-iteration response independently for each triangle manifold,
## not its final joint-coupled solver impulse. Coplanar manifold responses are
## alternative estimates of one support patch, so average them rather than
## adding the same wheel response repeatedly at mesh/material seams.
## Interior-slider normal_load observes solved native momentum minus the known
## applied suspension/tire forces. These geometry estimates remain the explicit
## fallback near native end stops or singular/missing sampling data. Native
## normal collision is untouched; none of this applies a supporting force.
## There is no raycast support, fictitious normal load or wheel-height cutoff.
var contact: bool = false
var normal_load: float = 0.0
var reported_normal_load: float = 0.0
var estimated_manifold_count: int = 0
var support_patch_count: int = 0
var contact_position: Vector3 = Vector3.ZERO
## Jolt's cached world contact belongs to the preceding collision geometry,
## while its callback transform is the solved hub pose. At 18 m/s and 240 Hz,
## combining those phases leaves a false 75 mm trailing tire-force lever.
## Transport the pressure patch by measured hub translation for next-step
## tangential forces. Keep the raw contact and native normal support untouched.
## A pressure patch is not a rotating material tread point: do not spin it
## around the axle when transporting the completed step's geometry.
var tire_contact_position: Vector3 = Vector3.ZERO
var tire_patch_translation: Vector3 = Vector3.ZERO
var tire_patch_phase_valid: bool = false
var _tire_previous_origin: Vector3 = Vector3.ZERO
var _tire_previous_frame: int = -1
var _tire_history_valid: bool = false
var contact_normal: Vector3 = Vector3.UP
var ground_velocity: Vector3 = Vector3.ZERO
var surface: String = "dirt"
var native_contact_count: int = 0
var contact_impulse: Vector3 = Vector3.ZERO
var last_contact_transform: Transform3D = Transform3D.IDENTITY
var _recovery_pose: Variant = null


## Brush-load observation from a completed native step, not a normal actuator.
## The free suspension axis removes ideal guide-constraint reactions. Native
## mechanical stops, singular geometry and missing phase data use the explicit
## manifold estimate instead. No additional normal force is applied.
var known_suspension_force := Vector3.ZERO
var known_tire_force := Vector3.ZERO
var known_slider_axis := Vector3.UP
var known_compression := 0.0
var known_travel := 0.3
var force_stamp := -1
var callback_stamp := -1
var velocity_sample_valid := false
var prior_native_velocity := Vector3.ZERO
var momentum_load_raw := 0.0
var previous_contact_estimate := 0.0
var load_method := "no_sample"
var method_counts: Dictionary = {}

func queue_reset(pose: Transform3D) -> void:
	global_transform = pose
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	clear_contact()
	contact_position = Vector3.ZERO
	contact_normal = Vector3.UP
	ground_velocity = Vector3.ZERO
	surface = "dirt"
	last_contact_transform = pose
	_recovery_pose = pose
	invalidate_load_history()
	known_suspension_force = Vector3.ZERO
	known_tire_force = Vector3.ZERO
	force_stamp = -1
	previous_contact_estimate = 0.0
	load_method = "reset"
	method_counts.clear()

func clear_contact() -> void:
	contact = false
	normal_load = 0.0
	reported_normal_load = 0.0
	estimated_manifold_count = 0
	support_patch_count = 0
	native_contact_count = 0
	contact_impulse = Vector3.ZERO
	tire_contact_position = Vector3.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _recovery_pose != null:
		state.transform = _recovery_pose
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		last_contact_transform = state.transform
		_recovery_pose = null
		clear_contact()
		_sample_tire_patch_pose(state.transform.origin)
		_observe_solved_load(state, true)
		return
	# Jolt's Godot adapter does not integrate free-body gyroscopic precession.
	# Complete Euler dynamics for this actual body's native inertia once;
	# this is neither a second virtual wheel nor an orientation controller.
	Gyro.integrate(state)
	clear_contact()
	_sample_tire_patch_pose(state.transform.origin)
	last_contact_transform = state.transform
	var samples: Array[Dictionary] = []
	for i in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(i)
		if collider == null:
			continue
		var normal := state.get_contact_local_normal(i).normalized()
		var impulse := state.get_contact_impulse(i)
		var normal_impulse := maxf(0.0, impulse.dot(normal))
		reported_normal_load += normal_impulse / maxf(state.step, 0.000001)
		contact_impulse += impulse
		native_contact_count += 1
		samples.append({"position": state.get_contact_local_position(i),
			"planePosition": state.get_contact_collider_position(i),
			"pointLimit": 2 if absf(normal.dot(state.transform.basis.x)) < 0.707106781 else max_contacts_reported,
			"normal": normal, "velocity": state.get_contact_collider_velocity_at_position(i),
			"normalImpulse": normal_impulse, "collider": state.get_contact_collider_id(i),
			"shape": state.get_contact_collider_shape(i), "static": collider is StaticBody3D,
			"surface": surface_at(collider, state.get_contact_collider_position(i))})
	contact = native_contact_count > 0
	if contact:
		var support := reduce_contact_samples(samples, state.step)
		normal_load = float(support.normalLoad)
		contact_position = support.position
		tire_contact_position = contact_position + tire_patch_translation
		contact_normal = support.normal
		ground_velocity = support.velocity
		surface = str(support.surface)
		estimated_manifold_count = int(support.manifolds)
		support_patch_count = int(support.patches)
	_observe_solved_load(state)

## A continuous collision mesh may contain several soils. Resolve the material
## at its native WORLD support point without splitting that mesh into edges.
## Ordinary bodies retain the existing metadata fallback.
static func surface_at(collider: Object, world_point: Vector3) -> String:
	var fallback := str(collider.get_meta("physics_surface", collider.get_meta("surface", "dirt"))).to_lower()
	var resolver: Variant = collider.get_meta("physics_surface_resolver") if collider.has_meta("physics_surface_resolver") else null
	if resolver is Callable and (resolver as Callable).is_valid() and world_point.is_finite():
		var result: Variant = (resolver as Callable).call(world_point)
		if result is String and not (result as String).is_empty():
			return (result as String).to_lower()
	return fallback

static func _contains_point(points: Array, position: Vector3) -> bool:
	for sample: Dictionary in points:
		if (sample.position as Vector3).distance_squared_to(position) < 0.00000001:
			return true
	return false

## Godot flushes each Jolt manifold's contacts contiguously. Its subshape ID is
## not exposed to scripts. A changed normal/collider or repeated shared edge
## point identifies the next response group. A native cylinder side supporting
## face contains two vertices (Jolt CylinderShape::GetSupportingFace), so each
## clipped side manifold has at most two contacts; enforce this geometry limit
## even when neighbouring coplanar groups have identical normals. This prevents
## order-dependent chains from merging into three-point response groups.
## Shared-point tolerance is 0.1 mm;
## coplanar patches allow 2 degrees/1 mm, including neighbouring static surface
## bodies. Distinct terrain normals and moving/dynamic supports stay separate.
## This cannot reconstruct unexposed manifolds with identical normals and no
## shared point, or ordering lost when a full contact buffer replaces shallow
## entries. It is a documented contact-estimate correction, not a second
## normal-force solver or a claim to recover Jolt's final impulses.
## Godot source: modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp,
## _try_add_contacts (per-manifold estimates) and _flush_contacts (group order).
static func reduce_contact_samples(samples: Array[Dictionary], dt: float) -> Dictionary:
	var manifolds: Array[Dictionary] = []
	var current: Dictionary = {}
	for sample: Dictionary in samples:
		var normal: Vector3 = sample.normal
		var position: Vector3 = sample.position
		if current.is_empty() or current.collider != sample.collider or current.shape != sample.shape or \
				(normal.distance_squared_to(current.normal) > 0.000000000001) or \
				current.points.size() >= int(current.pointLimit) or \
				_contains_point(current.points, position):
			current = {"collider": sample.collider, "shape": sample.shape,
				"normal": normal, "points": [], "impulse": 0.0,
				"pointLimit": sample.get("pointLimit", 2),
				"static": sample.static, "surface": sample.surface}
			manifolds.append(current)
		current.points.append(sample)
		current.impulse = float(current.impulse) + float(sample.normalImpulse)
	var patches: Array[Dictionary] = []
	for manifold: Dictionary in manifolds:
		var plane_centre := Vector3.ZERO
		var velocity := Vector3.ZERO
		for sample: Dictionary in manifold.points:
			plane_centre += sample.get("planePosition", sample.position) as Vector3
			velocity += sample.velocity as Vector3
		plane_centre /= float(manifold.points.size())
		velocity /= float(manifold.points.size())
		var patch: Dictionary = {}
		for candidate: Dictionary in patches:
			var same_support: bool = (candidate.collider == manifold.collider and candidate.shape == manifold.shape) or \
				(bool(candidate.static) and bool(manifold.static) and (candidate.velocity as Vector3).distance_squared_to(velocity) < 0.0025)
			if same_support and (candidate.normal as Vector3).dot(manifold.normal) > 0.999390827 and \
					absf((plane_centre - (candidate.centre as Vector3)).dot(candidate.normal)) < 0.001:
				patch = candidate
				break
		if patch.is_empty():
			patch = {"collider": manifold.collider, "shape": manifold.shape,
				"static": manifold.static, "centre": plane_centre, "normal": manifold.normal,
				"velocity": velocity, "points": [], "impulse": 0.0, "responses": 0,
				"normalSum": Vector3.ZERO, "strongest": -1.0, "surface": manifold.surface}
			patches.append(patch)
		patch.impulse = float(patch.impulse) + float(manifold.impulse)
		patch.responses = int(patch.responses) + 1
		patch.normalSum = (patch.normalSum as Vector3) + (manifold.normal as Vector3)
		if float(manifold.impulse) > float(patch.strongest):
			patch.strongest = manifold.impulse
			patch.surface = manifold.surface
		for sample: Dictionary in manifold.points:
			if not _contains_point(patch.points, sample.position):
				patch.points.append(sample)
	var position_sum := Vector3.ZERO
	var normal_sum := Vector3.ZERO
	var velocity_sum := Vector3.ZERO
	var impulse_sum := 0.0
	var weight_sum := 0.0
	var strongest := -1.0
	var selected_surface := "dirt"
	for patch: Dictionary in patches:
		var impulse: float = float(patch.impulse) / float(patch.responses)
		var weight := maxf(impulse, 0.00001)
		var centre := Vector3.ZERO
		var velocity := Vector3.ZERO
		for sample: Dictionary in patch.points:
			centre += sample.position as Vector3
			velocity += sample.velocity as Vector3
		centre /= float(patch.points.size())
		velocity /= float(patch.points.size())
		position_sum += centre * weight
		normal_sum += (patch.normalSum as Vector3).normalized() * weight
		velocity_sum += velocity * weight
		impulse_sum += impulse
		weight_sum += weight
		if impulse > strongest:
			strongest = impulse
			selected_surface = str(patch.surface)
	return {"normalLoad": impulse_sum / maxf(dt, 0.000001),
		"position": position_sum / maxf(weight_sum, 0.00000001),
		"normal": normal_sum.normalized() if weight_sum > 0.0 else Vector3.UP,
		"velocity": velocity_sum / maxf(weight_sum, 0.00000001),
		"surface": selected_surface, "manifolds": manifolds.size(), "patches": patches.size()}

func record_axial_loading(axis: Vector3, force: Vector3, compression: float, travel: float) -> void:
	known_slider_axis = axis.normalized()
	known_suspension_force = force
	known_compression = compression
	known_travel = travel
	force_stamp = Engine.get_physics_frames()

func record_tire_loading(force: Vector3) -> void:
	known_tire_force = force

## Use after an externally prescribed velocity/impulse not recorded by this
## wheel's force ledger, including a bench's one-time initial conditions.
## This invalidates observations only; it does not change any native motion.
func invalidate_load_history() -> void:
	velocity_sample_valid = false
	callback_stamp = -1
	momentum_load_raw = 0.0
	# A prescribed pose/velocity starts a new contact phase too. Missing or
	# skipped native samples use raw geometry rather than a guessed velocity
	# offset or a displacement crossing a remount/teleport.
	_tire_history_valid = false
	_tire_previous_frame = -1
	tire_patch_translation = Vector3.ZERO
	tire_patch_phase_valid = false
	tire_contact_position = contact_position if contact else Vector3.ZERO

func _sample_tire_patch_pose(origin: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	tire_patch_phase_valid = _tire_history_valid and frame == _tire_previous_frame + 1 and origin.is_finite()
	tire_patch_translation = origin - _tire_previous_origin if tire_patch_phase_valid else Vector3.ZERO
	_tire_previous_origin = origin
	_tire_previous_frame = frame
	_tire_history_valid = origin.is_finite()

func _observe_solved_load(state: PhysicsDirectBodyState3D, resetting: bool = false) -> void:
	var native_velocity := state.linear_velocity
	var frame := Engine.get_physics_frames()
	previous_contact_estimate = normal_load
	momentum_load_raw = 0.0
	var phase := frame - force_stamp
	var alignment := contact_normal.dot(known_slider_axis)
	if resetting:
		normal_load = 0.0
		load_method = "reset"
		velocity_sample_valid = false
	elif not contact:
		normal_load = 0.0
		load_method = "unsupported"
	elif not velocity_sample_valid:
		load_method = "first_velocity_sample"
	elif phase != 1 or callback_stamp != frame - 1:
		load_method = "force_phase_mismatch"
	elif known_compression <= 0.004 or known_compression >= known_travel - 0.004:
		# A native axial limit contributes an unreported end-stop impulse.
		# The free-axis equation cannot attribute it to tire support.
		load_method = "mechanical_end_stop"
	elif alignment <= 0.20:
		# Dividing by a nearly perpendicular support normal is ill-conditioned;
		# an inverted slider also violates the assumed supporting geometry.
		load_method = "near_axis_singular"
	else:
		var acceleration := (native_velocity - prior_native_velocity) / maxf(state.step, 0.000001)
		var known_force := known_suspension_force + known_tire_force
		momentum_load_raw = (mass * (acceleration - state.total_gravity).dot(known_slider_axis) - known_force.dot(known_slider_axis)) / alignment
		if is_finite(momentum_load_raw):
			# A nonadhesive tire cannot supply a tensile normal reaction. There is
			# no upper cap, invented supporting load or body-orientation target.
			normal_load = maxf(0.0, momentum_load_raw)
			load_method = "free_axis_momentum"
		else:
			load_method = "nonfinite_momentum"
	method_counts[load_method] = int(method_counts.get(load_method, 0)) + 1
	prior_native_velocity = native_velocity
	callback_stamp = frame
	if not resetting:
		velocity_sample_valid = true
