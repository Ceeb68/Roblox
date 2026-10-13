--!strict
-- Run from the repository root: luau tests/WheelContact.spec.luau
local Tire = require("../src/shared/Physics/Tire")
local WheelContact = require("../src/shared/Physics/WheelContact")
local Bike = require("../src/shared/Physics/Bike250")

local tests, assertions, failures = 0, 0, 0
local function check(condition: boolean, message: string)
	assertions += 1
	assert(condition, message)
end
local function near(actual: number, expected: number, tolerance: number, message: string)
	check(math.abs(actual - expected) <= tolerance, message .. string.format(" (%.9g versus %.9g)", actual, expected))
end
local function test(name: string, fn: () -> ())
	tests += 1
	local passed, message = pcall(fn)
	if passed then print("PASS " .. name) else failures += 1; print("FAIL " .. name .. ": " .. tostring(message)) end
end
local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end
local function input(vx: number, vy: number, omega: number, camber: number?): Tire.Input
	return { normalLoad = 920, longitudinalVelocity = vx, lateralVelocity = vy, wheelOmega = omega,
		radius = Bike.FrontRadius, camber = camber or 0, contact = true }
end
local function axial(result: WheelContact.Output, c: number, a: number, b: number): number
	return result.normalLoad * c + result.tyre.longitudinalForce * a + result.tyre.lateralForce * b
end

test("vertical wheel support equals spring force for combined tire slip", function()
	local result = WheelContact.step(Tire.new(), input(12, 5, 0), 1 / 240, Bike.Tire, Bike.Surfaces.dirt, 1200, 1, 0, 0, Tire)
	near(result.normalLoad, 1200, 1e-10, "Tangential road forces cannot change axial support for a vertical wheel")
	near(result.axialError, 0, 1e-10, "Vertical equilibrium residual")
	check(result.tyre.longitudinalForce < 0 and result.tyre.lateralForce < 0, "Combined braking and lateral force should remain functional")
end)

test("30 and 45 degree steady-turn forces satisfy axial suspension equilibrium", function()
	-- At a steady flat turn, Fy/N = tan(lean). With tire slip saturating at that
	-- ratio, force projection predicts N=Fs*cos(lean), independently of solver.
	local cfg = table.clone(Bike.Tire)
	cfg.LoadSensitivity = 0
	for _, degrees in { 30, 45 } do
		local angle = math.rad(degrees)
		local c, b, force = math.cos(angle), math.sin(angle), 1000
		local state = Tire.new()
		state.slipAngle = -1
		local sample = input(10, 0, 10 / Bike.FrontRadius, angle)
		local surface = { Grip = math.tan(angle), Rolling = 0 }
		local result = WheelContact.step(state, sample, 0, cfg, surface, force, c, 0, b, Tire)
		near(result.normalLoad, force * c, force * 1e-4, "Steady turn load must include lateral contact projection")
		near(axial(result, c, 0, b), force, force * 1e-4, "Solved support must match spring load")
		local naiveInput = table.clone(sample)
		naiveInput.normalLoad = force / c
		local naive = Tire.evaluate(state, naiveInput, cfg, surface)
		local naiveAxial = naiveInput.normalLoad * c + naive.lateralForce * b
		check(naiveAxial > force * 1.3, "The old N=Fs/cos approximation must demonstrably over-support a leaned wheel")
		check(result.normalLoad < naiveInput.normalLoad, "Corrected suspension must avoid artificial lean-dependent support")
	end
end)

test("front caster couples braking and acceleration to spring load", function()
	local c, a = math.cos(Bike.Steering.Caster), -math.sin(Bike.Steering.Caster)
	local spring = 1300
	local brakeState = Tire.new()
	brakeState.slipRatio = -1
	local brake = WheelContact.step(brakeState, input(15, 0, 0), 0, Bike.Tire, Bike.Surfaces.dirt, spring, c, a, 0, Tire)
	near(axial(brake, c, a, 0), spring, spring * 1e-4, "Braking caster equilibrium")
	check(brake.normalLoad < spring / c, "Braking tire force along fork travel must reduce required normal support")
	local driveState = Tire.new()
	driveState.slipRatio = 1
	local drive = WheelContact.step(driveState, input(15, 0, 30 / Bike.FrontRadius), 0, Bike.Tire, Bike.Surfaces.dirt, spring, c, a, 0, Tire)
	near(axial(drive, c, a, 0), spring, spring * 1e-4, "Acceleration caster equilibrium")
	check(drive.normalLoad > spring / c, "Forward traction opposing fork travel needs greater normal load")
end)

