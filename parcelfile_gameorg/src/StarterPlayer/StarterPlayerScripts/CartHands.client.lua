-- CartHands v2 | LocalScript | StarterPlayer > StarterPlayerScripts
-- Rigged hands locked to the camera, like a first-person viewmodel.
-- Fill in ANIMATION_IDS as you publish real animations; empty slots use a built-in fallback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local cart = workspace:WaitForChild("Cart")
local cameraPoint = cart:WaitForChild("CameraPoint", 10)
local foodModels = ReplicatedStorage:FindFirstChild("FoodModels")
local camera = workspace.CurrentCamera
local baseFOV = camera.FieldOfView
local focus = 0

if not cameraPoint then return end

----------------------------------------------------------------
-- FILL THESE IN AS YOU PUBLISH ANIMATIONS (see Update 5 guide, Part B/C)
----------------------------------------------------------------
local ANIMATION_IDS = {
	Right = {
		pickup = "rbxassetid://124841351774402",
		cut = "rbxassetid://92082295865025",
		splash = nil,
		panplace = "rbxassetid://86427532385676",
		panout = nil,
		sauce = nil,
		serve = "rbxassetid://124841351774402",
	},
	Left = {
		cut = "rbxassetid://116704067983399",
	},
}

----------------------------------------------------------------
-- LOAD THE RIGS
----------------------------------------------------------------
local handRigsSource = ReplicatedStorage:WaitForChild("HandRigs")

local rigs = {} -- rigs.Right / rigs.Left = { model, root, palm, animator, offset }

local HOME = {
	Right = CFrame.new(0.85, -0.9, -1.3) * CFrame.Angles(math.rad(15), math.rad(-10), 0),
	Left = CFrame.new(-0.85, -0.9, -1.3) * CFrame.Angles(math.rad(15), math.rad(10), 0),
}

for _, side in ipairs({ "Right", "Left" }) do
	local template = handRigsSource:FindFirstChild(side .. "HandRig")
	if not template then
		warn("[CartHands] Missing " .. side .. "HandRig in ReplicatedStorage > HandRigs. Run the Update 5 rig-builder command first.")
	else
		local model = template:Clone()
		model.Parent = workspace
		local root = model:FindFirstChild("Root")
		local palm = model:FindFirstChild("Palm")
		local ac = model:FindFirstChildOfClass("AnimationController")
		local animator = ac and ac:FindFirstChildOfClass("Animator")
		rigs[side] = {
			model = model, root = root, palm = palm, animator = animator,
			offset = HOME[side], busy = false, held = nil,
		}
	end
end

----------------------------------------------------------------
-- EVERY FRAME: place each hand relative to the CURRENT camera view
-- (runs after CartClient updates the camera this same frame)
----------------------------------------------------------------
RunService:BindToRenderStep("CartHandsFollow", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local t = os.clock()
	for side, hand in pairs(rigs) do
		local sway = CFrame.new(0, 0, 0)
		if not hand.busy then
			sway = CFrame.new(math.sin(t * 1.1 + (side == "Left" and 1 or 0)) * 0.015, math.sin(t * 0.8) * 0.015, 0)
				* CFrame.Angles(math.noise(t * 0.4, side == "Left" and 4 or 1) * 0.02, math.noise(t * 0.3, side == "Left" and 5 or 2) * 0.02, 0)
		end
		hand.root.CFrame = camera.CFrame * hand.offset * sway
		if hand.held then
			hand.held:PivotTo(hand.palm.CFrame * CFrame.new(0, -0.05, -0.4))
		end
	end

	-- lean-in zoom while either hand is doing something
	local anyBusy = (rigs.Right and rigs.Right.busy) or (rigs.Left and rigs.Left.busy)
	local target = anyBusy and 1 or 0
	focus += (target - focus) * math.clamp(dt * 6, 0, 1)
	camera.FieldOfView = baseFOV - focus * 4
	camera.CFrame = camera.CFrame * CFrame.new(0, 0, -focus * 0.15)
end)

----------------------------------------------------------------
-- HELD ITEM VISUAL
----------------------------------------------------------------
local FALLBACK_COLOR = {
	Bun = Color3.fromRGB(214, 170, 110), Bread = Color3.fromRGB(222, 188, 130),
	RawSausage = Color3.fromRGB(210, 120, 120), CookedSausage = Color3.fromRGB(140, 70, 55),
	PotatoStuff = Color3.fromRGB(225, 200, 140),
}

local function attachHeld(side, itemId)
	local hand = rigs[side]
	if not hand then return end
	if hand.held then hand.held:Destroy(); hand.held = nil end
	if not itemId then return end
	local template = foodModels and foodModels:FindFirstChild(itemId)
	local model
	if template then
		model = template:Clone()
	else
		local p = Instance.new("Part")
		p.Size = Vector3.new(0.4, 0.35, 0.7)
		p.Color = FALLBACK_COLOR[itemId] or Color3.fromRGB(200, 200, 200)
		p.Material = Enum.Material.SmoothPlastic
		model = p
	end
	for _, d in ipairs(model:IsA("Model") and model:GetDescendants() or { model }) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
	end
	model.Parent = workspace
	hand.held = model
