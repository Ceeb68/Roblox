extends SceneTree
## Actual Godot/Jolt free-rotor checks plus implicit Euler regression cases.
## Run with godot --headless --path standalone --fixed-fps 240
## --script res://tests/gyro_tests.gd
const Gyro = preload("res://physics/gyroscope.gd")
const WHEEL_I: Vector3 = Vector3(0.72, 0.3816, 0.3816)

class RotorProbe:
	extends RigidBody3D
	var corrected: bool = true
	var initial_omega: Vector3 = Vector3(30.0, 5.0, 0.0)
	var duration: float = 0.5
	var elapsed: float = 0.0
	var started: bool = false
	var done: bool = false
	var initial_momentum: Vector3 = Vector3.ZERO
	var initial_energy: float = 0.0
	var final_momentum: Vector3 = Vector3.ZERO
	var max_momentum_error: float = 0.0
	var max_energy_error: float = 0.0
	var final_omega: Vector3 = Vector3.ZERO
	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if done:
			return
		if not started:
			state.angular_velocity = initial_omega
			initial_momentum = state.inverse_inertia_tensor.inverse() * initial_omega
			initial_energy = 0.5 * initial_omega.dot(initial_momentum)
			started = true
		else:
			elapsed += state.step
			final_momentum = state.inverse_inertia_tensor.inverse() * state.angular_velocity
			var energy: float = 0.5 * state.angular_velocity.dot(final_momentum)
			max_momentum_error = maxf(max_momentum_error, final_momentum.distance_to(initial_momentum) / initial_momentum.length())
			max_energy_error = maxf(max_energy_error, absf(energy - initial_energy) / initial_energy)
			if elapsed >= duration - 0.000001:
				final_omega = state.angular_velocity
				done = true
				return
		if corrected:
			Gyro.integrate(state)

var cases: int = 0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("GYRO FAIL: " + message)

func _case(label: String, run: Callable) -> void:
	cases += 1
	var before: int = failures.size()
	run.call()
	print(("PASS " if failures.size() == before else "FAIL ") + label)

func _energy(omega: Vector3, inertia: Vector3) -> float:
	return 0.5 * omega.dot(inertia * omega)

func _pure_rotors() -> void:
	for omega: Vector3 in [Vector3(30, 5, 0), Vector3(100, 5, 0), Vector3(240, 25, 10), Vector3(-100, -8, 12)]:
		var result: Vector3 = Gyro.corrected_omega(omega, Basis.IDENTITY, WHEEL_I, 1.0 / 240.0)
		_check(result.is_finite(), "Implicit wheel precession stays finite at native speed cap")
		_check(absf(_energy(result, WHEEL_I) - _energy(omega, WHEEL_I)) <= 0.000003 * _energy(omega, WHEEL_I), "Wheel midpoint conserves free-rotor kinetic energy")
		_check(absf((WHEEL_I * result).length() - (WHEEL_I * omega).length()) <= 0.000003 * (WHEEL_I * omega).length(), "Wheel midpoint conserves angular momentum magnitude")

func _pure_chassis() -> void:
	var inertia: Vector3 = Vector3(39, 29, 14)
	for omega: Vector3 in [Vector3(3, 5, 7), Vector3(-80, 30, 10), Vector3(200, 80, 20)]:
		var result: Vector3 = Gyro.corrected_omega(omega, Basis.IDENTITY, inertia, 1.0 / 240.0)
		_check(result.is_finite(), "Chassis precession stays finite after large rotational input")
		_check(absf(_energy(result, inertia) - _energy(omega, inertia)) <= 0.000003 * _energy(omega, inertia), "Anisotropic chassis midpoint conserves energy")

func _covariance() -> void:
	var omega: Vector3 = Vector3(100, 5, 2)
	var local: Vector3 = Gyro.corrected_omega(omega, Basis.IDENTITY, WHEEL_I, 1.0 / 240.0)
	for basis: Basis in [Basis(Vector3(1, 2, 3).normalized(), 0.7), Basis(Vector3.RIGHT, PI), Basis(Vector3.FORWARD, PI / 2.0)]:
		var transformed: Vector3 = Gyro.corrected_omega(basis * omega, basis, WHEEL_I, 1.0 / 240.0)
		_check(transformed.distance_to(basis * local) < 0.00004, "Precession is frame invariant including upside-down bodies")

func _no_targets() -> void:
	var spin: Vector3 = Vector3(100, 0, 0)
	_check(Gyro.corrected_omega(spin, Basis.IDENTITY, WHEEL_I, 1.0 / 240.0) == spin, "Pure principal-axis spin needs no artificial correction")
	var arbitrary: Vector3 = Vector3(4, -3, 6)
	_check(Gyro.corrected_omega(arbitrary, Basis.IDENTITY, Vector3.ONE, 1.0 / 240.0) == arbitrary, "Isotropic rotor has no gyroscopic precession")
	_check(Gyro.corrected_omega(arbitrary, Basis.IDENTITY, WHEEL_I, 0.0) == arbitrary, "Zero duration leaves physical state unchanged")
	_check(Gyro.corrected_omega(arbitrary, Basis.IDENTITY, WHEEL_I, 1.0 / 240.0).distance_to(arbitrary) > 0.001, "Cross-axis spin creates actual precession")

