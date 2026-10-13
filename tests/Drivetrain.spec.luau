--!strict
-- Pure SI dynamics tests; these do not establish Roblox riding/handling quality.
local Drivetrain = require("../src/shared/Physics/Drivetrain")
local Bike250 = require("../src/shared/Physics/Bike250")
local cfg = Bike250.Drive
local controls: Drivetrain.Controls = { throttle = 0, clutch = 0, rearBrake = 0 }
local rpmToRad = math.pi / 30
local tests, assertions, failures = 0, 0, 0

local function check(condition: boolean, message: string)
	assertions += 1
	assert(condition, message)
end

local function near(actual: number, expected: number, tolerance: number, message: string)
	check(math.abs(actual - expected) <= tolerance, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name: string, run: () -> ())
	tests += 1
	local success, message = pcall(run)
	if success then
		print("PASS " .. name)
	else
		failures += 1
		print("FAIL " .. name .. ": " .. tostring(message))
	end
end

local function ratio(gear: number): number
	return cfg.PrimaryRatio * cfg.FinalRatio * cfg.GearRatios[gear]
end

local function passiveConfig(): Drivetrain.DriveConfig
	local copy = table.clone(cfg)
	copy.FrictionTorque = 0
	copy.EngineBrakeTorque = 0
	copy.Efficiency = 1
	copy.TorqueCurve = { { 0, 0 }, { 13500, 0 } }
	return copy
end

local function energy(state: Drivetrain.State, configuration: Drivetrain.DriveConfig): number
	return 0.5 * configuration.EngineInertia * state.engineOmega ^ 2
		+ 0.5 * configuration.RearInertia * state.rearOmega ^ 2
end

local function run(state: Drivetrain.State, input: Drivetrain.Controls, torque: number, duration: number, timestep: number)
	for _ = 1, math.floor(duration / timestep + 0.5) do
		Drivetrain.step(state, input, torque, timestep, cfg)
	end
end

test("new engine idles in neutral and idle control applies finite torque", function()
	local state = Drivetrain.new(cfg)
	check(state.gear == 0 and not state.stalled, "Expected neutral with engine running")
	run(state, controls, 0, 10, 1 / 240)
	near(state.engineOmega, cfg.IdleRPM * rpmToRad, 1e-9, "Unloaded idle")
	near(state.rearOmega, 0, 1e-12, "Neutral must not drive the rear wheel")
end)

test("neutral throttle revs the engine without moving the rear wheel", function()
	local state = Drivetrain.new(cfg)
	run(state, { throttle = 1, clutch = 0 }, 0, 1, 1 / 240)
	check(state.engineOmega > cfg.IdleRPM * rpmToRad * 2, "Engine should rev")
	near(state.rearOmega, 0, 1e-12, "No neutral drive torque")
end)

test("a completely open clutch isolates the rear wheel in gear", function()
	local state = Drivetrain.new(cfg)
	state.gear = 1
	run(state, { throttle = 1, clutch = 1 }, 0, 0.4, 1 / 240)
	check(state.engineOmega > cfg.IdleRPM * rpmToRad, "Open-clutch engine must rev freely")
	near(state.rearOmega, 0, 1e-12, "Open-clutch wheel must remain unpowered")
end)

test("manual shifts reject unsafe input and do not directly change rotor speeds", function()
	local state = Drivetrain.new(cfg)
	local engine, wheel = state.engineOmega, state.rearOmega
	check(not Drivetrain.shift(state, 1, { clutch = 0, throttle = 1 }, cfg), "Loaded shift should be rejected")
	check(state.gear == 0, "Rejected shift changed gear")
	check(Drivetrain.shift(state, 1, { clutch = 1, throttle = 1 }, cfg), "Clutched shift should be accepted")
	near(state.engineOmega, engine, 0, "Shift must not reset engine RPM")
	near(state.rearOmega, wheel, 0, "Shift must not set wheel speed")
	check(not Drivetrain.shift(state, 1, { clutch = 1, throttle = 0 }, cfg), "Shift-cut interval must prevent double shift")
	state.shiftTimer = 0
	check(Drivetrain.shift(state, 1, { clutch = 0, throttle = 0 }, cfg), "Unloaded shift should be accepted")
	state.shiftTimer = 0
	check(not Drivetrain.shift(state, 2, { clutch = 1, throttle = 0 }, cfg), "Cannot skip gears with one shift event")
	state.gear = 5
	check(not Drivetrain.shift(state, 1, { clutch = 1, throttle = 0 }, cfg), "Cannot exceed top gear")
	state.gear = 0
	check(not Drivetrain.shift(state, -1, { clutch = 1, throttle = 0 }, cfg), "Cannot select a reverse gear")
end)