test("solved normal load still limits simultaneous braking and corner force", function()
	local angle = math.rad(35)
	local state = Tire.new()
	state.slipRatio, state.slipAngle = -1, -0.6
	local sample = input(14, -6, 0, angle)
	local c, b = math.cos(angle), math.sin(angle)
	local result = WheelContact.step(state, sample, 0, Bike.Tire, Bike.Surfaces.mud, 1800, c, 0, b, Tire)
	local magnitude = math.sqrt(result.tyre.longitudinalForce ^ 2 + result.tyre.lateralForce ^ 2)
	check(magnitude <= result.tyre.grip * result.normalLoad + 1e-7, "Trial-load solve cannot exceed the tire friction circle")
	near(axial(result, c, 0, b), 1800, 0.18, "Combined slip axial equilibrium")
	check(result.tyre.sliding, "A fully saturated muddy contact should preserve slide telemetry")
end)

test("contact memory advances once and input remains unchanged", function()
	local state, reference = Tire.new(), Tire.new()
	local sample = input(12, -5, 28 / Bike.FrontRadius, math.rad(30))
	local original = table.clone(sample)
	local c, b = math.cos(math.rad(30)), math.sin(math.rad(30))
	local result = WheelContact.step(state, sample, 1 / 240, Bike.Tire, Bike.Surfaces.dirt, 1800, c, 0, b, Tire)
	Tire.step(reference, sample, 1 / 240, Bike.Tire, Bike.Surfaces.dirt)
	near(state.slipRatio, reference.slipRatio, 0, "Secant iterations cannot advance longitudinal patch memory")
	near(state.slipAngle, reference.slipAngle, 0, "Secant iterations cannot advance lateral patch memory")
	for key, value in pairs(original :: any) do check((sample :: any)[key] == value, "Solver mutated input " .. key) end
	near(result.axialError, axial(result, c, 0, b) - 1800, 1e-9, "Reported error must describe returned contact forces")
end)

test("pure tire evaluation never mutates state and exposes signed rolling torque", function()
	local state = Tire.new()
	state.slipRatio, state.slipAngle, state.contact = 0.3, -0.2, true
	local before = table.clone(state)
	local sample = input(12, -3, 15 / Bike.FrontRadius)
	local first = Tire.evaluate(state, sample, Bike.Tire, Bike.Surfaces.sand)
	sample.normalLoad *= 2
	Tire.evaluate(state, sample, Bike.Tire, Bike.Surfaces.sand)
	for key, value in pairs(before :: any) do check((state :: any)[key] == value, "Evaluation mutated tire state " .. key) end
	check(first.rollingTorque < 0, "Positive wheel rotation must receive negative rolling torque")
	near(first.contactTorque, -first.longitudinalForce * sample.radius + first.rollingTorque, 1e-9, "Total contact torque includes signed rolling loss")
	sample.wheelOmega = -sample.wheelOmega
	check(Tire.evaluate(state, sample, Bike.Tire, Bike.Surfaces.sand).rollingTorque > 0, "Rolling resistance must oppose reverse rotation")
end)

test("airborne and zero-spring contacts have no forces or ground torque", function()
	for _, airborne in { true, false } do
		local state = Tire.new()
		state.slipRatio, state.slipAngle = 0.5, 0.2
		local sample = input(12, 5, 80)
		sample.contact = not airborne
		local result = WheelContact.step(state, sample, 1 / 240, Bike.Tire, Bike.Surfaces.dirt, if airborne then 1400 else 0, 1, 0, 0, Tire)
		near(result.normalLoad, 0, 0, "Unsupported tire has no normal load")
		near(result.tyre.longitudinalForce, 0, 0, "Unsupported tire has no longitudinal force")
		near(result.tyre.lateralForce, 0, 0, "Unsupported tire has no lateral force")
		near(result.tyre.contactTorque, 0, 0, "Unsupported tire has no contact torque")
		near(result.tyre.rollingTorque, 0, 0, "Unsupported tire has no rolling torque")
		near(result.axialError, 0, 0, "Absent spring support is not an unresolved equilibrium")
		check(not state.contact, "Patch state must become unloaded")
	end
end)

