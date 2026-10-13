--!strict

-- Server-owned arcade bikes. Forces keep gravity and ramp launches intact;
-- an orientation constraint supplies the balance a two-wheel vehicle needs.
local Players = game:GetService("Players")

local Bikes = {}
Bikes.__index = Bikes

local TOP_SPEED = 100 -- studs/second (about 101 km/h)
local REVERSE_SPEED = 24
local ENGINE_ACCELERATION = 44
local BRAKE_ACCELERATION = 95
local INPUT_TIMEOUT = 0.5
local STUDS_TO_KMH = 0.28 * 3.6
local WHEEL_RADIUS = 1.05
local WHEEL_BASE = 1.75
local WHEEL_HEIGHT = -0.7

local ORANGE = Color3.fromRGB(255, 119, 34)
local TEAL = Color3.fromRGB(28, 218, 192)
local BLACK = Color3.fromRGB(23, 29, 35)
local METAL = Color3.fromRGB(148, 161, 172)

type BikeRecord = {
	model: Model,
	chassis: Part,
	seat: VehicleSeat,
	force: VectorForce,
	balance: AlignOrientation,
	connections: { RBXScriptConnection },
	wheels: { Motor6D },
	wheelOffsets: { CFrame },
	yaw: number,
	normal: Vector3,
	wheelAngle: number,
	wheelElapsed: number,
	throttle: number,
	steer: number,
	brake: boolean,
	lastInput: number,
	lastAcceptedInput: number,
	raycast: RaycastParams,
}

type Service = {
	_folder: Folder,
	_bikes: { [Player]: BikeRecord },
	spawn: (Service, Player, CFrame) -> Model,
	remove: (Service, Player) -> (),
	input: (Service, Player, number, number, boolean) -> (),
	update: (Service, number) -> (),
	getBike: (Service, Player) -> Model?,
	getSpeed: (Service, Player) -> number,
	getPosition: (Service, Player) -> Vector3?,
	isRiding: (Service, Player) -> boolean,
}

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function unitOr(vector: Vector3, fallback: Vector3): Vector3
	if vector.Magnitude > 0.001 then
		return vector.Unit
	end
	return fallback
end

local function weld(base: BasePart, part: BasePart)
	local connection = Instance.new("WeldConstraint")
	connection.Part0 = base
	connection.Part1 = part
	connection.Parent = part
end