test("ignition shift cut interrupts engine torque then expires", function()
	local state = Drivetrain.new(cfg)
	check(Drivetrain.shift(state, 1, { clutch = 1, throttle = 1 }, cfg), "Shift")
	local before = state.engineOmega
	Drivetrain.step(state, { throttle = 1, clutch = 1 }, 0, cfg.ShiftCutTime / 2, cfg)
	check(state.engineOmega < before and state.shiftTimer > 0, "Ignition should be cut during a shift")
	run(state, { throttle = 1, clutch = 1 }, 0, 0.2, 1 / 240)
	check(state.engineOmega > before and state.shiftTimer == 0, "Ignition must resume without automatic shifting")
	check(state.gear == 1, "Revving must not shift automatically")
end)

test("redline limiter cuts combustion without forcing an RPM target", function()
	local state = Drivetrain.new(cfg)
	state.engineOmega = (cfg.RedlineRPM + 200) * rpmToRad
	local before = state.engineOmega
	Drivetrain.step(state, { throttle = 1, clutch = 1 }, 0, 1 / 240, cfg)
	check(state.limiter and state.engineOmega < before, "Over-rev must cut engine torque")
	check(state.engineOmega > cfg.RedlineRPM * rpmToRad, "Limiter must not instantly clamp angular momentum")
	run(state, { throttle = 1, clutch = 1 }, 0, 10, 1 / 240)
	check(state.engineOmega / rpmToRad < cfg.RedlineRPM + 100, "No-load engine must remain near redline")
	check(not state.stalled and state.gear == 0, "Limiter must preserve running state and manual gear")
end)

test("dumping the clutch against a braked wheel can stall the engine", function()
	local state = Drivetrain.new(cfg)
	state.gear = 1
	run(state, { throttle = 0, clutch = 0, rearBrake = 1 }, 0, 1, 1 / 240)
	check(state.stalled, "Finite idle governor must not prevent a clutch-dump stall")
	check(state.engineOmega < cfg.StallRPM * rpmToRad, "Stall must follow low physical crank speed")
	run(state, { throttle = 1, clutch = 1 }, 0, 0.5, 1 / 240)
	check(state.stalled, "Stalled engine must not automatically restart from throttle")
end)

test("starter requires neutral or fully pulled clutch and cannot reset a live engine", function()
	local state = Drivetrain.new(cfg)
	check(not Drivetrain.start(state, { throttle = 0, clutch = 1 }, cfg), "A live engine must not gain starter energy")
	state.stalled, state.engineOmega, state.gear = true, 0, 1
	check(not Drivetrain.start(state, { throttle = 0, clutch = 0.8 }, cfg), "In-gear starter requires clutch above 0.8")
	check(Drivetrain.start(state, { throttle = 0, clutch = 1 }, cfg), "Pulled clutch should permit restart")
	near(state.engineOmega, cfg.IdleRPM * rpmToRad, 1e-12, "Starter restores idle crank speed")
	check(not state.stalled, "Successful restart clears stall")
	state.stalled, state.engineOmega, state.gear = true, 0, 0
	check(Drivetrain.start(state, { throttle = 0, clutch = 0 }, cfg), "Neutral should permit restart")
end)

test("ideal clutch conserves reflected angular momentum and dissipates slip energy", function()
	local configuration = passiveConfig()
	for _, speeds in { { 900, 0 }, { 100, 80 }, { 0, -40 }, { -100, 40 } } do
		local state = Drivetrain.new(configuration)
		state.gear, state.stalled = 1, true
		state.engineOmega, state.rearOmega = speeds[1], speeds[2]
		local beforeEnergy = energy(state, configuration)
		local beforeMomentum = configuration.EngineInertia * state.engineOmega + configuration.RearInertia * state.rearOmega / ratio(1)
		Drivetrain.step(state, controls, 0, 0.05, configuration)
		near(configuration.EngineInertia * state.engineOmega + configuration.RearInertia * state.rearOmega / ratio(1), beforeMomentum, 1e-10, "Gear-transformed clutch momentum")
		check(energy(state, configuration) <= beforeEnergy + 1e-9, "Passive clutch must never generate kinetic energy")
	end
end)

test("inefficient transmission also dissipates energy when rear wheel back-drives engine", function()
	local configuration = passiveConfig()
	configuration.Efficiency = 0.5
	for engine = -400, 800, 200 do
		for wheel = -60, 60, 20 do
			local state = Drivetrain.new(configuration)
			state.gear, state.stalled = 3, true
			state.engineOmega, state.rearOmega = engine, wheel
			local previous = energy(state, configuration)
			for _ = 1, 30 do
				Drivetrain.step(state, controls, 0, 1 / 240, configuration)
				local current = energy(state, configuration)
				check(current <= previous + 1e-9, "Efficiency loss must be passive for both power-flow directions")
				previous = current
			end
		end
	end
end)

