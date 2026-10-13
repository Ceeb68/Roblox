--!strict
-- Pure network/setup boundaries and physical crash observations; no Roblox mocks.
local Controls = require("../src/shared/Physics/Controls")
local Crash = require("../src/shared/Physics/Crash")
local Bike = require("../src/shared/Physics/Bike250")

local tests, assertions, failures = 0, 0, 0
local function equal(actual: any, expected: any, message: string)
	assertions += 1
	assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(condition: boolean, message: string)
	assertions += 1
	assert(condition, message)
end
local function test(name: string, fn: () -> ())
	tests += 1
	local passed, message = pcall(fn)
	if passed then print("PASS " .. name) else failures += 1; print("FAIL " .. name .. ": " .. tostring(message)) end
end
local function packet(seq: number?): any
	return Controls.neutral(seq or 1)
end
local function setup(): any
	return { Front = table.clone(Bike.Suspension.Front), Rear = table.clone(Bike.Suspension.Rear) }
end
local badValues: {any} = {
	{ name = "missing" }, { name = "NaN", value = 0 / 0 },
	{ name = "positive infinity", value = math.huge }, { name = "negative infinity", value = -math.huge },
	{ name = "string", value = "0.5" }, { name = "boolean", value = true },
	{ name = "table", value = {} }, { name = "function", value = function() return 0 end },
}
local axes = { "throttle", "frontBrake", "rearBrake", "clutch", "steer", "lean", "bodyForward", "bodySide" }

test("neutral controls disengage the clutch and expose every independent axis", function()
	local neutral = Controls.neutral()
	equal(neutral.seq, 0, "Initial sequence")
	for _, axis in axes do equal(neutral[axis], if axis == "clutch" then 1 else 0, "Neutral " .. axis) end
	equal(neutral.standing, false, "Neutral standing")
	equal(neutral.footDown, true, "Neutral foot support")
	equal(neutral.shift, 0, "Neutral gear action")
end)

test("non-table and incomplete control packets are rejected", function()
	equal(Controls.normalize(nil, 0), nil, "Missing packet")
	for _, value in { false, 0, "controls", function() end } do
		equal(Controls.normalize(value, 0), nil, "Non-table packet")
	end
	equal(Controls.normalize({}, 0), nil, "Empty packet")
	equal(Controls.normalize({ seq = 1 }, 0), nil, "Sequence alone is insufficient")
end)

test("each control axis must be a present finite number", function()
	for _, axis in axes do
		for _, bad in badValues do
			local value = packet()
			value[axis] = bad.value
			equal(Controls.normalize(value, 0), nil, axis .. " rejects " .. bad.name)
		end
	end
end)

test("control values clamp to their separate scalar limits", function()
	for _, extreme in { -1000000, 1000000 } do
		local value = packet()
		for _, axis in axes do value[axis] = extreme end
		local normalized = Controls.normalize(value, 0)
		check(normalized ~= nil, "Finite over-range controls should clamp")
		for _, axis in axes do
			local positiveOnly = axis == "throttle" or axis == "frontBrake" or axis == "rearBrake" or axis == "clutch"
			equal(normalized[axis], if extreme > 0 then 1 else (if positiveOnly then 0 else -1), "Clamp " .. axis)
			equal(value[axis], extreme, "Normalizer must not modify the incoming " .. axis)
		end
	end
end)

test("throttle brakes clutch steering and rider movement remain independent", function()
	local value = packet()
	value.throttle, value.frontBrake, value.rearBrake, value.clutch = 0.31, 0.12, 0.79, 0.62
	value.steer, value.lean, value.bodyForward, value.bodySide = -0.34, 0.56, 0.87, -0.91
	value.standing, value.footDown = true, false
	local normalized = Controls.normalize(value, 0)
	check(normalized ~= nil and normalized ~= value, "Return an independent sanitized packet")
	for _, axis in axes do equal(normalized[axis], value[axis], "Preserve independent " .. axis) end
	equal(normalized.standing, true, "Standing remains independent")
	equal(normalized.footDown, false, "Foot support remains independent")
end)

