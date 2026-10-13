class_name DLDrivetrain
extends RefCounted
## SI-unit crank, manual dog gearbox, dry clutch and rear rotor.
## Wheel speed is an integrated momentum state, never a vehicle-speed target.

const RPM_TO_RAD: float = PI / 30.0
const MAX_STEP: float = 1.0 / 240.0

static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

static func _normalized(value: float) -> float:
	return clampf(value, 0.0, 1.0) if _finite(value) else 0.0

static func ratio_for(gear: int, cfg: Dictionary) -> float:
	return 0.0 if gear == 0 else float(cfg.PrimaryRatio) * float(cfg.GearRatios[gear - 1]) * float(cfg.FinalRatio)

static func curve_torque(rpm: float, cfg: Dictionary) -> float:
	var curve: Array = cfg.TorqueCurve
	if rpm <= float(curve[0][0]):
		return float(curve[0][1])
	for index: int in range(1, curve.size()):
		var previous: Array = curve[index - 1]
		var point: Array = curve[index]
		if rpm <= float(point[0]):
			var alpha: float = (rpm - float(previous[0])) / (float(point[0]) - float(previous[0]))
			return lerpf(float(previous[1]), float(point[1]), alpha)
	return float(curve[-1][1])

## A dissipative Coulomb impulse cannot push a rotor through zero.
static func retard(omega: float, impulse: float, inertia: float) -> float:
	var change: float = minf(absf(omega), maxf(0.0, impulse) / inertia)
	return omega - signf(omega) * change

static func new_state(cfg: Dictionary) -> Dictionary:
	assert(float(cfg.EngineInertia) > 0.0 and float(cfg.RearInertia) > 0.0, "Rotor inertia must be positive")
	assert(float(cfg.IdleRPM) > float(cfg.StallRPM) and float(cfg.StallRPM) > 0.0, "Idle must exceed stall RPM")
	assert(float(cfg.RedlineRPM) > float(cfg.IdleRPM), "Redline must exceed idle RPM")
	assert(float(cfg.PrimaryRatio) > 0.0 and float(cfg.FinalRatio) > 0.0 and cfg.GearRatios.size() > 0, "Invalid gearing")
	assert(float(cfg.Efficiency) > 0.0 and float(cfg.Efficiency) <= 1.0 and float(cfg.ClutchCapacity) >= 0.0, "Invalid transmission")
	var curve: Array = cfg.TorqueCurve
	assert(curve.size() >= 2, "Engine requires at least two torque samples")
	for index: int in range(curve.size()):
		assert(float(curve[index][1]) >= 0.0 and (index == 0 or float(curve[index][0]) > float(curve[index - 1][0])), "Invalid torque curve")
	for gear_ratio: Variant in cfg.GearRatios:
		assert(float(gear_ratio) > 0.0, "Gear ratios must be positive")
	return {"gear": 0, "engineOmega": float(cfg.IdleRPM) * RPM_TO_RAD, "rearOmega": 0.0, "stalled": false, "shiftTimer": 0.0, "limiter": false}

static func shift(state: Dictionary, delta: int, input: Dictionary, cfg: Dictionary) -> bool:
	if delta != 1 and delta != -1:
		return false
	var next_gear: int = int(state.gear) + delta
	if next_gear < 0 or next_gear > cfg.GearRatios.size() or float(state.shiftTimer) > 0.0:
		return false
	if _normalized(float(input.get("clutch", 0.0))) < 0.8 and _normalized(float(input.get("throttle", 0.0))) > 0.08:
		return false
	# A shift cuts ignition; it does not synchronize either rotor's speed.
	state.gear = next_gear
	state.shiftTimer = float(cfg.ShiftCutTime)
	return true

static func start(state: Dictionary, input: Dictionary, cfg: Dictionary) -> bool:
	if not bool(state.stalled) or (int(state.gear) != 0 and _normalized(float(input.get("clutch", 0.0))) <= 0.8):
		return false
	# Only this explicit starter action supplies restart energy.
	state.stalled = false
	state.limiter = false
	state.engineOmega = float(cfg.IdleRPM) * RPM_TO_RAD
	return true

