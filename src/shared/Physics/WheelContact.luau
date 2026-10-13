--!strict
-- Quasi-static unsprung-wheel equilibrium along its suspension travel axis.
-- Tire tangential force participates in spring load, especially on a lean.
-- Patch strain advances once; trial normal loads use the pure force evaluator.
-- The caller injects its Tire library: Roblox resolves ModuleScripts, while
-- standalone Luau resolves filesystem modules. This solver needs neither API.
local WheelContact = {}

type TireState = { slipRatio: number, slipAngle: number, contact: boolean }
type TireInput = {
	normalLoad: number, longitudinalVelocity: number, lateralVelocity: number,
	wheelOmega: number, radius: number, camber: number, contact: boolean,
}
type TireConfig = {
	LongitudinalStiffness: number, LateralStiffness: number, CamberStiffness: number,
	RelaxationLength: number, MinimumSpeed: number, ReferenceLoad: number,
	LoadSensitivity: number, RollingResistance: number,
}
type TireSurface = { Grip: number, Rolling: number }
type TireOutput = {
	longitudinalForce: number, lateralForce: number, contactTorque: number, rollingTorque: number,
	slipRatio: number, slipAngle: number, utilization: number, sliding: boolean, grip: number,
}
export type TireModel = {
	step: (TireState, TireInput, number, TireConfig, TireSurface) -> TireOutput,
	evaluate: (TireState, TireInput, TireConfig, TireSurface) -> TireOutput,
}
export type Output = { normalLoad: number, tyre: TireOutput, axialError: number }

local MAX_ITERATIONS = 10
local RELATIVE_TOLERANCE = 1e-4
local MAX_NORMAL_LOAD = 250000 -- Numerical penetration guard, in newtons.

local function finite(value: number, fallback: number): number
	return if value == value and math.abs(value) < math.huge then value else fallback
end

function WheelContact.step(state: TireState, input: TireInput, dt: number, cfg: TireConfig, surface: TireSurface,
	springForce: number, normalProjection: number, forwardProjection: number, rightProjection: number, tireModel: TireModel): Output
	local force = math.max(finite(springForce, 0), 0)
	local c = math.clamp(finite(normalProjection, 0), -1, 1)
	local a = math.clamp(finite(forwardProjection, 0), -1, 1)
	local b = math.clamp(finite(rightProjection, 0), -1, 1)
	local trial = table.clone(input)
	local valid = input.contact and force > 0 and c > 0 and finite(input.radius, 0) > 0
	trial.contact = valid
	trial.normalLoad = if valid then math.min(force / math.max(c, 0.001), MAX_NORMAL_LOAD) else 0
	-- The relaxation targets do not depend on positive normal-load magnitude.
	-- This single call updates the tire state for the whole contact solve.
	local first = tireModel.step(state, trial, dt, cfg, surface)
	if not valid then
		return { normalLoad = 0, tyre = first, axialError = if input.contact and force > 0 then -force else 0 }
	end
	local tolerance = math.max(force * RELATIVE_TOLERANCE, 1e-6)
	local function errorAt(load: number): (number, TireOutput)
		trial.normalLoad = load
		local tyre = tireModel.evaluate(state, trial, cfg, surface)
		local error = load * c + tyre.longitudinalForce * a + tyre.lateralForce * b - force
		return error, tyre
	end
	local bestLoad = trial.normalLoad
	local bestTyre = first
	local bestError = bestLoad * c + first.longitudinalForce * a + first.lateralForce * b - force
	if math.abs(bestError) <= tolerance then
		return { normalLoad = bestLoad, tyre = first, axialError = bestError }
	end
	local low, lowError = 0, -force
	local high, highError = bestLoad, bestError
	if bestError < 0 then
		low, lowError = bestLoad, bestError
		-- This conservative upper bound uses the maximal allowed μ and the
		-- friction circle to cover tangential forces opposing the travel axis.
		local gripBound = math.max(finite(surface.Grip, 0), 0) * 1.5
		local tangentProjection = math.sqrt(a * a + b * b)
		high = math.min(force / math.max(c - gripBound * tangentProjection, 0.05), MAX_NORMAL_LOAD)
		high = math.max(high, low)
		local upperTyre: TireOutput
		highError, upperTyre = errorAt(high)
		if math.abs(highError) < math.abs(bestError) then bestLoad, bestTyre, bestError = high, upperTyre, highError end
		if math.abs(highError) <= tolerance or highError <= 0 or high <= low then
			-- No positive root within the numerical bound: preserve finite
			-- physical forces and report the residual; never fake stabilization.
			return { normalLoad = bestLoad, tyre = bestTyre, axialError = bestError }
		end
	end
	for iteration = 1, MAX_ITERATIONS do
		local width = high - low
		local load = low - lowError * width / (highError - lowError)
		-- A bracketed secant is normally enough for this nearly linear contact
		-- law. Periodic bisection prevents pathological endpoint stagnation.
		if iteration % 4 == 0 or load <= low or load >= high then load = (low + high) * 0.5 end
		local error, tyre = errorAt(load)
		if math.abs(error) < math.abs(bestError) then bestLoad, bestTyre, bestError = load, tyre, error end
		if math.abs(error) <= tolerance then break end
		if error > 0 then high, highError = load, error else low, lowError = load, error end
	end
	return { normalLoad = bestLoad, tyre = bestTyre, axialError = bestError }
end

return WheelContact
