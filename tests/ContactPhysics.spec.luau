--!strict
-- Run from the repository root: luau tests/ContactPhysics.spec.luau
local Suspension = require("../src/shared/Physics/Suspension")
local Tire = require("../src/shared/Physics/Tire")
local Bike = require("../src/shared/Physics/Bike250")

local tests, assertions, failures = 0, 0, 0
local function check(condition: boolean, message: string)
	assertions += 1
	assert(condition, message)
end
local function near(actual: number, expected: number, tolerance: number, message: string)
	check(math.abs(actual - expected) <= tolerance, message .. string.format(" (%.8g versus %.8g)", actual, expected))
end
local function test(name: string, fn: () -> ())
	tests += 1
	local passed, message = pcall(fn)
	if passed then print("PASS " .. name) else failures += 1; print("FAIL " .. name .. ": " .. tostring(message)) end
end
local function input(vx: number, vy: number, omega: number, load: number?): Tire.Input
	return { normalLoad = load or 920, longitudinalVelocity = vx, lateralVelocity = vy, wheelOmega = omega, radius = Bike.RearRadius, camber = 0, contact = true }
end
local function settled(sample: Tire.Input, surface: Tire.Surface?): Tire.Output
	local state = Tire.new()
	local output = Tire.step(state, sample, 1 / 240, Bike.Tire, surface or Bike.Surfaces.dirt)
	for _ = 1, 480 do output = Tire.step(state, sample, 1 / 240, Bike.Tire, surface or Bike.Surfaces.dirt) end
	return output
end
local function forceLength(output: Tire.Output): number
	return math.sqrt(output.longitudinalForce ^ 2 + output.lateralForce ^ 2)
end

test("suspension preload supports a contacting wheel and no force is adhesive", function()
	local preload = Suspension.step(Suspension.new(), 0, 0, true, 1 / 240, Bike.Suspension.Front)
	near(preload.force, Bike.Suspension.Front.SpringRate * Bike.Suspension.Front.Preload, 1e-9, "Preload should be present at full extension")
	local unloaded = Suspension.step(Suspension.new(), 0.04, -10, true, 1 / 240, Bike.Suspension.Front)
	near(unloaded.force, 0, 0, "Rebound cannot pull the chassis into the track")
end)

test("spring stiffness and preload noticeably alter support", function()
	local cfg = table.clone(Bike.Suspension.Rear)
	local baseline = Suspension.step(Suspension.new(), 0.1, 0, true, 1 / 240, cfg)
	cfg.SpringRate *= 1.4
	local stiff = Suspension.step(Suspension.new(), 0.1, 0, true, 1 / 240, cfg)
	check(stiff.force > baseline.force * 1.3, "Spring adjustment should alter contact load")
	cfg.Preload += 0.02
	local preloaded = Suspension.step(Suspension.new(), 0.1, 0, true, 1 / 240, cfg)
	check(preloaded.force > stiff.force, "Additional preload should increase support")
end)

test("compression and rebound damping depend on actual motion direction", function()
	local cfg = Bike.Suspension.Front
	local static = Suspension.step(Suspension.new(), 0.15, 0, true, 1 / 240, cfg)
	local compress = Suspension.step(Suspension.new(), 0.15, 0.5, true, 1 / 240, cfg)
	local rebound = Suspension.step(Suspension.new(), 0.15, -0.5, true, 1 / 240, cfg)
	near(compress.force - static.force, cfg.Compression * 0.5, 1e-8, "Compression damper must resist compression")
	near(static.force - rebound.force, cfg.Rebound * 0.5, 1e-8, "Rebound damper must resist extension")
	local adjusted = table.clone(cfg)
	adjusted.Compression *= 2
	near(Suspension.step(Suspension.new(), 0.15, 0.5, true, 1 / 240, adjusted).force - static.force, cfg.Compression, 1e-8, "Compression setting must affect load")
	adjusted.Rebound *= 0.5
	check(Suspension.step(Suspension.new(), 0.15, -0.5, true, 1 / 240, adjusted).force > rebound.force, "Less rebound damping permits faster extension")
end)