test("each selected gear couples by its ratio rather than prescribing vehicle speed", function()
	local configuration = passiveConfig()
	for gear = 1, 5 do
		local state = Drivetrain.new(configuration)
		state.gear, state.stalled = gear, true
		state.engineOmega, state.rearOmega = 400, 20
		Drivetrain.step(state, controls, 0, 0.1, configuration)
		near(state.engineOmega, state.rearOmega * ratio(gear), 1e-8, "Locked clutch gear ratio")
	end
end)

test("rear brake stops positive and negative wheel spin independently of the engine", function()
	local configuration = passiveConfig()
	for _, wheel in { -100, -0.1, 0, 0.1, 100 } do
		local state = Drivetrain.new(configuration)
		state.stalled = true
		state.engineOmega, state.rearOmega = 0, wheel
		local before = math.abs(wheel)
		Drivetrain.step(state, { throttle = 0, clutch = 1, rearBrake = 1 }, 0, 0.5, configuration)
		check(math.abs(state.rearOmega) <= before, "Rear brake must reduce wheel energy")
		check(state.rearOmega * wheel >= 0, "Rear brake must not make wheel reverse")
		near(state.rearOmega, 0, 1e-10, "Rear brake must stop small/free spin")
	end
	local free = Drivetrain.new(configuration)
	free.stalled, free.engineOmega, free.rearOmega = true, 0, 20
	Drivetrain.step(free, { throttle = 0, clutch = 1, rearBrake = 0 }, 0, 0.5, configuration)
	near(free.rearOmega, 20, 1e-10, "No rear brake must leave wheel spin unchanged")
end)

test("signed contact torque permits rollback and is excluded from chassis reaction", function()
	local configuration = passiveConfig()
	local state = Drivetrain.new(configuration)
	state.stalled, state.engineOmega = true, 0
	local output = Drivetrain.step(state, { throttle = 0, clutch = 1 }, -72, 0.1, configuration)
	near(state.rearOmega, -10, 1e-10, "External torque must be able to roll a wheel backwards")
	near(output.engineReaction, 0, 1e-10, "External tire torque must not also become internal chassis reaction")
end)

test("rear spin-up reacts nose-up and an airborne rear brake reacts nose-down", function()
	local state = Drivetrain.new(cfg)
	state.gear = 1
	state.engineOmega = 9000 * rpmToRad
	local result = Drivetrain.step(state, { throttle = 1, clutch = 0 }, 0, 1 / 240, cfg)
	check(result.rearOmega > 0 and result.engineReaction > 0, "Airborne throttle/clutch transfer should react nose-up")
	state.rearOmega = 100
	local braked = Drivetrain.step(state, { throttle = 0, clutch = 1, rearBrake = 1 }, 0, 1 / 240, cfg)
	check(braked.engineReaction < 0, "Airborne rear brake must react nose-down with clutch open")
end)

test("crank and wheel reaction balances their internal angular momentum change", function()
	local state = Drivetrain.new(cfg)
	state.gear, state.engineOmega, state.rearOmega = 2, 8000 * rpmToRad, 40
	local before = cfg.EngineInertia * state.engineOmega + cfg.RearInertia * state.rearOmega
	local timestep, external = 1 / 60, -25
	local output = Drivetrain.step(state, { throttle = 0.4, clutch = 0.2, rearBrake = 0.1 }, external, timestep, cfg)
	local after = cfg.EngineInertia * state.engineOmega + cfg.RearInertia * state.rearOmega
	near((output.engineReaction + external) * timestep, after - before, 1e-10, "Reaction impulse accounting")
end)

test("closed-throttle engine braking reaches the rear wheel through an engaged clutch", function()
	local coupled, open = Drivetrain.new(cfg), Drivetrain.new(cfg)
	for _, state in { coupled, open } do
		state.gear = 3
		state.engineOmega = 9000 * rpmToRad
		state.rearOmega = state.engineOmega / ratio(3)
	end
	local initialWheel = coupled.rearOmega
	run(coupled, { throttle = 0, clutch = 0 }, 0, 0.4, 1 / 240)
	run(open, { throttle = 0, clutch = 1 }, 0, 0.4, 1 / 240)
	check(coupled.rearOmega < initialWheel, "Engaged drivetrain should slow rear wheel during engine braking")
	near(open.rearOmega, initialWheel, 1e-10, "Open clutch must prevent engine braking at rear wheel")
end)

