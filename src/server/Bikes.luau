--!strict
-- Phase 1 SI adapter. Roblox advances the native, unanchored rigid body.
-- PreSimulation samples geometry once; tyre/drivetrain state uses 240Hz steps.
-- Roblox itself is NOT claimed to have a guaranteed 240Hz rigid-body timestep.
-- No attitude targets, steering/landing corrections, velocity locks or speed cap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Physics = ReplicatedStorage:WaitForChild("Motocross"):WaitForChild("Physics")
local Bike250 = require(Physics:WaitForChild("Bike250"))
local Drivetrain = require(Physics:WaitForChild("Drivetrain"))
local Suspension = require(Physics:WaitForChild("Suspension"))
local Tire = require(Physics:WaitForChild("Tire"))
local WheelContact = require(Physics:WaitForChild("WheelContact"))
local StepBudget = require(Physics:WaitForChild("StepBudget"))
local Controls = require(Physics:WaitForChild("Controls"))
local Crash = require(Physics:WaitForChild("Crash"))

local Bikes = {}
Bikes.__index = Bikes
local INPUT_TIMEOUT = 0.5
local ORANGE = Color3.fromRGB(255, 119, 34)
local TEAL = Color3.fromRGB(28, 218, 192)
local BLACK = Color3.fromRGB(23, 29, 35)
local METAL = Color3.fromRGB(148, 161, 172)
type Record = any
type Service = any

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end
local function unitOr(vector: Vector3, fallback: Vector3): Vector3
	return if vector.Magnitude > 1e-6 then vector.Unit else fallback
end
local function clone(value: any): any
	if typeof(value) ~= "table" then return value end
	local result = {}
	for key, child in value do result[key] = clone(child) end
	return result
end
local function idleInput(footDown: boolean, standing: boolean): any
	return { throttle = 0, frontBrake = 0, rearBrake = 0, clutch = 1,
		steer = 0, lean = 0, bodyForward = 0, bodySide = 0,
		standing = standing, footDown = footDown, shift = 0, seq = 0 }
end
local function motor(base: BasePart, part: BasePart, offset: CFrame): Motor6D
	local joint = Instance.new("Motor6D")
	joint.Name = part.Name .. "Joint"; joint.Part0 = base; joint.Part1 = part
	joint.C0 = offset; joint.Parent = base
	return joint
