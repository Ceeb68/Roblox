--!strict
-- A self-contained course built entirely from Roblox primitives.

local Track = {}

export type Gate = {
	cframe: CFrame,
	width: number,
}

export type Course = {
	gates: { Gate },
	checkpointCount: number,
	spawnCFrame: (self: Course, slot: number) -> CFrame,
}

local ROAD_WIDTH = 38
local ROAD_HEIGHT = 1
local ORANGE = Color3.fromRGB(255, 122, 45)
local TEAL = Color3.fromRGB(38, 209, 190)
local INK = Color3.fromRGB(27, 39, 42)
local WHITE = Color3.fromRGB(249, 245, 232)
local DIRT = Color3.fromRGB(145, 97, 59)

local POINTS = {
	Vector3.new(-180, ROAD_HEIGHT, -100),
	Vector3.new(-80, ROAD_HEIGHT, -130),
	Vector3.new(50, ROAD_HEIGHT, -130),
	Vector3.new(170, ROAD_HEIGHT, -100),
	Vector3.new(200, ROAD_HEIGHT, 0),
	Vector3.new(160, ROAD_HEIGHT, 110),
	Vector3.new(50, ROAD_HEIGHT, 140),
	Vector3.new(-80, ROAD_HEIGHT, 130),
	Vector3.new(-190, ROAD_HEIGHT, 70),
	Vector3.new(-210, ROAD_HEIGHT, -20),
}

local function folder(parent: Instance, name: string): Folder
	local result = Instance.new("Folder")
	result.Name = name
	result.Parent = parent
	return result
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean?
): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Size = size
	result.CFrame = cframe
	result.Color = color
	result.Material = material
	result.Anchored = true
	result.CanCollide = if canCollide == nil then true else canCollide
	result.CanTouch = result.CanCollide
	result.TopSurface = Enum.SurfaceType.Smooth
	result.BottomSurface = Enum.SurfaceType.Smooth
	result.Parent = parent
	return result
end