test("pose velocities checkpoint results and rewards never pass the network boundary", function()
	local value = packet()
	value.position, value.rotation, value.velocity = { 999, 999, 999 }, { 0, 0, 0 }, { 1000, 0, 0 }
	value.cframe, value.lapTime, value.checkpoint, value.reward, value.crashed = "client pose", 1, 99, 1000000, false
	local normalized = Controls.normalize(value, 0)
	check(normalized ~= nil, "Untrusted extra fields should not invalidate valid controls")
	local permitted: any = { seq = true, standing = true, footDown = true, shift = true }
	for _, axis in axes do permitted[axis] = true end
	for key in normalized do equal(permitted[key], true, "Only declared controls survive: " .. tostring(key)) end
	for _, key in { "position", "rotation", "velocity", "cframe", "lapTime", "checkpoint", "reward", "crashed" } do
		equal(normalized[key], nil, "Discard client " .. key)
	end
end)

test("control sequences accept only strictly newer bounded integers", function()
	for _, bad in badValues do
		local value = packet()
		value.seq = bad.value
		equal(Controls.normalize(value, 0), nil, "Sequence rejects " .. bad.name)
	end
	for _, seq in { -1, 0, 0.5, 2147483648 } do equal(Controls.normalize(packet(seq), 0), nil, "Reject invalid sequence " .. seq) end
	local first = Controls.normalize(packet(11), 10)
	check(first ~= nil, "Next sequence should be accepted")
	equal(Controls.normalize(packet(11), first.seq), nil, "Replay must be rejected")
	equal(Controls.normalize(packet(9), first.seq), nil, "Out-of-order controls must be rejected")
	check(Controls.normalize(packet(100), first.seq) ~= nil, "Dropped packets do not prevent a newer sequence")
	check(Controls.normalize(packet(2147483647), 2147483646) ~= nil, "Largest protocol sequence is valid")
end)

test("standing and foot support require actual booleans", function()
	for _, field in { "standing", "footDown" } do
		for _, bad in badValues do
			if bad.name ~= "boolean" then
				local value = packet()
				value[field] = bad.value
				equal(Controls.normalize(value, 0), nil, field .. " rejects " .. bad.name)
			end
		end
	end
end)

test("gear requests are discrete down neutral or up actions", function()
	for _, shift in { -1, 0, 1 } do
		local value = packet()
		value.shift = shift
		local normalized = Controls.normalize(value, 0)
		check(normalized ~= nil, "A discrete gear request is valid")
		equal(normalized.shift, shift, "Keep requested shift direction")
	end
	for _, shift in { -2, 2, -0.5, 0.5 } do
		local value = packet()
		value.shift = shift
		equal(Controls.normalize(value, 0), nil, "Reject non-discrete gear action")
	end
	for _, bad in badValues do
		local value = packet()
		value.shift = bad.value
		equal(Controls.normalize(value, 0), nil, "Gear rejects " .. bad.name)
	end
end)

test("a partial suspension setup preserves every untuned field and clones both axles", function()
	local current = setup()
	local result = Controls.normalizeSetup({ Front = { SpringRate = 24000 } }, current)
	check(result ~= nil and result ~= current, "Setup update should return a new setup")
	check(result.Front ~= current.Front and result.Rear ~= current.Rear and result.Front ~= result.Rear, "Axles must be separate clones")
	for key, value in current.Front do equal(result.Front[key], if key == "SpringRate" then 24000 else value, "Preserve front " .. key) end
	for key, value in current.Rear do equal(result.Rear[key], value, "Preserve rear " .. key) end
	result.Front.Rebound = 3100
	result.Rear.Compression = 2600
	equal(current.Front.SpringRate, Bike.Suspension.Front.SpringRate, "No update mutates current front")
	equal(current.Front.Rebound, Bike.Suspension.Front.Rebound, "Returned front is isolated")
	equal(current.Rear.Compression, Bike.Suspension.Rear.Compression, "Returned rear is isolated")
	equal(Bike.Suspension.Front.SpringRate, 18000, "Factory calibration remains intact")
end)

