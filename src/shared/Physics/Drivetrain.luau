--!strict
-- SI-unit engine, manual gearbox, dry clutch, and rear wheel. This module
-- does not prescribe vehicle speed: the tire model supplies signed axle torque.
local Drivetrain = {}

export type DriveConfig = {
	IdleRPM: number,
	StallRPM: number,
	RedlineRPM: number,
	EngineInertia: number,
	RearInertia: number,
	PrimaryRatio: number,
	FinalRatio: number,
	GearRatios: { number },
	Efficiency: number,
	ClutchCapacity: number,
	EngineBrakeTorque: number,
	FrictionTorque: number,
	ShiftCutTime: number,
	RearBrakeTorque: number,
	TorqueCurve: { { number } },
}

export type Controls = { throttle: number, clutch: number, rearBrake: number? }
export type State = {
	gear: number,
	engineOmega: number,
	rearOmega: number,
	stalled: boolean,
	shiftTimer: number,
	limiter: boolean,
}
export type Output = {
	rearOmega: number,
	rpm: number,
	gear: number,
	stalled: boolean,
	clutchSlip: number,
	engineReaction: number,
	power: number,
}

local RPM_TO_RAD = math.pi / 30
local MAX_STEP = 1 / 240

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function normalized(value: number): number
	return if finite(value) then math.clamp(value, 0, 1) else 0
end

local function ratioFor(gear: number, cfg: DriveConfig): number
	return if gear == 0 then 0 else cfg.PrimaryRatio * cfg.GearRatios[gear] * cfg.FinalRatio
end

