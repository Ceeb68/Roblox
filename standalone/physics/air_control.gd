class_name DLAirControl
extends RefCounted
## Optional, explicit game assistance around the native motorcycle dynamics.
## Rider/fork reactions, wheel angular momentum and free-body Euler dynamics
## remain in the bike controller. This task requests bounded angular RATES,
## never a world attitude, heading, transform, velocity or flight trajectory.
## The published torque/power budget is gameplay assistance, not a claim that
## a real rider can apply an external torque to an unsupported motorcycle.

# Rates are rad/s; response, delay and handoff values are seconds. Torque
# limits are N m and power limits are watts. Speed thresholds are m/s; the
# remaining strengths/travel/response scales are dimensionless controls.
const DEFAULTS := {
	"Strength": 1.0,
	"PitchRate": 1.1, "RollRate": 1.4, "YawRate": 1.3,
	"RateResponse": 0.20, "InputResponse": 0.025,
	"NeutralDampingTime": 0.55, "ActivationDelay": 0.015,
	"ActivationTime": 0.04, "PoseHandoffTime": 0.12,
	"MaxPitchTorque": 100.0, "MaxRollTorque": 160.0,
	"MaxYawTorque": 140.0, "MaxTotalTorque": 220.0,
	"MaxPower": 450.0, "MaxDissipationPower": 650.0,
	"PitchTravel": 1.35, "WhipResponse": 1.0,
	"WhipRecovery": 1.15, "LowSpeed": 3.0, "FullSpeed": 12.0,
	"LowSpeedAuthority": 0.75
}

var _air_time := 0.0
var _blend := 0.0
var _input := Vector3.ZERO

func reset() -> void:
	_air_time = 0.0
	_blend = 0.0
	_input = Vector3.ZERO

static func _value(cfg: Dictionary, key: String) -> float:
	var value := float(cfg.get(key, DEFAULTS[key]))
	return value if is_finite(value) else float(DEFAULTS[key])

static func _sum(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)

## Actual five-body inertia about the instantaneous complete assembly COM.
## Wheels retain their independent spin; their inertia belongs to the tensor,
## while the native gyroscope handles that spin's separate angular momentum.
static func assembly_tensor(bodies: Array) -> Basis:
	var center := Vector3.ZERO
	var total_mass := 0.0
	for body: RigidBody3D in bodies:
		center += (body.global_transform * body.center_of_mass) * body.mass
		total_mass += body.mass
	if total_mass <= 0.0:
		return Basis.IDENTITY
	center /= total_mass
	var result := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for body: RigidBody3D in bodies:
		var inverse := body.get_inverse_inertia_tensor()
		var native: Basis
		if absf(inverse.determinant()) > 0.000000000001:
			native = inverse.inverse()
		else:
			# A newly added native body may not have a solver tensor yet. Its
			# configured inertia is the meaningful first-step fallback.
			var diagonal := Basis(Vector3(body.inertia.x, 0, 0),
				Vector3(0, body.inertia.y, 0), Vector3(0, 0, body.inertia.z))
			native = body.global_basis * diagonal * body.global_basis.transposed()
		var d := body.global_transform * body.center_of_mass - center
		var parallel := Basis(
			Vector3(d.y * d.y + d.z * d.z, -d.x * d.y, -d.x * d.z),
			Vector3(-d.y * d.x, d.x * d.x + d.z * d.z, -d.y * d.z),
			Vector3(-d.z * d.x, -d.z * d.y, d.x * d.x + d.y * d.y)) * body.mass
		result = _sum(result, _sum(native, parallel))
	return result

