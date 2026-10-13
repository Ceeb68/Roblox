--!strict
-- Network boundary: accept controls, never client physics poses or lap results.
local Controls = {}

local AXES: { [string]: { number } } = {
	throttle = { 0, 1 }, frontBrake = { 0, 1 }, rearBrake = { 0, 1 }, clutch = { 0, 1 },
	steer = { -1, 1 }, lean = { -1, 1 }, bodyForward = { -1, 1 }, bodySide = { -1, 1 },
}
local TUNING: { [string]: { number } } = {
	SpringRate = { 8000, 40000 }, Compression = { 300, 5000 },
	Rebound = { 300, 6000 }, Preload = { 0, 0.035 },
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Controls.neutral(seq: number?): any
	return {
		seq = seq or 0, throttle = 0, frontBrake = 0, rearBrake = 0, clutch = 1,
		steer = 0, lean = 0, bodyForward = 0, bodySide = 0,
		standing = false, footDown = true, shift = 0,
	}
end

function Controls.normalize(packet: any, lastSeq: number): any?
	if type(packet) ~= "table" or not finite(packet.seq) or packet.seq % 1 ~= 0
		or packet.seq <= lastSeq or packet.seq > 2147483647 then
		return nil
	end
	if type(packet.standing) ~= "boolean" or type(packet.footDown) ~= "boolean"
		or not finite(packet.shift) or packet.shift % 1 ~= 0 or math.abs(packet.shift) > 1 then
		return nil
	end
	local result = Controls.neutral(packet.seq)
	for axis, range in AXES do
		local value = packet[axis]
		if not finite(value) then
			return nil
		end
		result[axis] = math.clamp(value, range[1], range[2])
	end
	result.standing = packet.standing
	result.footDown = packet.footDown
	result.shift = packet.shift
	return result
end

function Controls.normalizeSetup(changes: any, current: any): any?
	if type(changes) ~= "table" then
		return nil
	end
	local result = { Front = table.clone(current.Front), Rear = table.clone(current.Rear) }
	local count = 0
	for axle, values in changes do
		if (axle ~= "Front" and axle ~= "Rear") or type(values) ~= "table" then
			return nil
		end
		for key, value in values do
			local range = TUNING[key]
			if not range or not finite(value) or value < range[1] or value > range[2] then
				return nil
			end
			result[axle][key] = value
			count += 1
		end
	end
	return if count > 0 then result else nil
end

return Controls