test("bottom-out is progressive and penetration cannot make infinite load", function()
	local cfg = Bike.Suspension.Front
	local before = Suspension.step(Suspension.new(), cfg.Travel * 0.8, 0, true, 1 / 240, cfg)
	local bottom = Suspension.step(Suspension.new(), cfg.Travel, 0, true, 1 / 240, cfg)
	local beyond = Suspension.step(Suspension.new(), cfg.Travel * 1.1, 0, true, 1 / 240, cfg)
	check(not before.bottomed and bottom.bottomed and beyond.bottomed, "Bottom-out threshold should follow physical travel")
	check(bottom.force > cfg.SpringRate * (cfg.Travel + cfg.Preload), "Bump stop should add load before mechanical end stop")
	check(beyond.force > bottom.force, "Overtravel should still stiffen the bump stop")
	local extreme = Suspension.step(Suspension.new(), 1e6, 1e6, true, 1 / 240, cfg)
	check(extreme.force > 0 and extreme.force < 100000, "Numerical penetration guard must retain finite sensible load")
end)

test("airborne suspension never pushes or pulls the bike", function()
	local state = Suspension.new()
	local output = Suspension.step(state, 0.28, 8, false, 1 / 240, Bike.Suspension.Rear)
	near(output.force, 0, 0, "No ground contact means no suspension force")
	check(not output.bottomed and not state.contact, "Airborne telemetry should identify absent contact")
end)

test("sprung-mass landing compresses then settles without numerical explosion", function()
	local mass, cfg = 94, Bike.Suspension.Rear
	local function land(step: number, count: number): (number, number, boolean)
		local compression, velocity, peak, bottomed = 0.005, 12, 0, false
		local state = Suspension.new()
		for _ = 1, count do
			local contact = compression >= 0
			local output = Suspension.step(state, compression, velocity, contact, step, cfg)
			velocity += (Bike.Gravity - output.force / mass) * step
			compression += velocity * step
			peak = math.max(peak, compression)
			bottomed = bottomed or output.bottomed
		end
		return compression, peak, bottomed
	end
	local coarse, coarsePeak, coarseBottom = land(1 / 120, 480)
	local normal, normalPeak, normalBottom = land(1 / 240, 960)
	local fine, finePeak, fineBottom = land(1 / 480, 1920)
	local staticSag = mass * Bike.Gravity / cfg.SpringRate - cfg.Preload
	near(normal, staticSag, 0.0001, "Damped landing should settle at physical static sag")
	near(coarse, fine, 0.0001, "Settled compression should converge across simulation rates")
	near(normalPeak, finePeak, 0.006, "Landing peak should converge at default simulation rate")
	-- The strongly nonlinear end stop needs the configured 240 Hz step;
	-- a coarser 120 Hz explicit integration permits up to 20 mm peak error.
	near(coarsePeak, finePeak, 0.02, "Coarser landing should remain within a small travel error")
	check(coarseBottom and normalBottom and fineBottom, "A hard impact must exercise the bump stop at each rate")
	check(finePeak < cfg.Travel * 1.2, "Progressive bump stop must prevent excessive overtravel")
end)

test("free rolling produces no longitudinal or lateral tire force", function()
	local output = settled(input(12, 0, 12 / Bike.RearRadius))
	near(output.longitudinalForce, 0, 1e-8, "Pure rolling has no longitudinal slip")
	near(output.lateralForce, 0, 1e-8, "Pure rolling has no lateral slip")
	check(output.contactTorque < 0, "Rolling resistance should oppose forward wheel rotation")
end)

test("wheelspin accelerates, locked wheel brakes, lateral slip opposes sliding", function()
	local spin = settled(input(8, 0, 18 / Bike.RearRadius))
	local lock = settled(input(8, 0, 0))
	local slide = settled(input(8, 5, 8 / Bike.RearRadius))
	check(spin.longitudinalForce > 0 and spin.slipRatio > 0 and spin.contactTorque < 0, "Spinning wheel should propel and lose angular momentum")
	check(lock.longitudinalForce < 0 and lock.slipRatio < 0 and lock.contactTorque > 0, "Locked wheel should brake while ground torque tries to spin it up")
	check(slide.lateralForce < 0 and slide.slipAngle > 0, "Sideways motion should produce opposing contact force")
end)

test("reverse motion retains physically opposing brake and rolling torque signs", function()
	local reverse = settled(input(-8, 0, -8 / Bike.RearRadius))
	check(reverse.contactTorque > 0, "Rolling torque must oppose reverse rotation")
	local locked = settled(input(-8, 0, 0))
	check(locked.longitudinalForce > 0 and locked.contactTorque < 0, "Braking backwards should push the chassis toward zero speed")
end)

