--!strict
-- All motorcycle forces and crash decisions come from the server simulation.
-- This script only captures rider controls and presents authoritative telemetry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local motocross = ReplicatedStorage:WaitForChild("Motocross")
local remotes = motocross:WaitForChild("Remotes")
local inputRemote = remotes:WaitForChild("Input") :: RemoteEvent
local actionRemote = remotes:WaitForChild("Action") :: RemoteEvent
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent
local bikeConfig = require(motocross:WaitForChild("Physics"):WaitForChild("Bike250"))

local colors = {
	panel = Color3.fromRGB(16, 24, 36),
	panelLight = Color3.fromRGB(27, 39, 54),
	border = Color3.fromRGB(60, 77, 93),
	text = Color3.fromRGB(244, 248, 252),
	muted = Color3.fromRGB(155, 176, 194),
	orange = Color3.fromRGB(255, 128, 54),
	teal = Color3.fromRGB(64, 236, 201),
	red = Color3.fromRGB(255, 104, 91),
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

local function button(parent: Instance, text: string, position: UDim2, size: UDim2): TextButton
	local result = create("TextButton", parent, {
		Position = position,
		Size = size,
		BackgroundColor3 = colors.panelLight,
		BorderSizePixel = 0,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = colors.text,
	}) :: TextButton
	corner(result, 6)
	return result
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
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
	}) :: Frame
	corner(frame, 12)
	create("UIStroke", frame, { Color = colors.border, Transparency = 0.4, Thickness = 1 })
	table.insert(panelScales, create("UIScale", frame, { Scale = 1 }))
	return frame
end

local brand = panel("Brand", UDim2.fromOffset(16, 16), UDim2.fromOffset(260, 116), Vector2.zero)
local title = label(brand, "DIRTLINE MX", UDim2.fromOffset(16, 10), UDim2.fromOffset(235, 30), 24)
title.Font = Enum.Font.GothamBlack
label(brand, "PHYSICS LAB  /  DL-MX 250F", UDim2.fromOffset(17, 43), UDim2.fromOffset(235, 17), 10, colors.orange)
local helpButton = button(brand, "H  CONTROLS", UDim2.fromOffset(16, 77), UDim2.fromOffset(109, 27))
local tuneButton = button(brand, "U  SUSPENSION", UDim2.fromOffset(135, 77), UDim2.fromOffset(109, 27))

local timing = panel("Timing", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(244, 116), Vector2.new(1, 0))
label(timing, "LAP TIME", UDim2.fromOffset(16, 11), UDim2.fromOffset(210, 17), 10, colors.muted)
local timeLabel = label(timing, "00:00.00", UDim2.fromOffset(14, 29), UDim2.fromOffset(219, 37), 32)
timeLabel.Font = Enum.Font.GothamBold
local bestLabel = label(timing, "BEST    --:--.--", UDim2.fromOffset(16, 86), UDim2.fromOffset(212, 18), 13, colors.teal)

local status = panel("Status", UDim2.new(0.5, 0, 0, 144), UDim2.fromOffset(620, 58), Vector2.new(0.5, 0))
local statusLabel = label(status, "NEUTRAL  /  CLUTCH IN  /  FEET DOWN", UDim2.fromOffset(14, 7), UDim2.new(1, -28, 0, 23), 14, colors.teal)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
local statusHint = label(status, "Select first with E / D-pad up; release clutch with B / LB and add throttle.", UDim2.fromOffset(14, 31), UDim2.new(1, -28, 0, 17), 10, colors.muted)
statusHint.TextXAlignment = Enum.TextXAlignment.Center

