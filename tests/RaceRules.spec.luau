--!strict
-- Run from the repository root: luau tests/RaceRules.spec.luau
local RaceRules = require("../src/shared/RaceRules")

local tests = 0
local assertions = 0
local failures = 0

local function equal(actual: any, expected: any, message: string?)
	assertions += 1
	assert(actual == expected, (message or "Values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name: string, run: () -> ())
	tests += 1
	local passed, message = pcall(run)
	if passed then
		print("PASS " .. name)
	else
		failures += 1
		print("FAIL " .. name .. ": " .. tostring(message))
	end
end

local function snapshot(state: any): any
	local copy = {}
	for key, value in pairs(state) do
		copy[key] = value
	end
	return copy
end

local function unchanged(state: any, before: any)
	for key, value in pairs(before) do
		equal(state[key], value, "Rejected crossing changed " .. key)
	end
	for key, value in pairs(state) do
		equal(value, before[key], "Rejected crossing added " .. key)
	end
end

local function rejected(state: any, gate: number, time: number)
	local before = snapshot(state)
	local accepted, lapTime = RaceRules.cross(state, gate, time)
	equal(accepted, false, "Crossing should be rejected")
	equal(lapTime, nil, "Rejected crossing must not complete a lap")
	unchanged(state, before)
end

local function accepted(state: any, gate: number, time: number, expectedLap: number?)
	local didAccept, lapTime = RaceRules.cross(state, gate, time)
	equal(didAccept, true, "Crossing should be accepted")
	equal(lapTime, expectedLap, "Completed lap time")
end

local function point(x: number, y: number, z: number)
	return { x = x, y = y, z = z }
end

test("new race requires a circuit with at least two whole-number gates", function()
	for _, count in { 0, 1, -2, 2.5, math.huge, 0 / 0 } do
		local success = pcall(RaceRules.new, count)
		equal(success, false)
	end
	local state = RaceRules.new(4)
	equal(state.checkpointCount, 4)
	equal(state.nextCheckpoint, 1)
	equal(state.lapStart, nil)
	equal(state.lap, 1)
	equal(state.lapsFinished, 0)
	equal(state.bestLap, nil)
end)

test("a race can only start at the start gate", function()
	local state = RaceRules.new(4)
	rejected(state, 2, 100)
	rejected(state, 4, 100)
	accepted(state, 1, 100, nil)
	equal(state.lapStart, 100)
	equal(state.nextCheckpoint, 2)
	equal(state.lapsFinished, 0)
end)

test("checkpoints advance in order and the finish gate completes a lap", function()
	local state = RaceRules.new(4)
	accepted(state, 1, 100, nil)
	accepted(state, 2, 110, nil)
	equal(state.nextCheckpoint, 3)
	accepted(state, 3, 120, nil)
	equal(state.nextCheckpoint, 4)
	accepted(state, 4, 125, nil)
	equal(state.nextCheckpoint, 1)
	equal(state.lapsFinished, 0)
	accepted(state, 1, 130, 30)
	equal(state.lapsFinished, 1)
	equal(state.lap, 2)
	equal(state.bestLap, 30)
	equal(state.lapStart, 130)
	equal(state.nextCheckpoint, 2)
end)

test("duplicate and skipped gates cannot advance or finish a lap", function()
	local state = RaceRules.new(4)
	accepted(state, 1, 100, nil)
	rejected(state, 1, 101)
	rejected(state, 3, 102)
	rejected(state, 4, 103)
	accepted(state, 2, 110, nil)
	rejected(state, 2, 111)
	rejected(state, 1, 112)
	accepted(state, 3, 120, nil)
	rejected(state, 1, 121)
	accepted(state, 4, 125, nil)
	rejected(state, 4, 126)
	accepted(state, 1, 130, 30)
end)

test("best lap survives a slower lap and updates after a faster lap", function()
	local state = RaceRules.new(3)
	accepted(state, 1, 100, nil)
	accepted(state, 2, 110, nil)
	accepted(state, 3, 120, nil)
	accepted(state, 1, 130, 30)
	accepted(state, 2, 145, nil)
	accepted(state, 3, 160, nil)
	accepted(state, 1, 170, 40)
	equal(state.bestLap, 30)
	accepted(state, 2, 175, nil)
	accepted(state, 3, 185, nil)
	accepted(state, 1, 190, 20)
	equal(state.bestLap, 20)
	equal(state.lapsFinished, 3)
	equal(state.lap, 4)
end)

test("reset discards an unfinished lap while keeping session results", function()
	local state = RaceRules.new(3)
	accepted(state, 1, 100, nil)
	accepted(state, 2, 110, nil)
	accepted(state, 3, 120, nil)
	accepted(state, 1, 130, 30)
	accepted(state, 2, 140, nil)
	RaceRules.reset(state)
	equal(state.lapStart, nil)
	equal(state.nextCheckpoint, 1)
	equal(state.lapsFinished, 1)
	equal(state.lap, 2)
	equal(state.bestLap, 30)
	rejected(state, 3, 145)
	accepted(state, 1, 150, nil)
	equal(state.lapsFinished, 1)
	accepted(state, 2, 160, nil)
	accepted(state, 3, 170, nil)
	accepted(state, 1, 185, 35)
	equal(state.bestLap, 30)
	equal(state.lapsFinished, 2)
end)

test("nonfinite clocks cannot start, advance, or complete a lap", function()
	local state = RaceRules.new(3)
	local invalidTimes = { 0 / 0, math.huge, -math.huge }
	for _, time in invalidTimes do
		rejected(state, 1, time)
	end
	accepted(state, 1, 100, nil)
	for _, time in invalidTimes do
		rejected(state, 2, time)
	end
	accepted(state, 2, 110, nil)
	accepted(state, 3, 120, nil)
	for _, time in invalidTimes do
		rejected(state, 1, time)
	end
	accepted(state, 1, 130, 30)
end)

test("a clock before the start of the current lap is rejected", function()
	local state = RaceRules.new(3)
	accepted(state, 1, 100, nil)
	rejected(state, 2, 99)
	accepted(state, 2, 110, nil)
	rejected(state, 3, 99)
	accepted(state, 3, 120, nil)
	rejected(state, 1, 99)
	accepted(state, 1, 130, 30)
end)

test("a clock behind the previous accepted checkpoint is rejected", function()
	local state = RaceRules.new(3)
	accepted(state, 1, 100, nil)
	accepted(state, 2, 120, nil)
	rejected(state, 3, 110)
	accepted(state, 3, 130, nil)
	rejected(state, 1, 125)
	accepted(state, 1, 140, 40)
end)

test("a zero-duration lap is rejected without losing checkpoint progress", function()
	local state = RaceRules.new(2)
	accepted(state, 1, 100, nil)
	accepted(state, 2, 100, nil)
	rejected(state, 1, 100)
	accepted(state, 1, 101, 1)
end)

test("forward travel across the gate plane is detected", function()
	equal(RaceRules.crossedGate(point(0, 2, 10), point(0, 2, -10), 20), true)
	equal(RaceRules.crossedGate(point(0, 2, 10), point(0, 2, 0), 20), true)
end)

test("reverse travel cannot trigger a gate", function()
	equal(RaceRules.crossedGate(point(0, 2, -10), point(0, 2, 10), 20), false)
end)

test("travel staying on either side cannot trigger a gate", function()
	equal(RaceRules.crossedGate(point(0, 2, 10), point(0, 2, 1), 20), false)
	equal(RaceRules.crossedGate(point(0, 2, -1), point(0, 2, -10), 20), false)
end)

test("tangent movement and departure from the plane cannot double count", function()
	equal(RaceRules.crossedGate(point(-5, 2, 0), point(5, 2, 0), 20), false)
	equal(RaceRules.crossedGate(point(0, 2, 0), point(0, 2, -10), 20), false)
end)

test("high-speed crossings use position interpolated at the gate plane", function()
	-- Both endpoints are outside the gate, but the path crosses its center.
	equal(RaceRules.crossedGate(point(40, 30, 20), point(-40, -20, -20), 20), true)
	-- Asymmetric depth gives alpha 1/4 and x=0, rather than midpoint x=-20.
	equal(RaceRules.crossedGate(point(20, 2, 10), point(-60, 2, -30), 20), true)
end)

test("a path outside the gate width is rejected at the plane", function()
	equal(RaceRules.crossedGate(point(14, 2, 10), point(14, 2, -10), 20), false)
	equal(RaceRules.crossedGate(point(-14, 2, 10), point(-14, 2, -10), 20), false)
	-- The endpoint enters the gate, but the crossing occurred outside it.
	equal(RaceRules.crossedGate(point(40, 2, 10), point(0, 2, -10), 20), false)
end)

test("gate width includes the documented three-stud bike allowance", function()
	equal(RaceRules.crossedGate(point(13, 2, 10), point(13, 2, -10), 20), true)
	equal(RaceRules.crossedGate(point(-13, 2, 10), point(-13, 2, -10), 20), true)
	equal(RaceRules.crossedGate(point(13.01, 2, 10), point(13.01, 2, -10), 20), false)
end)

test("jumping above the checkpoint height cannot trigger a gate", function()
	equal(RaceRules.crossedGate(point(0, 21, 10), point(0, 21, -10), 20), false)
	equal(RaceRules.crossedGate(point(0, 30, 10), point(0, 15, -10), 20), false)
	equal(RaceRules.crossedGate(point(0, 40, 10), point(0, 0, -10), 20), true)
end)

test("the gate permits its height boundaries and rejects travel below it", function()
	equal(RaceRules.crossedGate(point(0, 20, 10), point(0, 20, -10), 20), true)
	equal(RaceRules.crossedGate(point(0, -3, 10), point(0, -3, -10), 20), true)
	equal(RaceRules.crossedGate(point(0, -3.01, 10), point(0, -3.01, -10), 20), false)
end)

print(string.format("RaceRules: %d tests, %d assertions, %d failures", tests, assertions, failures))
assert(failures == 0, string.format("%d RaceRules tests failed", failures))