end

----------------------------------------------------------------
-- OFFSET TWEENING (fallback gestures move the whole hand in camera-local space)
----------------------------------------------------------------
local function tweenOffset(side, targetOffset, time, style, dir)
	local hand = rigs[side]
	if not hand then return end
	local proxy = Instance.new("CFrameValue")
	proxy.Value = hand.offset
	local tween = TweenService:Create(proxy, TweenInfo.new(time, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.InOut), { Value = targetOffset })
	local conn = proxy:GetPropertyChangedSignal("Value"):Connect(function() hand.offset = proxy.Value end)
	tween:Play()
	tween.Completed:Wait()
	conn:Disconnect()
	proxy:Destroy()
end

local function toggleKnife(on)
	local knife = rigs.Right and rigs.Right.model:FindFirstChild("Knife")
	if knife then knife.Transparency = on and 0 or 1 end
end
local SAUCE_TINTS = {
	Ketchup = Color3.fromRGB(200, 40, 30),
	Mustard = Color3.fromRGB(230, 190, 40),
	Mayo = Color3.fromRGB(245, 240, 220),
}

local function showPassport(show)
	local passport = rigs.Left and rigs.Left.model:FindFirstChild("Passport")
	if passport then passport.Transparency = show and 0 or 1 end
end

local function toggleBottle(on, color)
	local bottle = rigs.Right and rigs.Right.model:FindFirstChild("Bottle")
	if bottle then
		bottle.Transparency = on and 0 or 1
		if color then bottle.Color = color end
	end
end
----------------------------------------------------------------
-- FALLBACK GESTURES (used whenever ANIMATION_IDS has no ID for that action)
----------------------------------------------------------------
local fallback = {}

fallback.pickup = function(side, duration, item)
	local hand = rigs[side]; if not hand then return end
	hand.busy = true
	tweenOffset(side, HOME[side] * CFrame.new(0, -0.25, 0.35), 0.25, Enum.EasingStyle.Quad)
	task.wait(0.1)
	attachHeld(side, item) -- the grab happens here; the item rides back with the hand
	tweenOffset(side, HOME[side], 0.3, Enum.EasingStyle.Quad)
	hand.busy = false
end