local telemetryPanel = panel("Motorcycle", UDim2.new(0, 16, 1, -16), UDim2.fromOffset(332, 224), Vector2.new(0, 1))
label(telemetryPanel, "250F  /  LIVE SIMULATION", UDim2.fromOffset(16, 10), UDim2.fromOffset(300, 17), 10, colors.muted)
local speedLabel = label(telemetryPanel, "0", UDim2.fromOffset(12, 27), UDim2.fromOffset(110, 52), 42)
speedLabel.Font = Enum.Font.GothamBlack
label(telemetryPanel, "KM/H", UDim2.fromOffset(122, 56), UDim2.fromOffset(43, 16), 10, colors.muted)
local gearLabel = label(telemetryPanel, "N", UDim2.fromOffset(214, 24), UDim2.fromOffset(70, 58), 48, colors.orange)
gearLabel.Font = Enum.Font.GothamBlack
local rpmLabel = label(telemetryPanel, "0 RPM", UDim2.fromOffset(16, 83), UDim2.fromOffset(300, 18), 12)
local rpmTrack = create("Frame", telemetryPanel, {
	Position = UDim2.fromOffset(16, 108), Size = UDim2.fromOffset(300, 5), BackgroundColor3 = colors.panelLight, BorderSizePixel = 0,
}) :: Frame
local rpmFill = create("Frame", rpmTrack, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = colors.orange, BorderSizePixel = 0 }) :: Frame
local inputLabel = label(telemetryPanel, "CLUTCH 100%  /  SEATED  /  FEET DOWN", UDim2.fromOffset(16, 123), UDim2.fromOffset(300, 18), 10, colors.teal)
local travelLabel = label(telemetryPanel, "TRAVEL  F 0 mm  /  R 0 mm", UDim2.fromOffset(16, 148), UDim2.fromOffset(300, 18), 11)
local slipLabel = label(telemetryPanel, "SLIP  F 0.00  /  R 0.00", UDim2.fromOffset(16, 174), UDim2.fromOffset(300, 18), 11)
local attitudeLabel = label(telemetryPanel, "ROLL 0°  /  PITCH 0°  /  GROUND", UDim2.fromOffset(16, 198), UDim2.fromOffset(300, 17), 10, colors.muted)

local progressPanel = panel("Progress", UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(290, 90), Vector2.new(0.5, 1))
local lapLabel = label(progressPanel, "LAP 01", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 23), 19)
local gateLabel = label(progressPanel, "NEXT GATE  01 / 01", UDim2.fromOffset(16, 40), UDim2.new(1, -32, 0, 18), 11, colors.muted)
local progressTrack = create("Frame", progressPanel, {
	Position = UDim2.fromOffset(16, 72), Size = UDim2.new(1, -32, 0, 4), BackgroundColor3 = colors.panelLight, BorderSizePixel = 0,
}) :: Frame
local progressFill = create("Frame", progressTrack, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = colors.teal, BorderSizePixel = 0 }) :: Frame

local actionsPanel = panel("Actions", UDim2.new(1, -16, 1, -16), UDim2.fromOffset(224, 132), Vector2.new(1, 1))
label(actionsPanel, "MANUAL SIMULATION", UDim2.fromOffset(16, 10), UDim2.fromOffset(196, 17), 10, colors.orange)
label(actionsPanel, "Riding skill controls balance.\nRecovering invalidates the current lap.", UDim2.fromOffset(16, 31), UDim2.fromOffset(196, 32), 10, colors.muted)
local resetButton = button(actionsPanel, "R  /  Y     RECOVER BIKE", UDim2.fromOffset(16, 70), UDim2.fromOffset(192, 24))
local starterButton = button(actionsPanel, "T  /  L-STICK     START ENGINE", UDim2.fromOffset(16, 100), UDim2.fromOffset(192, 24))

local help = panel("Help", UDim2.fromScale(0.5, 0.48), UDim2.fromOffset(680, 490), Vector2.new(0.5, 0.5))
help.Visible = false
label(help, "LEARN THE 250F", UDim2.fromOffset(22, 14), UDim2.fromOffset(580, 30), 23, colors.orange)
local helpClose = button(help, "CLOSE", UDim2.new(1, -88, 0, 17), UDim2.fromOffset(66, 25))
local keyboardHelp = table.concat({
	"KEYBOARD",
	"W  Progressive throttle    Space  Front brake    S  Rear brake",
	"V / B  Meter clutch in / out    Shift  Quick clutch pull    Q / E  Shift",
	"A / D  Handlebar steering    Z / X  Bike lean",
	"I / K  Body forward / back    J / L  Body left / right",
	"C  Stand / sit    F  Feet down / up",
	"T  Engine starter    R  Recover bike    U  Suspension setup",
}, "\n")
local controllerHelp = table.concat({
	"CONTROLLER",
	"RT  Throttle    LT  Front brake    RB  Rear brake    LB  Pull clutch",
	"Left stick  Steering    Right stick  Rider fore/aft and side",
	"D-pad left / right  Bike lean    D-pad down / up  Shift",
	"A  Stand / sit    X  Feet down / up    Y  Recover",
	"Left stick click  Engine starter    Right stick click  Controls help",
}, "\n")
local helpText = label(help, keyboardHelp .. "\n\n" .. controllerHelp, UDim2.fromOffset(22, 57), UDim2.new(1, -44, 0, 287), 12)
helpText.TextYAlignment = Enum.TextYAlignment.Top
local helpTips = label(help, "Begin in neutral, clutch in and feet down. Select first, add throttle, then hold B to meter clutch release (V pulls it back). Shift is a quick pull override. On controller, hold LB; release it for a 0.6s lever release, re-pull or tap to meter. Lift feet when moving.\n\nIn the air: move your body with I / K and J / L; use Z / X for roll. Throttle and the rear brake affect rotating-wheel reaction. Takeoff and touchdown are physical; there is no landing correction.", UDim2.fromOffset(22, 350), UDim2.new(1, -44, 0, 116), 11, colors.muted)
helpTips.TextWrapped = true
helpTips.TextYAlignment = Enum.TextYAlignment.Top