test("hardpack dirt sand and mud produce ordered traction", function()
	local sample = input(12, 8, 30 / Bike.RearRadius)
	local hardpack = forceLength(settled(sample, Bike.Surfaces.hardpack))
	local dirt = forceLength(settled(sample, Bike.Surfaces.dirt))
	local sand = forceLength(settled(sample, Bike.Surfaces.sand))
	local mud = forceLength(settled(sample, Bike.Surfaces.mud))
	check(hardpack > dirt and dirt > sand and sand > mud, "Surface friction must change available traction")
	local rolling = input(12, 0, 12 / Bike.RearRadius)
	check(math.abs(settled(rolling, Bike.Surfaces.sand).contactTorque) > math.abs(settled(rolling, Bike.Surfaces.hardpack).contactTorque), "Loose sand should add rolling loss")
end)

test("braking while cornering shares the friction budget", function()
	local corner = settled(input(12, 6, 12 / Bike.RearRadius))
	local combinedInput = input(12, 6, 0)
	local combined = settled(combinedInput)
	check(combined.longitudinalForce < 0 and combined.lateralForce < 0, "Both braking and corner force should exist")
	check(math.abs(combined.lateralForce) < math.abs(corner.lateralForce), "Braking must reduce available cornering force")
	check(forceLength(combined) <= combined.grip * combinedInput.normalLoad + 1e-7, "Combined forces must fit inside friction circle")
	check(combined.sliding and combined.utilization > 0.999, "Saturated combined slip should identify a sliding tire")
end)

test("independent axle loads change front and rear grip during load transfer", function()
	local frontState, rearState = Tire.new(), Tire.new()
	local frontInput = input(14, 9, 0, 1350)
	local rearInput = input(14, 9, 0, 450)
	local front = Tire.step(frontState, frontInput, 1, Bike.Tire, Bike.Surfaces.dirt)
	local rear = Tire.step(rearState, rearInput, 1, Bike.Tire, Bike.Surfaces.dirt)
	check(forceLength(front) > forceLength(rear), "Loaded front should have greater absolute force capacity")
	check(front.grip < rear.grip, "Load sensitivity must reduce friction coefficient on heavily loaded axle")
	local balanced = forceLength(settled(input(14, 9, 0, 900))) * 2
	check(forceLength(front) + forceLength(rear) < balanced, "Uneven loading should reduce total load-sensitive grip")
	local rearRatio = rearState.slipRatio
	Tire.step(frontState, input(14, -9, 30 / Bike.RearRadius, 1350), 1 / 240, Bike.Tire, Bike.Surfaces.dirt)
	near(rearState.slipRatio, rearRatio, 0, "Front contact updates must not mutate rear tire memory")
end)

test("camber thrust turns toward lean and still respects friction budget", function()
	local sample = input(12, 0, 12 / Bike.RearRadius)
	sample.camber = math.rad(30)
	local output = settled(sample)
	check(output.lateralForce > 0, "Wheel-right lean must create wheel-right camber thrust")
	check(forceLength(output) <= output.grip * sample.normalLoad + 1e-7, "Camber force cannot exceed available grip")
	sample.camber = -sample.camber
	near(settled(sample).lateralForce, -output.lateralForce, 1e-8, "Opposite camber should reverse camber thrust")
end)

test("airborne or unloaded tires produce exactly zero forces and torque", function()
	local sample = input(20, 10, 100)
	local state = Tire.new()
	Tire.step(state, sample, 0.1, Bike.Tire, Bike.Surfaces.dirt)
	sample.contact = false
	local output = Tire.step(state, sample, 1 / 240, Bike.Tire, Bike.Surfaces.dirt)
	near(output.longitudinalForce, 0, 0, "Airborne longitudinal force")
	near(output.lateralForce, 0, 0, "Airborne lateral force")
	near(output.contactTorque, 0, 0, "Airborne contact torque")
	sample.contact = true
	sample.normalLoad = 0
	near(forceLength(Tire.step(state, sample, 1 / 240, Bike.Tire, Bike.Surfaces.dirt)), 0, 0, "Zero-load wheel cannot produce grip")
end)