end
local function cosmetic(model: Model, chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name; part.Size = size; part.CFrame = chassis.CFrame * offset
	part.Color = color; part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false; part.CanTouch = false; part.CanQuery = false; part.Massless = true
	part.Parent = model
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = chassis; joint.Part1 = part; joint.Parent = part
	return part
end
local function massProperties(part: BasePart, mass: number, friction: number)
	part.CustomPhysicalProperties = PhysicalProperties.new(mass / (part.Size.X * part.Size.Y * part.Size.Z), friction, 0, 100, 100)
end
local function updateLink(link: any, a: Vector3, b: Vector3, width: number, m: number)
	local length = math.max((b - a).Magnitude, 0.01)
	link.part.Size = Vector3.new(length, width, width) / m
	link.joint.C0 = CFrame.lookAt((a + b) / (2 * m), b / m) * CFrame.Angles(0, math.pi / 2, 0)
end
local function makeLink(model: Model, chassis: Part, name: string, a: Vector3, b: Vector3, width: number, m: number): any
	local part = Instance.new("Part")
	part.Name = name; part.Shape = Enum.PartType.Cylinder; part.Color = METAL; part.Material = Enum.Material.Metal
	part.CanCollide = false; part.CanTouch = false; part.CanQuery = false; part.Massless = true; part.Parent = model
	local link = { part = part, joint = motor(chassis, part, CFrame.identity) }
	updateLink(link, a, b, width, m)
	part.CFrame = chassis.CFrame * link.joint.C0
	return link
end
local function applyForce(record: Record, forceN: Vector3, point: Vector3, dt: number)
	-- Native mass is kg; native length is studs. F_native = F_SI / m_per_stud.
	record.chassis:ApplyImpulseAtPosition(forceN * (dt / record.cfg.MetresPerStud), point)
end
local function applyAngular(record: Record, momentumSI: Vector3)
	record.chassis:ApplyAngularImpulse(momentumSI / (record.cfg.MetresPerStud ^ 2))
end

local POSE_ATTRIBUTES = { "MotocrossRiding", "MotocrossStanding", "MotocrossBodyForward", "MotocrossBodySide", "MotocrossLean" }
local function restoreCharacter(record: Record)
	if record.characterConnection then record.characterConnection:Disconnect(); record.characterConnection = nil end
	for part, saved in record.characterParts do
		if part.Parent then part.CanCollide = saved.CanCollide; part.Massless = saved.Massless end
	end
	record.characterParts = {}
	if record.character then
		for _, name in POSE_ATTRIBUTES do record.character:SetAttribute(name, nil) end
	end
	record.character = nil
end
local function makeCharacterMassless(record: Record, character: Model)
	restoreCharacter(record)
	record.character = character
	local function prepare(instance: Instance)
		if instance:IsA("BasePart") then
			record.characterParts[instance] = { CanCollide = instance.CanCollide, Massless = instance.Massless }
			instance.CanCollide = false; instance.Massless = true
		end
	end
	for _, instance in character:GetDescendants() do prepare(instance) end
	record.characterConnection = character.DescendantAdded:Connect(prepare)
	character:SetAttribute("MotocrossRiding", true)
end
local function riding(player: Player, record: Record): boolean
	local occupant = record.seat.Occupant
	return not record.crashed and occupant ~= nil and occupant.Health > 0 and occupant.Parent == player.Character
end

local function wheel(model: Model, chassis: Part, radius: number, z: number, front: boolean, m: number): Motor6D
	local part = Instance.new("Part")
	part.Name = if front then "FrontTire" else "RearTire"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(if front then 0.085 / m else 0.115 / m, radius * 2 / m, radius * 2 / m)
	part.Color = BLACK; part.Material = Enum.Material.Slate; part.Massless = true
	part.CanCollide = false; part.CanTouch = false; part.CanQuery = false; part.Parent = model
	local offset = CFrame.new(0, -0.44 / m, z / m)
	part.CFrame = chassis.CFrame * offset
	local joint = motor(chassis, part, offset)
	local rim = cosmetic(model, part, "Rim", Vector3.new(0.06, radius * 1.5, radius * 1.5) / m, CFrame.identity, METAL)
	rim.Shape = Enum.PartType.Cylinder
	-- No wheel/sphere colliders secretly supporting the bike: tyre rays carry it.
	return joint
end

local function buildBike(player: Player, spawnCFrame: CFrame): Record
	local cfg = clone(Bike250)
	local m = cfg.MetresPerStud
	local model = Instance.new("Model")
	model.Name = player.Name .. "_250F"
	model:SetAttribute("OwnerUserId", player.UserId); model:SetAttribute("BikeName", cfg.Name)
	model:SetAttribute("PhysicsVersion", cfg.Version); model:SetAttribute("Assists", false)
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"; chassis.Size = Vector3.new(0.30, 0.45, 1.20) / m
	chassis.CFrame = spawnCFrame; chassis.Transparency = 1; chassis.CanCollide = true; chassis.RootPriority = 127
	massProperties(chassis, cfg.BikeMass, 0.12); chassis.Parent = model; model.PrimaryPart = chassis
	cosmetic(model, chassis, "Engine", Vector3.new(0.24, 0.30, 0.34) / m, CFrame.new(0, 0.01 / m, 0), METAL)
	cosmetic(model, chassis, "Tank", Vector3.new(0.25, 0.22, 0.37) / m, CFrame.new(0, 0.28 / m, -0.16 / m), ORANGE)
	cosmetic(model, chassis, "FrontMudguard", Vector3.new(0.22, 0.035, 0.55) / m, CFrame.new(0, 0.07 / m, -0.72 / m), ORANGE)
	cosmetic(model, chassis, "RearMudguard", Vector3.new(0.23, 0.035, 0.52) / m, CFrame.new(0, 0.31 / m, 0.56 / m), TEAL)
	cosmetic(model, chassis, "Handlebar", Vector3.new(0.80, 0.05, 0.05) / m, CFrame.new(0, 0.47 / m, -0.38 / m), METAL)
	local guards = {}
	for _, side in { -1, 1 } do
		local guard = cosmetic(model, chassis, "CrashGuard", Vector3.new(0.06, 0.08, 0.15) / m, CFrame.new(side * 0.24 / m, 0.08 / m, 0), BLACK)
		guard.CanCollide = true; guard.CanTouch = true
		guard.CustomPhysicalProperties = PhysicalProperties.new(1, 0.12, 0, 100, 100)
		table.insert(guards, guard)
	end
	local seat = Instance.new("Seat") -- rider attachment only, never VehicleSeat propulsion
	seat.Name = "DriverSeat"; seat.Size = Vector3.new(0.23, 0.07, 0.48) / m
	seat.CFrame = chassis.CFrame * CFrame.new(0, 0.35 / m, 0.20 / m); seat.Color = BLACK
	seat.CanCollide = false; seat.CanTouch = false; seat.CanQuery = false; seat.Massless = true; seat.Parent = model
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = chassis; joint.Part1 = seat; joint.Parent = seat
	local ballast = Instance.new("Part")
	ballast.Name = "RiderMass"; ballast.Size = Vector3.new(0.29, 0.70, 0.23) / m
	ballast.CFrame = chassis.CFrame * CFrame.new(0, 0.57 / m, 0.05 / m); ballast.Transparency = 1
	ballast.CanCollide = false; ballast.CanTouch = false; ballast.CanQuery = false; ballast.Massless = false
	massProperties(ballast, cfg.RiderMass, 0); ballast.Parent = model
	local riderJoint = motor(chassis, ballast, CFrame.new(0, 0.57 / m, 0.05 / m))
	local feet = {}
	for _, side in { -1, 1 } do
		-- Real collision support from voluntarily planted rider legs. F raises feet;
		-- leaving them down while riding causes physical ground drag, not assistance.
		local foot = cosmetic(model, chassis, "RiderFoot", Vector3.new(0.13, 0.07, 0.23) / m, CFrame.new(side * 0.32 / m, -0.725 / m, 0.15 / m), BLACK)
		foot.CanCollide = true; foot.CustomPhysicalProperties = PhysicalProperties.new(1, 0.65, 0, 100, 100)
		table.insert(feet, foot)
	end
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude; raycast.RespectCanCollide = true
	local links = { forks = {}, swingarms = {} }
	for _, side in { -1, 1 } do
		table.insert(links.forks, makeLink(model, chassis, "FrontFork", Vector3.new(side * 0.064, 0.36, -0.35), Vector3.new(side * 0.064, -0.44, -cfg.Wheelbase / 2), 0.042, m))
		table.insert(links.swingarms, makeLink(model, chassis, "Swingarm", Vector3.new(side * 0.075, -0.16, 0.20), Vector3.new(side * 0.075, -0.44, cfg.Wheelbase / 2), 0.045, m))
	end
	links.shock = makeLink(model, chassis, "RearShock", Vector3.new(0, 0.23, 0.15), Vector3.new(0, -0.30, 0.47), 0.060, m)
	return {
		cfg = cfg, model = model, chassis = chassis, seat = seat, ballast = ballast, riderJoint = riderJoint,
		feet = feet, guards = guards, links = links, frontWheel = wheel(model, chassis, cfg.FrontRadius, -cfg.Wheelbase / 2, true, m),
		rearWheel = wheel(model, chassis, cfg.RearRadius, cfg.Wheelbase / 2, false, m),
		frontSuspension = Suspension.new(), rearSuspension = Suspension.new(), frontTire = Tire.new(), rearTire = Tire.new(),
		drive = Drivetrain.new(cfg.Drive), input = idleInput(true, false), lastSeq = -1,
		lastInput = -math.huge, lastAcceptedInput = -math.huge, raycast = raycast,
		connections = {}, characterParts = {}, characterConnection = nil, character = nil, poseElapsed = 0,
		seatJoint = nil, seatJointBase = nil,
		frontOmega = 0, frontAngle = 0, rearAngle = 0, steerAngle = 0, steerRate = 0,
		frontCompression = 0, rearCompression = 0,
		riderPosition = Vector3.new(0, 0.57, 0.05), riderVelocity = Vector3.zero,
		riderRoll = 0, riderRollVelocity = 0, riderPitch = 0, riderPitchVelocity = 0, riderMomentum = Vector3.zero,
		budgetOverrunCount = 0, maxFrameDt = 0, grounded = false, airborneFor = 0,
		crashed = false, crashedAt = 0, crashReason = nil, bodyContactAt = -math.huge,
		previousRearSliding = false, setupVersion = 1, telemetry = {},
	}
end

local function surface(record: Record, hit: RaycastResult): (any, string)
	local instance: Instance? = hit.Instance
	while instance and instance ~= workspace do
		local name = instance:GetAttribute("PhysicsSurface") or instance:GetAttribute("SurfaceType")
		if typeof(name) == "string" and record.cfg.Surfaces[string.lower(name)] then return record.cfg.Surfaces[string.lower(name)], string.lower(name) end
		instance = instance.Parent
	end
	local material = hit.Material
	local name = if material == Enum.Material.Sand then "sand" elseif material == Enum.Material.Mud then "mud"
		elseif material == Enum.Material.Grass then "grass"
		elseif material == Enum.Material.Concrete or material == Enum.Material.Asphalt then "concrete" else "dirt"
	return record.cfg.Surfaces[name], name
end

local function contact(record: Record, front: boolean, frameDt: number): any
	local cfg = record.cfg
	local sus = if front then cfg.Suspension.Front else cfg.Suspension.Rear
	local frame = record.chassis.CFrame
	local downLocal = if front then Vector3.new(0, -math.cos(cfg.Steering.Caster), -math.sin(cfg.Steering.Caster)) else -Vector3.yAxis
	local restAxle = Vector3.new(0, -0.44, if front then -cfg.Wheelbase / 2 else cfg.Wheelbase / 2)
	local anchorLocal = restAxle - downLocal * sus.RestLength
	local anchor = frame:PointToWorldSpace(anchorLocal / cfg.MetresPerStud)
	local down = frame:VectorToWorldSpace(downLocal)
	local radius = if front then cfg.FrontRadius else cfg.RearRadius
	local axis = Vector3.yAxis * math.cos(cfg.Steering.Caster) + Vector3.zAxis * math.sin(cfg.Steering.Caster)
	local wheelFrame = if front then frame * CFrame.fromAxisAngle(axis, -record.steerAngle) else frame
	local hit = workspace:Raycast(anchor, down * ((sus.RestLength + radius + 0.08) / cfg.MetresPerStud), record.raycast)
	local compression = 0
	local point = anchor
	if hit and -down:Dot(hit.Normal) > 0.20 then
		local tyreNormal = unitOr(hit.Normal - wheelFrame.RightVector * wheelFrame.RightVector:Dot(hit.Normal), hit.Normal)
		local radiusNormal = radius * math.max(0, tyreNormal:Dot(hit.Normal))
		local distance = hit.Distance * cfg.MetresPerStud - radiusNormal / math.max(0.20, -down:Dot(hit.Normal))
		compression = math.max(0, sus.RestLength - distance)
		-- The cast follows fork travel, but force acts at the wheel's actual
		-- tangent point, rather than the ray hit (which biases caster wheelbase).
		point = anchor + down * (distance / cfg.MetresPerStud) - tyreNormal * (radius / cfg.MetresPerStud)
		if distance > sus.RestLength then hit = nil; compression = 0 end
	else hit = nil end
	local previous = if front then record.frontCompression else record.rearCompression
	local velocity = if hit then (compression - previous) / math.max(frameDt, cfg.FixedStep) else 0
	if front then record.frontCompression = compression else record.rearCompression = compression end
	local surfaceCfg, surfaceName = cfg.Surfaces.dirt, "dirt"
	if hit then surfaceCfg, surfaceName = surface(record, hit) end
	return { hit = hit, compression = compression, compressionVelocity = velocity, down = down,
		downLocal = downLocal, anchorLocal = anchorLocal, radius = radius, wheelFrame = wheelFrame, point = point,
		surface = surfaceCfg, surfaceName = surfaceName }
end

local function pose(record: Record, normal: Vector3): (number, number)
	local frame = record.chassis.CFrame
	local forward = unitOr(frame.LookVector - normal * frame.LookVector:Dot(normal), frame.LookVector)
	local right = unitOr(forward:Cross(normal), frame.RightVector)
	return math.atan2(frame.UpVector:Dot(right), frame.UpVector:Dot(normal)), math.atan2(frame.LookVector:Dot(normal), frame.UpVector:Dot(normal))
end

local function advanceRider(record: Record, input: any, dt: number)
	if record.crashed then return end
	local cfg = record.cfg.Rider
	local target = Vector3.new(input.bodySide * cfg.SideTravel, 0.57 + (if input.standing then cfg.StandingHeight else 0), 0.05 - input.bodyForward * cfg.ForeAftTravel)
	local desired = (target - record.riderPosition) * 7
	if desired.Magnitude > cfg.MoveRate then desired = desired.Unit * cfg.MoveRate end
	record.riderVelocity = record.riderVelocity:Lerp(desired, 1 - math.exp(-dt * 12))
	record.riderPosition += record.riderVelocity * dt
	-- Positive bike lean articulates the rider left, generating an opposite
	-- finite physical roll reaction. BodySide controls mass position separately.
	local rollVelocity = math.clamp((-input.lean * cfg.MaxRoll - record.riderRoll) * 7, -cfg.MoveRate, cfg.MoveRate)
	local pitchVelocity = math.clamp((-input.bodyForward * cfg.MaxPitch - record.riderPitch) * 7, -cfg.MoveRate, cfg.MoveRate)
	record.riderRollVelocity += (rollVelocity - record.riderRollVelocity) * (1 - math.exp(-dt * 12))
	record.riderPitchVelocity += (pitchVelocity - record.riderPitchVelocity) * (1 - math.exp(-dt * 12))
	record.riderRoll += record.riderRollVelocity * dt; record.riderPitch += record.riderPitchVelocity * dt
	-- Relative rider momentum has finite travel. Holding still in the air gives
	-- zero torque; returning the body transfers the opposite angular impulse.
	local momentum = record.riderPosition:Cross(record.riderVelocity) * record.cfg.RiderMass
		+ Vector3.new(cfg.PitchInertia * record.riderPitchVelocity, 0, -cfg.RollInertia * record.riderRollVelocity)
	local change = momentum - record.riderMomentum
	local limit = cfg.MaxReactionTorque * dt
	if change.Magnitude > limit then change = change.Unit * limit end
	record.riderMomentum += change
	applyAngular(record, -record.chassis.CFrame:VectorToWorldSpace(change))
	record.riderJoint.C0 = CFrame.new(record.riderPosition / record.cfg.MetresPerStud) * CFrame.Angles(record.riderPitch, 0, -record.riderRoll)
	for _, foot in record.feet do foot.CanCollide = input.footDown end
end

local function tyreForces(record: Record, sample: any, front: boolean, dt: number): any
	local cfg = record.cfg
	local susCfg = if front then cfg.Suspension.Front else cfg.Suspension.Rear
	local susState = if front then record.frontSuspension else record.rearSuspension
	local sus = Suspension.step(susState, sample.compression, sample.compressionVelocity, sample.hit ~= nil, dt, susCfg)
	local omega = if front then record.frontOmega else record.drive.rearOmega
	local state = if front then record.frontTire else record.rearTire
	if not sample.hit then
		return { suspension = sus, tyre = Tire.step(state, { normalLoad = 0, longitudinalVelocity = 0, lateralVelocity = 0,
			wheelOmega = omega, radius = sample.radius, camber = 0, contact = false }, dt, cfg.Tire, sample.surface),
			normalLoad = 0, lateralVelocity = 0, axialError = 0 }
	end
	local hit = sample.hit
	local forward = unitOr(sample.wheelFrame.LookVector - hit.Normal * sample.wheelFrame.LookVector:Dot(hit.Normal), record.chassis.CFrame.LookVector)
	local right = unitOr(forward:Cross(hit.Normal), record.chassis.CFrame.RightVector)
	local roadVelocity = Vector3.zero
	if hit.Instance:IsA("BasePart") then roadVelocity = hit.Instance:GetVelocityAtPosition(sample.point) end
	local velocity = (record.chassis:GetVelocityAtPosition(sample.point) - roadVelocity) * cfg.MetresPerStud - sample.down * sample.compressionVelocity
	local camber = math.atan2(sample.wheelFrame.UpVector:Dot(right), sample.wheelFrame.UpVector:Dot(hit.Normal))
	local up = -sample.down
	-- Tangential tyre force participates in axial spring equilibrium on a lean.
	local contactResult = WheelContact.step(state, { normalLoad = 0, longitudinalVelocity = velocity:Dot(forward), lateralVelocity = velocity:Dot(right),
		wheelOmega = omega, radius = sample.radius, camber = camber, contact = true }, dt, cfg.Tire, sample.surface,
		sus.force, hit.Normal:Dot(up), forward:Dot(up), right:Dot(up), Tire)
	local load, result = contactResult.normalLoad, contactResult.tyre
	-- Independent contact forces create native roll, yaw and load-transfer pitch.
	applyForce(record, hit.Normal * load + forward * result.longitudinalForce + right * result.lateralForce, sample.point, dt)
	-- Rolling resistance supplies an external wheel contact couple; total rotor
	-- momentum compensation later transfers its share to the native body.
	applyAngular(record, -sample.wheelFrame.RightVector * result.rollingTorque * dt)
	return { suspension = sus, tyre = result, normalLoad = load, lateralVelocity = velocity:Dot(right), axialError = contactResult.axialError }
end

local function advanceSteering(record: Record, input: any, front: any, roll: number, dt: number): (number, Vector3)
	local cfg = record.cfg.Steering
	local axis = unitOr(record.chassis.CFrame.UpVector * math.cos(cfg.Caster) - record.chassis.CFrame.LookVector * math.sin(cfg.Caster), record.chassis.CFrame.UpVector)
	local internal = input.steer * cfg.InputTorque - record.steerRate * cfg.Damping
	-- Trail aligning and caster wheel-flop use measured tyre force/load, never
	-- target lean/heading. Damping is the steering bearing, not body stabilization.
	local road = -cfg.Trail * front.tyre.lateralForce * math.cos(cfg.Caster)
		+ front.normalLoad * cfg.Trail * math.sin(cfg.Caster) * math.sin(roll)
	local oldRate = record.steerRate
	record.steerRate += (internal + road) * dt / cfg.Inertia
	record.steerAngle += record.steerRate * dt
	if math.abs(record.steerAngle) > cfg.MaxAngle then
		record.steerAngle = math.sign(record.steerAngle) * cfg.MaxAngle
		if record.steerRate * record.steerAngle > 0 then record.steerRate = 0 end
	end
	-- Native contact force already carries road moments. The virtual steering
	-- rotor has L=-axis*I*rate; transfer its complete change, including stops.
	applyAngular(record, axis * (cfg.Inertia * (record.steerRate - oldRate)))
	return (oldRate + record.steerRate) * 0.5, axis
end

local function crashBike(player: Player, record: Record, reason: string)
	if record.crashed then return end
	record.crashed = true; record.crashedAt = os.clock(); record.crashReason = reason
	record.model:SetAttribute("Crashed", true); record.model:SetAttribute("CrashReason", reason)
	record.input = idleInput(false, false); record.ballast.Massless = true
	for _, foot in record.feet do foot.CanCollide = false end
	-- Rider safety switch kills engine; native bike motion continues uncorrected.
	record.drive.stalled = true -- retain crank momentum; friction spins it down
	local humanoid = record.seat.Occupant
	local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	local velocity = if root and root:IsA("BasePart") then record.chassis:GetVelocityAtPosition(root.Position) else Vector3.zero
	if humanoid then humanoid.Sit = false end
	local seatJoint = record.seat:FindFirstChild("SeatWeld")
	if seatJoint then seatJoint:Destroy() end
	restoreCharacter(record)
	if root and root:IsA("BasePart") then root.AssemblyLinearVelocity = velocity end
	if humanoid then
		humanoid.PlatformStand = true
		task.delay(0.8, function() if humanoid.Parent and humanoid.Health > 0 then humanoid.PlatformStand = false end end)
	end
	if record.chassis:CanSetNetworkOwnership() then record.chassis:SetNetworkOwner(nil) end
end

function Bikes.new(world: Instance): Service
	local folder = Instance.new("Folder"); folder.Name = "DirtBikes"; folder.Parent = world
	return setmetatable({ _folder = folder, _bikes = {} }, Bikes)
end

function Bikes.spawn(self: Service, player: Player, spawnCFrame: CFrame): Model
	self:remove(player)
	local record = buildBike(player, spawnCFrame)
	self._bikes[player] = record; record.model.Parent = self._folder; record.chassis:SetNetworkOwner(nil)
	local function seatCharacter(character: Model)
		local pending: RBXScriptConnection? = nil
		local function whenReady(): boolean
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if not humanoid or not root or not root:IsA("BasePart") then return false end
			if pending then pending:Disconnect() end
			if self._bikes[player] ~= record or record.crashed or player.Character ~= character or humanoid.Health <= 0 then return true end
			makeCharacterMassless(record, character); character:PivotTo(record.seat.CFrame * CFrame.new(0, 2, 0)); record.seat:Sit(humanoid)
			task.delay(0.2, function()
				if self._bikes[player] == record and not record.crashed and player.Character == character and humanoid.Health > 0 and not record.seat.Occupant then record.seat:Sit(humanoid) end
			end)
			return true
		end
		if whenReady() then return end
		pending = character.ChildAdded:Connect(whenReady); table.insert(record.connections, pending :: RBXScriptConnection)
		task.delay(8, function() if pending then pending:Disconnect() end end)
	end
	table.insert(record.connections, player.CharacterAdded:Connect(seatCharacter))
	table.insert(record.connections, record.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = record.seat.Occupant
		if occupant and occupant.Parent ~= player.Character then occupant.Sit = false end
		if not occupant then restoreCharacter(record) end
		if record.chassis:IsDescendantOf(workspace) and record.chassis:CanSetNetworkOwnership() then record.chassis:SetNetworkOwner(nil) end
		record.lastInput = -math.huge
		record.seatJoint = nil; record.seatJointBase = nil
	end))
	local function bodyContact(other: BasePart)
		if other:IsDescendantOf(record.model) or (player.Character and other:IsDescendantOf(player.Character)) then return end
		if other.CanCollide then record.bodyContactAt = os.clock() end
	end
	table.insert(record.connections, record.chassis.Touched:Connect(bodyContact))
	for _, guard in record.guards do table.insert(record.connections, guard.Touched:Connect(bodyContact)) end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Mount 250F"; prompt.ObjectText = "Manual simulation"; prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9; prompt.RequiresLineOfSight = false; prompt.Parent = record.seat
	table.insert(record.connections, prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer == player and not record.crashed and not riding(player, record) and player.Character then seatCharacter(player.Character) end
	end))
	if player.Character then task.defer(seatCharacter, player.Character) end
	return record.model