local tuning = panel("SuspensionSetup", UDim2.fromScale(0.5, 0.48), UDim2.fromOffset(580, 405), Vector2.new(0.5, 0.5))
tuning.Visible = false
label(tuning, "SUSPENSION SETUP", UDim2.fromOffset(22, 14), UDim2.fromOffset(430, 29), 21, colors.orange)
local tuneClose = button(tuning, "CLOSE", UDim2.new(1, -88, 0, 17), UDim2.fromOffset(66, 25))
local tuneExplanation = label(tuning, "Park in the physics lab before applying. A setup change invalidates the current lap.\nValues use SI units; each wheel has its own spring and damping settings.", UDim2.fromOffset(22, 52), UDim2.new(1, -44, 0, 44), 11, colors.muted)
tuneExplanation.TextWrapped = true
label(tuning, "FRONT", UDim2.fromOffset(22, 103), UDim2.fromOffset(244, 21), 13, colors.teal)
label(tuning, "REAR", UDim2.fromOffset(310, 103), UDim2.fromOffset(244, 21), 13, colors.teal)

local setupValues: { [string]: { [string]: number } } = { Front = {}, Rear = {} }
local setupBoxes: { [string]: { [string]: TextBox } } = { Front = {}, Rear = {} }
local setupRows = {
	{ key = "SpringRate", title = "Spring (N/m)", step = 500, min = 8000, max = 40000, format = "%.0f" },
	{ key = "Compression", title = "Compress (N·s/m)", step = 100, min = 300, max = 5000, format = "%.0f" },
	{ key = "Rebound", title = "Rebound (N·s/m)", step = 100, min = 300, max = 6000, format = "%.0f" },
	{ key = "Preload", title = "Preload (m)", step = 0.002, min = 0, max = 0.035, format = "%.3f" },
}

local function updateSetupBox(side: string, spec: any)
	setupBoxes[side][spec.key].Text = string.format(spec.format, setupValues[side][spec.key])
end

for sideIndex, side in ipairs({ "Front", "Rear" }) do
	local x = if sideIndex == 1 then 22 else 310
	for rowIndex, spec in ipairs(setupRows) do
		local y = 130 + (rowIndex - 1) * 43
		setupValues[side][spec.key] = bikeConfig.Suspension[side][spec.key]
		label(tuning, spec.title, UDim2.fromOffset(x, y), UDim2.fromOffset(131, 26), 10, colors.muted)
		local minus = button(tuning, "−", UDim2.fromOffset(x + 134, y), UDim2.fromOffset(24, 27))
		local box = create("TextBox", tuning, {
			Position = UDim2.fromOffset(x + 162, y), Size = UDim2.fromOffset(57, 27), BackgroundColor3 = colors.panelLight,
			Text = "", ClearTextOnFocus = false, TextSize = 11, Font = Enum.Font.GothamMedium, TextColor3 = colors.text, BorderSizePixel = 0,
		}) :: TextBox
		corner(box, 5)
		setupBoxes[side][spec.key] = box
		updateSetupBox(side, spec)
		local plus = button(tuning, "+", UDim2.fromOffset(x + 222, y), UDim2.fromOffset(24, 27))
		minus.Activated:Connect(function()
			setupValues[side][spec.key] = math.clamp(setupValues[side][spec.key] - spec.step, spec.min, spec.max)
			updateSetupBox(side, spec)
		end)
		plus.Activated:Connect(function()
			setupValues[side][spec.key] = math.clamp(setupValues[side][spec.key] + spec.step, spec.min, spec.max)
			updateSetupBox(side, spec)
		end)
		box.FocusLost:Connect(function()
			local number = tonumber(box.Text)
			if number and number == number and math.abs(number) < math.huge then
				setupValues[side][spec.key] = math.clamp(number, spec.min, spec.max)
			end
			updateSetupBox(side, spec)
		end)
	end