local function cosmetic(
	model: Model,
	base: BasePart,
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = base.CFrame * localCFrame
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	weld(base, part)
	return part
end

local function rod(model: Model, base: BasePart, name: string, a: Vector3, b: Vector3, width: number, color: Color3)
	local midpoint = (a + b) / 2
	local localCFrame = CFrame.lookAt(midpoint, b) * CFrame.Angles(0, math.pi / 2, 0)
	local part = cosmetic(model, base, name, Vector3.new((b - a).Magnitude, width, width), localCFrame, color, Enum.Material.Metal)
	part.Shape = Enum.PartType.Cylinder
end

local function makeWheel(model: Model, chassis: Part, z: number, accent: Color3): (Motor6D, CFrame)
	local offset = CFrame.new(0, WHEEL_HEIGHT, z)
	local tire = Instance.new("Part")
	tire.Name = if z < 0 then "FrontTire" else "RearTire"
	tire.Shape = Enum.PartType.Cylinder
	tire.Size = Vector3.new(0.62, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2)
	tire.CFrame = chassis.CFrame * offset
	tire.Color = BLACK
	tire.Material = Enum.Material.Slate
	tire.CanCollide = false
	tire.CanTouch = false
	tire.CanQuery = false
	tire.Massless = true
	tire.Parent = model

	local motor = Instance.new("Motor6D")
	motor.Name = tire.Name .. "Axle"
	motor.Part0 = chassis
	motor.Part1 = tire
	motor.C0 = offset
	motor.Parent = chassis

	for _, x in { -0.33, 0.33 } do
		local rim = cosmetic(model, tire, "Rim", Vector3.new(0.05, 1.54, 1.54), CFrame.new(x, 0, 0), accent, Enum.Material.Metal)
		rim.Shape = Enum.PartType.Cylinder
		local inside = cosmetic(model, tire, "RimInset", Vector3.new(0.065, 1.32, 1.32), CFrame.new(x, 0, 0), BLACK)
		inside.Shape = Enum.PartType.Cylinder
		for spoke = 0, 5 do
			cosmetic(model, tire, "Spoke", Vector3.new(0.08, 0.055, 1.36), CFrame.new(x, 0, 0) * CFrame.Angles(spoke * math.pi / 6, 0, 0), METAL, Enum.Material.Metal)
		end
	end
	local hub = cosmetic(model, tire, "Hub", Vector3.new(0.8, 0.3, 0.3), CFrame.identity, METAL, Enum.Material.Metal)
	hub.Shape = Enum.PartType.Cylinder

	-- Rounded contact proxies avoid the snagging a welded, nonrolling cylinder
	-- causes on ramp seams. Their visual wheels remain narrow motorcycle tires.
	local contact = cosmetic(model, chassis, tire.Name .. "Contact", Vector3.one * (WHEEL_RADIUS * 2), offset, BLACK)
	contact.Shape = Enum.PartType.Ball
	contact.Transparency = 1
	contact.CanCollide = true
	contact.CustomPhysicalProperties = PhysicalProperties.new(1, 0.03, 0, 100, 1)
	return motor, offset
end

local function riding(player: Player, record: BikeRecord): boolean
	local humanoid = record.seat.Occupant
	return humanoid ~= nil and humanoid.Health > 0 and humanoid.Parent == player.Character
end

local function buildBike(player: Player, spawnCFrame: CFrame): BikeRecord
	local model = Instance.new("Model")
	model.Name = player.Name .. "_DirtBike"
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("BikeName", "Dirtline 250")

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(1.35, 0.85, 3.6)
	chassis.CFrame = spawnCFrame
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.RootPriority = 127
	chassis.CustomPhysicalProperties = PhysicalProperties.new(3, 0.03, 0, 100, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	cosmetic(model, chassis, "Engine", Vector3.new(0.9, 0.8, 1.15), CFrame.new(0, 0.05, 0.25), METAL, Enum.Material.Metal)
	cosmetic(model, chassis, "Tank", Vector3.new(0.95, 0.65, 1.45), CFrame.new(0, 0.75, -0.35) * CFrame.Angles(math.rad(-9), 0, 0), ORANGE)
	cosmetic(model, chassis, "Tail", Vector3.new(0.82, 0.22, 1.7), CFrame.new(0, 1.03, 0.9) * CFrame.Angles(math.rad(5), 0, 0), ORANGE)
	cosmetic(model, chassis, "FrontMudguard", Vector3.new(0.88, 0.15, 1.85), CFrame.new(0, 0.58, -1.65), ORANGE)
	cosmetic(model, chassis, "RearMudguard", Vector3.new(0.85, 0.15, 1.65), CFrame.new(0, 0.58, 1.65), TEAL)
	for _, x in { -0.43, 0.43 } do
		rod(model, chassis, "FrameRail", Vector3.new(x, -0.2, 0.8), Vector3.new(x, 0.7, -1.15), 0.14, ORANGE)
		rod(model, chassis, "Swingarm", Vector3.new(x, -0.1, 0.2), Vector3.new(x, WHEEL_HEIGHT, WHEEL_BASE), 0.16, METAL)
		rod(model, chassis, "FrontFork", Vector3.new(x * 0.8, WHEEL_HEIGHT, -WHEEL_BASE), Vector3.new(x * 0.8, 1.4, -1.05), 0.15, METAL)
		cosmetic(model, chassis, "SideNumberPlate", Vector3.new(0.09, 0.6, 0.95), CFrame.new(x * 1.3, 0.6, 0.7), TEAL)
		cosmetic(model, chassis, "FootPeg", Vector3.new(0.4, 0.13, 0.35), CFrame.new(x * 1.65, -0.1, 0.4), BLACK, Enum.Material.Metal)
	end
	rod(model, chassis, "Handlebar", Vector3.new(-0.95, 1.72, -1.03), Vector3.new(0.95, 1.72, -1.03), 0.12, METAL)
	for _, x in { -0.85, 0.85 } do
		local grip = cosmetic(model, chassis, "HandlebarGrip", Vector3.new(0.38, 0.18, 0.18), CFrame.new(x, 1.72, -1.03), BLACK)
		grip.Shape = Enum.PartType.Cylinder
	end
	rod(model, chassis, "ExhaustPipe", Vector3.new(0.54, 0.05, -0.2), Vector3.new(0.6, 0.68, 1.6), 0.2, METAL)
	local muffler = cosmetic(model, chassis, "Muffler", Vector3.new(0.95, 0.32, 0.32), CFrame.new(0.61, 0.73, 1.23) * CFrame.Angles(0, math.pi / 2, 0), BLACK, Enum.Material.Metal)
	muffler.Shape = Enum.PartType.Cylinder

	local plate = cosmetic(model, chassis, "FrontNumberPlate", Vector3.new(0.83, 0.65, 0.13), CFrame.new(0, 1.13, -1.33), Color3.fromRGB(244, 248, 251))
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Face = Enum.NormalId.Front
	plateGui.CanvasSize = Vector2.new(200, 150)
	plateGui.LightInfluence = 0.2
	plateGui.Parent = plate
	local plateText = Instance.new("TextLabel")
	plateText.Size = UDim2.fromScale(1, 1)
	plateText.BackgroundTransparency = 1
	plateText.Font = Enum.Font.GothamBlack
	plateText.Text = "MX"
	plateText.TextScaled = true
	plateText.TextColor3 = BLACK
	plateText.Parent = plateGui

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(0.86, 0.24, 1.5)
	seat.CFrame = chassis.CFrame * CFrame.new(0, 1.17, 0.5)
	seat.Color = BLACK
	seat.Material = Enum.Material.SmoothPlastic
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model
	weld(chassis, seat)

	local frontWheel, frontOffset = makeWheel(model, chassis, -WHEEL_BASE, ORANGE)
	local rearWheel, rearOffset = makeWheel(model, chassis, WHEEL_BASE, TEAL)
	local attachment = Instance.new("Attachment")
	attachment.Name = "BikeCenter"
	attachment.Parent = chassis
	local force = Instance.new("VectorForce")
	force.Name = "EngineAndGrip"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Parent = chassis
	local balance = Instance.new("AlignOrientation")
	balance.Name = "RiderBalance"
	balance.Mode = Enum.OrientationAlignmentMode.OneAttachment
	balance.Attachment0 = attachment
	balance.MaxTorque = 10000000
	balance.MaxAngularVelocity = 7
	balance.Responsiveness = 22
	balance.RigidityEnabled = false
	balance.CFrame = spawnCFrame.Rotation
	balance.Parent = chassis

	local look = spawnCFrame.LookVector
	local direction = unitOr(Vector3.new(look.X, 0, look.Z), Vector3.new(0, 0, -1))
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.RespectCanCollide = true
	return {
		model = model,
		chassis = chassis,
		seat = seat,
		force = force,
		balance = balance,
		connections = {},
		wheels = { frontWheel, rearWheel },
		wheelOffsets = { frontOffset, rearOffset },
		yaw = math.atan2(-direction.X, -direction.Z),
		normal = Vector3.yAxis,
		wheelAngle = 0,
		wheelElapsed = 0,
		throttle = 0,
		steer = 0,
		brake = true,
		lastInput = -math.huge,
		lastAcceptedInput = -math.huge,
		raycast = raycast,
	}
end

function Bikes.new(world: Instance): Service
	local folder = Instance.new("Folder")
	folder.Name = "DirtBikes"
	folder.Parent = world
	return setmetatable({ _folder = folder, _bikes = {} }, Bikes) :: any
end

function Bikes.spawn(self: Service, player: Player, spawnCFrame: CFrame): Model
	self:remove(player)
	local record = buildBike(player, spawnCFrame)
	self._bikes[player] = record
	record.model.Parent = self._folder
	-- Keep both the bike and its seated rider under server physics authority.
	record.chassis:SetNetworkOwner(nil)

	local function seatCharacter(character: Model)
		local function attempt(humanoid: Humanoid)
			if self._bikes[player] ~= record or player.Character ~= character or humanoid.Health <= 0 then
				return
			end
			character:PivotTo(record.seat.CFrame * CFrame.new(0, 3, 0))
			record.seat:Sit(humanoid)
			task.delay(0.2, function()
				if self._bikes[player] == record and player.Character == character and humanoid.Health > 0 and record.seat.Occupant == nil then
					record.seat:Sit(humanoid)
				end
			end)
		end
		local pending: RBXScriptConnection? = nil
		local function whenReady(): boolean
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoid and rootPart and rootPart:IsA("BasePart") then
				if pending then pending:Disconnect() end
				attempt(humanoid)
				return true
			end
			return false
		end
		if whenReady() then return end
		pending = character.ChildAdded:Connect(function()
			whenReady()
		end)
		table.insert(record.connections, pending :: RBXScriptConnection)
		task.delay(8, function()
			if pending then pending:Disconnect() end
		end)
	end

	table.insert(record.connections, player.CharacterAdded:Connect(seatCharacter))
	table.insert(record.connections, record.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = record.seat.Occupant
		if occupant and occupant.Parent ~= player.Character then
			occupant.Sit = false
		end
		-- Seating changes the assembly; reaffirm server authority for it.
		if record.chassis:IsDescendantOf(workspace) and record.chassis:CanSetNetworkOwnership() then
			record.chassis:SetNetworkOwner(nil)
		end
		record.throttle = 0
		record.steer = 0
		record.brake = true
		record.lastInput = -math.huge
	end))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RidePrompt"
	prompt.ActionText = "Ride"
	prompt.ObjectText = "Dirtline 250"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = record.seat
	table.insert(record.connections, prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer == player and not riding(player, record) and player.Character then
			seatCharacter(player.Character)
		end
	end))
	if player.Character then
		task.defer(seatCharacter, player.Character)
	end
	return record.model
