extends RigidBody3D
class_name DLWheelBody

const Gyro = preload("res://physics/gyroscope.gd")

## Native wheel contact reporting. Despite the historical name, Godot's
## get_contact_local_position() returns WORLD coordinates (4.6 API).
## These contact normals/impulses also come from the native world solver.
## There is no raycast support, fictitious normal load or wheel-height cutoff.
var contact: bool = false
var normal_load: float = 0.0
var contact_position: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
var ground_velocity: Vector3 = Vector3.ZERO
var surface: String = "dirt"
var native_contact_count: int = 0
var contact_impulse: Vector3 = Vector3.ZERO
var last_contact_transform: Transform3D = Transform3D.IDENTITY

func clear_contact() -> void:
	contact = false
	normal_load = 0.0
	native_contact_count = 0
	contact_impulse = Vector3.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Jolt's Godot adapter does not integrate free-body gyroscopic precession.
	# Complete Euler dynamics for this actual body's native inertia once;
	# this is neither a second virtual wheel nor an orientation controller.
	Gyro.integrate(state)
	clear_contact()
	last_contact_transform = state.transform
	var weighted_position := Vector3.ZERO
	var weighted_normal := Vector3.ZERO
	var weighted_velocity := Vector3.ZERO
	var strongest := 0.0
	var total_weight := 0.0
	for i in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(i)
		if collider == null:
			continue
		var normal := state.get_contact_local_normal(i).normalized()
		var impulse := state.get_contact_impulse(i)
		var normal_impulse := maxf(0.0, impulse.dot(normal))
		# Contacts exist before the first reported solver impulse. Retain their
		# geometry but do not fabricate a supporting force for that first tick.
		var weight := maxf(normal_impulse, 0.00001)
		weighted_position += state.get_contact_local_position(i) * weight
		weighted_normal += normal * weight
		weighted_velocity += state.get_contact_collider_velocity_at_position(i) * weight
		total_weight += weight
		normal_load += normal_impulse / maxf(state.step, 0.000001)
		contact_impulse += impulse
		native_contact_count += 1
		if weight > strongest:
			strongest = weight
			surface = str(collider.get_meta("physics_surface", collider.get_meta("surface", "dirt"))).to_lower()
	contact = native_contact_count > 0
	if total_weight > 0.0:
		contact_position = weighted_position / total_weight
		contact_normal = weighted_normal.normalized()
		ground_velocity = weighted_velocity / total_weight
