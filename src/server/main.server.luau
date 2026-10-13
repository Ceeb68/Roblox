--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Motocross")
local Config = require(shared:WaitForChild("Config"))
local RaceRules = require(shared:WaitForChild("RaceRules"))
local Bikes = require(script.Parent:WaitForChild("Bikes"))
local Track = require(script.Parent:WaitForChild("Track"))

local world = Instance.new("Folder")
world.Name = "DirtlineMX"
world.Parent = workspace
-- Retain the original race circuit; Phase 1 opens in the dedicated physics lab.
local track = if Config.Mode == "PhysicsLab"
	then require(script.Parent:WaitForChild("TestTrack")).build(world)
	else Track.build(world)
local bikes = Bikes.new(world)

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = shared
local function remote(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end
local input = remote("Input")
local action = remote("Action")
local stateEvent = remote("State")

type Rider = {
	race: RaceRules.State,
	slot: number,
	lastPosition: Vector3?,
	lastReset: number,
	respawning: boolean,
	message: string,
	messageUntil: number,
	laps: IntValue,
	best: NumberValue,
	characterConnection: RBXScriptConnection?,
	lastAction: number,
	crashNotified: boolean,
	outOfBounds: boolean,
}
local riders: { [Player]: Rider } = {}
local nextSlot = 0

local function setMessage(rider: Rider, text: string)
	rider.message = text
	rider.messageUntil = workspace:GetServerTimeNow() + 5
end

local function respawn(player: Player)
	local rider = riders[player]
	if not rider or not player.Character or not player.Character.Parent then
		return
	end
	if rider.respawning then
		return
	end
	rider.respawning = true
	rider.lastReset = workspace:GetServerTimeNow()
	rider.lastPosition = nil
	rider.crashNotified = false
	rider.outOfBounds = false
	RaceRules.reset(rider.race)
	setMessage(rider, "Cross START / FINISH to start your lap")
	bikes:spawn(player, track:spawnCFrame(rider.slot))
	rider.respawning = false
end

local function addPlayer(player: Player)
	if riders[player] then
		return
	end
	nextSlot += 1
	local leaderboard = Instance.new("Folder")
	leaderboard.Name = "leaderstats"
	leaderboard.Parent = player
	local laps = Instance.new("IntValue")
	laps.Name = "Laps"
	laps.Parent = leaderboard
	local best = Instance.new("NumberValue")
	best.Name = "BestLap"
	best.Parent = leaderboard
	local rider: Rider = {
		race = RaceRules.new(track.checkpointCount),
		slot = (nextSlot - 1) % 8 + 1,
		lastPosition = nil,
		lastReset = -math.huge,
		respawning = false,
		message = "",
		messageUntil = 0,
		laps = laps,
		best = best,
		characterConnection = nil,
		lastAction = -math.huge,
		crashNotified = false,
		outOfBounds = false,
	}
	riders[player] = rider
	rider.characterConnection = player.CharacterAdded:Connect(function()
		task.defer(respawn, player)
	end)
	if player.Character then
		task.defer(respawn, player)
	end
end

input.OnServerEvent:Connect(function(player, packet)
	-- Bikes validates sequence, independent control axes, rate and rider ownership.
	bikes:input(player, packet)
end)

action.OnServerEvent:Connect(function(player, command, payload)
	local rider = riders[player]
	if not rider or typeof(command) ~= "string" then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - rider.lastAction < 0.2 then
		return
	end
	rider.lastAction = now
	if command == "Respawn" then
		local telemetry = bikes:getTelemetry(player)
		if telemetry and telemetry.crashed and (telemetry.recoveryRemaining or 0) > 0 then
			setMessage(rider, string.format("Recover in %.1fs", telemetry.recoveryRemaining))
			return
		end
		if not rider.respawning and now - rider.lastReset >= Config.ResetCooldown then
			task.defer(respawn, player)
		end
	elseif command == "StartEngine" then
		setMessage(rider, if bikes:restart(player) then "Engine started — clutch, select gear, raise feet" else "Pull the clutch or select neutral to start")
	elseif command == "Tune" then
		-- Competitive sessions use identical server calibration. Setup exploration
		-- is allowed only in this lab, stationary, with manual feet deployed.
		if Config.Mode == "PhysicsLab" and bikes:tune(player, payload) then
			RaceRules.reset(rider.race)
			rider.lastPosition = nil
			setMessage(rider, "Suspension setup applied — current test lap invalidated")
		else
			setMessage(rider, "Tune only while parked in the physics lab with feet down")
		end
	end
end)

Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	local rider = riders[player]
	if rider and rider.characterConnection then
		rider.characterConnection:Disconnect()
	end
	bikes:remove(player)
	riders[player] = nil
end)
for _, player in Players:GetPlayers() do
	addPlayer(player)
