class_name DLGyroscope
extends RefCounted
## Godot 4.6 Jolt does not apply free-body Euler precession by default.
## Integrate I*w_dot + w x (I*w) = 0 in the principal frame with an implicit
## midpoint solve. This conserves the quadratic free-rotor energy and |L| in
## the solve; native orientation/constraint integration adds finite dt error.
## There are no attitude, heading, speed or world-up targets in this law.

const ITERATIONS: int = 12
const RESIDUAL_SCALE: float = 0.0000002

static func _residual(candidate: Vector3, initial: Vector3, inertia: Vector3, dt: float) -> Vector3:
	var midpoint: Vector3 = (initial + candidate) * 0.5
	return inertia * (candidate - initial) + midpoint.cross(inertia * midpoint) * dt

## The basis columns are the WORLD directions of the body's principal axes.
static func corrected_omega(omega_world: Vector3, principal_axes: Basis,
		inertia: Vector3, dt: float) -> Vector3:
	if dt <= 0.0 or not is_finite(dt) or not omega_world.is_finite() or not inertia.is_finite():
		return omega_world
	if inertia.x <= 0.0 or inertia.y <= 0.0 or inertia.z <= 0.0:
		return omega_world
	var initial: Vector3 = principal_axes.inverse() * omega_world
	var candidate: Vector3 = initial
	var threshold: float = RESIDUAL_SCALE * maxf(1.0, (inertia * initial).length())
	for _iteration: int in range(ITERATIONS):
		var residual: Vector3 = _residual(candidate, initial, inertia, dt)
		if residual.length() <= threshold:
			break
		var midpoint: Vector3 = (initial + candidate) * 0.5
		var momentum: Vector3 = inertia * midpoint
		# Analytic Jacobian of the implicit midpoint Euler equations.
		var jx: Vector3 = Vector3.RIGHT * inertia.x + (Vector3.RIGHT.cross(momentum) + midpoint.cross(Vector3.RIGHT * inertia.x)) * (dt * 0.5)
		var jy: Vector3 = Vector3.UP * inertia.y + (Vector3.UP.cross(momentum) + midpoint.cross(Vector3.UP * inertia.y)) * (dt * 0.5)
		var jz: Vector3 = Vector3.BACK * inertia.z + (Vector3.BACK.cross(momentum) + midpoint.cross(Vector3.BACK * inertia.z)) * (dt * 0.5)
		var jacobian: Basis = Basis(jx, jy, jz)
		if absf(jacobian.determinant()) < 0.000000000001:
			return omega_world
		var correction: Vector3 = jacobian.inverse() * residual
		# A short line search keeps the nonlinear solve bounded after crashes.
		var scale: float = 1.0
		var trial: Vector3 = candidate - correction
		for _search: int in range(6):
			if trial.is_finite() and _residual(trial, initial, inertia, dt).length_squared() <= residual.length_squared():
				break
			scale *= 0.5
			trial = candidate - correction * scale
		candidate = trial
	if not candidate.is_finite():
		return omega_world
	return principal_axes * candidate

## Call exactly once per native body's _integrate_forces callback. Read the
## engine's actual principal inertia rather than guessing collision inertia.
## Native forces/joint impulses remain active; only missing free-body Euler
## dynamics are integrated here. This is a physical state integration step.
static func integrate(state: PhysicsDirectBodyState3D) -> void:
	var inverse: Vector3 = state.inverse_inertia
	if inverse.x <= 0.0 or inverse.y <= 0.0 or inverse.z <= 0.0:
		return
	var inertia: Vector3 = Vector3(1.0 / inverse.x, 1.0 / inverse.y, 1.0 / inverse.z)
	state.angular_velocity = corrected_omega(state.angular_velocity,
		state.principal_inertia_axes, inertia, state.step)
