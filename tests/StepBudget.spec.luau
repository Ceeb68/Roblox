--!strict
local StepBudget = require("../src/shared/Physics/StepBudget")
local Bike = require("../src/shared/Physics/Bike250")
local tests, assertions = 0, 0
local function check(ok: boolean, message: string)
	assertions += 1
	assert(ok, message)
end
local function test(name: string, fn: () -> ())
	tests += 1
	fn()
	print("PASS " .. name)
end
test("native time is preserved at normal and over-budget frame rates", function()
	for _, frame in { 1e-6, 1 / 240, 1 / 120, 1 / 60, 1 / 30, 1 / 20, 0.1, 0.25 } do
		local plan = StepBudget.plan(frame, Bike.FixedStep, Bike.MaxSubsteps)
		check(math.abs(plan.steps * plan.dt - frame) < 1e-12, "Native force duration was dropped")
		check(plan.duration == frame and plan.steps >= 1 and plan.steps <= Bike.MaxSubsteps, "Budget does not bound work")
	end
end)
test("supporting force still balances gravity in a long native frame", function()
	local mass = Bike.BikeMass + Bike.RiderMass
	for _, frame in { 1 / 60, 0.1, 0.25 } do
		local plan = StepBudget.plan(frame, Bike.FixedStep, Bike.MaxSubsteps)
		local supportImpulse = mass * Bike.Gravity * plan.dt * plan.steps
		local gravityImpulse = mass * Bike.Gravity * frame
		check(math.abs(supportImpulse - gravityImpulse) < 1e-10, "Long frames artificially reduced support")
	end
end)
test("normal frames use target subdivisions and over-budget frames are explicit", function()
	local normal = StepBudget.plan(1 / 60, Bike.FixedStep, Bike.MaxSubsteps)
	check(normal.steps == 4 and not normal.overrun, "60Hz should receive four contact subdivisions")
	local stalled = StepBudget.plan(0.1, Bike.FixedStep, Bike.MaxSubsteps)
	check(stalled.steps == 12 and stalled.overrun and stalled.dt > Bike.FixedStep, "Coarse overrun must be reported")
	local edge = StepBudget.plan(Bike.FixedStep * Bike.MaxSubsteps, Bike.FixedStep, Bike.MaxSubsteps)
	check(not edge.overrun, "Exact boundary must remain supported")
end)
test("invalid simulation intervals cannot enter the force adapter", function()
	for _, value in { 0, -0.01, 0 / 0, math.huge, -math.huge } do
		check(not pcall(function() StepBudget.plan(value, Bike.FixedStep, Bike.MaxSubsteps) end), "Invalid frame accepted")
	end
	check(not pcall(function() StepBudget.plan(0.1, 0, 12) end), "Zero target step accepted")
	check(not pcall(function() StepBudget.plan(0.1, 1 / 240, 1.5) end), "Fractional step budget accepted")
end)
print(string.format("StepBudget: %d tests, %d assertions, 0 failures", tests, assertions))
