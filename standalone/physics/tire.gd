class_name DLTire
extends RefCounted
## Independent brush patches: SI force, distance relaxation, combined grip.
## Engineering prototype coefficients, not measured tire data.

static func _finite(value: float, fallback: float) -> float:
	return fallback if is_nan(value) or is_inf(value) else value

static func new_state() -> Dictionary:
	return {"slipRatio": 0.0, "slipAngle": 0.0, "contact": false}

## Pure evaluation permits a native contact solver to try a load without
## advancing patch strain or altering the other axle's state.
static func evaluate(state: Dictionary, input: Dictionary, cfg: Dictionary, surface: Dictionary) -> Dictionary:
	var minimum_speed: float = maxf(_finite(float(cfg.MinimumSpeed), 1.5), 0.1)
	var omega: float = _finite(float(input.wheelOmega), 0.0)
	var radius: float = maxf(_finite(float(input.radius), 0.0), 0.0)
	var wheel_speed: float = _finite(omega * radius, 0.0)
	var load: float = maxf(_finite(float(input.normalLoad), 0.0), 0.0)
	var contact: bool = bool(input.contact) and load > 0.0 and radius > 0.0
	var fx: float = 0.0
	var fy: float = 0.0
	var torque: float = 0.0
	var rolling_torque: float = 0.0
	var utilization: float = 0.0
	var grip: float = 0.0
	var sliding: bool = false
	if contact:
		var reference_load: float = maxf(_finite(float(cfg.ReferenceLoad), 920.0), 1.0)
		var sensitivity: float = clampf(_finite(float(cfg.LoadSensitivity), 0.0), 0.0, 0.5)
		var load_factor: float = clampf((load / reference_load) ** -sensitivity, 0.5, 1.5)
		grip = maxf(_finite(float(surface.Grip), 0.0), 0.0) * load_factor
		var capacity: float = grip * load
		if capacity > 0.0:
			var demand_x: float = load * maxf(_finite(float(cfg.LongitudinalStiffness), 0.0), 0.0) * _finite(float(state.slipRatio), 0.0)
			# Camber thrust comes from transported/deformed tread, rather than an
			# external sideways support force on a stationary tilted wheel. Fade
			# only that term at walking speeds; remembered slip strain and the
			# combined friction budget still use their original brush equations.
			var transport: float = maxf(absf(wheel_speed), absf(_finite(float(input.longitudinalVelocity), 0.0)))
			var camber_transport := smoothstep(0.0, minimum_speed, transport)
			# Positive camber leans to wheel-right; lateral slip opposes that motion.
			var demand_y: float = load * (-maxf(_finite(float(cfg.LateralStiffness), 0.0), 0.0) * _finite(float(state.slipAngle), 0.0) + maxf(_finite(float(cfg.CamberStiffness), 0.0), 0.0) * sin(_finite(float(input.get("camber", 0.0)), 0.0)) * camber_transport)
			var demand: float = sqrt(demand_x * demand_x + demand_y * demand_y)
			if demand > 0.0:
				var brush_slip: float = clampf(demand / (3.0 * capacity), 0.0, 1.0)
				utilization = 1.0 - (1.0 - brush_slip) ** 3
				var scale: float = capacity * utilization / demand
				fx = demand_x * scale
				fy = demand_y * scale
				sliding = brush_slip >= 1.0
		var rolling: float = maxf(_finite(float(cfg.RollingResistance), 0.0), 0.0) + maxf(_finite(float(surface.Rolling), 0.0), 0.0)
		# Signed rolling loss is smooth at rest; it cannot invent launch traction.
		rolling_torque = -rolling * load * radius * tanh(wheel_speed / minimum_speed)
		torque = -fx * radius + rolling_torque
	return {"longitudinalForce": fx, "lateralForce": fy, "contactTorque": torque, "rollingTorque": rolling_torque, "slipRatio": float(state.slipRatio), "slipAngle": float(state.slipAngle), "utilization": utilization, "sliding": sliding, "grip": grip}

static func step(state: Dictionary, input: Dictionary, dt: float, cfg: Dictionary, surface: Dictionary) -> Dictionary:
	var minimum_speed: float = maxf(_finite(float(cfg.MinimumSpeed), 1.5), 0.1)
	var relaxation: float = maxf(_finite(float(cfg.RelaxationLength), 0.25), 0.001)
	var vx: float = _finite(float(input.longitudinalVelocity), 0.0)
	var vy: float = _finite(float(input.lateralVelocity), 0.0)
	var radius: float = maxf(_finite(float(input.radius), 0.0), 0.0)
	var wheel_speed: float = _finite(_finite(float(input.wheelOmega), 0.0) * radius, 0.0)
	var denominator: float = sqrt(vx * vx + minimum_speed * minimum_speed)
	var target_ratio: float = clampf(_finite((wheel_speed - vx) / denominator, 0.0), -20.0, 20.0)
	var target_angle: float = atan(vy / denominator)
	var contact: bool = bool(input.contact) and _finite(float(input.normalLoad), 0.0) > 0.0 and radius > 0.0
	var transport_speed: float = maxf(maxf(absf(vx), absf(wheel_speed)), minimum_speed)
	var alpha: float = 1.0 - exp(-transport_speed * maxf(_finite(dt, 0.0), 0.0) / relaxation)
	state.slipRatio = _finite(float(state.slipRatio), 0.0) + ((target_ratio if contact else 0.0) - _finite(float(state.slipRatio), 0.0)) * alpha
	state.slipAngle = _finite(float(state.slipAngle), 0.0) + ((target_angle if contact else 0.0) - _finite(float(state.slipAngle), 0.0)) * alpha
	state.contact = contact
	return evaluate(state, input, cfg, surface)
