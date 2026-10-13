--!strict
-- Native simulation time must not be discarded: gravity still integrates it.
-- Normal frames use ~240 Hz contact steps. Over-budget frames use fewer,
-- coarser contact steps, report the condition, and invalidate timed lab runs.
local StepBudget = {}

function StepBudget.plan(frameDt: number, targetDt: number, maxSteps: number): { steps: number, dt: number, duration: number, overrun: boolean }
	assert(frameDt > 0 and frameDt < math.huge and frameDt == frameDt, "Invalid native frame interval")
	assert(targetDt > 0 and targetDt < math.huge, "Invalid target interval")
	assert(maxSteps >= 1 and maxSteps % 1 == 0 and maxSteps < math.huge, "Invalid substep budget")
	local requested = math.ceil(frameDt / targetDt - 1e-9)
	local steps = math.clamp(requested, 1, maxSteps)
	return { steps = steps, dt = frameDt / steps, duration = frameDt, overrun = requested > maxSteps }
end

return StepBudget
