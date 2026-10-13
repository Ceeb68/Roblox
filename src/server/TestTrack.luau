--!strict
-- A development proving ground, not a finished race venue. Every measurement
-- below is in metres; only this builder converts to Roblox studs (0.28 m/stud).
-- Surface geometry is collision geometry. Labels and reference lines never
-- participate in wheel raycasts or change the motorcycle's balance.

local TestTrack = {}

export type Gate = { cframe: CFrame, width: number }
export type Station = {
	id: string,
	title: string,
	difficulty: string,
	surface: string,
	frame: CFrame,
	lengthM: number,
	widthM: number,
	notes: string,
}
export type Course = {
	gates: { Gate },
	checkpointCount: number,
	stations: { Station },
	spawnCFrame: (self: Course, slot: number) -> CFrame,
}

local METRES_PER_STUD = 0.28
local ROAD_Y = 1
local ROAD_WIDTH_M = 10
local ROAD_EPSILON_M = 0.002
local WHITE = Color3.fromRGB(245, 242, 229)
local ORANGE = Color3.fromRGB(246, 132, 54)
local TEAL = Color3.fromRGB(43, 196, 178)
local INK = Color3.fromRGB(30, 39, 43)

local SURFACES: { [string]: { color: Color3, material: Enum.Material } } = {
	dirt = { color = Color3.fromRGB(146, 102, 65), material = Enum.Material.Ground },
	loam = { color = Color3.fromRGB(118, 83, 54), material = Enum.Material.Ground },
	sand = { color = Color3.fromRGB(203, 180, 131), material = Enum.Material.Sand },
	mud = { color = Color3.fromRGB(83, 64, 49), material = Enum.Material.Mud },
	hardpack = { color = Color3.fromRGB(175, 141, 104), material = Enum.Material.Sandstone },
	grass = { color = Color3.fromRGB(103, 121, 78), material = Enum.Material.Grass },
	concrete = { color = Color3.fromRGB(157, 156, 149), material = Enum.Material.Concrete },
}

local function m(value: number): number
	return value / METRES_PER_STUD
end

local function position(x: number, height: number, z: number): Vector3
	return Vector3.new(m(x), ROAD_Y + m(height), m(z))
end

local function folder(parent: Instance, name: string): Folder
	local result = Instance.new("Folder")
	result.Name = name
	result.Parent = parent
	return result
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	frame: CFrame,
	color: Color3,
	material: Enum.Material,
	collision: boolean
): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Anchored = true
	result.Size = size
	result.CFrame = frame
	result.Color = color
	result.Material = material
	result.CanCollide = collision
	-- Body/guard impact detection uses Touched. Both the chassis and its
	-- collision surface must permit events; visual guides remain inert.
	result.CanTouch = collision
	result.CanQuery = collision
	result.TopSurface = Enum.SurfaceType.Smooth
	result.BottomSurface = Enum.SurfaceType.Smooth
	result.Parent = parent
	return result
end

local function collisionSurface(result: BasePart, surface: string)
	result:SetAttribute("PhysicsSurface", surface)
	-- Native collision friction concerns the chassis/feet. Tire grip itself is
	-- evaluated by the simulation, independently for each raycast contact.
	result.CustomPhysicalProperties = PhysicalProperties.new(1, 0.5, 0, 1, 1)
end

-- from/to describe TOP centreline points. Moving half the thickness along the
-- normal keeps slopes flush at their endpoints, including banked surfaces.
local function span(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	widthM: number,
	surface: string,
	roll: number?
): Part
	local visual = SURFACES[surface] or SURFACES.dirt
	local thickness = m(0.2)
	local angle = roll or 0
	local frame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, 0, angle)
	local result = block(parent, name,
		Vector3.new(m(widthM) / math.cos(angle), thickness, (to - from).Magnitude + m(0.006)),
		frame * CFrame.new(0, -thickness / 2, 0), visual.color, visual.material, true)
	collisionSurface(result, surface)
	return result
end

local function flat(parent: Instance, name: string, x: number, z: number, widthM: number, lengthM: number, surface: string): Part
	return span(parent, name,
		position(x, ROAD_EPSILON_M, z - lengthM / 2),
		position(x, ROAD_EPSILON_M, z + lengthM / 2), widthM, surface)
end

