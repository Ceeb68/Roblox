--!strict
-- Independent brush contacts with distance-based stress relaxation and a
-- combined Coulomb friction circle. All units are metres, seconds, N and Nm.
-- Coefficients are prototype engineering choices, not measured MX tire data.
local Tire = {}

export type State = { slipRatio: number, slipAngle: number, contact: boolean }
export type Input = {
	normalLoad: number,
	longitudinalVelocity: number,
	lateralVelocity: number,
	wheelOmega: number,
	radius: number,
	camber: number,
	contact: boolean,
}
export type Config = {
	LongitudinalStiffness: number,
	LateralStiffness: number,
	CamberStiffness: number,
	RelaxationLength: number,
	MinimumSpeed: number,
	ReferenceLoad: number,
	LoadSensitivity: number,
	RollingResistance: number,
}
export type Surface = { Grip: number, Rolling: number }
export type Output = {
	longitudinalForce: number,
	lateralForce: number,
	contactTorque: number,
	rollingTorque: number,
	slipRatio: number,
	slipAngle: number,
	utilization: number,
	sliding: boolean,
	grip: number,
}

local function finite(value: number, fallback: number): number
	return if value == value and math.abs(value) < math.huge then value else fallback
end

function Tire.new(): State
	return { slipRatio = 0, slipAngle = 0, contact = false }
end

-- Evaluate an already-relaxed contact at a trial normal load. This is pure:
-- suspension equilibrium solvers can call it without advancing patch strain.
function Tire.evaluate(state: State, input: Input, cfg: Config, surface: Surface): Output
	local minimumSpeed = math.max(finite(cfg.MinimumSpeed, 1.5), 0.1)
	local omega = finite(input.wheelOmega, 0)
	local radius = math.max(finite(input.radius, 0), 0)
	local wheelSpeed = finite(omega * radius, 0)
	local load = math.max(finite(input.normalLoad, 0), 0)
	local contact = input.contact and load > 0 and radius > 0
	local fx, fy, torque, rollingTorque, utilization, grip = 0, 0, 0, 0, 0, 0
	local sliding = false
	if contact then
		local referenceLoad = math.max(finite(cfg.ReferenceLoad, 920), 1)
		local sensitivity = math.clamp(finite(cfg.LoadSensitivity, 0), 0, 0.5)
		-- Pneumatic tires become less efficient as their load rises. The two
		-- axles receive separate loads; their grip is never redistributed here.
		local loadFactor = math.clamp((load / referenceLoad) ^ -sensitivity, 0.5, 1.5)
		grip = math.max(finite(surface.Grip, 0), 0) * loadFactor
		local capacity = grip * load
		if capacity > 0 then
			local demandX = load * math.max(finite(cfg.LongitudinalStiffness, 0), 0) * state.slipRatio
			-- Positive camber is lean toward wheel-right. Camber thrust acts
			-- toward that lean; lateral slip resists wheel-right motion.
			local demandY = load * (-math.max(finite(cfg.LateralStiffness, 0), 0) * state.slipAngle
				+ math.max(finite(cfg.CamberStiffness, 0), 0) * math.sin(finite(input.camber, 0)))
			local demand = math.sqrt(demandX * demandX + demandY * demandY)
			if demand > 0 then
				-- Isotropic brush law: progressively slipping bristles saturate
				-- at μN. Braking and cornering share one force budget.
				local brushSlip = math.clamp(demand / (3 * capacity), 0, 1)
				utilization = 1 - (1 - brushSlip) ^ 3
				local scale = capacity * utilization / demand
				fx = demandX * scale
				fy = demandY * scale
				sliding = brushSlip >= 1
			end
		end
		local rolling = math.max(finite(cfg.RollingResistance, 0), 0) + math.max(finite(surface.Rolling, 0), 0)
		-- Smooth rolling torque near zero prevents sign chatter; it consumes
		-- wheel rotation rather than resetting velocity or inventing traction.
		rollingTorque = -rolling * load * radius * math.tanh(wheelSpeed / minimumSpeed)
		torque = -fx * radius + rollingTorque
	end
	return {
		longitudinalForce = fx, lateralForce = fy, contactTorque = torque, rollingTorque = rollingTorque,
		slipRatio = state.slipRatio, slipAngle = state.slipAngle,
		utilization = utilization, sliding = sliding, grip = grip,
	}
end

function Tire.step(state: State, input: Input, dt: number, cfg: Config, surface: Surface): Output
	local minimumSpeed = math.max(finite(cfg.MinimumSpeed, 1.5), 0.1)
	local relaxationLength = math.max(finite(cfg.RelaxationLength, 0.25), 0.001)
	local vx = finite(input.longitudinalVelocity, 0)
	local vy = finite(input.lateralVelocity, 0)
	local radius = math.max(finite(input.radius, 0), 0)
	local wheelSpeed = finite(finite(input.wheelOmega, 0) * radius, 0)
	-- Smooth low-speed slip avoids dividing by near-zero chassis speed, while
	-- retaining finite force for a spinning tire trying to accelerate at rest.
	local denominator = math.sqrt(vx * vx + minimumSpeed * minimumSpeed)
	local targetRatio = math.clamp(finite((wheelSpeed - vx) / denominator, 0), -20, 20)
	local targetAngle = math.atan(vy / denominator)
	local contact = input.contact and finite(input.normalLoad, 0) > 0 and radius > 0
	local transportSpeed = math.max(math.abs(vx), math.abs(wheelSpeed), minimumSpeed)
	local alpha = 1 - math.exp(-transportSpeed * math.max(finite(dt, 0), 0) / relaxationLength)
	-- Airborne tires have no ground force. Stored patch strain can dissipate;
	-- this changes contact memory only, never bike or wheel velocity.
	state.slipRatio += ((if contact then targetRatio else 0) - state.slipRatio) * alpha
	state.slipAngle += ((if contact then targetAngle else 0) - state.slipAngle) * alpha
	state.contact = contact
	return Tire.evaluate(state, input, cfg, surface)
end

return Tire