end

function Bikes.remove(self: Service, player: Player)
	local record = self._bikes[player]
	if not record then return end
	self._bikes[player] = nil
	for _, connection in record.connections do connection:Disconnect() end
	if record.seat.Occupant then record.seat.Occupant.Sit = false end
	restoreCharacter(record); record.model:Destroy()
end

function Bikes.input(self: Service, player: Player, packet: any)
	local record = self._bikes[player]
	if not record or not riding(player, record) then return end
	local now = os.clock()
	if now - record.lastAcceptedInput < 1 / 120 then return end
	local normalized = Controls.normalize(packet, record.lastSeq)
	if not normalized then return end
	record.lastAcceptedInput = now; record.lastInput = now; record.lastSeq = normalized.seq; record.input = normalized
	if normalized.shift ~= 0 then Drivetrain.shift(record.drive, normalized.shift, normalized, record.cfg.Drive) end
end
function Bikes.restart(self: Service, player: Player): boolean
	local record = self._bikes[player]
	return record ~= nil and riding(player, record) and Drivetrain.start(record.drive, record.input, record.cfg.Drive)
end
function Bikes.tune(self: Service, player: Player, changes: any): boolean
	local record = self._bikes[player]
	if not record or not riding(player, record) or not record.grounded or not record.input.footDown
		or record.chassis.AssemblyLinearVelocity.Magnitude * record.cfg.MetresPerStud >= 1 then return false end
	local setup = Controls.normalizeSetup(changes, record.cfg.Suspension)
	if not setup then return false end
	record.cfg.Suspension = setup; record.setupVersion += 1; record.model:SetAttribute("SetupVersion", record.setupVersion)
	return true
