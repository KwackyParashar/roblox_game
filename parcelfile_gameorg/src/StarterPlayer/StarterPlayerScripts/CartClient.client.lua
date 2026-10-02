-- CartClient v4 | LocalScript | StarterPlayer > StarterPlayerScripts
-- Always-on mouselook (cursor hidden + centered, crosshair shown), HUD, dialogue box.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local cart = workspace:WaitForChild("Cart")

----------------------------------------------------------------
-- LOOK SETTINGS
----------------------------------------------------------------
local LOOK_SENSITIVITY = 0.25  -- degrees turned per pixel of mouse movement
local KEY_TURN_SPEED = 90      -- degrees per second when using the arrow keys (kept as a backup option)
local MAX_PITCH = 80

local yaw, pitch = 0, 0
local inDialogue = false
local easeBack = false
local inCutscene = false
local CUTSCENE_PITCH = math.rad(30) -- how far the view dips down; flip the sign if it dips the wrong way

----------------------------------------------------------------
-- 1) Camera fixed in place, mouse always looks around
----------------------------------------------------------------
local cameraPoint = cart:WaitForChild("CameraPoint", 10)

local function hidePart(obj)
	if obj:IsA("BasePart") or obj:IsA("Decal") then
		obj.Transparency = 1
	end
end

local function setupCharacter(character)
	local hum = character:WaitForChild("Humanoid", 10)
	if hum then
		hum.WalkSpeed = 0
		hum.UseJumpPower = true
		hum.JumpPower = 0
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	for _, d in ipairs(character:GetDescendants()) do hidePart(d) end
	character.DescendantAdded:Connect(hidePart)
end

local function setLookLocked(locked)
	if locked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

if cameraPoint then
	if player.Character then task.spawn(setupCharacter, player.Character) end
	player.CharacterAdded:Connect(setupCharacter)

	setLookLocked(true) -- cursor hidden + centered by default; crosshair added in the HUD section below

	RunService:BindToRenderStep("CartCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local rx, ry = cameraPoint.CFrame:ToOrientation()

		if inDialogue or easeBack or inCutscene then
			yaw = (yaw + math.pi) % (2 * math.pi) - math.pi
			local a = math.min(1, dt * 6)
			local targetPitch = inCutscene and CUTSCENE_PITCH or 0
			yaw -= yaw * a
			pitch += (targetPitch - pitch) * a
			if not inDialogue and not inCutscene and math.abs(yaw) < 0.005 and math.abs(pitch) < 0.005 then
				yaw, pitch = 0, 0
				easeBack = false
			end
		else
			local turn = math.rad(KEY_TURN_SPEED) * dt
			if UserInputService:IsKeyDown(Enum.KeyCode.Left) then yaw += turn end
			if UserInputService:IsKeyDown(Enum.KeyCode.Right) then yaw -= turn end
			if UserInputService:IsKeyDown(Enum.KeyCode.Up) then pitch += turn end
			if UserInputService:IsKeyDown(Enum.KeyCode.Down) then pitch -= turn end
		end

		local maxP = math.rad(MAX_PITCH)
		pitch = math.clamp(pitch, -maxP - rx, maxP - rx)

		local t = os.clock()
		local sway = CFrame.Angles(math.sin(t * 0.5) * 0.0015, math.sin(t * 0.35) * 0.002, 0)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.new(cameraPoint.Position)
			* CFrame.fromOrientation(rx + pitch, ry + yaw, 0)
			* sway
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.R and not inDialogue and not inCutscene then
			easeBack = true
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not inDialogue and not inCutscene and input.UserInputType == Enum.UserInputType.MouseMovement then
			yaw -= math.rad(input.Delta.X * LOOK_SENSITIVITY)
			pitch -= math.rad(input.Delta.Y * LOOK_SENSITIVITY)
		end
	end)
else
	warn("[CartClient] CameraPoint not found inside Workspace > Cart. Camera left normal.")
end

----------------------------------------------------------------
-- 2) HUD
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CartHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function addCorner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = obj
end

local function styleBox(label)
	label.BackgroundColor3 = Color3.fromRGB(35, 28, 22)
	label.TextColor3 = Color3.fromRGB(255, 240, 220)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 20
	addCorner(label)
end

-- Crosshair (replaces the OS cursor while the mouse is locked to center)
local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(16, 16)
crosshair.BackgroundTransparency = 1
crosshair.Parent = gui

local function crossBar(w, h)
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromOffset(w, h)
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.5
	stroke.Parent = bar
	bar.Parent = crosshair
end
crossBar(14, 2)
crossBar(2, 14)

-- What's in your hand (bottom-left)
local heldLabel = Instance.new("TextLabel")
heldLabel.AnchorPoint = Vector2.new(0, 1)
heldLabel.Position = UDim2.fromScale(0.02, 0.96)
heldLabel.Size = UDim2.fromOffset(300, 42)
heldLabel.BackgroundTransparency = 0.35
heldLabel.Visible = false
styleBox(heldLabel)
heldLabel.Parent = gui