end
local defaultsButton = button(tuning, "250F DEFAULTS", UDim2.fromOffset(22, 318), UDim2.fromOffset(157, 30))
local applyButton = button(tuning, "APPLY PARKED SETUP", UDim2.fromOffset(192, 318), UDim2.fromOffset(366, 30))
local setupStatus = label(tuning, "Defaults shown. Acceptance is confirmed by the server.", UDim2.fromOffset(22, 364), UDim2.new(1, -44, 0, 19), 10, colors.muted)
defaultsButton.Activated:Connect(function()
	for _, side in ipairs({ "Front", "Rear" }) do
		for _, spec in ipairs(setupRows) do
			setupValues[side][spec.key] = bikeConfig.Suspension[side][spec.key]
			updateSetupBox(side, spec)
		end
	end
end)

local mobileNotice = panel("MobileNotice", UDim2.fromScale(0.5, 0.37), UDim2.fromOffset(580, 92), Vector2.new(0.5, 0.5))
mobileNotice.Visible = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
local mobileText = label(mobileNotice, "Simulation controls require a keyboard or controller.\nMobile riding controls will be adapted later.", UDim2.fromOffset(18, 15), UDim2.new(1, -36, 1, -30), 14, colors.orange)
mobileText.TextWrapped = true
mobileText.TextXAlignment = Enum.TextXAlignment.Center

local seated = false
local focused = true
local menuOpen = false
local heldKeys: { [Enum.KeyCode]: boolean } = {}
local steerStick, bodySideStick, bodyForwardStick, triggerThrottle, triggerFrontBrake = 0, 0, 0, 0, 0
local keyboardThrottle, keyboardFrontBrake, keyboardRearBrake = 0, 0, 0
local standing = false
local footDown = true
local safetyClutch = true
local manualClutch = 1
local gamepadClutch = 1
local gamepadMode = false
local pendingShifts: { number } = {}
local sequence = 0
local lastRecovery = -math.huge
local lastStarter = -math.huge
local ownedBike: Instance? = nil
local bindingActive = false

local function canAct(): boolean
	return focused and not menuOpen and UserInputService:GetFocusedTextBox() == nil
end

local function canDrive(): boolean
	return seated and canAct() and not help.Visible and not tuning.Visible
end

local function sendPacket(packet: { [string]: any })
	sequence += 1
	packet.seq = sequence
	inputRemote:FireServer(packet)
end

local function neutralPacket(): { [string]: any }
	return {
		throttle = 0, frontBrake = 0, rearBrake = 0, clutch = 1,
		steer = 0, lean = 0, bodyForward = 0, bodySide = 0,
		standing = standing, footDown = footDown, shift = 0,
	}
end

local function clearControls()
	table.clear(heldKeys)
	table.clear(pendingShifts)
	steerStick, bodySideStick, bodyForwardStick, triggerThrottle, triggerFrontBrake = 0, 0, 0, 0, 0
	keyboardThrottle, keyboardFrontBrake, keyboardRearBrake = 0, 0, 0
	safetyClutch = true
	manualClutch, gamepadClutch = 1, 1
	-- Focus loss sends an immediate release; the server also enforces an input timeout.
	sendPacket(neutralPacket())
end

local function toggleHelp()
	help.Visible = not help.Visible
	tuning.Visible = false
	clearControls()
end
local function toggleTuning()
	tuning.Visible = not tuning.Visible
	help.Visible = false
	clearControls()
end
helpButton.Activated:Connect(toggleHelp)
helpClose.Activated:Connect(toggleHelp)
tuneButton.Activated:Connect(toggleTuning)
tuneClose.Activated:Connect(toggleTuning)

local function resetBike()
	if not canAct() or os.clock() - lastRecovery < 0.8 then
		return
	end
	lastRecovery = os.clock()
	standing = false
	footDown = true
	clearControls()
	actionRemote:FireServer("Respawn")
end
local function startEngine()
	if not canAct() or os.clock() - lastStarter < 0.5 then
		return
	end
	lastStarter = os.clock()
	actionRemote:FireServer("StartEngine")
end
resetButton.Activated:Connect(resetBike)
starterButton.Activated:Connect(startEngine)
applyButton.Activated:Connect(function()
	if not canAct() then
		return
	end
	clearControls()
	actionRemote:FireServer("Tune", { Front = table.clone(setupValues.Front), Rear = table.clone(setupValues.Rear) })
	setupStatus.Text = "Setup requested. Waiting for server confirmation."
end)

local function deadzone(value: number): number
	return if math.abs(value) < 0.08 then 0 else math.sign(value) * ((math.abs(value) - 0.08) / 0.92)
end