static func step(state: Dictionary, input: Dictionary, rear_contact_torque: float, dt: float, cfg: Dictionary) -> Dictionary:
	assert(_finite(dt) and dt >= 0.0, "Drivetrain dt must be finite and nonnegative")
	assert(_finite(rear_contact_torque), "Rear contact torque must be finite")
	var throttle: float = _normalized(float(input.get("throttle", 0.0)))
	var engagement: float = 1.0 - _normalized(float(input.get("clutch", 0.0)))
	var brake: float = _normalized(float(input.get("rearBrake", 0.0)))
	var ratio: float = ratio_for(int(state.gear), cfg)
	var engine_inertia: float = float(cfg.EngineInertia)
	var rear_inertia: float = float(cfg.RearInertia)
	var initial_engine: float = float(state.engineOmega)
	var initial_rear: float = float(state.rearOmega)
	var initial_momentum: float = engine_inertia * initial_engine + rear_inertia * initial_rear
	var shaft_work: float = 0.0
	var substeps: int = maxi(1, ceili(dt / MAX_STEP))
	var h: float = dt / float(substeps)
	if dt > 0.0:
		for _substep: int in range(substeps):
			var previous_engine: float = float(state.engineOmega)
			var rpm: float = maxf(0.0, previous_engine / RPM_TO_RAD)
			if rpm >= float(cfg.RedlineRPM):
				state.limiter = true
			elif rpm < float(cfg.RedlineRPM) * 0.97:
				state.limiter = false
			var combustion: float = 0.0
			var losses: float = float(cfg.FrictionTorque) + float(cfg.EngineBrakeTorque) * (1.0 - throttle)
			if not bool(state.stalled) and not bool(state.limiter) and float(state.shiftTimer) <= 0.0:
				# Idle-air governor is bounded torque; clutch loading can overwhelm it.
				var idle_omega: float = float(cfg.IdleRPM) * RPM_TO_RAD
				var idle_torque: float = clampf(float(cfg.FrictionTorque) + float(cfg.EngineBrakeTorque) + (idle_omega - previous_engine) * engine_inertia * 12.0, 0.0, curve_torque(float(cfg.IdleRPM), cfg))
				combustion = throttle * curve_torque(rpm, cfg) + (1.0 - throttle) * idle_torque
			state.engineOmega = float(state.engineOmega) + combustion * h / engine_inertia
			state.engineOmega = retard(float(state.engineOmega), losses * h, engine_inertia)
			shaft_work += 0.5 * engine_inertia * (float(state.engineOmega) ** 2 - previous_engine ** 2)
			state.rearOmega = float(state.rearOmega) + rear_contact_torque * h / rear_inertia
			if ratio > 0.0 and engagement > 0.0:
				# Implicit two-inertia clutch removes slip without stiff explicit forces.
				var slip: float = float(state.engineOmega) - float(state.rearOmega) * ratio
				var inverse_inertia: float = 1.0 / engine_inertia + ratio ** 2 / rear_inertia
				var limit: float = float(cfg.ClutchCapacity) * engagement * h
				var impulse: float = clampf(slip / inverse_inertia, -limit, limit)
				state.engineOmega = float(state.engineOmega) - impulse / engine_inertia
				state.rearOmega = float(state.rearOmega) + impulse * ratio / rear_inertia
				# Dissipate after ideal coupling so wheel back-drive remains passive.
				state.rearOmega = retard(float(state.rearOmega), (1.0 - float(cfg.Efficiency)) * absf(impulse * ratio), rear_inertia)
			state.rearOmega = retard(float(state.rearOmega), brake * float(cfg.RearBrakeTorque) * h, rear_inertia)
			if not bool(state.stalled) and float(state.engineOmega) < float(cfg.StallRPM) * RPM_TO_RAD:
				state.stalled = true
				state.limiter = false
			state.shiftTimer = maxf(0.0, float(state.shiftTimer) - h)
	var final_momentum: float = engine_inertia * float(state.engineOmega) + rear_inertia * float(state.rearOmega)
	return {
		"rearOmega": float(state.rearOmega), "rpm": maxf(0.0, float(state.engineOmega) / RPM_TO_RAD),
		"gear": int(state.gear), "stalled": bool(state.stalled),
		"clutchSlip": float(state.engineOmega) - float(state.rearOmega) * ratio if ratio > 0.0 else 0.0,
		"engineReaction": (final_momentum - initial_momentum) / dt - rear_contact_torque if dt > 0.0 else 0.0,
		# Native wheel bodies already carry wheel angular momentum: apply their
		# motor/brake reaction separately and use this crank-only term on chassis.
		"engineOnlyReaction": engine_inertia * (float(state.engineOmega) - initial_engine) / dt if dt > 0.0 else 0.0,
		"power": shaft_work / dt if dt > 0.0 else 0.0,
	}