local function sign(board: BasePart, face: Enum.NormalId, title: string, subtitle: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.LightInfluence = 0.15
	gui.Parent = board
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromScale(0.94, 0.61)
	titleLabel.Position = UDim2.fromScale(0.03, 0.04)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = title
	titleLabel.TextColor3 = WHITE
	titleLabel.TextScaled = true
	titleLabel.Parent = gui
	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.fromScale(0.94, 0.25)
	subtitleLabel.Position = UDim2.fromScale(0.03, 0.68)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = TEAL
	subtitleLabel.TextScaled = true
	subtitleLabel.Parent = gui
end

-- The surface's end points describe the top of each slope. Subtracting
-- half the thickness along its normal keeps those points flush with the road.
local function slope(parent: Instance, name: string, from: Vector3, to: Vector3, width: number)
	local surfaceFrame = CFrame.lookAt((from + to) / 2, to)
	local thickness = 0.8
	local ramp = part(
		parent,
		name,
		Vector3.new(width, thickness, (to - from).Magnitude),
		surfaceFrame * CFrame.new(0, -thickness / 2, 0),
		DIRT,
		Enum.Material.Ground
	)
	-- The bike's contact material sets sliding resistance; lateral grip is
	-- supplied by its controller so welded contact spheres can roll over seams.
	ramp.CustomPhysicalProperties = PhysicalProperties.new(1, 0.15, 0, 1, 1)
end

local function tabletop(parent: Instance, origin: Vector3, forward: Vector3, number: number, height: number)
	local rampFolder = folder(parent, "Jump" .. number)
	local riseLength = 22
	local crestLength = 5
	local landingLength = 26
	local top = origin + forward * riseLength + Vector3.new(0, height, 0)
	local farTop = top + forward * crestLength
	local finish = farTop + forward * landingLength - Vector3.new(0, height, 0)
	slope(rampFolder, "Takeoff", origin, top, ROAD_WIDTH)
	slope(rampFolder, "Crest", top, farTop, ROAD_WIDTH)
	slope(rampFolder, "Landing", farTop, finish, ROAD_WIDTH)
	local right = forward:Cross(Vector3.yAxis)
	for _, side in { -1, 1 } do
		local markerPosition = origin + right * (ROAD_WIDTH / 2 + 3) * side
		part(rampFolder, "JumpMarker", Vector3.new(0.8, 5, 0.8), CFrame.new(markerPosition + Vector3.new(0, 2.5, 0)), ORANGE, Enum.Material.SmoothPlastic)
		local flag = part(rampFolder, "JumpFlag", Vector3.new(2.8, 1.8, 0.2), CFrame.lookAt(markerPosition + Vector3.new(0, 4.2, 0), markerPosition + forward + Vector3.new(0, 4.2, 0)), ORANGE, Enum.Material.SmoothPlastic, false)
		sign(flag, Enum.NormalId.Front, "JUMP", tostring(number))
	end
end

local function gate(parent: Instance, frame: CFrame, index: number)
	local model = folder(parent, if index == 1 then "StartFinish" else "Checkpoint" .. index)
	for _, side in { -1, 1 } do
		local color = if side < 0 then ORANGE else TEAL
		part(model, "Post", Vector3.new(2.2, 14, 2.2), frame * CFrame.new(side * (ROAD_WIDTH / 2 + 4), 7, 0), color, Enum.Material.SmoothPlastic)
		part(model, "PostFoot", Vector3.new(4, 0.7, 4), frame * CFrame.new(side * (ROAD_WIDTH / 2 + 4), 0.35, 0), INK, Enum.Material.Metal)
		part(model, "Light", Vector3.new(2.3, 0.45, 2.3), frame * CFrame.new(side * (ROAD_WIDTH / 2 + 4), 11.5, 0), WHITE, Enum.Material.Neon, false)
	end
	local board = part(model, "OverheadSign", Vector3.new(ROAD_WIDTH + 10, 5, 1.1), frame * CFrame.new(0, 14, 0), INK, Enum.Material.SmoothPlastic, false)
	local title = if index == 1 then "DIRTLINE MX" else string.format("CHECKPOINT %02d", index)
	local subtitle = if index == 1 then "START / FINISH" else "KEEP THE DIRT FLYING"
	sign(board, Enum.NormalId.Front, title, subtitle)
	sign(board, Enum.NormalId.Back, title, subtitle)
	if index == 1 then
		for row = 0, 1 do
			for column = 0, 11 do
				local color = if (row + column) % 2 == 0 then WHITE else INK
				part(model, "FinishTile", Vector3.new(ROAD_WIDTH / 12, 0.035, 1.8), frame * CFrame.new(-ROAD_WIDTH / 2 + (column + 0.5) * ROAD_WIDTH / 12, 0.025, (row - 0.5) * 1.8), color, Enum.Material.SmoothPlastic, false)
			end
		end
	else
		part(model, "CheckpointLine", Vector3.new(ROAD_WIDTH, 0.035, 0.7), frame * CFrame.new(0, 0.025, 0), TEAL, Enum.Material.SmoothPlastic, false)
	end
end

local function fenceLine(parent: Instance, from: Vector3, to: Vector3)
	local delta = to - from
	local sections = math.ceil(delta.Magnitude / 24)
	local forward = delta.Unit
	for index = 0, sections do
		local position = from:Lerp(to, index / sections)
		part(parent, "FencePost", Vector3.new(1.4, 5, 1.4), CFrame.new(position + Vector3.new(0, 2.5, 0)), Color3.fromRGB(95, 73, 51), Enum.Material.Wood)
	end
	for index = 1, sections do
		local a = from:Lerp(to, (index - 1) / sections)
		local b = from:Lerp(to, index / sections)
		for _, height in { 1.8, 3.8 } do
			part(parent, "FenceRail", Vector3.new(0.55, 0.55, (b - a).Magnitude + 0.5), CFrame.lookAt((a + b) / 2 + Vector3.new(0, height, 0), (a + b) / 2 + forward + Vector3.new(0, height, 0)), Color3.fromRGB(154, 119, 78), Enum.Material.Wood)
		end
	end
end

local function tree(parent: Instance, position: Vector3, height: number)
	part(parent, "Trunk", Vector3.new(2.4, height * 0.58, 2.4), CFrame.new(position + Vector3.new(0, height * 0.29, 0)), Color3.fromRGB(105, 78, 51), Enum.Material.Wood)
	for tier = 0, 2 do
		local radius = height * (0.46 - tier * 0.08)
		local crown = part(parent, "Foliage", Vector3.new(radius, height * 0.36, radius), CFrame.new(position + Vector3.new(0, height * (0.55 + tier * 0.17), 0)), if tier % 2 == 0 then Color3.fromRGB(58, 102, 67) else Color3.fromRGB(79, 124, 68), Enum.Material.Grass)
		crown.Shape = Enum.PartType.Ball
	end
end

local function scenery(parent: Instance)
	local fences = folder(parent, "PerimeterFence")
	local corners = {
		Vector3.new(-270, 0, -205),
		Vector3.new(270, 0, -205),
		Vector3.new(270, 0, 210),
		Vector3.new(-270, 0, 210),
	}
	for index, position in corners do
		fenceLine(fences, position, corners[index % #corners + 1])
	end
	local trees = folder(parent, "Trees")
	for index = 1, 48 do
		local angle = index / 48 * math.pi * 2
		local radius = 305 + (index % 4) * 17
		tree(trees, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius * 0.83), 17 + (index % 5) * 3)
	end
	local mountains = folder(parent, "Mountains")
	for index = 1, 16 do
		local angle = index / 16 * math.pi * 2
		local height = 62 + (index % 5) * 17
		local radius = 420 + (index % 3) * 13
		local position = Vector3.new(math.cos(angle) * radius, height / 2 - 12, math.sin(angle) * radius * 0.83)
		local peak = Instance.new("WedgePart")
		peak.Name = "Mountain"
		peak.Size = Vector3.new(100 + (index % 3) * 22, height, 115)
		peak.CFrame = CFrame.new(position) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		peak.Color = if index % 2 == 0 then Color3.fromRGB(96, 111, 103) else Color3.fromRGB(113, 125, 110)
		peak.Material = Enum.Material.Slate
		peak.Anchored = true
		peak.CanTouch = false
		peak.Parent = mountains
	end
end

local function pit(parent: Instance, start: CFrame)
	local paddock = folder(parent, "Paddock")
	local frame = start * CFrame.new(64, -ROAD_HEIGHT, 6)
	part(paddock, "PitApron", Vector3.new(62, 0.4, 62), frame * CFrame.new(0, 0.2, 0), Color3.fromRGB(123, 120, 109), Enum.Material.Concrete)
	for index = 1, 2 do
		local tent = frame * CFrame.new((index - 1.5) * 29, 0, -13)
		local color = if index == 1 then ORANGE else TEAL
		for _, x in { -11, 11 } do
			for _, z in { -9, 9 } do
				part(paddock, "TentLeg", Vector3.new(0.6, 10, 0.6), tent * CFrame.new(x, 5, z), INK, Enum.Material.Metal)
			end
		end
		part(paddock, "TentRoof", Vector3.new(25, 1.2, 21), tent * CFrame.new(0, 10.4, 0), color, Enum.Material.SmoothPlastic)
		local banner = part(paddock, "TeamBanner", Vector3.new(22, 2.4, 0.2), tent * CFrame.new(0, 8.8, 9.6), INK, Enum.Material.SmoothPlastic, false)
		sign(banner, Enum.NormalId.Back, if index == 1 then "DIRTLINE RACING" else "THE RIDER PADDOCK", "RIDE  •  JUMP  •  RACE")
		part(paddock, "Workbench", Vector3.new(14, 1, 4), tent * CFrame.new(0, 3, -5), Color3.fromRGB(174, 140, 92), Enum.Material.Wood)
		for _, x in { -5, 5 } do
			part(paddock, "WorkbenchLeg", Vector3.new(1, 3, 3), tent * CFrame.new(x, 1.5, -5), INK, Enum.Material.Metal)
		end
		part(paddock, "ToolChest", Vector3.new(5, 3.5, 3), tent * CFrame.new(7, 2.15, 3), color, Enum.Material.Metal)
	end
	for row = 1, 3 do
		local bench = frame * CFrame.new(0, 0, 10 + row * 5)
		part(paddock, "SpectatorBench", Vector3.new(42, 0.7, 2.8), bench * CFrame.new(0, 1.5 + row * 0.45, 0), Color3.fromRGB(174, 140, 92), Enum.Material.Wood)
		for _, x in { -17, 0, 17 } do
			part(paddock, "BenchLeg", Vector3.new(1.2, 1.5 + row * 0.45, 1.8), bench * CFrame.new(x, (1.5 + row * 0.45) / 2, 0), INK, Enum.Material.Metal)
		end
	end
	for index, height in { 2.5, 4, 1.5 } do
		local podium = part(paddock, "Podium", Vector3.new(6, height, 5), frame * CFrame.new((index - 2) * 6.4, height / 2 + 0.4, 6), if index == 2 then ORANGE else TEAL, Enum.Material.SmoothPlastic)
		sign(podium, Enum.NormalId.Back, tostring(if index == 1 then 2 elseif index == 2 then 1 else 3), "MX")
	end
end

function Track.build(world: Instance): Course
	local courseFolder = folder(world, "DirtlineMX")
	part(courseFolder, "Ground", Vector3.new(1060, 2, 1060), CFrame.new(0, -1, 0), Color3.fromRGB(99, 130, 77), Enum.Material.Grass)
	local road = folder(courseFolder, "Circuit")
	local checkpoints = folder(courseFolder, "Gates")
	local jumps = folder(courseFolder, "Jumps")
	local gates: { Gate } = {}
	local jumpNumber = 0
	for index, from in POINTS do
		local to = POINTS[index % #POINTS + 1]
		local delta = to - from
		local forward = delta.Unit
		local midpoint = (from + to) / 2
		local frame = CFrame.lookAt(midpoint, midpoint + forward)
		local shoulder = part(road, "DirtShoulder" .. index, Vector3.new(ROAD_WIDTH + 9, 0.24, delta.Magnitude + 4), frame * CFrame.new(0, -0.88, 0), Color3.fromRGB(163, 119, 76), Enum.Material.Ground)
		shoulder.CanTouch = false
		local surface = part(road, "Straight" .. index, Vector3.new(ROAD_WIDTH, 1, delta.Magnitude + 3), frame * CFrame.new(0, -0.5, 0), DIRT, Enum.Material.Ground)
		surface.CustomPhysicalProperties = PhysicalProperties.new(1, 0.15, 0, 1, 1)
		local corner = part(road, "WideCorner" .. index, Vector3.new(1, ROAD_WIDTH + 8, ROAD_WIDTH + 8), CFrame.new(from - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), DIRT, Enum.Material.Ground)
		corner.Shape = Enum.PartType.Cylinder
		corner.CustomPhysicalProperties = surface.CustomPhysicalProperties
		-- The outside edge rises gently; the full road remains unobstructed.
		local bermFrame = frame * CFrame.new(-(ROAD_WIDTH / 2 + 3), 0.25, 0) * CFrame.Angles(0, 0, -math.rad(12))
		part(road, "OutsideBerm" .. index, Vector3.new(6, 0.8, math.max(12, delta.Magnitude - 24)), bermFrame, Color3.fromRGB(133, 88, 53), Enum.Material.Ground)
		-- Four easy tabletop jumps leave a flat approach to the next gate.
		if index == 2 or index == 4 or index == 7 or index == 9 then
			jumpNumber += 1
			local jumpOrigin = from + forward * 12
			tabletop(jumps, jumpOrigin, forward, jumpNumber, if index == 9 then 3 else 4)
		end
		local gateFraction = if index == 1 then 0.6 else 0.83
		local gatePosition = from + delta * gateFraction
		local gateFrame = CFrame.lookAt(gatePosition, gatePosition + forward)
		table.insert(gates, { cframe = gateFrame, width = ROAD_WIDTH })
		gate(checkpoints, gateFrame, index)
	end
	local decorations = folder(courseFolder, "Scenery")
	scenery(decorations)
	pit(decorations, gates[1].cframe)
	local result: Course = {
		gates = gates,
		checkpointCount = #gates,
		spawnCFrame = function(self: Course, slot: number): CFrame
			local safeSlot = math.clamp(math.floor(slot), 1, 8) - 1
			local lane = (safeSlot % 4 - 1.5) * 6
			local row = math.floor(safeSlot / 4)
			return self.gates[1].cframe * CFrame.new(lane, 4, 24 + row * 6)
		end,
	}
	return result
end

return Track