local function handleControl(_actionName: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local key = input.KeyCode
	local released = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
	if released then
		heldKeys[key] = nil
		if key == Enum.KeyCode.Thumbstick1 then
			steerStick = 0
		elseif key == Enum.KeyCode.Thumbstick2 then
			bodySideStick, bodyForwardStick = 0, 0
		elseif key == Enum.KeyCode.ButtonR2 then
			triggerThrottle = 0
		elseif key == Enum.KeyCode.ButtonL2 then
			triggerFrontBrake = 0
		end
	end
	if not canAct() then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		if key == Enum.KeyCode.H or key == Enum.KeyCode.ButtonR3 then
			toggleHelp()
			return Enum.ContextActionResult.Sink
		elseif key == Enum.KeyCode.U then
			toggleTuning()
			return Enum.ContextActionResult.Sink
		elseif key == Enum.KeyCode.R or key == Enum.KeyCode.ButtonY then
			resetBike()
			return Enum.ContextActionResult.Sink
		elseif key == Enum.KeyCode.T or key == Enum.KeyCode.ButtonL3 then
			startEngine()
			return Enum.ContextActionResult.Sink
		end
	end
	if not canDrive() then
		-- Permit GUI navigation, while preventing Space from ejecting the
		-- seated rider when a setup/help panel covers the riding HUD.
		if key == Enum.KeyCode.Space then return Enum.ContextActionResult.Sink end
		return Enum.ContextActionResult.Pass
	end
	if not released then
		gamepadMode = string.sub(input.UserInputType.Name, 1, 7) == "Gamepad"
		if key == Enum.KeyCode.Thumbstick1 then
			steerStick = deadzone(input.Position.X)
		elseif key == Enum.KeyCode.Thumbstick2 then
			bodySideStick = deadzone(input.Position.X)
			bodyForwardStick = deadzone(input.Position.Y)
		elseif key == Enum.KeyCode.ButtonR2 then
			triggerThrottle = math.clamp(input.Position.Z, 0, 1)
		elseif key == Enum.KeyCode.ButtonL2 then
			triggerFrontBrake = math.clamp(input.Position.Z, 0, 1)
		else
			local wasHeld = heldKeys[key] == true
			heldKeys[key] = true
			if inputState == Enum.UserInputState.Begin and not wasHeld then
				if key == Enum.KeyCode.C or key == Enum.KeyCode.ButtonA then
					standing = not standing
				elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonX then
					footDown = not footDown
				elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.DPadDown then
					if #pendingShifts < 4 then table.insert(pendingShifts, -1) end
				elseif key == Enum.KeyCode.E or key == Enum.KeyCode.DPadUp then
					if #pendingShifts < 4 then table.insert(pendingShifts, 1) end
				end
			end
		end
		-- The first deliberate input leaves the focus-loss safety state.
		-- The manual lever still starts pulled until the rider releases it.
		if inputState == Enum.UserInputState.Begin or triggerThrottle > 0.01 then
			safetyClutch = false
		end
	end
	return Enum.ContextActionResult.Sink
end

local controlKeys = {
	Enum.KeyCode.W, Enum.KeyCode.Space, Enum.KeyCode.S, Enum.KeyCode.LeftShift, Enum.KeyCode.V, Enum.KeyCode.B,
	Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.Z, Enum.KeyCode.X,
	Enum.KeyCode.I, Enum.KeyCode.K, Enum.KeyCode.J, Enum.KeyCode.L,
	Enum.KeyCode.C, Enum.KeyCode.F, Enum.KeyCode.Q, Enum.KeyCode.E,
	Enum.KeyCode.R, Enum.KeyCode.T, Enum.KeyCode.H, Enum.KeyCode.U,
	Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2,
	Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL1,
	Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadUp,
	Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonL3, Enum.KeyCode.ButtonR3,
}

local function setBindings(enabled: boolean)
	if bindingActive == enabled then return end
	bindingActive = enabled
	if enabled then
		-- Right stick is body motion while mounted; mouse camera still works.
		ContextActionService:BindActionAtPriority("DirtlineSimulation", handleControl, false, 3000, table.unpack(controlKeys))
	else
		ContextActionService:UnbindAction("DirtlineSimulation")
	end
end

local function ownsSeat(seat: BasePart?): boolean
	if seat == nil or not seat:IsA("Seat") or seat.Name ~= "DriverSeat" then
		return false
	end
	local ancestor: Instance? = seat
	while ancestor and ancestor ~= workspace do
		if ancestor:GetAttribute("OwnerUserId") == player.UserId then
			ownedBike = ancestor
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
		setBindings(seated)
	end
end

local characterConnections: { RBXScriptConnection } = {}
local function watchCharacter(character: Model)
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
	seated = false
	setBindings(false)
	clearControls()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") or player.Character ~= character then return end
	table.insert(characterConnections, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function() updateSeat(humanoid) end))
	table.insert(characterConnections, humanoid.Died:Connect(function() updateSeat(humanoid) end))
	updateSeat(humanoid)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then task.spawn(watchCharacter, player.Character) end