end

local sinceSnapshot = 0
-- Contact/rotor impulses are supplied before Roblox integrates its rigid bodies.
RunService.PreSimulation:Connect(function(dt)
	bikes:update(dt)
end)
RunService.Heartbeat:Connect(function(dt)
	sinceSnapshot += dt
	local publish = sinceSnapshot >= Config.StateInterval
	if publish then
		sinceSnapshot %= Config.StateInterval
	end
	local now = workspace:GetServerTimeNow()
	for player, rider in riders do
		local physics = bikes:getTelemetry(player)
		if physics and physics.budgetOverrun and rider.race.lapStart ~= nil then
			RaceRules.reset(rider.race)
			rider.lastPosition = nil
			setMessage(rider, "Physics step budget exceeded — test lap invalidated")
		end
		if physics and physics.crashed and not rider.crashNotified then
			rider.crashNotified = true
			RaceRules.reset(rider.race)
			rider.lastPosition = nil
			setMessage(rider, (physics.crashReason or "Crash") .. " — wait, then R to recover")
		end
		local position = bikes:getPosition(player)
		if position and not rider.respawning then
			if position.Y < Config.OutOfBoundsY or math.abs(position.X) > Config.ArenaLimit or math.abs(position.Z) > Config.ArenaLimit then
				if not rider.outOfBounds then
					rider.outOfBounds = true
					RaceRules.reset(rider.race)
					setMessage(rider, "Outside test area — use R for manual recovery")
				end
				rider.lastPosition = nil
			elseif bikes:isRiding(player) and not physics.budgetOverrun then
				rider.outOfBounds = false
				local previous = rider.lastPosition
				if previous then
					local gate = track.gates[rider.race.nextCheckpoint]
					local before = gate.cframe:PointToObjectSpace(previous)
					local after = gate.cframe:PointToObjectSpace(position)
					if RaceRules.crossedGate(
						{ x = before.X, y = before.Y, z = before.Z },
						{ x = after.X, y = after.Y, z = after.Z },
						gate.width
					) then
						local accepted, completed = RaceRules.cross(rider.race, rider.race.nextCheckpoint, now)
						if accepted then
							if completed then
								rider.laps.Value = rider.race.lapsFinished
								rider.best.Value = math.floor((rider.race.bestLap or 0) * 100) / 100
								setMessage(rider, string.format("LAP COMPLETE  %.2fs  —  keep riding!", completed))
							elseif rider.race.nextCheckpoint == 2 then
								setMessage(rider, "Lap started — follow the numbered gates")
							else
								setMessage(rider, string.format("Gate cleared — next gate %d", rider.race.nextCheckpoint))
							end
						end
					end
				end
				rider.lastPosition = position
			else
				rider.lastPosition = nil
			end
		end
		if publish then
			stateEvent:FireClient(player, {
				speed = bikes:getSpeed(player),
				lap = rider.race.lap,
				nextCheckpoint = rider.race.nextCheckpoint,
				checkpointCount = rider.race.checkpointCount,
				lapTime = if rider.race.lapStart then now - rider.race.lapStart else 0,
				bestLap = rider.race.bestLap,
				lapsFinished = rider.race.lapsFinished,
				racing = rider.race.lapStart ~= nil,
				message = if now < rider.messageUntil then rider.message else nil,
				physics = physics,
				mode = Config.Mode,
			})
		end
	end
end)