test("relaxed equilibrium converges across fixed time steps", function()
	local angle = math.rad(35)
	local c, b = math.cos(angle), math.sin(angle)
	local sample = input(6, -2, 7 / Bike.FrontRadius, angle)
	local function solve(step: number, count: number): WheelContact.Output
		local state = Tire.new()
		local result = WheelContact.step(state, sample, step, Bike.Tire, Bike.Surfaces.dirt, 1600, c, 0, b, Tire)
		for _ = 2, count do result = WheelContact.step(state, sample, step, Bike.Tire, Bike.Surfaces.dirt, 1600, c, 0, b, Tire) end
		return result
	end
	local coarse, normal, fine = solve(1 / 120, 12), solve(1 / 240, 24), solve(1 / 480, 48)
	near(coarse.tyre.slipRatio, fine.tyre.slipRatio, 1e-10, "Solver must preserve exponential tire relaxation across rates")
	near(normal.tyre.slipAngle, fine.tyre.slipAngle, 1e-10, "Lateral relaxation must remain rate-consistent")
	near(coarse.normalLoad, fine.normalLoad, 1e-7, "Equal strain should produce equal equilibrium normal load")
	near(normal.axialError, fine.axialError, 1e-7, "Equilibrium residual should remain consistent")
end)

test("impossible bounded contact equilibrium is finite and explicitly reported", function()
	local cfg = table.clone(Bike.Tire)
	cfg.LoadSensitivity = 0
	local state = Tire.new()
	state.slipAngle = -1
	local result = WheelContact.step(state, input(12, -5, 12 / Bike.FrontRadius), 0, cfg, Bike.Surfaces.dirt, 1000, 0.2, 0, -math.sqrt(0.96), Tire)
	check(finite(result.normalLoad) and finite(result.axialError) and result.normalLoad <= 250000, "Unresolvable contact must remain bounded")
	check(math.abs(result.axialError) > 0.1, "Solver must expose unresolved axial force instead of inventing support")
	near(result.axialError, axial(result, 0.2, 0, -math.sqrt(0.96)) - 1000, 1e-8, "Unresolved residual must remain truthful")
end)

test("finite loads surfaces and leaning/braking sweeps preserve force budgets", function()
	for _, surface in { Bike.Surfaces.hardpack, Bike.Surfaces.dirt, Bike.Surfaces.sand, Bike.Surfaces.mud } do
		for _, force in { 0.001, 50, 1000, 8000, 35000 } do
			for _, degrees in { 0, 15, 30, 45, 60 } do
				for _, slip in { -1, 0, 1 } do
					local angle = math.rad(degrees)
					local state = Tire.new()
					state.slipRatio, state.slipAngle = slip, -0.3
					local sample = input(10, -3, (1 + slip) * 10 / Bike.FrontRadius, angle)
					local c, b = math.cos(angle), math.sin(angle)
					local result = WheelContact.step(state, sample, 0, Bike.Tire, surface, force, c, 0, b, Tire)
					check(finite(result.normalLoad) and finite(result.axialError) and result.normalLoad >= 0, "Valid contact sweep must stay finite")
					near(axial(result, c, 0, b), force, math.max(force * 1e-4, 1e-6), "Physically feasible sweep should converge")
					local magnitude = math.sqrt(result.tyre.longitudinalForce ^ 2 + result.tyre.lateralForce ^ 2)
					check(magnitude <= result.tyre.grip * result.normalLoad + 1e-7, "Solved forces must obey friction budget")
				end
			end
		end
	end
end)

print(string.format("WheelContact: %d tests, %d assertions, %d failures", tests, assertions, failures))
assert(failures == 0, string.format("%d WheelContact tests failed", failures))
