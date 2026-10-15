class_name DLTire
extends RefCounted
## Independent, load-sensitive brush patches with SI force and distance
## relaxation. Each axle can override the shared engineering coefficients;
## these are prototype knobby-tire curves, not measured competition data.

static func _finite(value: float, fallback: float) -> float:
	return fallback if is_nan(value) or is_inf(value) else value

static func _setting(cfg: Dictionary, key: String, fallback: float) -> float:
	return _finite(float(cfg.get(key, fallback)), fallback)

## Resolve once when a bike is configured/tuned, rather than mutating shared
## tire settings while one axle is being evaluated. Returned dictionaries and
## their nested values cannot alter the other axle or the caller's config.
static func axle_settings(base: Dictionary, axle: String) -> Dictionary:
	var settings := base.duplicate(true)
	settings.erase("Front")
	settings.erase("Rear")
	var overrides: Dictionary = base.get(axle, {})
	settings.merge(overrides.duplicate(true), true)
	return settings

static func new_state() -> Dictionary:
	return {"slipRatio": 0.0, "slipAngle": 0.0, "contact": false}

## Pure evaluation permits the native contact solver/tests to try a load
## without advancing patch strain or altering the other axle's state.
static func evaluate(state: Dictionary, input: Dictionary, cfg: Dictionary, surface: Dictionary) -> Dictionary:
	var minimum_speed := maxf(_setting(cfg, "MinimumSpeed", 1.5), 0.1)
	var omega := _finite(float(input.wheelOmega), 0.0)
	var radius := maxf(_finite(float(input.radius), 0.0), 0.0)
	var wheel_speed := _finite(omega * radius, 0.0)
	var vx := _finite(float(input.longitudinalVelocity), 0.0)
	var vy := _finite(float(input.get("lateralSlipVelocity", input.lateralVelocity)), 0.0)
	var load := maxf(_finite(float(input.normalLoad), 0.0), 0.0)
	var contact: bool = bool(input.contact) and load > 0.0 and radius > 0.0
	var fx := 0.0
	var fy := 0.0
	var torque := 0.0
	var rolling_torque := 0.0
	var utilization := 0.0
	var grip := 0.0
	var surface_grip := 0.0
	var capacity_x := 0.0
	var capacity_y := 0.0
	var normalized_demand := 0.0
	var slip_power := 0.0
	var limited_slip_work := false
	var sliding := false
	if contact:
		var reference_load := maxf(_setting(cfg, "ReferenceLoad", 920.0), 1.0)
		var sensitivity := clampf(_setting(cfg, "LoadSensitivity", 0.0), 0.0, 0.5)
		var load_factor := clampf((load / reference_load) ** -sensitivity, 0.5, 1.5)
		surface_grip = maxf(_finite(float(surface.Grip), 0.0), 0.0) * load_factor * maxf(_setting(cfg, "GripScale", 1.0), 0.0)
		var demand_x := load * maxf(_setting(cfg, "LongitudinalStiffness", 0.0), 0.0) * _finite(float(state.slipRatio), 0.0)
		# The sign of force relative to travel distinguishes acceleration from
		# braking, including reverse rolling; positive Fx alone does not.
		var travel := vx if absf(vx) > 0.25 else wheel_speed
		var braking := demand_x * travel < 0.0
		var longitudinal_grip := maxf(_setting(cfg, "BrakingGrip" if braking else "AccelerationGrip", 1.0), 0.0)
		var lateral_grip := maxf(_setting(cfg, "LateralGrip", 1.0), 0.0)
		capacity_x = surface_grip * load * longitudinal_grip
		capacity_y = surface_grip * load * lateral_grip
		# 'grip' remains a conservative enclosing circle for existing telemetry
		# and force-budget guards. capacityX/Y expose the stricter actual ellipse.
		grip = surface_grip * maxf(longitudinal_grip, lateral_grip)
		# Rolling camber thrust requires transported tread. A stationary tilted
		# wheel gains no external sideways support; remembered lateral strain
		# is still allowed to oppose an existing slide at walking pace.
		var transport := maxf(absf(wheel_speed), absf(vx))
		var camber_transport := smoothstep(0.0, minimum_speed, transport)
		var demand_y := load * (-maxf(_setting(cfg, "LateralStiffness", 0.0), 0.0) * _finite(float(state.slipAngle), 0.0) + maxf(_setting(cfg, "CamberStiffness", 0.0), 0.0) * sin(_finite(float(input.get("camber", 0.0)), 0.0)) * camber_transport)
		# Normalize in an ellipse so drive/brake demand consumes lateral grip
		# progressively. Increasing small-slip stiffness changes response, not
		# peak capacity; each axle still has one shared contact budget.
		if capacity_x <= 0.0:
			demand_x = 0.0
		if capacity_y <= 0.0:
			demand_y = 0.0
		var demand_x_normalized := demand_x / capacity_x if capacity_x > 0.0 else 0.0
		var demand_y_normalized := demand_y / capacity_y if capacity_y > 0.0 else 0.0
		normalized_demand = sqrt(demand_x_normalized * demand_x_normalized + demand_y_normalized * demand_y_normalized)
		if normalized_demand > 0.0:
			var brush_slip := clampf(normalized_demand / 3.0, 0.0, 1.0)
			utilization = 1.0 - (1.0 - brush_slip) ** 3
			fx = demand_x * utilization / normalized_demand
			fy = demand_y * utilization / normalized_demand
			sliding = brush_slip >= 1.0
		# Report instantaneous tread work for native force/energy diagnostics.
		# A relaxing brush can briefly return stored strain energy when motion
		# reverses. The optional strict-work limiter removes that active part
		# in normalized ellipse coordinates, but is OFF for riding: clipping
		# legitimate transient strain reaction can reduce steering support.
		# Callers may supply exact full-patch lateral velocity on skewed terrain.
		var slip_x := vx - wheel_speed
		var slip_y := _finite(float(input.get("lateralSlipVelocity", vy)), 0.0)
		slip_power = fx * slip_x + fy * slip_y
		if bool(cfg.get("LimitSlipWork", false)) and slip_power > 0.0:
			var scaled_x := capacity_x * slip_x
			var scaled_y := capacity_y * slip_y
			var denominator := scaled_x * scaled_x + scaled_y * scaled_y
			if denominator > 0.000000000001:
				var correction := slip_power / denominator
				fx -= correction * capacity_x * scaled_x
				fy -= correction * capacity_y * scaled_y
				limited_slip_work = true
				slip_power = fx * slip_x + fy * slip_y
				var used_x := fx / capacity_x if capacity_x > 0.0 else 0.0
				var used_y := fy / capacity_y if capacity_y > 0.0 else 0.0
				utilization = sqrt(used_x * used_x + used_y * used_y)
		var rolling := maxf(_setting(cfg, "RollingResistance", 0.0), 0.0) + maxf(_finite(float(surface.Rolling), 0.0), 0.0)
		# Signed rolling loss is smooth at rest; it cannot invent launch traction.
		rolling_torque = -rolling * load * radius * tanh(wheel_speed / minimum_speed)
		torque = -fx * radius + rolling_torque
	return {"longitudinalForce": fx, "lateralForce": fy, "contactTorque": torque, "rollingTorque": rolling_torque,
		"slipRatio": _finite(float(state.slipRatio), 0.0), "slipAngle": _finite(float(state.slipAngle), 0.0),
		"utilization": utilization, "sliding": sliding, "grip": grip, "surfaceGrip": surface_grip,
		"capacityX": capacity_x, "capacityY": capacity_y, "normalizedDemand": normalized_demand,
		"slipPower": slip_power, "limitedSlipWork": limited_slip_work}