end

function Bikes.update(self: Service, frameDt: number)
	if typeof(frameDt) ~= "number" or not finite(frameDt) or frameDt <= 0 then return end
	local now = os.clock()
	local exclusions: { Instance } = { self._folder }
	for _, player in Players:GetPlayers() do if player.Character then table.insert(exclusions, player.Character) end end
	for player, record in self._bikes do
		if not record.chassis.Parent then continue end
		local cfg = record.cfg
		record.raycast.FilterDescendantsInstances = exclusions
		local budget = StepBudget.plan(frameDt, cfg.FixedStep, cfg.MaxSubsteps)
		local steps = budget.steps
		-- Preserve the whole native interval: gravity advances this duration too.
		-- Over-budget frames use coarser contact steps and invalidate timed lab runs.
		if budget.overrun then record.budgetOverrunCount += 1 end
		record.maxFrameDt = math.max(record.maxFrameDt, frameDt)
		local frontSample = contact(record, true, frameDt)
		local rearSample = contact(record, false, frameDt)
		local grounded = frontSample.hit ~= nil or rearSample.hit ~= nil
		local normal = Vector3.yAxis
		if grounded then normal = unitOr((if frontSample.hit then frontSample.hit.Normal else Vector3.zero) + (if rearSample.hit then rearSample.hit.Normal else Vector3.zero), Vector3.yAxis) end
		local roll, pitch = pose(record, normal) -- ground-relative on berms
		local landing = grounded and not record.grounded and record.airborneFor >= 0.08
		local impact = 0
		if landing then
			for _, sample in { frontSample, rearSample } do
				if sample.hit then impact = math.max(impact, -record.chassis:GetVelocityAtPosition(sample.point):Dot(sample.hit.Normal) * cfg.MetresPerStud) end
			end
		end
		record.airborneFor = if grounded then 0 else record.airborneFor + budget.duration
		local active = riding(player, record) and now - record.lastInput <= INPUT_TIMEOUT
		-- Disconnect releases throttle/clutch/brakes; commanded feet/posture remain.
		-- It adds no balancing force and no automatic foot planting.
		local input = if active then record.input else idleInput(not record.crashed and record.input.footDown, record.input.standing)
		local front, rear, driveResult
		for _ = 1, steps do
			local dt = budget.dt
			local steeringAxisLocal = Vector3.yAxis * math.cos(cfg.Steering.Caster) + Vector3.zAxis * math.sin(cfg.Steering.Caster)
			frontSample.wheelFrame = record.chassis.CFrame * CFrame.fromAxisAngle(steeringAxisLocal, -record.steerAngle)
			advanceRider(record, input, dt)
			front = tyreForces(record, frontSample, true, dt)
			rear = tyreForces(record, rearSample, false, dt)
			driveResult = Drivetrain.step(record.drive, input, rear.tyre.contactTorque, dt, cfg.Drive)
			local oldFrontOmega = record.frontOmega
			local candidate = oldFrontOmega + front.tyre.contactTorque * dt / cfg.FrontInertia
			record.frontOmega = math.sign(candidate) * math.max(0, math.abs(candidate) - input.frontBrake * cfg.Drive.FrontBrakeTorque * dt / cfg.FrontInertia)
			-- Ground-point forces include external torque. Massless visual rotors do
			-- not carry native momentum, so transfer opposite TOTAL spin change to
			-- the chassis, including tyre torque, to avoid double-counting traction.
			applyAngular(record, frontSample.wheelFrame.RightVector * ((record.frontOmega - oldFrontOmega) * cfg.FrontInertia))
			applyAngular(record, record.chassis.CFrame.RightVector * ((driveResult.engineReaction + rear.tyre.contactTorque) * dt))
			local steeringRate, steeringAxis = advanceSteering(record, input, front, roll, dt)
			local frontMomentum = -frontSample.wheelFrame.RightVector * (cfg.FrontInertia * record.frontOmega)
			local rotorMomentum = frontMomentum - record.chassis.CFrame.RightVector * (cfg.RearInertia * record.drive.rearOmega + cfg.Drive.EngineInertia * record.drive.engineOmega)
				- steeringAxis * (cfg.Steering.Inertia * record.steerRate)
			local gyroTorque = -record.chassis.AssemblyAngularVelocity:Cross(rotorMomentum) + steeringAxis:Cross(frontMomentum) * steeringRate
			applyAngular(record, gyroTorque * dt)
			local velocity = record.chassis.AssemblyLinearVelocity * cfg.MetresPerStud
			applyForce(record, -velocity * velocity.Magnitude * 0.42, record.chassis.CFrame:PointToWorldSpace(Vector3.new(0, 0.30 / cfg.MetresPerStud, 0)), dt)
			local omega = record.chassis.AssemblyAngularVelocity
			applyAngular(record, -omega * omega.Magnitude * 0.045 * dt) -- small physical air drag
			record.frontAngle = (record.frontAngle - record.frontOmega * dt) % (2 * math.pi)
			record.rearAngle = (record.rearAngle - record.drive.rearOmega * dt) % (2 * math.pi)
		end
		local function wheelOffset(sample: any, angle: number, frontWheel: boolean): CFrame
			local sus = if frontWheel then cfg.Suspension.Front else cfg.Suspension.Rear
			local point = sample.anchorLocal + sample.downLocal * (sus.RestLength - math.clamp(sample.compression, 0, sus.Travel))
			local axis = Vector3.yAxis * math.cos(cfg.Steering.Caster) + Vector3.zAxis * math.sin(cfg.Steering.Caster)
			return CFrame.new(point / cfg.MetresPerStud) * (if frontWheel then CFrame.fromAxisAngle(axis, -record.steerAngle) else CFrame.identity) * CFrame.Angles(angle, 0, 0)
		end
		record.frontWheel.C0 = wheelOffset(frontSample, record.frontAngle, true)
		record.rearWheel.C0 = wheelOffset(rearSample, record.rearAngle, false)
		-- Presentation follows actual travel. These parts are massless and cannot
		-- collide, steer, propel, stabilize or otherwise drive the rigid body.
		local frontAxle = record.frontWheel.C0.Position * cfg.MetresPerStud
		local rearAxle = record.rearWheel.C0.Position * cfg.MetresPerStud
		local frontTop = frontSample.anchorLocal - frontSample.downLocal * 0.38
		for index, side in { -1, 1 } do
			updateLink(record.links.forks[index], frontTop + Vector3.xAxis * side * 0.064, frontAxle + Vector3.xAxis * side * 0.064, 0.042, cfg.MetresPerStud)
			updateLink(record.links.swingarms[index], Vector3.new(side * 0.075, -0.16, 0.20), rearAxle + Vector3.xAxis * side * 0.075, 0.045, cfg.MetresPerStud)
		end
		updateLink(record.links.shock, Vector3.new(0, 0.23, 0.15), Vector3.new(0, -0.16, 0.20):Lerp(rearAxle, 0.5), 0.060, cfg.MetresPerStud)
		local speed = record.chassis.AssemblyLinearVelocity.Magnitude * cfg.MetresPerStud
		local sample = { roll = roll, pitch = pitch, grounded = grounded, landing = landing, landingRoll = roll, landingPitch = pitch,
			normalImpactSpeed = impact, sideLandingSpeed = math.max(math.abs(front.lateralVelocity), math.abs(rear.lateralVelocity)),
			speed = speed, frontSliding = front.tyre.sliding, rearSliding = rear.tyre.sliding,
			frontUtilization = front.tyre.utilization, rearUtilization = rear.tyre.utilization,
			rearSlipAngle = rear.tyre.slipAngle, rearWasSliding = record.previousRearSliding,
			rearGripRecovered = record.previousRearSliding and not rear.tyre.sliding,
			rollRate = record.chassis.AssemblyAngularVelocity:Dot(record.chassis.CFrame.LookVector),
			frontContact = frontSample.hit ~= nil, rearContact = rearSample.hit ~= nil, bodyContact = now - record.bodyContactAt <= 0.12 }
		if riding(player, record) then local reason = Crash.evaluate(sample, cfg.Crash); if reason then crashBike(player, record, reason) end end
		record.previousRearSliding = rear.tyre.sliding; record.grounded = grounded
		record.poseElapsed += frameDt
		if record.character and not record.crashed and record.poseElapsed >= 1 / 15 then
			record.poseElapsed %= 1 / 15
			local seatJoint = record.seat:FindFirstChild("SeatWeld")
			if seatJoint and seatJoint:IsA("Weld") then
				if record.seatJoint ~= seatJoint then record.seatJoint = seatJoint; record.seatJointBase = seatJoint.C0 end
				local delta = record.riderPosition - Vector3.new(0, 0.57, 0.05)
				seatJoint.C0 = CFrame.new(delta / cfg.MetresPerStud) * record.seatJointBase
			end
			local attributes = { MotocrossRiding = true, MotocrossStanding = input.standing, MotocrossBodyForward = input.bodyForward,
				MotocrossBodySide = input.bodySide, MotocrossLean = record.riderRoll / cfg.Rider.MaxRoll }
			for name, value in attributes do if record.character:GetAttribute(name) ~= value then record.character:SetAttribute(name, value) end end
		end
		record.telemetry = { rpm = driveResult.rpm, gear = driveResult.gear, stalled = driveResult.stalled,
			clutch = input.clutch, throttle = input.throttle, frontBrake = input.frontBrake, rearBrake = input.rearBrake,
			frontCompression = front.suspension.compression, rearCompression = rear.suspension.compression,
			frontBottomed = front.suspension.bottomed, rearBottomed = rear.suspension.bottomed,
			frontSlip = front.tyre.slipRatio, rearSlip = rear.tyre.slipRatio, frontSlipAngle = front.tyre.slipAngle, rearSlipAngle = rear.tyre.slipAngle,
			frontGrip = front.tyre.grip, rearGrip = rear.tyre.grip, frontLoad = front.normalLoad, rearLoad = rear.normalLoad,
			frontSliding = front.tyre.sliding, rearSliding = rear.tyre.sliding, roll = roll, pitch = pitch, steerAngle = record.steerAngle,
			grounded = grounded, frontContact = sample.frontContact, rearContact = sample.rearContact,
			surfaceFront = frontSample.surfaceName, surfaceRear = rearSample.surfaceName,
			frontCompressionVelocity = frontSample.compressionVelocity, rearCompressionVelocity = rearSample.compressionVelocity,
			frontAxialError = front.axialError, rearAxialError = rear.axialError, clutchSlip = driveResult.clutchSlip,
			rollRate = sample.rollRate, pitchRate = record.chassis.AssemblyAngularVelocity:Dot(record.chassis.CFrame.RightVector),
			crashed = record.crashed, crashReason = record.crashReason, standing = input.standing, footDown = input.footDown,
			setupVersion = record.setupVersion, physicsVersion = cfg.Version, assists = false, substeps = steps,
			budgetOverrun = budget.overrun, budgetOverrunCount = record.budgetOverrunCount, maxFrameDt = record.maxFrameDt,
			power = driveResult.power, frontOmega = record.frontOmega, rearOmega = record.drive.rearOmega,
			landing = landing, impact = impact }
	end
end

function Bikes.getBike(self: Service, player: Player): Model?
	local record = self._bikes[player]; return if record then record.model else nil
end
function Bikes.getSpeed(self: Service, player: Player): number
	local record = self._bikes[player]
	return if record then record.chassis.AssemblyLinearVelocity.Magnitude * record.cfg.MetresPerStud * 3.6 else 0
end
function Bikes.getPosition(self: Service, player: Player): Vector3?
	local record = self._bikes[player]; return if record then record.chassis.Position else nil
end
function Bikes.isRiding(self: Service, player: Player): boolean
	local record = self._bikes[player]; return record ~= nil and riding(player, record)
end
function Bikes.getTelemetry(self: Service, player: Player): any
	local record = self._bikes[player]
	if not record then return {} end
	local result = table.clone(record.telemetry)
	result.recoveryRemaining = if record.crashed then math.max(0, record.cfg.Crash.RecoveryDelay - (os.clock() - record.crashedAt)) else 0
	return result
end

return Bikes