## frame: bodies, basis, omega(world), velocity(world), grounded(loaded tire),
## enabled(virtual rider && !crashed), bodyReference(takeoff fore/aft posture).
## The caller applies returned torque ONCE to the chassis. It uses the pose
## requests in its existing muscle/bar task rather than adding another servo.
func update(frame: Dictionary, controls: Dictionary, dt: float, cfg: Dictionary = {}) -> Dictionary:
	var strength := clampf(_value(cfg, "Strength"), 0.0, 1.0)
	var basis: Basis = frame.get("basis", Basis.IDENTITY)
	var steer := clampf(float(controls.get("steer", 0.0)), -1.0, 1.0)
	var side := clampf(float(controls.get("bodySide", 0.0)), -1.0, 1.0)
	var forward := clampf(float(controls.get("bodyForward", 0.0)), -1.0, 1.0)
	var lean := clampf(float(controls.get("lean", 0.0)), -1.0, 1.0)
	var result := {"active": false, "torque": Vector3.ZERO,
		"localTorque": Vector3.ZERO, "targetRate": Vector3.ZERO,
		"powerWatts": 0.0, "blend": 0.0,
		"barRequest": -steer, "bodySideRequest": -side,
		"riderLeanRequest": -lean, "twistRequest": -side,
		"pitchPoseRequest": clampf(float(frame.get("bodyReference", 0.0))
			- forward * _value(cfg, "PitchTravel"), -1.0, 1.0)}
	if not bool(frame.get("enabled", false)) or strength <= 0.0 or dt <= 0.0:
		reset()
		return result
	var grounded := bool(frame.get("grounded", true))
	_air_time = 0.0 if grounded else _air_time + dt
	var activation := smoothstep(maxf(0.0, _value(cfg, "ActivationDelay")),
		maxf(0.0, _value(cfg, "ActivationDelay")) + maxf(0.001, _value(cfg, "ActivationTime")), _air_time)
	if grounded:
		_blend = move_toward(_blend, 0.0, dt / maxf(0.001, _value(cfg, "PoseHandoffTime")))
	else:
		_blend = maxf(_blend, activation)
	result.blend = _blend
	# Pose continuity can outlive contact loss; external assistance cannot.
	if grounded:
		_input = Vector3.ZERO
		return result
	var requested := Vector3(-forward, -side, -steer)
	_input += (requested - _input) * (1.0 - exp(-dt / maxf(0.001, _value(cfg, "InputResponse"))))
	var omega_world: Vector3 = frame.get("omega", Vector3.ZERO)
	var omega := basis.transposed() * omega_world
	var velocity: Vector3 = frame.get("velocity", Vector3.ZERO)
	var speed_authority := lerpf(clampf(_value(cfg, "LowSpeedAuthority"), 0.0, 1.0), 1.0,
		smoothstep(_value(cfg, "LowSpeed"), maxf(_value(cfg, "LowSpeed") + 0.01, _value(cfg, "FullSpeed")), velocity.length()))
	var rates := Vector3(maxf(0.0, _value(cfg, "PitchRate")),
		maxf(0.0, _value(cfg, "YawRate")), maxf(0.0, _value(cfg, "RollRate")))
	rates.y *= maxf(0.0, _value(cfg, "WhipResponse"))
	rates.z *= maxf(0.0, _value(cfg, "WhipResponse"))
	var target := _input * rates * speed_authority
	# Counter-input may ask for a quicker return RATE. It never knows the
	# takeoff heading or whether the motorcycle has become straight again.
	for axis: int in range(3):
		if target[axis] * omega[axis] < -0.02:
			target[axis] *= maxf(1.0, _value(cfg, "WhipRecovery")) if axis > 0 else 1.0
	var response := maxf(0.02, _value(cfg, "RateResponse"))
	if requested.length_squared() < 0.0004:
		response = maxf(response, _value(cfg, "NeutralDampingTime"))
	var acceleration := basis * ((target - omega) / response)
	var tensor := assembly_tensor(frame.get("bodies", []))
	var torque := basis.transposed() * (tensor * acceleration)
	var limits := Vector3(maxf(0.0, _value(cfg, "MaxPitchTorque")),
		maxf(0.0, _value(cfg, "MaxYawTorque")), maxf(0.0, _value(cfg, "MaxRollTorque")))
	for axis: int in range(3):
		torque[axis] = clampf(torque[axis], -limits[axis], limits[axis])
	torque = torque.limit_length(maxf(0.0, _value(cfg, "MaxTotalTorque"))) * strength * activation
	var world_torque := basis * torque
	var power := world_torque.dot(omega_world)
	var power_limit := maxf(0.0, _value(cfg, "MaxPower") if power >= 0.0 else _value(cfg, "MaxDissipationPower")) * strength
	if absf(power) > power_limit and absf(power) > 0.000001:
		world_torque *= power_limit / absf(power)
		torque = basis.transposed() * world_torque
		power = world_torque.dot(omega_world)
	result.active = activation > 0.0
	result.torque = world_torque
	result.localTorque = torque
	result.targetRate = target
	result.powerWatts = power
	return result