static func step(state: Dictionary, input: Dictionary, dt: float, cfg: Dictionary, surface: Dictionary) -> Dictionary:
	var minimum_speed := maxf(_setting(cfg, "MinimumSpeed", 1.5), 0.1)
	var legacy_relaxation := maxf(_setting(cfg, "RelaxationLength", 0.25), 0.001)
	var longitudinal_relaxation := maxf(_setting(cfg, "LongitudinalRelaxationLength", legacy_relaxation), 0.001)
	var lateral_relaxation := maxf(_setting(cfg, "LateralRelaxationLength", legacy_relaxation), 0.001)
	var vx := _finite(float(input.longitudinalVelocity), 0.0)
	var vy := _finite(float(input.get("lateralSlipVelocity", input.lateralVelocity)), 0.0)
	var radius := maxf(_finite(float(input.radius), 0.0), 0.0)
	var wheel_speed := _finite(_finite(float(input.wheelOmega), 0.0) * radius, 0.0)
	var denominator := sqrt(vx * vx + minimum_speed * minimum_speed)
	var target_ratio := clampf(_finite((wheel_speed - vx) / denominator, 0.0), -20.0, 20.0)
	# An exact lateral override requires a contact lever and body state from
	# the same simulation phase. Raw native world contacts can precede the
	# solved hub by a step; spinning about that stale lever invents sideslip.
	# The game therefore uses non-spin transport plus the separate camber law.
	# Coherent callers can supply lateralSlipVelocity without changing the API.
	var target_angle := atan(vy / denominator)
	var contact: bool = bool(input.contact) and _finite(float(input.normalLoad), 0.0) > 0.0 and radius > 0.0
	var transport_speed := maxf(maxf(absf(vx), absf(wheel_speed)), minimum_speed)
	var distance := transport_speed * maxf(_finite(dt, 0.0), 0.0)
	var alpha_x := 1.0 - exp(-distance / longitudinal_relaxation)
	var alpha_y := 1.0 - exp(-distance / lateral_relaxation)
	state.slipRatio = _finite(float(state.slipRatio), 0.0) + ((target_ratio if contact else 0.0) - _finite(float(state.slipRatio), 0.0)) * alpha_x
	state.slipAngle = _finite(float(state.slipAngle), 0.0) + ((target_angle if contact else 0.0) - _finite(float(state.slipAngle), 0.0)) * alpha_y
	state.contact = contact
	return evaluate(state, input, cfg, surface)