UserInputService.InputEnded:Connect(function(input: InputObject)
	heldKeys[input.KeyCode] = nil
end)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	-- Recovery remains reachable after a crash ejects the rider; normal riding
	-- actions are only bound while seated in the player's own plain Seat.
	if processed or seated or not canAct() or ownedBike == nil then return end
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
		resetBike()
	elseif input.KeyCode == Enum.KeyCode.H or input.KeyCode == Enum.KeyCode.ButtonR3 then
		toggleHelp()
	elseif input.KeyCode == Enum.KeyCode.U then
		toggleTuning()
	end
end)
UserInputService.WindowFocusReleased:Connect(function() focused = false; clearControls() end)
UserInputService.WindowFocused:Connect(function() focused = true end)
UserInputService.TextBoxFocused:Connect(clearControls)
GuiService.MenuOpened:Connect(function() menuOpen = true; clearControls() end)
GuiService.MenuClosed:Connect(function() menuOpen = false end)
UserInputService.GamepadDisconnected:Connect(clearControls)

local function layout()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local scale = math.clamp(math.min(viewport.X / 1180, viewport.Y / 730), 0.44, 1)
	for _, panelScale in ipairs(panelScales) do panelScale.Scale = scale end
	status.Position = UDim2.new(0.5, 0, 0, 16 + 116 * scale + 12)
	local compact = viewport.X < 1050
	progressPanel.AnchorPoint = if compact then Vector2.new(1, 0) else Vector2.new(0.5, 1)
	progressPanel.Position = if compact then UDim2.new(1, -16, 0, 16 + 116 * scale + 12) else UDim2.new(0.5, 0, 1, -16)
	if compact then status.Position = UDim2.new(0.5, 0, 0, 16 + 218 * scale + 12) end
	mobileNotice.Visible = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
end
local viewportConnection: RBXScriptConnection? = nil
local function watchCamera()
	if viewportConnection then viewportConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
	layout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(layout)
UserInputService.GamepadConnected:Connect(layout)
UserInputService.GamepadDisconnected:Connect(layout)
watchCamera()

local race = {
	speed = 0, lap = 1, nextCheckpoint = 1, checkpointCount = 1, lapTime = 0,
	bestLap = nil :: number?, lapsFinished = 0, racing = false,
}
local physics: { [string]: any } = {
	rpm = 0, gear = 0, clutch = 1, frontCompression = 0, rearCompression = 0,
	frontSlip = 0, rearSlip = 0, roll = 0, pitch = 0, grounded = false,
	crashed = false, crashReason = "", standing = false, footDown = true, stalled = false, setupVersion = 0, recoveryRemaining = 0, surfaceFront = "dirt", surfaceRear = "dirt",
}
local receivedAt = os.clock()
local physicsReceivedAt = os.clock()
local eventMessage, eventMessageUntil = "", 0
local lastSetupVersion = 0

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 1e9
end
local function timeText(seconds: number): string
	local hundredths = math.floor(math.max(seconds, 0) * 100)
	return string.format("%02d:%02d.%02d", math.floor(hundredths / 6000), math.floor(hundredths / 100) % 60, hundredths % 100)
end