local function curveTorque(rpm: number, cfg: DriveConfig): number
	local curve = cfg.TorqueCurve
	if rpm <= curve[1][1] then
		return curve[1][2]
	end
	for index = 2, #curve do
		local previous, point = curve[index - 1], curve[index]
		if rpm <= point[1] then
			local alpha = (rpm - previous[1]) / (point[1] - previous[1])
			return previous[2] + (point[2] - previous[2]) * alpha
		end
	end
	return curve[#curve][2]
end

-- Coulomb brake impulse opposes the current motion and cannot start reverse
-- motion. This is used for bearing/pumping drag and the independent rear brake.
local function retard(omega: number, impulse: number, inertia: number): number
	local change = math.min(math.abs(omega), math.max(0, impulse) / inertia)
	return omega - math.sign(omega) * change
end

function Drivetrain.new(cfg: DriveConfig): State
	assert(cfg.EngineInertia > 0 and cfg.RearInertia > 0, "Rotor inertia must be positive")
	assert(cfg.IdleRPM > cfg.StallRPM and cfg.StallRPM > 0, "Idle must be above stall RPM")
	assert(cfg.RedlineRPM > cfg.IdleRPM, "Redline must be above idle RPM")
	assert(cfg.PrimaryRatio > 0 and cfg.FinalRatio > 0 and #cfg.GearRatios > 0, "Invalid gearing")
	assert(cfg.Efficiency > 0 and cfg.Efficiency <= 1 and cfg.ClutchCapacity >= 0, "Invalid clutch")
	assert(#cfg.TorqueCurve >= 2, "An engine requires at least two torque-curve samples")
	for index, point in cfg.TorqueCurve do
		assert(point[2] >= 0 and (index == 1 or point[1] > cfg.TorqueCurve[index - 1][1]), "Invalid torque curve")
	end
	for _, ratio in cfg.GearRatios do
		assert(ratio > 0, "Gear ratios must be positive")
	end
	return {
		gear = 0,
		engineOmega = cfg.IdleRPM * RPM_TO_RAD,
		rearOmega = 0,
		stalled = false,
		shiftTimer = 0,
		limiter = false,
	}
end

function Drivetrain.shift(state: State, delta: number, controls: Controls, cfg: DriveConfig): boolean
	if delta ~= 1 and delta ~= -1 then
		return false
	end
	local nextGear = state.gear + delta
	if nextGear < 0 or nextGear > #cfg.GearRatios or state.shiftTimer > 0 then
		return false
	end
	-- The prototype models a dog gearbox and an ignition interruption. It does
	-- not synchronize RPM or change wheel momentum when the rider selects gear.
	if normalized(controls.clutch) < 0.8 and normalized(controls.throttle) > 0.08 then
		return false
	end
	state.gear = nextGear
	state.shiftTimer = cfg.ShiftCutTime
	return true
end

function Drivetrain.start(state: State, controls: Controls, cfg: DriveConfig): boolean
	if not state.stalled or (state.gear ~= 0 and normalized(controls.clutch) <= 0.8) then
		return false
	end
	-- A starter adds real energy; it is an explicit rider action, never an
	-- automatic stall recovery or an engine-speed reset during normal riding.
	state.stalled = false
	state.limiter = false
	state.engineOmega = cfg.IdleRPM * RPM_TO_RAD
	return true
end

function Drivetrain.step(state: State, input: Controls, rearContactTorque: number, dt: number, cfg: DriveConfig): Output
	assert(finite(dt) and dt >= 0, "Drivetrain dt must be finite and nonnegative")
	assert(finite(rearContactTorque), "Rear contact torque must be finite")
	local throttle = normalized(input.throttle)
	local engagement = 1 - normalized(input.clutch)
	local rearBrake = normalized(input.rearBrake or 0)
	local ratio = ratioFor(state.gear, cfg)
	local initialMomentum = cfg.EngineInertia * state.engineOmega + cfg.RearInertia * state.rearOmega
	local shaftWork = 0
	local substeps = math.max(1, math.ceil(dt / MAX_STEP))
	local h = dt / substeps

	if dt > 0 then
		for _ = 1, substeps do
			local previousEngine = state.engineOmega
			local rpm = math.max(0, previousEngine / RPM_TO_RAD)
			if rpm >= cfg.RedlineRPM then
				state.limiter = true
			elseif rpm < cfg.RedlineRPM * 0.97 then
				state.limiter = false
			end

			local combustion = 0
			local losses = cfg.FrictionTorque + cfg.EngineBrakeTorque * (1 - throttle)
			if not state.stalled and not state.limiter and state.shiftTimer <= 0 then
				-- A bounded idle-air governor supplies torque, not an RPM constraint.
				-- It can keep an unloaded engine alive, but cannot resist a clutch dump.
				local idleOmega = cfg.IdleRPM * RPM_TO_RAD
				local idleTorque = math.clamp(cfg.FrictionTorque + cfg.EngineBrakeTorque
					+ (idleOmega - previousEngine) * cfg.EngineInertia * 12, 0, curveTorque(cfg.IdleRPM, cfg))
				combustion = throttle * curveTorque(rpm, cfg) + (1 - throttle) * idleTorque
			end
			state.engineOmega += combustion * h / cfg.EngineInertia
			state.engineOmega = retard(state.engineOmega, losses * h, cfg.EngineInertia)
			-- Mechanical power at the crank, signed during engine braking. Using
			-- average omega makes this equal the free crank's kinetic energy change.
			shaftWork += 0.5 * cfg.EngineInertia * (state.engineOmega ^ 2 - previousEngine ^ 2)
			state.rearOmega += rearContactTorque * h / cfg.RearInertia

			if ratio > 0 and engagement > 0 then
				-- Implicit two-inertia clutch: a single bounded angular impulse
				-- removes slip without overshoot, regardless of clutch stiffness/dt.
				local slip = state.engineOmega - state.rearOmega * ratio
				local inverseInertia = 1 / cfg.EngineInertia + ratio ^ 2 / cfg.RearInertia
				local limit = cfg.ClutchCapacity * engagement * h
				local impulse = math.clamp(slip / inverseInertia, -limit, limit)
				state.engineOmega -= impulse / cfg.EngineInertia
				state.rearOmega += impulse * ratio / cfg.RearInertia
				-- Transmission loss is an additional opposing wheel impulse. First
				-- solve the ideal coupling, then dissipate energy; multiplying a signed
				-- drive impulse by efficiency would add energy during back-driving.
				state.rearOmega = retard(state.rearOmega, (1 - cfg.Efficiency) * math.abs(impulse * ratio), cfg.RearInertia)
			end

			state.rearOmega = retard(state.rearOmega, rearBrake * cfg.RearBrakeTorque * h, cfg.RearInertia)
			if not state.stalled and state.engineOmega < cfg.StallRPM * RPM_TO_RAD then
				state.stalled = true
				state.limiter = false
			end
			state.shiftTimer = math.max(0, state.shiftTimer - h)
		end
	end

	local finalMomentum = cfg.EngineInertia * state.engineOmega + cfg.RearInertia * state.rearOmega
	return {
		rearOmega = state.rearOmega,
		rpm = math.max(0, state.engineOmega / RPM_TO_RAD),
		gear = state.gear,
		stalled = state.stalled,
		clutchSlip = if ratio > 0 then state.engineOmega - state.rearOmega * ratio else 0,
		-- Forward rotor spin is about -bodyRight, so increasing spin reacts
		-- nose-up about +bodyRight. Exclude the external tire torque because
		-- the caller already applies its contact force to the rigid chassis.
		engineReaction = if dt > 0 then (finalMomentum - initialMomentum) / dt - rearContactTorque else 0,
		power = if dt > 0 then shaftWork / dt else 0,
	}
end

return Drivetrain