test("low speed stays finite without inventing force at rest", function()
	for _, vx in { -1e-8, 0, 1e-8 } do
		local sample = input(vx, 0, vx / Bike.RearRadius)
		local output = settled(sample)
		near(output.longitudinalForce, 0, 1e-6, "No artificial launch or braking force")
		check(output.slipRatio == output.slipRatio and math.abs(output.slipRatio) < math.huge, "Slip must remain finite near rest")
	end
	local spinning = settled(input(0, 0, 40))
	check(spinning.longitudinalForce > 0, "A spinning wheel must be able to launch from rest")
end)

test("contact force builds over relaxation distance instead of changing instantly", function()
	local sample = input(8, 0, 10 / Bike.RearRadius)
	local state = Tire.new()
	local first = Tire.step(state, sample, 1 / 240, Bike.Tire, Bike.Surfaces.dirt)
	local second = Tire.step(state, sample, 1 / 240, Bike.Tire, Bike.Surfaces.dirt)
	local final = settled(sample)
	check(first.slipRatio > 0 and first.slipRatio < second.slipRatio and second.slipRatio < final.slipRatio, "Patch stress should build progressively")
	check(first.longitudinalForce < second.longitudinalForce and second.longitudinalForce < final.longitudinalForce, "Force should follow contact relaxation")
end)

test("relaxation converges across different fixed time steps", function()
	local sample = input(3, 0.3, 3.3 / Bike.RearRadius)
	local function simulate(step: number, count: number): Tire.Output
		local state = Tire.new()
		local output = Tire.step(state, sample, step, Bike.Tire, Bike.Surfaces.dirt)
		for _ = 2, count do output = Tire.step(state, sample, step, Bike.Tire, Bike.Surfaces.dirt) end
		return output
	end
	local a, b, c = simulate(1 / 120, 12), simulate(1 / 240, 24), simulate(1 / 480, 48)
	near(a.slipRatio, c.slipRatio, 1e-10, "Longitudinal strain should converge with time step")
	near(b.slipAngle, c.slipAngle, 1e-10, "Lateral strain should converge with time step")
	near(a.longitudinalForce, c.longitudinalForce, 1e-8, "Same constant input interval should produce the same force")
end)

test("coupled wheel and chassis acceleration is stable across simulation rates", function()
	-- An external drive torque accelerates a sprung mass through this contact.
	-- Check the coupled numerical system, rather than only constant tire input.
	local function accelerate(step: number, count: number): (number, number)
		local mass, wheelInertia, driveTorque = 94, Bike.RearInertia, 75
		local velocity, omega = 5, 5 / Bike.RearRadius
		local state = Tire.new()
		for _ = 1, count do
			local output = Tire.step(state, input(velocity, 0, omega, mass * Bike.Gravity), step, Bike.Tire, Bike.Surfaces.dirt)
			velocity += output.longitudinalForce * step / mass
			omega += (driveTorque + output.contactTorque) * step / wheelInertia
			check(velocity == velocity and omega == omega and math.abs(velocity) < 100 and math.abs(omega) < 1000, "Contact integration must remain finite and bounded")
		end
		return velocity, omega
	end
	local coarseV, coarseW = accelerate(1 / 120, 240)
	local normalV, normalW = accelerate(1 / 240, 480)
	local fineV, fineW = accelerate(1 / 480, 960)
	check(normalV > 7 and normalW > 5 / Bike.RearRadius, "Drive torque must accelerate both wheel and mass")
	near(coarseV, fineV, 0.025, "Chassis result should converge across rates")
	near(normalV, fineV, 0.01, "Default-step chassis result should approach reference")
	near(coarseW, fineW, 0.08, "Wheel angular integration should converge across rates")
	near(normalW, fineW, 0.04, "Default-step wheel result should approach reference")
end)

test("force and wheel torque obey consistent contact work signs", function()
	for _, sample in { input(12, 4, 25 / Bike.RearRadius), input(12, -4, 0), input(-12, 4, -25 / Bike.RearRadius) } do
		local output = settled(sample)
		local dissipation = output.longitudinalForce * (sample.longitudinalVelocity - sample.wheelOmega * sample.radius)
			+ output.lateralForce * sample.lateralVelocity
		check(dissipation <= 1e-8, "Uncambered tire slip must dissipate energy")
	end
end)

print(string.format("ContactPhysics: %d tests, %d assertions, %d failures", tests, assertions, failures))
assert(failures == 0, string.format("%d ContactPhysics tests failed", failures))
