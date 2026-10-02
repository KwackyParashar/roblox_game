-- CartDayCycle | Script | ServerScriptService
-- Compressed evening clock with a wind-down window before day's end,
-- an End Day button, and coins only banked once a day is confirmed complete.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartSave = require(script.Parent:WaitForChild("CartSave"))

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local SETTINGS = {
	DayLengthSeconds = 60, --450
	WindDownSeconds = 10,  -- real seconds before day's end where spawning stops and the clock freezes
	EveningStartClock = 18,
	EveningEndClock = 24,
	AutosaveEverySeconds = 60,
}

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
if ServerStorage:FindFirstChild("DayStarted") then
	warn("[CartDayCycle] Another copy of this script is already running. Disabling this one - delete the duplicate CartDayCycle in ServerScriptService.")
	return
end

local dayStarted = Instance.new("BindableEvent")
dayStarted.Name = "DayStarted"
dayStarted.Parent = ServerStorage

local clockUI = Instance.new("RemoteEvent")
clockUI.Name = "ClockUI"
clockUI.Parent = ReplicatedStorage

local dayEndRemote = Instance.new("RemoteEvent")
dayEndRemote.Name = "DayEnd"
dayEndRemote.Parent = ReplicatedStorage

----------------------------------------------------------------
-- OPTIONAL SCENE PIECES
----------------------------------------------------------------
local cartFolder = workspace:FindFirstChild("Cart")
local cartLights = cartFolder and cartFolder:FindFirstChild("CartLights")
local worldFolder = workspace:FindFirstChild("World")
local moon = worldFolder and worldFolder:FindFirstChild("Moon")

if cartLights then
	for _, light in ipairs(cartLights:GetChildren()) do
		if (light:IsA("PointLight") or light:IsA("SpotLight")) and light:GetAttribute("BaseBrightness") == nil then
			light:SetAttribute("BaseBrightness", light.Brightness)
		end
	end
end

local function setLightsForProgress(progress)
	local warmth = 1
	if progress < 0.05 then warmth = progress / 0.05
	elseif progress > 0.9 then warmth = (1 - progress) / 0.1 end
	warmth = math.clamp(warmth, 0, 1)

	if cartLights then
		for _, light in ipairs(cartLights:GetChildren()) do
			if light:IsA("PointLight") or light:IsA("SpotLight") then
				light.Brightness = warmth * (light:GetAttribute("BaseBrightness") or 5)
			end
		end
	end

	if moon then
		local angle = math.rad(30 + progress * 40)
		local radius = 300
		moon.Position = Vector3.new(math.cos(angle) * radius, 150 + math.sin(progress * math.pi) * 40, math.sin(angle) * radius)
	end
end

----------------------------------------------------------------
-- THE EVENING LOOP
----------------------------------------------------------------
local function ownerPlayer()
	return Players:GetPlayers()[1]
end

local function runEvening(player, data, coins)
	local elapsed, progress = 0, 0
	local frozen, dayEndRequested = false, false
	dayStarted:Fire(data.day, data)
	ServerStorage:SetAttribute("SpawningPaused", false)

	local conn
	conn = dayEndRemote.OnServerEvent:Connect(function(plr)
		if plr == player and frozen then
			dayEndRequested = true
		end
	end)

	local windDownAt = math.max(0, SETTINGS.DayLengthSeconds - SETTINGS.WindDownSeconds)

	while not dayEndRequested do
		local dt = task.wait(0.5)
		if not frozen then
			elapsed += dt
			progress = math.clamp(elapsed / SETTINGS.DayLengthSeconds, 0, 1)
			local clockTime = SETTINGS.EveningStartClock + progress * (SETTINGS.EveningEndClock - SETTINGS.EveningStartClock)
			Lighting.ClockTime = clockTime
			setLightsForProgress(progress)

			if elapsed >= windDownAt then
				frozen = true
				ServerStorage:SetAttribute("SpawningPaused", true)
				clockUI:FireAllClients(data.day, clockTime, true) -- true = show the End Day button
			else
				clockUI:FireAllClients(data.day, clockTime, false)
			end
		end
	end

	conn:Disconnect()
	ServerStorage:SetAttribute("SpawningPaused", false)
	data.coins = coins.Value
	data.day += 1
	print(("[CartDayCycle] Day ended. Now starting day %d"):format(data.day))
	CartSave.Save(player)
end

local loopStarted = {}
Players.PlayerAdded:Connect(function(player)
	local data = CartSave.Load(player)

	local ls = player:WaitForChild("leaderstats", 10)
	local coins = ls and ls:FindFirstChild("Coins")
	if coins then
		coins.Value = data.coins
	end

	clockUI:FireClient(player, data.day, Lighting.ClockTime, false)

	if ownerPlayer() == player and coins and not loopStarted[player] then
		loopStarted[player] = true
		task.spawn(function()
			while player.Parent do
				runEvening(player, data, coins)
			end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	CartSave.Save(player)
	CartSave.Release(player)
end)

task.spawn(function()
	while true do
		task.wait(SETTINGS.AutosaveEverySeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			CartSave.Save(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		CartSave.Save(player)
	end
end)

print("[CartDayCycle] Ready. Evening length: " .. SETTINGS.DayLengthSeconds .. "s, wind-down: " .. SETTINGS.WindDownSeconds .. "s")