test("front and rear tuning can change independently in one request", function()
	local current = setup()
	local result = Controls.normalizeSetup({ Front = { Preload = 0.020, Compression = 1900 }, Rear = { Preload = 0.025, Rebound = 3300 } }, current)
	check(result ~= nil, "Independent front/rear settings are valid")
	equal(result.Front.Preload, 0.020, "Front preload")
	equal(result.Rear.Preload, 0.025, "Rear preload")
	equal(result.Front.Compression, 1900, "Front compression")
	equal(result.Rear.Compression, current.Rear.Compression, "Do not share front compression")
	equal(result.Rear.Rebound, 3300, "Rear rebound")
	equal(result.Front.Rebound, current.Front.Rebound, "Do not share rear rebound")
end)

test("suspension tuning permits its exact engineering limits but rejects out-of-range values", function()
	local limits: any = { SpringRate = { 8000, 40000 }, Compression = { 300, 5000 }, Rebound = { 300, 6000 }, Preload = { 0, 0.035 } }
	for _, axle in { "Front", "Rear" } do
		for key, range in limits do
			for _, value in range do
				local result = Controls.normalizeSetup({ [axle] = { [key] = value } }, setup())
				check(result ~= nil, axle .. " " .. key .. " boundary is valid")
				equal(result[axle][key], value, "Tuning values should be preserved without clamping")
			end
			for _, value in { range[1] - 0.00001, range[2] + 0.00001 } do
				equal(Controls.normalizeSetup({ [axle] = { [key] = value } }, setup()), nil, "Reject out-of-range " .. axle .. " " .. key)
			end
		end
	end
end)

test("setup rejects malformed unknown and empty changes without altering the current calibration", function()
	local current = setup()
	equal(Controls.normalizeSetup(nil, current), nil, "Missing changes")
	for _, changes in { false, 0, "settings", {}, { Front = {} }, { Rear = {} }, { front = { Preload = 0.02 } }, { Front = 1 }, { Rear = false }, { Front = { Travel = 0.4 } }, { Rear = { Grip = 2 } } } do
		equal(Controls.normalizeSetup(changes, current), nil, "Malformed, empty, or unknown settings")
	end
	for _, axle in { "Front", "Rear" } do
		for _, bad in badValues do
			if bad.name ~= "missing" then
				equal(Controls.normalizeSetup({ [axle] = { SpringRate = bad.value } }, current), nil, "Tuning rejects " .. bad.name)
			end
		end
	end
	equal(Controls.normalizeSetup({ Front = { SpringRate = 24000 }, Rear = { Preload = -1 } }, current), nil, "An invalid axle rejects the entire request")
	for _, axle in { "Front", "Rear" } do
		for key, value in (Bike.Suspension :: any)[axle] do equal(current[axle][key], value, "Rejected request leaves " .. axle .. " " .. key .. " intact") end
	end
end)

local crashCfg = Bike.Crash
test("upright balanced and hard aligned landings do not invent crashes", function()
	equal(Crash.evaluate({}, crashCfg), nil, "No physical failure")
	for _, impact in { 0, 7.5, 20 } do
		equal(Crash.evaluate({ landing = true, grounded = true, roll = math.rad(10), pitch = math.rad(15), normalImpactSpeed = impact, sideLandingSpeed = 0 }, crashCfg), nil, "Aligned landing remains valid")
	end
	equal(Crash.evaluate({ landing = true, landingPitch = -math.rad(60), normalImpactSpeed = crashCfg.LandingSpeed - 0.001 }, crashCfg), nil, "An angled soft landing is not classified by angle alone")
end)

test("hard nose-heavy and rear-heavy landings use the actual landing orientation", function()
	equal(Crash.evaluate({ landing = true, landingPitch = -crashCfg.LandingAngle, pitch = 0, normalImpactSpeed = crashCfg.LandingSpeed }, crashCfg), "Nose-heavy landing", "Nose impact at the threshold")
	equal(Crash.evaluate({ landing = true, landingPitch = crashCfg.LandingAngle, pitch = 0, normalImpactSpeed = crashCfg.LandingSpeed }, crashCfg), "Rear-heavy landing", "Rear impact at the threshold")
	equal(Crash.evaluate({ landing = true, pitch = -math.rad(50), normalImpactSpeed = 9 }, crashCfg), "Nose-heavy landing", "Fallback current pitch")
	equal(Crash.evaluate({ landing = false, pitch = -math.rad(50), normalImpactSpeed = 9 }, crashCfg), nil, "Pitch alone during flight is harmless")
end)