local function label(board: BasePart, face: Enum.NormalId, title: string, detail: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "StationLabel"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 28
	gui.LightInfluence = 0.1
	gui.Parent = board
	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.fromScale(0.94, 0.36)
	heading.Position = UDim2.fromScale(0.03, 0.03)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.Text = title
	heading.TextColor3 = WHITE
	heading.TextScaled = true
	heading.Parent = gui
	local description = Instance.new("TextLabel")
	description.Size = UDim2.fromScale(0.94, 0.54)
	description.Position = UDim2.fromScale(0.03, 0.43)
	description.BackgroundTransparency = 1
	description.Font = Enum.Font.Gotham
	description.Text = detail
	description.TextWrapped = true
	description.TextScaled = true
	description.TextColor3 = TEAL
	description.Parent = gui
end

local function sign(parent: Instance, name: string, frame: CFrame, title: string, detail: string)
	-- Practice signs are intentionally outside the riding lane and noncolliding.
	block(parent, name .. "Post", Vector3.new(m(0.1), m(2), m(0.1)),
		frame * CFrame.new(0, m(1), 0), INK, Enum.Material.Metal, false)
	local board = block(parent, name, Vector3.new(m(4.8), m(1.7), m(0.08)),
		frame * CFrame.new(0, m(2.4), 0), INK, Enum.Material.SmoothPlastic, false)
	label(board, Enum.NormalId.Front, title, detail)
	label(board, Enum.NormalId.Back, title, detail)
end

local function referenceLine(parent: Instance, name: string, frame: CFrame, widthM: number, color: Color3)
	block(parent, name, Vector3.new(m(widthM), m(0.004), m(0.055)),
		frame * CFrame.new(0, m(0.009), 0), color, Enum.Material.SmoothPlastic, false)
end

local function station(
	stations: { Station }, parent: Instance, id: string, title: string,
	difficulty: string, surface: string, frame: CFrame, lengthM: number,
	widthM: number, notes: string
)
	table.insert(stations, {
		id = id, title = title, difficulty = difficulty, surface = surface,
		frame = frame, lengthM = lengthM, widthM = widthM, notes = notes,
	})
	sign(parent, id .. "Sign", frame * CFrame.new(-m(widthM / 2 + 2.8), 0, 0),
		title .. " | " .. difficulty, notes)
end

local function profile(
	parent: Instance, name: string, origin: Vector3, forward: Vector3,
	lengthM: number, widthM: number, surface: string,
	height: (distanceM: number) -> number, stepM: number?
)
	local count = math.ceil(lengthM / (stepM or 0.25))
	for index = 1, count do
		local a = (index - 1) / count * lengthM
		local b = index / count * lengthM
		span(parent, name .. string.format("%03d", index),
			origin + forward * m(a) + Vector3.yAxis * m(height(a)),
			origin + forward * m(b) + Vector3.yAxis * m(height(b)), widthM, surface)
	end
end

local function curvedRoad(parent: Instance, name: string, centreX: number, centreZ: number, fromAngle: number, banked: boolean)
	local radiusM = 10
	local segments = 32
	local function point(t: number): Vector3
		local angle = fromAngle + t * math.pi / 2
		return position(centreX + math.cos(angle) * radiusM, ROAD_EPSILON_M,
			centreZ + math.sin(angle) * radiusM)
	end
	local function bank(t: number): number
		-- 0 degree seams, rising smoothly to 16 degrees at mid-corner.
		return if banked then math.rad(16) * math.sin(t * math.pi) ^ 2 else 0
	end
	for index = 1, segments do
		local ta, tb = (index - 1) / segments, index / segments
		local a, b = point(ta), point(tb)
		local frame = CFrame.lookAt((a + b) / 2, b)
		if banked then
			local quarterWidth = ROAD_WIDTH_M / 4
			local offset = frame.RightVector * m(quarterWidth)
			span(parent, name .. "Inner" .. index, a + offset, b + offset, ROAD_WIDTH_M / 2, "loam")
			-- The outside half rises away from the flat inner half. There is no
			-- upright retaining curb or invisible force keeping the bike in it.
			local outerA = a - offset + Vector3.yAxis * m(quarterWidth * math.tan(bank(ta)))
			local outerB = b - offset + Vector3.yAxis * m(quarterWidth * math.tan(bank(tb)))
			span(parent, name .. "Berm" .. index, outerA, outerB,
				ROAD_WIDTH_M / 2, "loam", -(bank(ta) + bank(tb)) / 2)
		else
			span(parent, name .. index, a, b, ROAD_WIDTH_M, "dirt")
		end
	end
end

local function rutSection(parent: Instance, origin: Vector3, forward: Vector3)
	local right = forward:Cross(Vector3.yAxis)
	local distances = { 0, 0.5, 1, 1.5, 2, 14, 14.5, 15, 15.5, 16 }
	local function envelope(distance: number): number
		local fade = math.min(distance / 2, (16 - distance) / 2, 1)
		return math.sin(math.clamp(fade, 0, 1) * math.pi / 2) ^ 2
	end
	local function ridge(offset: number): number
		return 0.16 * math.cos(offset / 0.7 * math.pi / 2) ^ 2
	end
	-- Four 0.6 m channels lie between five rounded earth ridges. Their floors
	-- remain at road level; raised banks create real 0.16 m depressions. Every
	-- ridge tapers into the flat road over 2 m at both ends.
	for _, ridgeX in { -4, -2, 0, 2, 4 } do
		for band = 1, 7 do
			local x0, x1 = -0.7 + (band - 1) * 0.2, -0.7 + band * 0.2
			local midX = (x0 + x1) / 2
			for segment = 2, #distances do
				local a, b = distances[segment - 1], distances[segment]
				local ea, eb = envelope(a), envelope(b)
				local centreHeight = (ridge(x0) + ridge(x1)) / 2
				local roll = math.atan((ridge(x1) - ridge(x0)) * (ea + eb) / 2 / 0.2)
				local offset = right * m(ridgeX + midX)
				span(parent, "RutBank", origin + forward * m(a) + offset + Vector3.yAxis * m(centreHeight * ea),
					origin + forward * m(b) + offset + Vector3.yAxis * m(centreHeight * eb), 0.2, "loam", roll)
			end
		end
	end
end

local function tabletop(
	parent: Instance, name: string, origin: Vector3, forward: Vector3,
	heightM: number, riseM: number, crestM: number, landingM: number, widthM: number
)
	local jump = folder(parent, name)
	profile(jump, "Takeoff", origin, forward, riseM, widthM, "dirt", function(distance)
		return heightM * (distance / riseM) ^ 2
	end)
	local crest = origin + forward * m(riseM) + Vector3.yAxis * m(heightM)
	span(jump, "Table", crest, crest + forward * m(crestM), widthM, "dirt")
	local landingOrigin = origin + forward * m(riseM + crestM)
	profile(jump, "Landing", landingOrigin, forward, landingM, widthM, "dirt", function(distance)
		return heightM * (1 - distance / landingM) ^ 2
	end)
	local endPoint = landingOrigin + forward * m(landingM)
	referenceLine(jump, "TakeoffDatum", CFrame.lookAt(origin, origin + forward), widthM, ORANGE)
	referenceLine(jump, "LandingEndDatum", CFrame.lookAt(endPoint, endPoint + forward), widthM, TEAL)
	-- Reference pitch lines next to the landing are measurement guides only.
	local right = forward:Cross(Vector3.yAxis)
	local guide = endPoint + right * m(widthM / 2 + 1.2)
	for _, degrees in { -30, 0, 30 } do
		local angle = math.rad(degrees)
		local target = guide + forward * m(1.6) * math.cos(angle) + Vector3.yAxis * m(1.6) * math.sin(angle)
		local frame = CFrame.lookAt((guide + target) / 2 + Vector3.yAxis * m(1.5), target + Vector3.yAxis * m(1.5))
		block(jump, "PitchReference" .. degrees, Vector3.new(m(0.055), m(0.055), (target - guide).Magnitude), frame,
			if degrees == 0 then WHITE else ORANGE, Enum.Material.SmoothPlastic, false)
	end
	sign(jump, "PitchGuide", CFrame.lookAt(guide + right * m(1.2), guide), "LANDING PITCH DATUM", "Lines: -30 / 0 / +30 degrees. Diagnostic guides, not safe-angle guarantees.")
end

local function gate(parent: Instance, frame: CFrame, index: number)
	local model = folder(parent, if index == 1 then "DevelopmentStartFinish" else "TestGate" .. index)
	for _, side in { -1, 1 } do
		block(model, "GatePost", Vector3.new(m(0.12), m(3), m(0.12)),
			frame * CFrame.new(side * m(ROAD_WIDTH_M / 2 + 0.7), m(1.5), 0),
			if side < 0 then ORANGE else TEAL, Enum.Material.SmoothPlastic, false)
	end
	local board = block(model, "GateLabel", Vector3.new(m(ROAD_WIDTH_M + 1.8), m(1), m(0.06)),
		frame * CFrame.new(0, m(3.7), 0), INK, Enum.Material.SmoothPlastic, false)
	label(board, Enum.NormalId.Front, if index == 1 then "250F PHYSICS LAB" else "TEST GATE " .. index,
		if index == 1 then "CLOCKWISE TEST LAP | DEVELOPMENT ONLY" else "Follow clockwise. Practice branches have no timing gates.")
	label(board, Enum.NormalId.Back, if index == 1 then "START / FINISH" else "TEST GATE " .. index, "Clockwise test route")
	referenceLine(model, "CrossingPlane", frame, ROAD_WIDTH_M, if index == 1 then WHITE else TEAL)
end

function TestTrack.build(world: Instance): Course
	local lab = folder(world, "250FPhysicsTestTrack")
	lab:SetAttribute("MetresPerStud", METRES_PER_STUD)
	lab:SetAttribute("Purpose", "Development validation; not approved competitive physics")
	local stations: { Station } = {}
	local road = folder(lab, "ClockwiseTestCircuit")
	local terrain = folder(lab, "SurfaceLab")
	local signs = folder(lab, "StationInstructions")
	local obstacles = folder(lab, "MeasuredObstacles")
	local ground = block(lab, "GrassRunoff", Vector3.new(m(70), m(1), m(106)),
		CFrame.new(0, ROAD_Y - m(0.5), 0), SURFACES.grass.color, SURFACES.grass.material, true)
	collisionSurface(ground, "grass")

	-- A 44 x 74 m rounded circuit. All roads are 10 m wide and flush with the
	-- runoff, so leaving the lane does not hit an artificial vertical road curb.
	span(road, "LaunchStraight", position(-22, ROAD_EPSILON_M, 27), position(-22, ROAD_EPSILON_M, -27), ROAD_WIDTH_M, "dirt")
	span(road, "NorthStraight", position(-12, ROAD_EPSILON_M, -37), position(12, ROAD_EPSILON_M, -37), ROAD_WIDTH_M, "dirt")
	span(road, "TabletopStraight", position(22, ROAD_EPSILON_M, -27), position(22, ROAD_EPSILON_M, 27), ROAD_WIDTH_M, "dirt")
	span(road, "WhoopsStraight", position(12, ROAD_EPSILON_M, 37), position(-12, ROAD_EPSILON_M, 37), ROAD_WIDTH_M, "loam")
	curvedRoad(road, "FlatNorthWestTurn", -12, -27, math.pi, false)
	curvedRoad(road, "NorthEastBerm", 12, -27, -math.pi / 2, true)
	curvedRoad(road, "FlatSouthEastTurn", 12, 27, 0, false)
	curvedRoad(road, "SouthWestBerm", -12, 27, math.pi / 2, true)

	local north, south, west = -Vector3.zAxis, Vector3.zAxis, -Vector3.xAxis
	local launchFrame = CFrame.lookAt(position(-22, ROAD_EPSILON_M, 25), position(-22, ROAD_EPSILON_M, 24))
	station(stations, signs, "launch", "01 | CLUTCH + BALANCE", "FOUNDATION", "dirt", launchFrame, 15, ROAD_WIDTH_M,
		"Neutral, clutch in, feet down. Select first, release clutch progressively. F raises / lowers feet. No automatic balance.")
	for distance = 0, 10 do
		if distance % 5 == 0 then
			local frame = launchFrame * CFrame.new(0, 0, -m(distance))
			referenceLine(signs, "Launch" .. distance .. "m", frame, 6, if distance == 10 then TEAL else WHITE)
		end
	end
	sign(signs, "LaunchDistance", launchFrame * CFrame.new(m(7.6), 0, -m(10)), "10 m LAUNCH DATUM", "Repeat from the 0 m line. Compare clutch slip, speed and wheelspin in telemetry.")

	local bumpOrigin = position(-22, ROAD_EPSILON_M + 0.003, 10)
	flat(terrain, "BrakingHardpack", -22, 4, 6, 12, "hardpack")
	local bumpHeights = { 0.12, 0.15, 0.18, 0.22, 0.16 }
	profile(obstacles, "BrakingBump", bumpOrigin, north, 12, 6, "hardpack", function(distance)
		local result = 0
		for index, height in bumpHeights do
			local centre = 1.8 + (index - 1) * 2
			local delta = math.abs(distance - centre)
			if delta < 0.65 then
				result = math.max(result, height * (1 + math.cos(math.pi * delta / 0.65)) / 2)
			end
		end
		return result
	end, 0.13)
	station(stations, signs, "braking", "02 | BRAKING BUMPS", "INTERMEDIATE", "hardpack",
		CFrame.lookAt(bumpOrigin, bumpOrigin + north), 12, 6,
		"Five bumps: 0.12-0.22 m tall, 2 m spacing. Ride north. Compare separate brakes and compression / rebound; flat bypass on both sides.")

	local rutOrigin = position(-22, ROAD_EPSILON_M + 0.003, -2)
	span(terrain, "LoamRutFloors", rutOrigin, rutOrigin + north * m(16), ROAD_WIDTH_M, "loam")
	rutSection(obstacles, rutOrigin, north)
	station(stations, signs, "ruts", "03 | REAL RUT CHANNELS", "INTERMEDIATE", "loam",
		CFrame.lookAt(rutOrigin, rutOrigin + north), 16, ROAD_WIDTH_M,
		"Ride north. Four 0.6 m lanes between rounded banks, depth 0.16 m. Channels are collision geometry; entering sideways can deflect a tire.")
	station(stations, signs, "flat-turn", "04 | FLAT CORNER", "FOUNDATION", "dirt",
		CFrame.lookAt(position(-22, ROAD_EPSILON_M, -25), position(-22, ROAD_EPSILON_M, -26)), 15.7, ROAD_WIDTH_M,
		"10 m centreline radius. Turn right. Brake before turning; learn steering, lean and rider-body movement without bank support.")
	station(stations, signs, "berm", "05 | BANKED CORNER", "INTERMEDIATE", "loam",
		CFrame.lookAt(position(10, ROAD_EPSILON_M, -37), position(11, ROAD_EPSILON_M, -37)), 15.7, ROAD_WIDTH_M,
		"Turn right. Outer half rises smoothly to a 16 degree bank; inner half stays flat. Repeat speed and line before adjusting suspension.")

	local easyOrigin = position(22, ROAD_EPSILON_M, -15)
	tabletop(obstacles, "EasyTabletop", easyOrigin, south, 1.3, 10, 3, 12, 6)
	station(stations, signs, "tabletop", "06 | SMALL TABLETOP", "INTERMEDIATE", "dirt",
		CFrame.lookAt(easyOrigin, easyOrigin + south), 25, 6,
		"Ride south: 1.3 m rise / 10 m takeoff / 3 m top / 12 m landing. 12 m approach. Flat side lanes bypass the jump.")
	for distance = 0, 10 do
		if distance % 10 == 0 then
			local p = position(22, ROAD_EPSILON_M, 10 + distance)
			referenceLine(signs, "SmallJumpRunout" .. distance .. "m", CFrame.lookAt(p, p + south), 6, WHITE)
		end
	end

	local whoopOrigin = position(10, ROAD_EPSILON_M, 37)
	profile(obstacles, "Whoop", whoopOrigin, west, 20, 4, "loam", function(distance)
		return 0.45 * math.sin(distance / 4 * math.pi) ^ 2
	end, 0.16)
	station(stations, signs, "whoops", "07 | FIVE MEASURED WHOOPS", "ADVANCED", "loam",
		CFrame.lookAt(whoopOrigin, whoopOrigin + west), 20, 4,
		"Ride west. Five rounded 0.45 m peaks, 4 m spacing. Stand and manage throttle / rider position. Flat bypass lanes flank the 4 m obstacle lane.")

	-- Independent jump branch: the lap circuit never requires this advanced
	-- obstacle. Its measured runout is open ground, not a wall or a spawn pad.
	span(terrain, "BigJumpLane", position(-2, ROAD_EPSILON_M, -49), position(-2, ROAD_EPSILON_M, 34), 8, "dirt")
	local bigOrigin = position(-2, ROAD_EPSILON_M, -31)
	tabletop(obstacles, "LargeJump", bigOrigin, south, 2.6, 18, 4, 20, 6)
	station(stations, signs, "large-jump", "08 | LARGE JUMP BRANCH", "ADVANCED", "dirt",
		CFrame.lookAt(bigOrigin, bigOrigin + south), 42, 6,
		"Ride south: 2.6 m rise / 18 m takeoff / 4 m top / 20 m landing. 18 m approach + 20 m clear runout. Inspect pitch, roll and tire loading.")
	for distance = 0, 20, 10 do
		local p = position(-2, ROAD_EPSILON_M, 11 + distance)
		referenceLine(signs, "LargeJumpRunout" .. distance .. "m", CFrame.lookAt(p, p + south), 8, if distance == 20 then TEAL else WHITE)
	end
	sign(signs, "LargeJumpLanding", CFrame.lookAt(position(5, 0, 11), position(4, 0, 11)),
		"LANDING + 20 m RUNOUT", "Check tire loads and crash state. Landing guides describe angles; they never correct the bike.")

	local surfaces = { "dirt", "sand", "mud", "hardpack" }
	for index, surface in surfaces do
		local z = -19 + (index - 1) * 9
		flat(terrain, surface .. "TractionPatch", 10, z, 6, 8, surface)
		local frame = CFrame.lookAt(position(10, ROAD_EPSILON_M, z - 4), position(10, ROAD_EPSILON_M, z - 3))
		station(stations, signs, "traction-" .. surface, string.upper(surface) .. " TRACTION PATCH", "FOUNDATION", surface,
			frame, 8, 6, "Ride south at a repeatable speed. Compare front brake washout, rear wheelspin, clutch and lean. Surface tags affect each tire independently.")
	end
	local pad = block(terrain, "FlatLowSpeedCornerPad", Vector3.new(m(0.2), m(16), m(16)),
		CFrame.new(position(10, ROAD_EPSILON_M, 23) - Vector3.yAxis * m(0.1)) * CFrame.Angles(0, 0, math.pi / 2),
		SURFACES.loam.color, SURFACES.loam.material, true)
	pad.Shape = Enum.PartType.Cylinder
	collisionSurface(pad, "loam")
	station(stations, signs, "corner-pad", "LOW-SPEED CORNER PAD", "FOUNDATION", "loam",
		CFrame.lookAt(position(10, ROAD_EPSILON_M, 15), position(10, ROAD_EPSILON_M, 16)), 16, 16,
		"Flat 16 m pad. Practice circles in either direction, feet, clutch and slow-speed steering. No hidden stabilizer or landing correction.")

	-- Gate normals point along clockwise travel. RaceRules accepts +local-Z
	-- to -local-Z crossings, so these frames preserve its existing contract.
	local points = {
		{ position(-22, ROAD_EPSILON_M, 16), north },
		{ position(-22, ROAD_EPSILON_M, -23), north },
		{ position(0, ROAD_EPSILON_M, -37), Vector3.xAxis },
		{ position(22, ROAD_EPSILON_M, -22), south },
		{ position(22, ROAD_EPSILON_M, 20), south },
		{ position(11, ROAD_EPSILON_M, 37), west },
		{ position(-11, ROAD_EPSILON_M, 37), west },
		{ position(-22, ROAD_EPSILON_M, 26), north },
	}
	local gates: { Gate } = {}
	local gateFolder = folder(lab, "DevelopmentLapGates")
	for index, data in points do
		local frame = CFrame.lookAt(data[1], data[1] + data[2])
		table.insert(gates, { cframe = frame, width = m(ROAD_WIDTH_M) })
		gate(gateFolder, frame, index)
	end
	return {
		gates = gates,
		checkpointCount = #gates,
		stations = stations,
		spawnCFrame = function(self: Course, slot: number): CFrame
			local safeSlot = math.clamp(math.floor(slot), 1, 8) - 1
			local laneM = (safeSlot % 4 - 1.5) * 1.8
			local rowM = math.floor(safeSlot / 4) * 3
			-- No platform or anchoring: manual feet support the stopped motorcycle.
			-- 3.2 studs puts the prototype COM just above its contact-rest height.
			return self.gates[1].cframe * CFrame.new(m(laneM), 3.2, m(6 + rowM))
		end,
	}
end

return TestTrack