-- Short messages (top-center)
local msgLabel = Instance.new("TextLabel")
msgLabel.AnchorPoint = Vector2.new(0.5, 0)
msgLabel.Position = UDim2.fromScale(0.5, 0.06)
msgLabel.Size = UDim2.fromOffset(460, 44)
msgLabel.BackgroundTransparency = 1
msgLabel.TextTransparency = 1
msgLabel.TextWrapped = true
styleBox(msgLabel)
msgLabel.Parent = gui

-- Day + clock (top-left)
local dayClockLabel = Instance.new("TextLabel")
dayClockLabel.AnchorPoint = Vector2.new(0, 0)
dayClockLabel.Position = UDim2.fromScale(0.02, 0.03)
dayClockLabel.Size = UDim2.fromOffset(220, 40)
dayClockLabel.BackgroundTransparency = 0.35
dayClockLabel.Text = "Day 1  •  6:00 PM"
styleBox(dayClockLabel)
dayClockLabel.Parent = gui

-- Coins (top-right)
local coinLabel = Instance.new("TextLabel")
coinLabel.AnchorPoint = Vector2.new(1, 0)
coinLabel.Position = UDim2.fromScale(0.98, 0.03)
coinLabel.Size = UDim2.fromOffset(140, 40)
coinLabel.BackgroundTransparency = 0.35
coinLabel.Text = "🪙 0"
styleBox(coinLabel)
coinLabel.Parent = gui

local function formatClock(t)
	t = t % 24
	local hour24 = math.floor(t)
	local minute = math.floor((t - hour24) * 60)
	local suffix = (hour24 >= 12) and "PM" or "AM"
	local hour12 = hour24 % 12
	if hour12 == 0 then hour12 = 12 end
	return string.format("%d:%02d %s", hour12, minute, suffix)
end

local clockUI = ReplicatedStorage:WaitForChild("ClockUI")
local endDayPrompt = Instance.new("TextLabel")
endDayPrompt.AnchorPoint = Vector2.new(0.5, 1)
endDayPrompt.Position = UDim2.fromScale(0.5, 0.9)
endDayPrompt.Size = UDim2.fromOffset(320, 40)
endDayPrompt.BackgroundTransparency = 1
endDayPrompt.TextColor3 = Color3.fromRGB(255, 244, 220)
endDayPrompt.Font = Enum.Font.GothamBold
endDayPrompt.TextSize = 22
endDayPrompt.TextStrokeTransparency = 0.4
endDayPrompt.Text = "Press [ E ] to end the day"
endDayPrompt.Visible = false
endDayPrompt.Parent = gui

local dayEndRemote = ReplicatedStorage:WaitForChild("DayEnd")
local endDayActive = false

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if endDayActive and input.KeyCode == Enum.KeyCode.E then
		endDayActive = false
		endDayPrompt.Visible = false
		dayEndRemote:FireServer()
	end
end)

RunService.RenderStepped:Connect(function()
	if endDayActive then
		local a = (math.sin(os.clock() * 3) + 1) / 2
		endDayPrompt.TextTransparency = 0.15 + a * 0.6
	end
end)

clockUI.OnClientEvent:Connect(function(day, clockTime, showEndPrompt)
	dayClockLabel.Text = ("Day %d  •  %s"):format(day, formatClock(clockTime))
	endDayActive = showEndPrompt or false
	endDayPrompt.Visible = endDayActive
end)

local function updateCoinLabel()
	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	if coins then
		coinLabel.Text = "🪙 " .. coins.Value
		coins:GetPropertyChangedSignal("Value"):Connect(function()
			coinLabel.Text = "🪙 " .. coins.Value
		end)
	end
end
if player:FindFirstChild("leaderstats") then
	updateCoinLabel()
else
	player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then updateCoinLabel() end
	end)
end

local msgToken = 0
local function showMessage(text, duration)
	msgToken += 1
	local mine = msgToken
	msgLabel.Text = text
	msgLabel.TextTransparency = 0
	msgLabel.BackgroundTransparency = 0.35
	task.delay(duration or 2.4, function()
		if mine ~= msgToken then return end
		TweenService:Create(msgLabel, TweenInfo.new(0.6), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
	end)
end

local notify = ReplicatedStorage:WaitForChild("Notify")
notify.OnClientEvent:Connect(function(kind, text, extra)
	if kind == "held" then
		heldLabel.Visible = text ~= ""
		heldLabel.Text = "In hand: " .. text
	elseif kind == "msg" then
		showMessage(text, extra)
	end
end)

local passportCutscene = ReplicatedStorage:WaitForChild("PassportCutscene")
passportCutscene.OnClientEvent:Connect(function(action)
	if action == "start" then
		inCutscene = true
	elseif action == "end" then
		inCutscene = false
	end
end)

task.delay(1.5, function()
	showMessage("Move your mouse to look around  •  R to recenter", 5)
end)

----------------------------------------------------------------
-- 3) Dialogue box
----------------------------------------------------------------
local dialogueRemote = ReplicatedStorage:WaitForChild("Dialogue")