fallback.cut = function(side, duration)
	duration = duration or 1.2
	local hand = rigs[side]; if not hand then return end
	hand.busy = true
	if side == "Right" then
		toggleKnife(true)
		tweenOffset(side, HOME[side] * CFrame.new(0.1, -0.35, 0.5) * CFrame.Angles(math.rad(-20), 0, 0), 0.25, Enum.EasingStyle.Quad)
		local chops = math.max(2, math.floor(duration / 0.35))
		for i = 1, chops do
			tweenOffset(side, HOME[side] * CFrame.new(0.1, -0.5, 0.5) * CFrame.Angles(math.rad(10), 0, 0), (duration / chops) * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tweenOffset(side, HOME[side] * CFrame.new(0.1, -0.3, 0.5) * CFrame.Angles(math.rad(-25), 0, 0), (duration / chops) * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		tweenOffset(side, HOME[side], 0.3, Enum.EasingStyle.Quad)
		toggleKnife(false)
	else
		tweenOffset(side, HOME[side] * CFrame.new(-0.1, -0.3, 0.45), 0.25, Enum.EasingStyle.Quad)
		task.wait(duration)
		tweenOffset(side, HOME[side], 0.3, Enum.EasingStyle.Quad)
	end
	hand.busy = false
end

fallback.place = function(side, duration)
	local hand = rigs[side]; if not hand then return end
	hand.busy = true
	tweenOffset(side, HOME[side] * CFrame.new(0, -0.3, 0.4), 0.25, Enum.EasingStyle.Quad)
	task.wait(0.1)
	attachHeld(side, nil) -- let go once the hand has arrived
	tweenOffset(side, HOME[side], 0.3, Enum.EasingStyle.Quad)
	hand.busy = false
end

fallback.splash = function(side, duration)
	local hand = rigs[side]; if not hand then return end
	hand.busy = true
	tweenOffset(side, HOME[side] * CFrame.new(0, -0.4, 0.45) * CFrame.Angles(math.rad(30), 0, 0), 0.25, Enum.EasingStyle.Quad)
	task.wait(0.1)
	tweenOffset(side, HOME[side], 0.3, Enum.EasingStyle.Quad)
	hand.busy = false
end

fallback.panplace = fallback.splash
fallback.panout = fallback.pickup

fallback.sauce = function(side, duration, item)
	local hand = rigs[side]; if not hand then return end
	hand.busy = true
	local target = HOME[side] * CFrame.new(0, -0.35, 0.4) * CFrame.Angles(math.rad(35), 0, 0)
	tweenOffset(side, target, 0.25, Enum.EasingStyle.Quad)
	toggleBottle(true, item and SAUCE_TINTS[item])
	for _ = 1, 3 do
		tweenOffset(side, target * CFrame.new(0, -0.05, 0), 0.1, Enum.EasingStyle.Quad)
		tweenOffset(side, target, 0.1, Enum.EasingStyle.Quad)
	end
	toggleBottle(false)
	tweenOffset(side, HOME[side], 0.3, Enum.EasingStyle.Quad)
	hand.busy = false
end

fallback.serve = function(side, duration)
	local hand = rigs[side]; if not hand then return end
	hand.busy = true
	tweenOffset(side, HOME[side] * CFrame.new(0, -0.15, 0.7), 0.3, Enum.EasingStyle.Quad)
	task.wait(0.15)
	tweenOffset(side, HOME[side], 0.35, Enum.EasingStyle.Quad)
	hand.busy = false
end

----------------------------------------------------------------
-- PLAY A REAL ANIMATION (used whenever an ANIMATION_IDS slot is filled in)
----------------------------------------------------------------
local function playAnimation(side, gestureName, animId, duration, item)
	local hand = rigs[side]
	if not (hand and hand.animator) then return end
	hand.busy = true
	if side == "Right" and gestureName == "cut" then toggleKnife(true) end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function() return hand.animator:LoadAnimation(anim) end)
	if not ok or not track then
		warn("[CartHands] Couldn't load animation " .. tostring(animId))
		hand.busy = false
		return
	end

	local effectiveDuration = duration
	if duration and track.Length > 0 then
		track:AdjustSpeed(track.Length / duration)
	else
		effectiveDuration = track.Length
	end

	track:Play()

	if side == "Right" and gestureName == "sauce" then
		task.delay((effectiveDuration or 0.6) * 0.4, function()
			toggleBottle(true, item and SAUCE_TINTS[item])
		end)
	elseif item then
		task.delay((effectiveDuration or 0.3) * 0.45, function()
			attachHeld(side, item)
		end)
	end

	track.Stopped:Wait()
	toggleKnife(false)
	if gestureName == "sauce" then toggleBottle(false) end
	hand.busy = false
end

----------------------------------------------------------------
-- DISPATCH: use the real animation if you've made one, otherwise the fallback
----------------------------------------------------------------
local function runGesture(side, gestureName, duration, item)
	local animId = ANIMATION_IDS[side] and ANIMATION_IDS[side][gestureName]
	if animId then
		task.spawn(playAnimation, side, gestureName, animId, duration, item)
	elseif fallback[gestureName] then
		task.spawn(fallback[gestureName], side, duration, item)
	end
end

----------------------------------------------------------------
-- WIRE UP TO THE SERVER
----------------------------------------------------------------
local cartFX = ReplicatedStorage:WaitForChild("CartFX")
cartFX.OnClientEvent:Connect(function(action, data)
	data = data or {}
	if action == "pickup" then
		runGesture("Right", "pickup", data.duration, data.item)
	elseif action == "cut" then
		runGesture("Right", "cut", data.duration)
		runGesture("Left", "cut", data.duration)
	elseif action == "splash" then
		runGesture("Right", "splash", data.duration)
	elseif action == "panplace" then
		runGesture("Right", "panplace", data.duration)
	elseif action == "panout" then
		runGesture("Right", "panout", data.duration)
	elseif action == "sauce" then
		runGesture("Right", "sauce", data.duration, data.item)
	elseif action == "place" then
		runGesture("Right", "place", data.duration)
	elseif action == "passportGlimpse" then
		rigs.Left.busy = true
		tweenOffset("Left", HOME.Left * CFrame.new(0.05, 0.05, 0.35) * CFrame.Angles(math.rad(10), 0, 0), 0.5, Enum.EasingStyle.Quad)
		showPassport(true)
	elseif action == "passportGlimpseEnd" then
		showPassport(false)
		tweenOffset("Left", HOME.Left, 0.4, Enum.EasingStyle.Quad)
		rigs.Left.busy = false
	elseif action == "serve" then
		runGesture("Right", "serve", data.duration)
	end
end)

local notify = ReplicatedStorage:WaitForChild("Notify")
notify.OnClientEvent:Connect(function(kind, _text, item)
	if kind ~= "held" then return end
	if not item then
		attachHeld("Right", nil) -- always let go, even mid-animation
	end
	-- picking something UP is now handled inside the "pickup" gesture itself,
	-- timed to appear as the hand starts retracting — see runGesture/playAnimation/fallback.pickup
end)