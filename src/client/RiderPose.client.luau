--!strict
-- Presentation only. Physical rider ballast and rotor reactions live on the
-- server. These joint poses cannot turn, pitch or stabilize the motorcycle.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

type Rig = { character: Model, motors: { [string]: Motor6D }, applied: boolean }
local rigs: { [Player]: Rig } = {}

local function observe(player: Player, character: Model)
	local rig: Rig = { character = character, motors = {}, applied = false }
	rigs[player] = rig
	local function remember(instance: Instance)
		if instance:IsA("Motor6D") then
			rig.motors[instance.Name] = instance
		end
	end
	for _, instance in character:GetDescendants() do
		remember(instance)
	end
	local connection: RBXScriptConnection? = nil
	connection = character.DescendantAdded:Connect(remember)
	character.Destroying:Once(function()
		if connection then connection:Disconnect() end
		if rigs[player] == rig then rigs[player] = nil end
	end)
end

local function addPlayer(player: Player)
	player.CharacterAdded:Connect(function(character) observe(player, character) end)
	if player.Character then observe(player, player.Character) end
end
for _, player in Players:GetPlayers() do addPlayer(player) end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player) rigs[player] = nil end)

local function axis(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if typeof(value) == "number" and value == value then math.clamp(value, -1, 1) else 0
end

local function pose(rig: Rig, name: string, x: number, y: number, z: number)
	local motor = rig.motors[name]
	if motor and motor.Parent then motor.Transform = CFrame.Angles(x, y, z) end
end

-- Animator updates Transform after PreAnimation. Apply prototype articulation
-- just before simulation so it replaces the default seated posture locally.
RunService.PreSimulation:Connect(function()
	for _, rig in rigs do
		local character = rig.character
		if character:GetAttribute("MotocrossRiding") == true then
			rig.applied = true
			local standing = character:GetAttribute("MotocrossStanding") == true
			local forward = axis(character, "MotocrossBodyForward")
			local side = axis(character, "MotocrossBodySide")
			local lean = axis(character, "MotocrossLean")
			local hip = math.rad(if standing then 18 else 65)
			local knee = math.rad(if standing then -30 else -82)
			local torsoPitch = math.rad(10 + forward * 15)
			local torsoRoll = math.rad(-side * 10 - lean * 6)
			pose(rig, "Waist", torsoPitch, 0, torsoRoll)
			pose(rig, "LeftHip", hip, 0, math.rad(-3))
			pose(rig, "RightHip", hip, 0, math.rad(3))
			pose(rig, "LeftKnee", knee, 0, 0)
			pose(rig, "RightKnee", knee, 0, 0)
			pose(rig, "LeftShoulder", math.rad(60 - forward * 8), 0, math.rad(-15))
			pose(rig, "RightShoulder", math.rad(60 - forward * 8), 0, math.rad(15))
			pose(rig, "LeftElbow", math.rad(20), 0, 0)
			pose(rig, "RightElbow", math.rad(20), 0, 0)
			-- R6 fallback; production hand/foot IK remains a separate asset task.
			pose(rig, "RootJoint", torsoPitch, 0, torsoRoll)
			pose(rig, "Left Hip", hip, 0, 0)
			pose(rig, "Right Hip", hip, 0, 0)
			pose(rig, "Left Shoulder", math.rad(60), 0, math.rad(-15))
			pose(rig, "Right Shoulder", math.rad(60), 0, math.rad(15))
		elseif rig.applied then
			rig.applied = false
			for _, motor in rig.motors do
				if motor.Parent then motor.Transform = CFrame.identity end
			end
		end
	end
end)