stateRemote.OnClientEvent:Connect(function(snapshot: any)
	if type(snapshot) ~= "table" then return end
	if finite(snapshot.speed) then race.speed = math.clamp(snapshot.speed, 0, 500) end
	if finite(snapshot.lap) then race.lap = math.clamp(math.floor(snapshot.lap), 1, 99999) end
	if finite(snapshot.checkpointCount) then race.checkpointCount = math.clamp(math.floor(snapshot.checkpointCount), 1, 999) end
	if finite(snapshot.nextCheckpoint) then race.nextCheckpoint = math.clamp(math.floor(snapshot.nextCheckpoint), 1, race.checkpointCount) end
	if finite(snapshot.lapTime) then race.lapTime = math.clamp(snapshot.lapTime, 0, 86400); receivedAt = os.clock() end
	if finite(snapshot.bestLap) and snapshot.bestLap > 0 then race.bestLap = math.clamp(snapshot.bestLap, 0, 86400) end
	if finite(snapshot.lapsFinished) then race.lapsFinished = math.clamp(math.floor(snapshot.lapsFinished), 0, 99999) end
	if type(snapshot.racing) == "boolean" then race.racing = snapshot.racing end
	if type(snapshot.message) == "string" and snapshot.message ~= "" then
		local message = string.sub(snapshot.message, 1, 120)
		if eventMessage ~= message then eventMessage = message; eventMessageUntil = os.clock() + 4 end
		if tuning.Visible then setupStatus.Text = message end
	elseif snapshot.message == nil then
		eventMessage, eventMessageUntil = "", 0
	end
	if type(snapshot.physics) == "table" then
		local source = snapshot.physics
		physicsReceivedAt = os.clock()
		for _, field in ipairs({ "rpm", "gear", "clutch", "frontCompression", "rearCompression", "frontSlip", "rearSlip", "roll", "pitch", "setupVersion", "recoveryRemaining" }) do
			if finite(source[field]) then physics[field] = source[field] end
		end
		for _, field in ipairs({ "grounded", "crashed", "standing", "footDown", "stalled" }) do
			if type(source[field]) == "boolean" then physics[field] = source[field] end
		end
		if type(source.crashReason) == "string" then physics.crashReason = string.sub(source.crashReason, 1, 90) end
		for _, field in ipairs({ "surfaceFront", "surfaceRear" }) do
			if type(source[field]) == "string" then physics[field] = string.sub(source[field], 1, 16) end
		end
		if physics.setupVersion ~= lastSetupVersion then
			lastSetupVersion = physics.setupVersion
			setupStatus.Text = string.format("Server confirmed setup version %d.", math.floor(lastSetupVersion))
		end
	end
	lapLabel.Text = string.format("LAP %02d", race.lap)
	gateLabel.Text = if race.racing and race.nextCheckpoint == 1 then "NEXT GATE  START / FINISH" else string.format("NEXT GATE  %02d / %02d", race.nextCheckpoint, race.checkpointCount)
	local cleared = if race.racing and race.nextCheckpoint == 1 then race.checkpointCount else race.nextCheckpoint - 1
	progressFill.Size = UDim2.fromScale(cleared / race.checkpointCount, 1)
	bestLabel.Text = "BEST    " .. (if race.bestLap then timeText(race.bestLap) else "--:--.--")
end)

local function pressed(key: Enum.KeyCode): number
	return if heldKeys[key] then 1 else 0
end
local function approach(value: number, target: number, rate: number, deltaTime: number): number
	local step = rate * deltaTime
	return value + math.clamp(target - value, -step, step)
end
local function controls(): { [string]: any }
	return {
		throttle = math.max(keyboardThrottle, triggerThrottle),
		frontBrake = math.max(keyboardFrontBrake, triggerFrontBrake),
		rearBrake = math.max(keyboardRearBrake, pressed(Enum.KeyCode.ButtonR1)),
		clutch = if safetyClutch or heldKeys[Enum.KeyCode.LeftShift] or heldKeys[Enum.KeyCode.ButtonL1] then 1 else (if gamepadMode then gamepadClutch else manualClutch),
		steer = math.clamp(pressed(Enum.KeyCode.D) - pressed(Enum.KeyCode.A) + steerStick, -1, 1),
		lean = math.clamp(pressed(Enum.KeyCode.X) + pressed(Enum.KeyCode.DPadRight) - pressed(Enum.KeyCode.Z) - pressed(Enum.KeyCode.DPadLeft), -1, 1),
		bodyForward = math.clamp(pressed(Enum.KeyCode.I) - pressed(Enum.KeyCode.K) + bodyForwardStick, -1, 1),
		bodySide = math.clamp(pressed(Enum.KeyCode.L) - pressed(Enum.KeyCode.J) + bodySideStick, -1, 1),
		standing = standing, footDown = footDown,
		shift = if #pendingShifts > 0 then table.remove(pendingShifts, 1) else 0,
	}
end