test("sideways and banked landings require a meaningful impact", function()
	equal(Crash.evaluate({ landing = true, sideLandingSpeed = crashCfg.SideLandingSpeed, normalImpactSpeed = 3 }, crashCfg), "Sideways landing", "Side landing speed boundary")
	equal(Crash.evaluate({ landing = true, sideLandingSpeed = crashCfg.SideLandingSpeed, normalImpactSpeed = 2 }, crashCfg), nil, "No significant normal impact")
	equal(Crash.evaluate({ landing = true, sideLandingSpeed = crashCfg.SideLandingSpeed - 0.001, normalImpactSpeed = 3 }, crashCfg), nil, "Lateral speed below its threshold")
	equal(Crash.evaluate({ landing = true, landingRoll = -math.rad(50), roll = 0, normalImpactSpeed = 4 }, crashCfg), "Landing on the side", "Negative landing roll is equally physical")
	equal(Crash.evaluate({ landing = true, landingRoll = math.rad(50), normalImpactSpeed = 3 }, crashCfg), nil, "Banked landing needs more than a mild impact")
end)

test("front washout and rear low-side require a physically fallen grounded bike", function()
	equal(Crash.evaluate({ grounded = true, roll = crashCfg.GroundRoll, frontSliding = true, frontUtilization = 0.9 }, crashCfg), "Front-wheel washout", "Loaded front tire loses the bike")
	equal(Crash.evaluate({ grounded = true, roll = -crashCfg.GroundRoll, rearSliding = true }, crashCfg), "Rear-wheel low-side", "Rear tire loses the bike on the opposite side")
	equal(Crash.evaluate({ grounded = true, roll = crashCfg.GroundRoll, frontSliding = true, frontUtilization = 0.89 }, crashCfg), "Lost balance", "Low utilization does not claim front washout")
	equal(Crash.evaluate({ grounded = true, roll = crashCfg.GroundRoll }, crashCfg), "Lost balance", "Grounded fall without tire evidence")
end)

test("ordinary sliding and leaned cornering do not trigger artificial low-sides", function()
	for _, roll in { -math.rad(45), 0, math.rad(45), crashCfg.GroundRoll - 0.001 } do
		equal(Crash.evaluate({ grounded = true, roll = roll, frontSliding = true, rearSliding = true, frontUtilization = 1.5, rollRate = 8 }, crashCfg), nil, "Slip with a recoverable grounded lean")
	end
end)

test("a high-side requires grip recovery with rapid roll and an existing lean", function()
	equal(Crash.evaluate({ grounded = true, rearGripRecovered = true, rollRate = 5.01, roll = 0.51 }, crashCfg), "High-side", "Rapid roll when rear grip returns")
	equal(Crash.evaluate({ grounded = true, rearGripRecovered = true, rollRate = -6, roll = -0.7 }, crashCfg), "High-side", "Opposite-side high-side")
	equal(Crash.evaluate({ grounded = true, rearGripRecovered = false, rollRate = 6, roll = 0.7 }, crashCfg), nil, "Rapid roll alone is not grip recovery")
	equal(Crash.evaluate({ grounded = true, rearGripRecovered = true, rollRate = 5, roll = 0.7 }, crashCfg), nil, "Recoverable roll rate boundary")
	equal(Crash.evaluate({ grounded = true, rearGripRecovered = true, rollRate = 6, roll = 0.5 }, crashCfg), nil, "Nearly upright grip recovery")
end)

test("loop-out requires rear-ground contact and rearward pitch beyond its limit", function()
	equal(Crash.evaluate({ grounded = true, rearContact = true, pitch = crashCfg.LoopPitch + 0.001 }, crashCfg), "Loop-out", "Rear wheel pushes a rotated chassis")
	equal(Crash.evaluate({ grounded = true, rearContact = true, pitch = crashCfg.LoopPitch }, crashCfg), nil, "Exact recoverable wheelie boundary")
	equal(Crash.evaluate({ grounded = true, rearContact = false, pitch = math.rad(100) }, crashCfg), nil, "No rear contact means no loop-out evidence")
	equal(Crash.evaluate({ grounded = true, rearContact = true, pitch = -math.rad(100) }, crashCfg), nil, "A forward rotation is not a loop-out")
end)