test("progressive throttle produces progressive wheel acceleration without an acceleration target", function()
	local half, full = Drivetrain.new(cfg), Drivetrain.new(cfg)
	for _, state in { half, full } do
		state.gear = 3
		state.engineOmega = 6500 * rpmToRad
		state.rearOmega = state.engineOmega / ratio(3)
	end
	run(half, { throttle = 0.5, clutch = 0 }, 0, 0.5, 1 / 240)
	run(full, { throttle = 1, clutch = 0 }, 0, 0.5, 1 / 240)
	check(full.rearOmega > half.rearOmega + 1, "Full throttle should accelerate more than half throttle")
end)

test("partly pulled clutch reduces transmitted torque without reducing combustion input", function()
	local pulled, engaged = Drivetrain.new(cfg), Drivetrain.new(cfg)
	for _, state in { pulled, engaged } do
		state.gear = 1
		state.engineOmega = 8000 * rpmToRad
	end
	Drivetrain.step(pulled, { throttle = 1, clutch = 0.9 }, 0, 1 / 240, cfg)
	Drivetrain.step(engaged, { throttle = 1, clutch = 0 }, 0, 1 / 240, cfg)
	check(pulled.rearOmega < engaged.rearOmega, "Partly engaged clutch must transfer less impulse")
	check(pulled.engineOmega > engaged.engineOmega, "Pulled clutch must allow more crank slip")
end)

test("internal substeps give the same result for 60 Hz and 240 Hz callers", function()
	local coarse, fine = Drivetrain.new(cfg), Drivetrain.new(cfg)
	for _, state in { coarse, fine } do
		state.gear = 3
		state.engineOmega = 6500 * rpmToRad
		state.rearOmega = state.engineOmega / ratio(3)
	end
	run(coarse, { throttle = 0.7, clutch = 0.3, rearBrake = 0.1 }, -10, 1, 1 / 60)
	run(fine, { throttle = 0.7, clutch = 0.3, rearBrake = 0.1 }, -10, 1, 1 / 240)
	near(coarse.engineOmega, fine.engineOmega, 1e-8, "Crank timestep equivalence")
	near(coarse.rearOmega, fine.rearOmega, 1e-8, "Rear timestep equivalence")
end)

test("halving an already small timestep converges rather than destabilizing a stiff clutch", function()
	local coarse, fine = Drivetrain.new(cfg), Drivetrain.new(cfg)
	for _, state in { coarse, fine } do
		state.gear = 3
		state.engineOmega = 6500 * rpmToRad
		state.rearOmega = state.engineOmega / ratio(3)
	end
	run(coarse, { throttle = 0.6, clutch = 0, rearBrake = 0 }, -20, 1, 1 / 240)
	run(fine, { throttle = 0.6, clutch = 0, rearBrake = 0 }, -20, 1, 1 / 480)
	near(coarse.engineOmega, fine.engineOmega, 2, "Crank step convergence in rad/s")
	near(coarse.rearOmega, fine.rearOmega, 0.1, "Rear step convergence in rad/s")
end)

test("thousands of varying input steps stay finite, preserve legal gears, and never auto-shift", function()
	local state = Drivetrain.new(cfg)
	state.gear = 2
	for index = 1, 12000 do
		local input: Drivetrain.Controls = {
			throttle = 0.5 + 0.5 * math.sin(index / 211),
			clutch = if index % 1200 < 300 then 1 else 0.2,
			rearBrake = 0.5 + 0.5 * math.sin(index / 377),
		}
		local output = Drivetrain.step(state, input, 80 * math.sin(index / 487), 1 / 240, cfg)
		for _, value in { state.engineOmega, output.rearOmega, output.rpm, output.clutchSlip, output.engineReaction, output.power } do
			check(value == value and math.abs(value) < math.huge, "Simulation must remain finite")
		end
		check(state.gear == 2, "Drivetrain must not auto-shift")
		if state.stalled and input.clutch == 1 then
			Drivetrain.start(state, input, cfg)
		end
	end
end)

test("zero-duration observation is side-effect free and invalid time/torque are rejected", function()
	local state = Drivetrain.new(cfg)
	local before = table.clone(state)
	local output = Drivetrain.step(state, { throttle = 1, clutch = 0 }, 50, 0, cfg)
	for key, value in (before :: any) do
		check((state :: any)[key] == value, "Zero dt must not modify " .. key)
	end
	near(output.engineReaction, 0, 0, "Zero dt has no force impulse")
	near(output.power, 0, 0, "Zero dt has no engine work")
	for _, timestep in { -1, math.huge, 0 / 0 } do
		check(not pcall(function()
			Drivetrain.step(state, controls, 0, timestep, cfg)
		end), "Invalid dt must be rejected")
	end
	check(not pcall(function()
		Drivetrain.step(state, controls, math.huge, 1 / 240, cfg)
	end), "Invalid external torque must be rejected")
end)

print(string.format("Drivetrain: %d tests, %d assertions, %d failures", tests, assertions, failures))
assert(failures == 0, string.format("%d drivetrain tests failed", failures))