local sendAccumulator = 0
local displayedSpeed = 0
RunService.Heartbeat:Connect(function(deltaTime: number)
	if canDrive() then
		keyboardThrottle = approach(keyboardThrottle, pressed(Enum.KeyCode.W), if heldKeys[Enum.KeyCode.W] then 1.5 else 4, deltaTime)
		keyboardFrontBrake = approach(keyboardFrontBrake, pressed(Enum.KeyCode.Space), 3, deltaTime)
		keyboardRearBrake = approach(keyboardRearBrake, pressed(Enum.KeyCode.S), 3, deltaTime)
		-- V/B directly position the clutch lever; no engine or traction state
		-- changes their response. LB has a fixed physical release travel time.
		manualClutch = math.clamp(manualClutch + (pressed(Enum.KeyCode.V) - pressed(Enum.KeyCode.B)) * 1.4 * deltaTime, 0, 1)
		gamepadClutch = if safetyClutch or heldKeys[Enum.KeyCode.ButtonL1] then 1 else approach(gamepadClutch, 0, 1 / 0.6, deltaTime)
	end
	sendAccumulator += deltaTime
	if sendAccumulator >= 1 / 30 then
		sendAccumulator %= 1 / 30
		if canDrive() then sendPacket(controls()) end
	end
end)

RunService.RenderStepped:Connect(function(deltaTime: number)
	displayedSpeed += (race.speed - displayedSpeed) * math.min(1, deltaTime * 9)
	speedLabel.Text = tostring(math.floor(displayedSpeed + 0.5))
	gearLabel.Text = if physics.gear == 0 then "N" else tostring(math.clamp(math.floor(physics.gear), 1, 5))
	rpmLabel.Text = string.format("%d RPM", math.floor(math.clamp(physics.rpm, 0, 25000)))
	rpmFill.Size = UDim2.fromScale(math.clamp(physics.rpm / bikeConfig.Drive.RedlineRPM, 0, 1), 1)
	rpmFill.BackgroundColor3 = if physics.rpm > bikeConfig.Drive.RedlineRPM * 0.93 then colors.red else colors.orange
	inputLabel.Text = string.format("CLUTCH %d%%  /  %s  /  FEET %s", math.floor(math.clamp(physics.clutch, 0, 1) * 100 + 0.5), if physics.standing then "STANDING" else "SEATED", if physics.footDown then "DOWN" else "UP")
	travelLabel.Text = string.format("TRAVEL  F %d mm  /  R %d mm", math.floor(physics.frontCompression * 1000 + 0.5), math.floor(physics.rearCompression * 1000 + 0.5))
	slipLabel.Text = string.format("SLIP  F %+.2f  /  R %+.2f  /  %s", physics.frontSlip, physics.rearSlip, string.upper(physics.surfaceRear))
	attitudeLabel.Text = string.format("ROLL %+.0f°  /  PITCH %+.0f°  /  %s", math.deg(physics.roll), math.deg(physics.pitch), if physics.grounded then "GROUND" else "AIR")
	-- Only display extrapolation: neither race state nor physics is predicted here.
	local extrapolated = if race.racing then math.min(os.clock() - receivedAt, 1) else 0
	timeLabel.Text = timeText(race.lapTime + extrapolated)
	statusLabel.TextColor3 = colors.teal
	if physics.crashed then
		statusLabel.TextColor3 = colors.red
		statusLabel.Text = "CRASH  /  " .. string.upper(physics.crashReason)
		local remaining = math.max(0, physics.recoveryRemaining - math.min(os.clock() - physicsReceivedAt, 1))
		statusHint.Text = if remaining > 0 then string.format("Recover available in %.1f seconds.", remaining) else "Press R / Y to recover. Your current lap is invalid."
	elseif physics.stalled then
		statusLabel.TextColor3 = colors.orange
		statusLabel.Text = "ENGINE STALLED"
		statusHint.Text = "Pull the clutch (Left Shift / LB), then press T / left stick click to start."
	elseif os.clock() < eventMessageUntil then
		statusLabel.Text = eventMessage
		statusHint.Text = "H: full controls   U: suspension setup   R / Y: recover"
	elseif not seated then
		statusLabel.Text = "PRESS R / Y TO RECOVER YOUR MOTORCYCLE"
		statusHint.Text = "Simulation riding requires a keyboard or controller."
	elseif physics.gear == 0 then
		statusLabel.Text = "NEUTRAL  /  SELECT FIRST GEAR"
		statusHint.Text = "E / D-pad up selects first. B meters clutch out; V pulls in. LB releases over 0.6s."
	elseif race.racing then
		statusLabel.Text = if race.nextCheckpoint == 1 then "CROSS START / FINISH TO COMPLETE YOUR LAP" else string.format("LAP %02d  /  FOLLOW GATE %02d", race.lap, race.nextCheckpoint)
		statusHint.Text = "Braking, lean and throttle share tire grip. Balance is your responsibility."
	else
		statusLabel.Text = "PHYSICS LAB  /  CROSS THE START GATE TO BEGIN"
		statusHint.Text = "Practice turns, bumps and jumps. Use H for the full manual controls."
	end
end)