func _probe(omega: Vector3, hz: int, corrected: bool, duration: float = 0.5) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var rotor: RotorProbe = RotorProbe.new()
	rotor.corrected = corrected
	rotor.initial_omega = omega
	rotor.duration = duration
	rotor.mass = 7.5
	rotor.inertia = WHEEL_I
	rotor.gravity_scale = 0.0
	rotor.can_sleep = false
	rotor.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	rotor.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	rotor.linear_damp = 0.0
	rotor.angular_damp = 0.0
	rotor.collision_layer = 0
	rotor.collision_mask = 0
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.1
	collider.shape = shape
	rotor.add_child(collider)
	root.add_child(rotor)
	var frames: int = 0
	while not rotor.done and frames < 2000:
		await process_frame
		frames += 1
	_check(rotor.done, "Native free rotor completed its measured simulation interval")
	var result: Dictionary = {"maxL": rotor.max_momentum_error, "maxE": rotor.max_energy_error,
		"finalL": rotor.final_momentum.distance_to(rotor.initial_momentum) / rotor.initial_momentum.length(),
		"omega": rotor.final_omega, "seconds": rotor.elapsed}
	rotor.queue_free()
	await process_frame
	return result

func _native_checks() -> void:
	cases += 1
	var baseline: Dictionary = await _probe(Vector3(30, 5, 0), 240, false)
	_check(float(baseline.maxL) > 0.08, "Uncorrected native Jolt demonstrates missing free-rotor angular momentum conservation")
	print("PASS baseline native gyro deficiency demonstrated: max |dL|/|L|=%.6f" % baseline.maxL)
	var normal30: Dictionary = await _probe(Vector3(30, 5, 0), 240, true)
	var fine30: Dictionary = await _probe(Vector3(30, 5, 0), 480, true)
	var normal100: Dictionary = await _probe(Vector3(100, 5, 0), 240, true)
	var fine100: Dictionary = await _probe(Vector3(100, 5, 0), 480, true)
	cases += 4
	for result: Dictionary in [normal30, fine30, normal100, fine100]:
		_check(is_finite(float(result.maxL)) and is_finite(float(result.maxE)), "Native corrected free rotor remains finite")
		_check(float(result.maxE) < 0.0001, "Native corrected rotor energy error stays below 0.01 percent")
		_check(absf(float(result.seconds) - 0.5) < 0.00001, "Native rotor validation uses 0.5 seconds of actual solver time")
	_check(float(normal30.maxL) < 0.01, "240 Hz, 30 rad/s native wheel momentum drift stays below 1 percent")
	_check(float(normal100.maxL) < 0.04, "240 Hz, 100 rad/s native wheel momentum drift stays below 4 percent")
	_check(float(normal100.omega.x) > 90.0, "Native 100 rad/s rotor retains speed above Jolt's former 47.1 rad/s cap")
	print("NATIVE gyro 30 rad/s: 240/480 Hz max |dL|/|L|=%.8f/%.8f, energy error=%.8f/%.8f" % [normal30.maxL, fine30.maxL, normal30.maxE, fine30.maxE])
	print("NATIVE gyro 100 rad/s: 240/480 Hz max |dL|/|L|=%.8f/%.8f, energy error=%.8f/%.8f" % [normal100.maxL, fine100.maxL, normal100.maxE, fine100.maxE])
	cases += 1
	_check(float(fine30.maxL) < float(normal30.maxL) * 0.75, "30 rad/s native gyroscopic momentum converges when halving timestep")
	_check(float(fine100.maxL) < float(normal100.maxL) * 0.75, "100 rad/s native gyroscopic momentum converges when halving timestep")

func _run() -> void:
	_check(ProjectSettings.get_setting("physics/3d/physics_engine", "") == "Jolt Physics", "Free-rotor regressions run on actual Jolt backend")
	_check(float(ProjectSettings.get_setting("physics/jolt_physics_3d/limits/max_angular_velocity", 0.0)) >= 200.0, "Native wheel angular limit accommodates realistic wheel speeds")
	_case("implicit wheel Euler step conserves quadratic invariants", _pure_rotors)
	_case("implicit anisotropic chassis step remains passive and finite", _pure_chassis)
	_case("gyroscopic dynamics are frame invariant", _covariance)
	_case("gyro integration imposes no speed or upright targets", _no_targets)
	await _native_checks()
	print("Gyroscopic dynamics: %d cases, %d checks, %d failures" % [cases, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
