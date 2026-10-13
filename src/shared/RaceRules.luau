--!strict
-- Engine-independent rules: the server supplies gate crossings and its clock.
local RaceRules = {}

export type State = {
	checkpointCount: number,
	nextCheckpoint: number,
	lapStart: number?,
	lastCross: number?,
	lap: number,
	bestLap: number?,
	lapsFinished: number,
}

export type Point = { x: number, y: number, z: number }

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

function RaceRules.new(checkpointCount: number): State
	assert(checkpointCount >= 2 and checkpointCount % 1 == 0, "A circuit needs at least two gates")
	return {
		checkpointCount = checkpointCount,
		nextCheckpoint = 1,
		lapStart = nil,
		lastCross = nil,
		lap = 1,
		bestLap = nil,
		lapsFinished = 0,
	}
end

function RaceRules.cross(state: State, index: number, now: number): (boolean, number?)
	if not finite(now) or index ~= state.nextCheckpoint or (state.lastCross ~= nil and now < state.lastCross) then
		return false, nil
	end
	if index == 1 then
		local completedTime: number? = nil
		if state.lapStart ~= nil then
			local elapsed = now - state.lapStart
			if elapsed <= 0 then
				return false, nil
			end
			completedTime = elapsed
			state.lapsFinished += 1
			state.lap = state.lapsFinished + 1
			if state.bestLap == nil or elapsed < state.bestLap then
				state.bestLap = elapsed
			end
		end
		state.lapStart = now
		state.lastCross = now
		state.nextCheckpoint = 2
		return true, completedTime
	end
	if state.lapStart == nil or now < state.lapStart then
		return false, nil
	end
	state.nextCheckpoint = if index == state.checkpointCount then 1 else index + 1
	state.lastCross = now
	return true, nil
end

function RaceRules.reset(state: State)
	state.lapStart = nil
	state.lastCross = nil
	state.nextCheckpoint = 1
end

-- Interpolate at the gate plane so fast bikes cannot skip a narrow trigger.
function RaceRules.crossedGate(previous: Point, current: Point, width: number): boolean
	if previous.z <= 0 or current.z > 0 then
		return false
	end
	local alpha = previous.z / (previous.z - current.z)
	local x = previous.x + (current.x - previous.x) * alpha
	local y = previous.y + (current.y - previous.y) * alpha
	return math.abs(x) <= width / 2 + 3 and y >= -3 and y <= 20
end

return RaceRules