test("midair rotation cannot become a ground crash before contact", function()
	equal(Crash.evaluate({ grounded = false, rearContact = false, roll = math.rad(150), pitch = math.rad(120), rollRate = 12, frontSliding = true, rearSliding = true, frontUtilization = 2, rearGripRecovered = true }, crashCfg), nil, "Midair whip is not a synthetic crash")
	equal(Crash.evaluate({ grounded = false, bodyContact = true, speed = 4 }, crashCfg), "Chassis impact", "Actual collision is still observed in flight")
	equal(Crash.evaluate({ bodyContact = true, speed = 3 }, crashCfg), nil, "Minor chassis touch")
end)

test("body contact identifies stationary physical falls even when both tire rays miss", function()
	for _, roll in { crashCfg.GroundRoll, -crashCfg.GroundRoll, math.pi, -math.pi } do
		local sample = { grounded = false, frontContact = false, rearContact = false, bodyContact = true, roll = roll, pitch = 0, speed = 0 }
		equal(Crash.evaluate(sample, crashCfg), "Lost balance", "A grounded chassis fall does not require wheel contact or speed")
		sample.bodyContact = false
		equal(Crash.evaluate(sample, crashCfg), nil, "The same orientation while airborne remains unrestricted")
	end
end)

test("a stationary balanced chassis touch does not artificially eject the rider", function()
	for _, speed in { 0, 0.2, 3 } do
		equal(Crash.evaluate({ grounded = false, frontContact = false, rearContact = false, bodyContact = true, roll = 0, pitch = 0, speed = speed }, crashCfg), nil, "Minor balanced body touch is recoverable")
	end
	equal(Crash.evaluate({ grounded = false, bodyContact = true, roll = crashCfg.GroundRoll - 0.001, pitch = crashCfg.LoopPitch - 0.001, speed = 0 }, crashCfg), nil, "Physical fall thresholds must still be respected")
end)

test("an over-rotated chassis impact requires contact and works in both pitch directions", function()
	for _, pitch in { crashCfg.LoopPitch, -crashCfg.LoopPitch, math.rad(100), -math.rad(100) } do
		local sample = { grounded = false, frontContact = false, rearContact = false, bodyContact = true, roll = 0, pitch = pitch, speed = 0 }
		equal(Crash.evaluate(sample, crashCfg), "Over-rotated impact", "A slow nose or rear chassis impact is still a physical failure")
		sample.bodyContact = false
		equal(Crash.evaluate(sample, crashCfg), nil, "Over-rotation alone cannot reject an airborne maneuver")
	end
end)

test("crash observation leaves the physical sample untouched", function()
	local sample: any = { landing = true, landingPitch = -math.rad(50), normalImpactSpeed = 10, speed = 18, roll = 0.2, rollRate = 4 }
	local before = table.clone(sample)
	equal(Crash.evaluate(sample, crashCfg), "Nose-heavy landing", "Observe landing failure")
	for key, value in before do equal(sample[key], value, "Observation does not change " .. key) end
	for key in sample do check(before[key] ~= nil, "Observation must not attach corrective forces or targets") end
end)

test("recovery requires the full calibrated 2.5 second delay", function()
	equal(crashCfg.RecoveryDelay, 2.5, "Prototype recovery delay")
	equal(Crash.canRecover(10, 9, crashCfg), false, "A clock before the crash cannot recover")
	equal(Crash.canRecover(10, 12.499999, crashCfg), false, "Remain crashed immediately before the boundary")
	equal(Crash.canRecover(10, 12.5, crashCfg), true, "Recover at the exact boundary")
	equal(Crash.canRecover(10, 12.500001, crashCfg), true, "Recovery stays available afterward")
end)

test("nonfinite recovery clocks cannot bypass the crash delay", function()
	for _, now in { 0 / 0, math.huge, -math.huge } do equal(Crash.canRecover(10, now, crashCfg), false, "Reject nonfinite current time") end
	for _, crashedAt in { 0 / 0, math.huge, -math.huge } do equal(Crash.canRecover(crashedAt, 20, crashCfg), false, "Reject nonfinite crash time") end
end)

print(string.format("PhysicsBoundary: %d tests, %d assertions, %d failures", tests, assertions, failures))
assert(failures == 0, string.format("%d PhysicsBoundary tests failed", failures))
