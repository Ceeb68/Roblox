--!strict
-- The bike is server simulated. This client sends controls and renders race state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Motocross"):WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild("Input") :: RemoteEvent
local actionRemote = remotes:WaitForChild("Action") :: RemoteEvent
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent

local colors = {
	panel = Color3.fromRGB(16, 24, 36),
	panelLight = Color3.fromRGB(27, 39, 54),
	border = Color3.fromRGB(60, 77, 93),
	text = Color3.fromRGB(244, 248, 252),
	muted = Color3.fromRGB(155, 176, 194),
	orange = Color3.fromRGB(255, 128, 54),
	teal = Color3.fromRGB(64, 236, 201),
}

local function create(className: string, parent: Instance, properties: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in pairs(properties) do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function corner(parent: Instance, radius: number)
	create("UICorner", parent, { CornerRadius = UDim.new(0, radius) })
end

local function label(parent: Instance, text: string, position: UDim2, size: UDim2, fontSize: number, color: Color3?): TextLabel
	return create("TextLabel", parent, {
		BackgroundTransparency = 1,
		Position = position,
		Size = size,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextSize = fontSize,
		TextColor3 = color or colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
end

local gui = create("ScreenGui", player:WaitForChild("PlayerGui"), {
	Name = "DirtlineHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}) :: ScreenGui

local panelScales: { UIScale } = {}
local function panel(name: string, position: UDim2, size: UDim2, anchor: Vector2): Frame
	local frame = create("Frame", gui, {
		Name = name,
		Position = position,
		Size = size,
		AnchorPoint = anchor,
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.09,
		BorderSizePixel = 0,
	}) :: Frame
	corner(frame, 14)
	create("UIStroke", frame, { Color = colors.border, Transparency = 0.5, Thickness = 1 })
	table.insert(panelScales, create("UIScale", frame, { Scale = 1 }))
	return frame
end

local brand = panel("Brand", UDim2.fromOffset(16, 16), UDim2.fromOffset(240, 108), Vector2.zero)
create("Frame", brand, {
	Position = UDim2.fromOffset(0, 17),
	Size = UDim2.fromOffset(4, 42),
	BackgroundColor3 = colors.orange,
	BorderSizePixel = 0,
})
local title = label(brand, "DIRTLINE MX", UDim2.fromOffset(16, 12), UDim2.fromOffset(213, 31), 25)
title.Font = Enum.Font.GothamBlack
label(brand, "MOTOCROSS TIME TRIAL", UDim2.fromOffset(17, 44), UDim2.fromOffset(210, 18), 10, colors.muted)
local resetButton = create("TextButton", brand, {
	Name = "ResetBike",
	Position = UDim2.fromOffset(16, 72),
	Size = UDim2.fromOffset(208, 26),
	BackgroundColor3 = colors.panelLight,
	BorderSizePixel = 0,
	AutoButtonColor = true,
	Text = "R  /  Y     RESET BIKE",
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = colors.text,
}) :: TextButton
corner(resetButton, 6)

local timing = panel("Timing", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(244, 108), Vector2.new(1, 0))
label(timing, "LAP TIME", UDim2.fromOffset(16, 11), UDim2.fromOffset(210, 17), 10, colors.muted)
local timeLabel = label(timing, "00:00.00", UDim2.fromOffset(14, 29), UDim2.fromOffset(219, 37), 32)
timeLabel.Font = Enum.Font.GothamBold
local bestLabel = label(timing, "BEST    --:--.--", UDim2.fromOffset(16, 78), UDim2.fromOffset(212, 18), 13, colors.teal)

local status = panel("Status", UDim2.new(0.5, 0, 0, 137), UDim2.fromOffset(430, 48), Vector2.new(0.5, 0))
local statusLabel = label(status, "CROSS THE START GATE TO BEGIN", UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0), 14, colors.teal)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center

local speedPanel = panel("Speed", UDim2.new(0, 16, 1, -16), UDim2.fromOffset(214, 120), Vector2.new(0, 1))
label(speedPanel, "GROUND SPEED", UDim2.fromOffset(16, 11), UDim2.fromOffset(188, 16), 10, colors.muted)
local speedLabel = label(speedPanel, "0", UDim2.fromOffset(13, 26), UDim2.fromOffset(128, 62), 52)
speedLabel.Font = Enum.Font.GothamBlack
label(speedPanel, "KM/H", UDim2.fromOffset(143, 62), UDim2.fromOffset(60, 21), 12, colors.muted)
local speedTrack = create("Frame", speedPanel, {
	Position = UDim2.fromOffset(16, 99),
	Size = UDim2.new(1, -32, 0, 5),
	BackgroundColor3 = colors.panelLight,
	BorderSizePixel = 0,
}) :: Frame
corner(speedTrack, 3)
local speedFill = create("Frame", speedTrack, {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = colors.orange,
	BorderSizePixel = 0,
}) :: Frame
corner(speedFill, 3)

local progressPanel = panel("Progress", UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(330, 90), Vector2.new(0.5, 1))
local lapLabel = label(progressPanel, "LAP 01", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 23), 19)
lapLabel.Font = Enum.Font.GothamBold
local gateLabel = label(progressPanel, "NEXT GATE  01 / 01", UDim2.fromOffset(16, 38), UDim2.new(1, -32, 0, 18), 11, colors.muted)
local progressTrack = create("Frame", progressPanel, {
	Position = UDim2.fromOffset(16, 69),
	Size = UDim2.new(1, -32, 0, 5),
	BackgroundColor3 = colors.panelLight,
	BorderSizePixel = 0,
}) :: Frame
corner(progressTrack, 3)
local progressFill = create("Frame", progressTrack, {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = colors.teal,
	BorderSizePixel = 0,
}) :: Frame
corner(progressFill, 3)

local controlsPanel = panel("Controls", UDim2.new(1, -16, 1, -16), UDim2.fromOffset(250, 90), Vector2.new(1, 1))
label(controlsPanel, "RIDE CONTROLS", UDim2.fromOffset(16, 10), UDim2.fromOffset(220, 17), 10, colors.orange)
local controlsLabel = label(controlsPanel, "W / S  Gas / reverse   A / D  Steer\nSPACE  Brake   R  Reset bike", UDim2.fromOffset(16, 32), UDim2.fromOffset(220, 43), 11, colors.muted)
controlsLabel.TextYAlignment = Enum.TextYAlignment.Top
controlsLabel.TextWrapped = true

local intro = panel("Welcome", UDim2.fromScale(0.5, 0.47), UDim2.fromOffset(520, 250), Vector2.new(0.5, 0.5))
intro.ZIndex = 5
local introTitle = label(intro, "FIND YOUR LINE.", UDim2.fromOffset(24, 18), UDim2.new(1, -48, 0, 38), 29)
introTitle.Font = Enum.Font.GothamBlack
label(intro, "Cross the start gate, then follow every numbered gate.\nKeep the wheels planted and chase your best lap.", UDim2.fromOffset(24, 64), UDim2.new(1, -48, 0, 48), 15, colors.muted).TextWrapped = true
local introControls = label(intro, "W / S  Gas / reverse   A / D  Steer\nSPACE  Brake   R  Reset bike / restart lap", UDim2.fromOffset(24, 128), UDim2.new(1, -48, 0, 44), 13)
introControls.TextWrapped = true
local dismissButton = create("TextButton", intro, {
	Position = UDim2.fromOffset(24, 188),
	Size = UDim2.new(1, -48, 0, 40),
	BackgroundColor3 = colors.orange,
	BorderSizePixel = 0,
	AutoButtonColor = true,
	Text = "LET'S RIDE",
	TextColor3 = colors.panel,
	TextSize = 14,
	Font = Enum.Font.GothamBold,
}) :: TextButton
corner(dismissButton, 8)

local introDismissed = false
local function dismissIntro()
	if introDismissed then
		return
	end
	introDismissed = true
	intro.Visible = false
end
dismissButton.Activated:Connect(dismissIntro)
task.delay(10, dismissIntro)

local seated = false
local focused = true
local menuOpen = false
local heldKeys: { [Enum.KeyCode]: boolean } = {}
local touchHeld: { [string]: { [InputObject]: boolean } } = {}
local stickSteer = 0
local triggerGas = 0
local triggerBrake = 0
local lastReset = -math.huge
local touchButtons: { TextButton } = {}

local function canDrive(): boolean
	return seated and focused and not menuOpen and UserInputService:GetFocusedTextBox() == nil
end

local function clearControls()
	table.clear(heldKeys)
	for _, touches in pairs(touchHeld) do
		table.clear(touches)
	end
	stickSteer = 0
	triggerGas = 0
	triggerBrake = 0
	-- A release packet must not wait for the next periodic update.
	inputRemote:FireServer(0, 0, false)
	for _, button in ipairs(touchButtons) do
		button.BackgroundColor3 = colors.panel
	end
end

local function resetBike()
	if not focused or menuOpen or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if os.clock() - lastReset < 0.8 then
		return
	end
	lastReset = os.clock()
	clearControls()
	actionRemote:FireServer("Respawn")
	dismissIntro()
end
resetButton.Activated:Connect(resetBike)

local function touchPressed(action: string): boolean
	return touchHeld[action] ~= nil and next(touchHeld[action]) ~= nil
end

local function controls(): (number, number, boolean)
	local forward = (heldKeys[Enum.KeyCode.W] or heldKeys[Enum.KeyCode.Up] or touchPressed("gas")) and 1 or 0
	local reverse = (heldKeys[Enum.KeyCode.S] or heldKeys[Enum.KeyCode.Down] or heldKeys[Enum.KeyCode.ButtonX] or touchPressed("reverse")) and 1 or 0
	local left = (heldKeys[Enum.KeyCode.A] or heldKeys[Enum.KeyCode.Left] or touchPressed("left")) and 1 or 0
	local right = (heldKeys[Enum.KeyCode.D] or heldKeys[Enum.KeyCode.Right] or touchPressed("right")) and 1 or 0
	local throttle = math.clamp(math.max(forward, triggerGas) - reverse, -1, 1)
	local steer = math.clamp(right - left + stickSteer, -1, 1)
	local brake = heldKeys[Enum.KeyCode.Space] == true or triggerBrake > 0.15 or touchPressed("brake")
	return throttle, steer, brake
end

local function handleControl(actionName: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local key = input.KeyCode
	local released = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
	if released then
		heldKeys[key] = nil
		if key == Enum.KeyCode.Thumbstick1 then
			stickSteer = 0
		elseif key == Enum.KeyCode.ButtonR2 then
			triggerGas = 0
		elseif key == Enum.KeyCode.ButtonL2 then
			triggerBrake = 0
		end
	end
	-- Reset also works after a crash or dismount, when normal controls pass through.
	if actionName == "DirtlineReset" then
		if not focused or menuOpen or UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			resetBike()
		end
		return Enum.ContextActionResult.Sink
	end
	if not canDrive() then
		return Enum.ContextActionResult.Pass
	end
	if not released then
		if key == Enum.KeyCode.Thumbstick1 then
			local x = input.Position.X
			stickSteer = if math.abs(x) < 0.12 then 0 else math.sign(x) * ((math.abs(x) - 0.12) / 0.88)
		elseif key == Enum.KeyCode.ButtonR2 then
			triggerGas = math.clamp(input.Position.Z, 0, 1)
		elseif key == Enum.KeyCode.ButtonL2 then
			triggerBrake = math.clamp(input.Position.Z, 0, 1)
		else
			heldKeys[key] = true
		end
		if key == Enum.KeyCode.W or key == Enum.KeyCode.Up or key == Enum.KeyCode.ButtonR2 then
			dismissIntro()
		end
	end
	return Enum.ContextActionResult.Sink
end

-- These return Pass whenever the rider leaves their seat, retaining Roblox movement.
ContextActionService:BindActionAtPriority("DirtlineThrottle", handleControl, false, 3000,
	Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonX)
ContextActionService:BindActionAtPriority("DirtlineSteer", handleControl, false, 3000,
	Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Thumbstick1)
ContextActionService:BindActionAtPriority("DirtlineBrake", handleControl, false, 3000,
	Enum.KeyCode.Space, Enum.KeyCode.ButtonL2)
ContextActionService:BindActionAtPriority("DirtlineReset", handleControl, false, 3000,
	Enum.KeyCode.R, Enum.KeyCode.ButtonY)

local touchLayer = create("Frame", gui, {
	Name = "TouchControls",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
}) :: Frame

local function touchButton(action: string, text: string, position: UDim2, anchor: Vector2)
	touchHeld[action] = {}
	local button = create("TextButton", touchLayer, {
		Name = action,
		Position = position,
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = anchor,
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = if action == "gas" then colors.teal else colors.text,
	}) :: TextButton
	corner(button, 16)
	create("UIStroke", button, { Color = colors.border, Transparency = 0.25, Thickness = 1 })
	table.insert(touchButtons, button)
	button.InputBegan:Connect(function(input: InputObject)
		if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and canDrive() then
			touchHeld[action][input] = true
			button.BackgroundColor3 = colors.panelLight
			dismissIntro()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		touchHeld[action][input] = nil
		if not touchPressed(action) then
			button.BackgroundColor3 = colors.panel
		end
	end)
end
touchButton("left", "LEFT", UDim2.new(0, 16, 1, -16), Vector2.new(0, 1))
touchButton("right", "RIGHT", UDim2.new(0, 88, 1, -16), Vector2.new(0, 1))
touchButton("gas", "GAS", UDim2.new(1, -16, 1, -88), Vector2.new(1, 1))
touchButton("brake", "BRAKE", UDim2.new(1, -16, 1, -16), Vector2.new(1, 1))
touchButton("reverse", "BACK", UDim2.new(1, -88, 1, -16), Vector2.new(1, 1))

-- InputEnded is global so dragging a finger off a control cannot leave it held.
UserInputService.InputEnded:Connect(function(input: InputObject)
	for _, touches in pairs(touchHeld) do
		touches[input] = nil
	end
	for _, button in ipairs(touchButtons) do
		if not touchPressed(button.Name) then
			button.BackgroundColor3 = colors.panel
		end
	end
	heldKeys[input.KeyCode] = nil
end)
UserInputService.WindowFocusReleased:Connect(function()
	focused = false
	clearControls()
end)
UserInputService.WindowFocused:Connect(function()
	focused = true
end)
UserInputService.TextBoxFocused:Connect(clearControls)
GuiService.MenuOpened:Connect(function()
	menuOpen = true
	clearControls()
end)
GuiService.MenuClosed:Connect(function()
	menuOpen = false
end)
UserInputService.GamepadDisconnected:Connect(clearControls)

local function ownsSeat(seat: BasePart?): boolean
	if seat == nil or not seat:IsA("VehicleSeat") or seat.Name ~= "DriverSeat" then
		return false
	end
	local ancestor: Instance? = seat
	while ancestor and ancestor ~= workspace do
		if ancestor:GetAttribute("OwnerUserId") == player.UserId then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function updateSeat(humanoid: Humanoid)
	local nextSeated = humanoid.Health > 0 and ownsSeat(humanoid.SeatPart)
	if seated ~= nextSeated then
		seated = nextSeated
		clearControls()
	end
	touchLayer.Visible = seated and UserInputService.TouchEnabled
end

local characterConnections: { RBXScriptConnection } = {}
local function watchCharacter(character: Model)
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	seated = false
	touchLayer.Visible = false
	clearControls()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	table.insert(characterConnections, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		updateSeat(humanoid)
	end))
	table.insert(characterConnections, humanoid.Died:Connect(function()
		updateSeat(humanoid)
	end))
	updateSeat(humanoid)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

local function layout()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local scale = math.clamp(math.min(viewport.X / 1120, viewport.Y / 690), 0.56, 1)
	for _, panelScale in ipairs(panelScales) do
		panelScale.Scale = scale
	end
	status.Position = UDim2.new(0.5, 0, 0, 16 + 108 * scale + 12)
	local mobile = UserInputService.TouchEnabled
	touchLayer.Visible = seated and mobile
	local compact = viewport.X < 930 or mobile
	controlsPanel.Visible = not compact
	progressPanel.AnchorPoint = if compact then Vector2.new(1, 1) else Vector2.new(0.5, 1)
	progressPanel.Position = if compact then UDim2.new(1, -16, 1, if mobile then -165 else -16) else UDim2.new(0.5, 0, 1, -16)
	progressPanel.Size = UDim2.fromOffset(if viewport.X < 500 then 260 else 330, 90)
	speedPanel.Position = UDim2.new(0, 16, 1, if mobile then -165 else -16)
	resetButton.Text = if mobile then "RESET BIKE / RESTART LAP" else "R  /  Y     RESET BIKE"
	if mobile then
		introControls.Text = "LEFT / RIGHT  Steer   GAS  Accelerate\nBRAKE  Slow down   BACK  Reverse"
	elseif UserInputService.GamepadEnabled then
		introControls.Text = "Left stick  Steer   RT  Gas   LT  Brake\nX  Reverse   Y  Reset bike / restart lap"
		controlsLabel.Text = "Left stick  Steer   RT  Gas   LT  Brake\nX  Reverse   Y  Reset bike"
	else
		introControls.Text = "W / S  Gas / reverse   A / D  Steer\nSPACE  Brake   R  Reset bike / restart lap"
	end
end
local viewportConnection: RBXScriptConnection? = nil
local function watchCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	layout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(layout)
UserInputService.GamepadConnected:Connect(layout)
watchCamera()

local race = {
	speed = 0,
	lap = 1,
	nextCheckpoint = 1,
	checkpointCount = 1,
	lapTime = 0,
	bestLap = nil :: number?,
	lapsFinished = 0,
	racing = false,
}
local receivedAt = os.clock()
local eventMessage = ""
local eventMessageUntil = 0

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 1e9
end

local function timeText(seconds: number): string
	local hundredths = math.floor(math.max(seconds, 0) * 100)
	return string.format("%02d:%02d.%02d", math.floor(hundredths / 6000), math.floor(hundredths / 100) % 60, hundredths % 100)
end

stateRemote.OnClientEvent:Connect(function(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	if finite(snapshot.speed) then
		race.speed = math.clamp(snapshot.speed, 0, 500)
	end
	if finite(snapshot.lap) then
		race.lap = math.clamp(math.floor(snapshot.lap), 1, 99999)
	end
	if finite(snapshot.checkpointCount) then
		race.checkpointCount = math.clamp(math.floor(snapshot.checkpointCount), 1, 999)
	end
	if finite(snapshot.nextCheckpoint) then
		race.nextCheckpoint = math.clamp(math.floor(snapshot.nextCheckpoint), 1, race.checkpointCount)
	end
	if finite(snapshot.lapTime) then
		race.lapTime = math.clamp(snapshot.lapTime, 0, 86400)
		receivedAt = os.clock()
	end
	if finite(snapshot.bestLap) and snapshot.bestLap > 0 then
		race.bestLap = math.clamp(snapshot.bestLap, 0, 86400)
	end
	if finite(snapshot.lapsFinished) then
		race.lapsFinished = math.clamp(math.floor(snapshot.lapsFinished), 0, 99999)
	end
	if type(snapshot.racing) == "boolean" then
		race.racing = snapshot.racing
	end
	if type(snapshot.message) == "string" and snapshot.message ~= "" then
		local message = string.sub(snapshot.message, 1, 100)
		if eventMessage ~= message then
			eventMessage = message
			eventMessageUntil = os.clock() + 3
		end
	elseif snapshot.message == nil then
		eventMessage = ""
		eventMessageUntil = 0
	end
	lapLabel.Text = string.format("LAP %02d", race.lap)
	gateLabel.Text = if race.racing and race.nextCheckpoint == 1 then "NEXT GATE  START / FINISH" else string.format("NEXT GATE  %02d / %02d", race.nextCheckpoint, race.checkpointCount)
	local cleared = if race.racing and race.nextCheckpoint == 1 then race.checkpointCount else race.nextCheckpoint - 1
	progressFill.Size = UDim2.fromScale(cleared / race.checkpointCount, 1)
	bestLabel.Text = "BEST    " .. (if race.bestLap then timeText(race.bestLap) else "--:--.--")
end)

local sendAccumulator = 0
local displayedSpeed = 0
RunService.Heartbeat:Connect(function(deltaTime: number)
	sendAccumulator += deltaTime
	if sendAccumulator >= 1 / 15 then
		sendAccumulator %= 1 / 15
		if canDrive() then
			local throttle, steer, brake = controls()
			inputRemote:FireServer(throttle, steer, brake)
		end
	end
end)

RunService.RenderStepped:Connect(function(deltaTime: number)
	displayedSpeed += (race.speed - displayedSpeed) * math.min(1, deltaTime * 9)
	speedLabel.Text = tostring(math.floor(displayedSpeed + 0.5))
	speedFill.Size = UDim2.fromScale(math.clamp(displayedSpeed / 120, 0, 1), 1)
	-- Extrapolation is capped if updates stop, so a disconnected client cannot invent laps.
	local extrapolated = if race.racing then math.min(os.clock() - receivedAt, 1) else 0
	timeLabel.Text = timeText(race.lapTime + extrapolated)
	if os.clock() < eventMessageUntil then
		statusLabel.Text = eventMessage
	elseif not seated then
		statusLabel.Text = "RESET YOUR BIKE TO GET BACK ON TRACK"
	elseif race.racing and race.nextCheckpoint == 1 then
		statusLabel.Text = "CROSS START / FINISH TO COMPLETE YOUR LAP"
	elseif race.racing then
		statusLabel.Text = string.format("LAP %02d  /  FOLLOW GATE %02d", race.lap, race.nextCheckpoint)
	else
		statusLabel.Text = "CROSS THE START GATE TO BEGIN"
	end
end)
