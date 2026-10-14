extends SceneTree
## Validate the rider's angular velocity sensors against rotated orientations.
## These are geometry benches, not simulated riding or a frozen riding fixture:
## each measured derivative is checked against independently advanced bases.

const Bike = preload("res://scripts/bike_controller.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(message + (": " + detail if not detail.is_empty() else ""))
		push_error("RIDER SENSOR FAIL: " + failures[-1])

func _bank(basis: Basis) -> float:
	return atan2(-basis.x.y, basis.y.y)

func _heading(basis: Basis) -> float:
	var forward := -basis.z
	return atan2(forward.x, forward.z)

func _run() -> void:
	# The controller need not run its motorcycle here. Its sensor reads a real
	# native body's orientation/velocity; no physics step occurs in this bench.
	var sensor := Bike.new()
	var body := RigidBody3D.new()
	root.add_child(body)
	sensor.chassis = body
	var orientations: Array[Vector3] = [Vector3.ZERO, Vector3(-27, 100, 22),
		Vector3(32, -75, -28), Vector3(-60, 35, 38)]
	const STEP := 0.0005
	for angles: Vector3 in orientations:
		var basis := Basis(Vector3.UP, deg_to_rad(angles.y)) * Basis(Vector3.RIGHT, deg_to_rad(angles.x)) * Basis(Vector3.BACK, deg_to_rad(angles.z))
		var velocities: Array[Vector3] = [Vector3.UP * 1.3, Vector3(0.7, 0.8, -0.5), basis.z * 0.9]
		for omega: Vector3 in velocities:
			body.global_basis = basis
			body.angular_velocity = omega
			var positive := Basis(omega.normalized(), omega.length() * STEP) * basis
			var negative := Basis(omega.normalized(), -omega.length() * STEP) * basis
			var expected_bank := wrapf(_bank(positive) - _bank(negative), -PI, PI) / (2.0 * STEP)
			# Positive-right heading is opposite atan2(forward.x, forward.z).
			var expected_heading := -wrapf(_heading(positive) - _heading(negative), -PI, PI) / (2.0 * STEP)
			var actual_bank: float = sensor._bank_rate()
			var actual_heading: float = sensor._heading_rate()
			_check(absf(actual_bank - expected_bank) < 0.003,
				"Bank derivative matches rotated-basis measurement", "%s / %s: %.5f versus %.5f" % [angles, omega, actual_bank, expected_bank])
			_check(absf(actual_heading - expected_heading) < 0.003,
				"Heading derivative matches rotated-basis measurement", "%s / %s: %.5f versus %.5f" % [angles, omega, actual_heading, expected_heading])
	# A world-Y rotation changes heading but cannot change measured bank,
	# including when the rider is pitched and banked on a whoop landing.
	body.global_basis = Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, deg_to_rad(-27.0)) * Basis(Vector3.BACK, deg_to_rad(22.0))
	body.angular_velocity = Vector3.UP * 1.3
	_check(absf(sensor._bank_rate()) < 0.0001, "Pitched world-yaw motion does not invent bank-rate feedback")
	_check(absf(sensor._heading_rate() + 1.3) < 0.0001, "Pitched world-yaw motion keeps the correct heading-rate sign")
	for pitch: float in [90.0, -89.5]:
		body.global_basis = Basis(Vector3.RIGHT, deg_to_rad(pitch))
		body.angular_velocity = Vector3(25.0, -30.0, 15.0)
		var bank_rate: float = sensor._bank_rate()
		var heading_rate: float = sensor._heading_rate()
		_check(is_finite(bank_rate) and absf(bank_rate) <= 15.0, "Vertical-bank sensor fallback stays finite and bounded")
		_check(is_finite(heading_rate) and absf(heading_rate) <= 10.0, "Vertical-heading sensor fallback stays finite and bounded")
	body.free()
	sensor.free()
	print("Rider sensor geometry checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