local panel = Instance.new("TextButton")
panel.Name = "DialoguePanel"
panel.AutoButtonColor = false
panel.Text = ""
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.fromScale(0.5, 0.96)
panel.Size = UDim2.new(0.6, 0, 0, 150)
panel.BackgroundColor3 = Color3.fromRGB(35, 28, 22)
panel.BackgroundTransparency = 0.12
panel.Visible = false
addCorner(panel, 14)
local limit = Instance.new("UISizeConstraint")
limit.MinSize = Vector2.new(340, 150)
limit.MaxSize = Vector2.new(820, 200)
limit.Parent = panel
panel.Parent = gui

local nameLabel = Instance.new("TextLabel")
nameLabel.BackgroundTransparency = 1
nameLabel.Position = UDim2.fromOffset(18, 10)
nameLabel.Size = UDim2.new(0.6, 0, 0, 26)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 22
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.Parent = panel

local textLabel = Instance.new("TextLabel")
textLabel.BackgroundTransparency = 1
textLabel.Position = UDim2.fromOffset(18, 42)
textLabel.Size = UDim2.new(1, -36, 1, -66)
textLabel.Font = Enum.Font.GothamMedium
textLabel.TextSize = 22
textLabel.TextColor3 = Color3.fromRGB(255, 244, 228)
textLabel.TextWrapped = true
textLabel.TextXAlignment = Enum.TextXAlignment.Left
textLabel.TextYAlignment = Enum.TextYAlignment.Top
textLabel.Parent = panel

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(1, 1)
hint.Position = UDim2.new(1, -16, 1, -8)
hint.Size = UDim2.fromOffset(80, 20)
hint.Font = Enum.Font.Gotham
hint.TextSize = 16
hint.TextColor3 = Color3.fromRGB(200, 180, 150)
hint.Text = "▼ click"
hint.Visible = false
hint.Parent = panel

local choiceFrame = Instance.new("Frame")
choiceFrame.AnchorPoint = Vector2.new(0.5, 1)
choiceFrame.Position = UDim2.fromScale(0.5, 0.96)
choiceFrame.Size = UDim2.new(0.6, 0, 0, 0)
choiceFrame.AutomaticSize = Enum.AutomaticSize.Y
choiceFrame.BackgroundTransparency = 1
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.VerticalAlignment = Enum.VerticalAlignment.Bottom
list.Parent = choiceFrame
local choiceLimit = Instance.new("UISizeConstraint")
choiceLimit.MinSize = Vector2.new(340, 0)
choiceLimit.MaxSize = Vector2.new(820, math.huge)
choiceLimit.Parent = choiceFrame
choiceFrame.Parent = gui

local mode = "none" -- "line" | "choice" | "none"
local typing = false
local lineToken = 0

local function clearChoices()
	for _, child in ipairs(choiceFrame:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function enterDialogue()
	inDialogue = true
	setLookLocked(false)
	crosshair.Visible = false
end

local function showLine(speaker, text)
	clearChoices()
	panel.Visible = true
	nameLabel.Text = speaker
	nameLabel.TextColor3 = (speaker == "You") and Color3.fromRGB(150, 200, 255) or Color3.fromRGB(255, 190, 120)
	hint.Visible = false
	mode = "line"

	lineToken += 1
	local mine = lineToken
	textLabel.Text = text
	textLabel.MaxVisibleGraphemes = 0
	typing = true

	task.spawn(function()
		local n = utf8.len(text) or #text
		for i = 1, n do
			if not typing or mine ~= lineToken then break end
			textLabel.MaxVisibleGraphemes = i
			task.wait(0.028)
		end
		if mine == lineToken then
			textLabel.MaxVisibleGraphemes = -1
			typing = false
			hint.Visible = true
		end
	end)
end

local function showChoices(options)
	panel.Visible = false
	clearChoices()
	mode = "choice"
	for i, text in ipairs(options) do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.Size = UDim2.new(1, 0, 0, 46)
		b.BackgroundColor3 = Color3.fromRGB(70, 55, 42)
		b.TextColor3 = Color3.fromRGB(255, 244, 228)
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 20
		b.TextWrapped = true
		b.Text = text
		addCorner(b, 10)
		b.Parent = choiceFrame
		b.MouseButton1Click:Connect(function()
			if mode ~= "choice" then return end
			mode = "none"
			clearChoices()
			dialogueRemote:FireServer(i)
		end)
	end
end

local function advance()
	if mode ~= "line" then return end
	if typing then
		typing = false
		textLabel.MaxVisibleGraphemes = -1
		hint.Visible = true
		return
	end
	mode = "none"
	hint.Visible = false
	dialogueRemote:FireServer()
end

panel.MouseButton1Click:Connect(advance)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Space then
		advance()
	end
end)

dialogueRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "line" then
		enterDialogue()
		showLine(a, b)
	elseif kind == "choice" then
		enterDialogue()
		showChoices(a)
	elseif kind == "end" then
		inDialogue = false
		setLookLocked(true)
		crosshair.Visible = true
		mode = "none"
		typing = false
		panel.Visible = false
		clearChoices()
	end
end)