end

function Bikes.remove(self: Service, player: Player)
	local record = self._bikes[player]
	if not record then return end
	self._bikes[player] = nil
	for _, connection in record.connections do connection:Disconnect() end
	if record.seat.Occupant then record.seat.Occupant.Sit = false end
	record.model:Destroy()
end

function Bikes.input(self: Service, player: Player, throttle: number, steer: number, brake: boolean)
	local record = self._bikes[player]
	if not record or not riding(player, record) then return end
	-- Remote arguments still need runtime validation despite the Luau signature.
	if typeof(throttle) ~= "number" or typeof(steer) ~= "number" or typeof(brake) ~= "boolean" then return end
	if not finite(throttle) or not finite(steer) then return end
	local now = os.clock()
	if now - record.lastAcceptedInput < 1 / 120 then return end
	record.lastAcceptedInput = now
	record.lastInput = now
	record.throttle = math.clamp(throttle, -1, 1)
	record.steer = math.clamp(steer, -1, 1)
	record.brake = brake
end

function Bikes.update(self: Service, frameDt: number)
	if not finite(frameDt) or frameDt <= 0 then return end
	-- Limit steering integration after a server stall, while avoiding a force
	-- impulse from dividing by a nearly zero timestep.
	local dt = math.clamp(frameDt, 1 / 240, 1 / 20)
	local now = os.clock()
	local exclusions: { Instance } = { self._folder }
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer.Character then table.insert(exclusions, otherPlayer.Character) end
	end
	for player, record in self._bikes do
		local chassis = record.chassis
		if not chassis.Parent then continue end
		record.raycast.FilterDescendantsInstances = exclusions
		local grounded = false
		local normalSum = Vector3.zero
		for _, z in { -WHEEL_BASE, WHEEL_BASE } do
			local center = chassis.CFrame:PointToWorldSpace(Vector3.new(0, WHEEL_HEIGHT, z))
			local hit = workspace:Raycast(center + Vector3.yAxis * 3, -Vector3.yAxis * 5.2, record.raycast)
			if hit and center.Y - hit.Position.Y <= WHEEL_RADIUS + 0.42 and center.Y - hit.Position.Y >= -0.2 and hit.Normal.Y > 0.35 then
				grounded = true
				normalSum += hit.Normal
			end
		end
		local targetNormal = if grounded then unitOr(normalSum, Vector3.yAxis) else Vector3.yAxis
		local blend = 1 - math.exp(-dt * (if grounded then 12 else 2.8))
		record.normal = unitOr(record.normal:Lerp(targetNormal, blend), Vector3.yAxis)

		local active = riding(player, record) and now - record.lastInput <= INPUT_TIMEOUT
		local throttle = if active then record.throttle else 0
		local steer = if active then record.steer else 0
		local braking = not active or record.brake
		local velocity = chassis.AssemblyLinearVelocity
		local horizontalHeading = Vector3.new(-math.sin(record.yaw), 0, -math.cos(record.yaw))
		local forward = unitOr(horizontalHeading - record.normal * horizontalHeading:Dot(record.normal), horizontalHeading)
		local speed = velocity:Dot(forward)
		local speedFraction = math.clamp(math.abs(speed) / TOP_SPEED, 0, 1)
		local movementSign = if speed < -1 then -1 else 1
		local turnRate = math.rad(125) * (1 - 0.3 * speedFraction) * math.clamp(math.abs(speed) / 10, 0, 1)
		record.yaw -= steer * movementSign * turnRate * dt * (if grounded then 1 else 0.25)
		horizontalHeading = Vector3.new(-math.sin(record.yaw), 0, -math.cos(record.yaw))
		forward = unitOr(horizontalHeading - record.normal * horizontalHeading:Dot(record.normal), horizontalHeading)
		local lean = -steer * movementSign * math.rad(14) * speedFraction * (if grounded then 1 else 0.3)
		record.balance.CFrame = CFrame.lookAt(Vector3.zero, forward, record.normal) * CFrame.Angles(0, 0, lean)

		if grounded then
			local acceleration: number
			if braking then
				acceleration = -math.sign(speed) * math.min(BRAKE_ACCELERATION, math.abs(speed) / dt)
			elseif math.abs(throttle) > 0.01 then
				local targetSpeed = throttle * (if throttle > 0 then TOP_SPEED else REVERSE_SPEED)
				local limit = if throttle * speed < -3 then BRAKE_ACCELERATION * 0.75 else ENGINE_ACCELERATION
				acceleration = math.clamp((targetSpeed - speed) * 3, -limit, limit)
			else
				acceleration = -speed * 0.65
			end
			local right = unitOr(forward:Cross(record.normal), chassis.CFrame.RightVector)
			local lateralAcceleration = -velocity:Dot(right) * 9
			record.force.Force = (forward * acceleration + right * lateralAcceleration) * chassis.AssemblyMass
		else
			-- Ballistic airtime: the engine never cancels vertical launch velocity.
			record.force.Force = Vector3.zero
		end

		-- A collision or a steep descent can exceed engine speed. This generous
		-- safety cap affects horizontal travel only, preserving jump/fall velocity.
		local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		if horizontalVelocity.Magnitude > TOP_SPEED * 1.6 then
			local limited = horizontalVelocity.Unit * TOP_SPEED * 1.6
			chassis.AssemblyLinearVelocity = Vector3.new(limited.X, velocity.Y, limited.Z)
		end
		record.wheelAngle = (record.wheelAngle - speed * dt / WHEEL_RADIUS) % (2 * math.pi)
		record.wheelElapsed += frameDt
		if record.wheelElapsed >= 1 / 20 then
			record.wheelElapsed = 0
			for index, motor in record.wheels do
				motor.C0 = record.wheelOffsets[index] * CFrame.Angles(record.wheelAngle, 0, 0)
			end
		end
	end
end

function Bikes.getBike(self: Service, player: Player): Model?
	local record = self._bikes[player]
	return if record then record.model else nil
end

function Bikes.getSpeed(self: Service, player: Player): number
	local record = self._bikes[player]
	if not record then return 0 end
	local velocity = record.chassis.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude * STUDS_TO_KMH
end

function Bikes.getPosition(self: Service, player: Player): Vector3?
	local record = self._bikes[player]
	return if record then record.chassis.Position else nil
end

function Bikes.isRiding(self: Service, player: Player): boolean
	local record = self._bikes[player]
	return record ~= nil and riding(player, record)
end

return Bikes
