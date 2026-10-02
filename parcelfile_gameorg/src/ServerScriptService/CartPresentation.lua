-- CartPresentation | ModuleScript | ServerScriptService
-- Turns game state into visible food + particles on the board, pot and pan.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Presentation = {}

----------------------------------------------------------------
local foodModels = ReplicatedStorage:FindFirstChild("FoodModels")

local warnedMissing = {}
local function getTemplate(name)
	if not foodModels then return nil end
	return foodModels:FindFirstChild(name)
		or (foodModels:FindFirstChild("Fillings") and foodModels.Fillings:FindFirstChild(name))
		or (foodModels:FindFirstChild("Sauces") and foodModels.Sauces:FindFirstChild(name))
end

-- Rough fallback look for anything you haven't modeled yet
local FALLBACK = {
	CutBun = { color = Color3.fromRGB(214, 170, 110), size = Vector3.new(1, 0.5, 1.6) },
	BreadSlice = { color = Color3.fromRGB(222, 188, 130), size = Vector3.new(1.2, 0.25, 1.2) },
	ToastedBreadSlice = { color = Color3.fromRGB(180, 120, 60), size = Vector3.new(1.2, 0.25, 1.2) },
	RawSausage = { color = Color3.fromRGB(210, 120, 120), size = Vector3.new(0.5, 0.5, 1.4) },
	CookedSausage = { color = Color3.fromRGB(140, 70, 55), size = Vector3.new(0.5, 0.5, 1.4) },
	Cheese = { color = Color3.fromRGB(250, 210, 90), size = Vector3.new(1, 0.15, 1) },
	Tomato = { color = Color3.fromRGB(200, 60, 50), size = Vector3.new(0.9, 0.2, 0.9) },
	Onion = { color = Color3.fromRGB(230, 225, 210), size = Vector3.new(0.9, 0.15, 0.9) },
	Sauce = { color = Color3.fromRGB(200, 50, 40), size = Vector3.new(0.9, 0.08, 0.9) },
	PotatoStuff = { color = Color3.fromRGB(225, 200, 140), size = Vector3.new(0.8, 0.3, 0.8) },
}
local SAUCE_COLORS = { Ketchup = Color3.fromRGB(200, 40, 30), Mustard = Color3.fromRGB(230, 190, 40), Mayo = Color3.fromRGB(245, 240, 220) }

local function makeFallback(name, colorOverride)
	local spec = FALLBACK[name] or { color = Color3.fromRGB(200, 200, 200), size = Vector3.new(0.8, 0.3, 0.8) }
	local part = Instance.new("Part")
	part.Name = name
	part.Size = spec.size
	part.Color = colorOverride or spec.color
	part.Material = Enum.Material.SmoothPlastic
	part.Shape = Enum.PartType.Block
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = "" -- left blank; SpecialMesh with no id just rounds nothing, safe no-op
	mesh:Destroy() -- (kept simple: plain rounded-looking block via Material only)
	return part
end

-- Spawns a food piece (custom model if you made one, otherwise a soft block) at a CFrame
local function spawnPiece(name, cframe, colorOverride, fallbackKind)
	local template = getTemplate(name)
	local model
	if template then
		model = template:Clone()
		if model:IsA("Model") then
			model:PivotTo(cframe)
		elseif model:IsA("BasePart") then
			local original = model.CFrame
			local delta = cframe * original:Inverse()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = delta * d.CFrame
				end
			end
			model.CFrame = cframe
		end
	else
		model = makeFallback(fallbackKind or name, colorOverride)
		model.CFrame = cframe
	end
	for _, d in ipairs(model:IsA("Model") and model:GetDescendants() or { model }) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	model.Parent = workspace:FindFirstChild("Cart")
	return model
end

----------------------------------------------------------------
-- PARTICLES
----------------------------------------------------------------
local PARTICLE_SPEC = {
	crumbs = { color = Color3.fromRGB(200, 160, 100), lifetime = NumberRange.new(0.3, 0.6), speed = NumberRange.new(2, 5), count = 10, spread = 60 },
	sauce = { color = Color3.fromRGB(200, 50, 40), lifetime = NumberRange.new(0.25, 0.4), speed = NumberRange.new(1, 3), count = 8, spread = 30 },
	steam = { color = Color3.fromRGB(255, 255, 255), lifetime = NumberRange.new(0.8, 1.4), speed = NumberRange.new(1, 2), count = 6, spread = 15 },
	sparkle = { color = Color3.fromRGB(255, 225, 150), lifetime = NumberRange.new(0.4, 0.7), speed = NumberRange.new(2, 4), count = 14, spread = 180 },
}

function Presentation.Burst(kind, position)
	local spec = PARTICLE_SPEC[kind]
	if not spec then return end
	local anchor = Instance.new("Part")
	anchor.Name = "FX_" .. kind
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(spec.color)
	emitter.Lifetime = spec.lifetime
	emitter.Speed = spec.speed
	emitter.SpreadAngle = Vector2.new(spec.spread, spec.spread)
	emitter.Rate = 0
	emitter.Size = NumberSequence.new(0.15)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	if kind == "steam" then
		emitter.Acceleration = Vector3.new(0, 4, 0)
	else
		emitter.Acceleration = Vector3.new(0, -8, 0)
	end
	emitter.Parent = anchor
	emitter:Emit(spec.count)

	Debris:AddItem(anchor, 2)
end

-- Turns a looping puff on/off (used for steam while boiling/toasting)
local loopEmitters = {}
function Presentation.SetLoopingSteam(key, part, on)
	if on and not loopEmitters[key] then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		emitter.Lifetime = NumberRange.new(0.8, 1.3)
		emitter.Speed = NumberRange.new(0.6, 1.2)
		emitter.SpreadAngle = Vector2.new(20, 20)
		emitter.Rate = 8
		emitter.Size = NumberSequence.new(0.18)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Acceleration = Vector3.new(0, 3, 0)
		emitter.Parent = part
		loopEmitters[key] = emitter
	elseif not on and loopEmitters[key] then
		loopEmitters[key]:Destroy()
		loopEmitters[key] = nil
	end
end

----------------------------------------------------------------
-- BOARD
----------------------------------------------------------------
local boardHolder, potHolder, panHolder

function Presentation.Init(stations)
	boardHolder = Instance.new("Folder"); boardHolder.Name = "BoardFood"; boardHolder.Parent = stations.CuttingBoard
	potHolder = Instance.new("Folder"); potHolder.Name = "PotFood"; potHolder.Parent = stations.Pot
	panHolder = Instance.new("Folder"); panHolder.Name = "PanFood"; panHolder.Parent = stations.Pan
end

local function clear(folder)
	for _, c in ipairs(folder:GetChildren()) do c:Destroy() end
end

local function findPoints(model, prefix)
	local points = {}
	local i = 1
	while true do
		local att = model:FindFirstChild(prefix .. i, true)
		if not att then break end
		table.insert(points, att)
		i += 1
	end
	return points
end
-- dish = the same table CartGame uses (base, sausage, toasted, fillings, sauces), or nil
function Presentation.SetBoard(boardPart, dish, rawItem)
	clear(boardHolder)
	if not dish and rawItem then
		local top = boardPart.Position + Vector3.new(0, boardPart.Size.Y / 2, 0)
		local piece = spawnPiece(rawItem, CFrame.new(top))
		piece.Parent = boardHolder
		return
	end
	if not dish then return end
	local top = boardPart.Position + Vector3.new(0, boardPart.Size.Y / 2, 0)

	if dish.base == "Hotdog" then
		if not dish.sausage then
			local base = spawnPiece("CutBun", CFrame.new(top + Vector3.new(0, 0.1, 0)))
			base.Parent = boardHolder
			return
		end

		local hotdogTemplate = getTemplate("Hotdog")
		if hotdogTemplate then
			local assembled = spawnPiece("Hotdog", CFrame.new(top + Vector3.new(0, 0.1, 0)))
			assembled.Parent = boardHolder
			local saucePoints = findPoints(assembled, "SaucePoint")
			if #saucePoints > 0 then
				for i, sauceName in ipairs(dish.sauces) do
					local att = saucePoints[((i - 1) % #saucePoints) + 1]
					local drop = spawnPiece(sauceName, att.WorldCFrame * CFrame.new(0, 0.05 * i, 0), SAUCE_COLORS[sauceName], "Sauce")
					drop.Parent = boardHolder
				end
			else
				for i, sauceName in ipairs(dish.sauces) do
					local drop = spawnPiece(sauceName, att.WorldCFrame * CFrame.new(0, 0.05 * i, 0), SAUCE_COLORS[sauceName], "Sauce")
					drop.Parent = boardHolder
				end
			end
			return
		end

		local base = spawnPiece("CutBun", CFrame.new(top + Vector3.new(0, 0.1, 0)))
		base.Parent = boardHolder
		local s = spawnPiece("CookedSausage", CFrame.new(top + Vector3.new(0, 0.3, 0)))
		s.Parent = boardHolder
		for i, sauceName in ipairs(dish.sauces) do
			local drop = spawnPiece(sauceName, att.WorldCFrame * CFrame.new(0, 0.05 * i, 0), SAUCE_COLORS[sauceName], "Sauce")
			drop.Parent = boardHolder
		end
		return
	end

	-- Sandwich
	local sliceName = dish.toasted and "ToastedBreadSlice" or "BreadSlice"

	if not dish.toasted or not dish.potato then
		local bottom = spawnPiece(sliceName, CFrame.new(top + Vector3.new(-0.75, 0, 0)))
		bottom.Parent = boardHolder
		local topSlice = spawnPiece(sliceName, CFrame.new(top + Vector3.new(0.75, 0, 0)))
		topSlice.Parent = boardHolder
		return
	end

	local sandwichTemplate = getTemplate("Sandwich")
	if sandwichTemplate then
		local assembled = spawnPiece("Sandwich", CFrame.new(top))
		assembled.Parent = boardHolder
		local toppingPoints = findPoints(assembled, "ToppingPoint")
		if #toppingPoints > 0 then
			for i, filling in ipairs(dish.fillings) do
				local att = toppingPoints[math.min(i, #toppingPoints)]
				local f = spawnPiece(filling, att.WorldCFrame)
				f.Parent = boardHolder
			end
		else
			local stackY = 0.3
			for _, filling in ipairs(dish.fillings) do
				local f = spawnPiece(filling, CFrame.new(top + Vector3.new(0, stackY, 0)))
				f.Parent = boardHolder
				stackY += 0.15
			end
		end
		local saucePoints = findPoints(assembled, "SaucePoint")
		if #saucePoints > 0 then
			for i, sauceName in ipairs(dish.sauces) do
				local att = saucePoints[((i - 1) % #saucePoints) + 1]
				local drop = spawnPiece(sauceName, att.WorldCFrame * CFrame.new(0, 0.05 * i, 0), SAUCE_COLORS[sauceName], "Sauce")
				drop.Parent = boardHolder
			end
		else
			for i, sauceName in ipairs(dish.sauces) do
				local drop = spawnPiece(sauceName, att.WorldCFrame * CFrame.new(0, 0.05 * i, 0), SAUCE_COLORS[sauceName], "Sauce")
				drop.Parent = boardHolder
			end
		end
		return
	end

	local bottom = spawnPiece(sliceName, CFrame.new(top))
	bottom.Parent = boardHolder
	local stackY = 0.25
	local p = spawnPiece("PotatoStuff", CFrame.new(top + Vector3.new(0, stackY, 0)))
	p.Parent = boardHolder
	stackY += 0.2
	for _, filling in ipairs(dish.fillings) do
		local f = spawnPiece(filling, CFrame.new(top + Vector3.new(0, stackY, 0)))
		f.Parent = boardHolder
		stackY += 0.15
	end
	for i, sauceName in ipairs(dish.sauces) do
		local drop = spawnPiece(sauceName, att.WorldCFrame * CFrame.new(0, 0.05 * i, 0), SAUCE_COLORS[sauceName], "Sauce")
		drop.Parent = boardHolder
		stackY += 0.05
	end
	local topSlice = spawnPiece(sliceName, CFrame.new(top + Vector3.new(0, stackY + 0.15, 0)))
	topSlice.Parent = boardHolder
end

----------------------------------------------------------------
-- POT  (entries = list of {progress = 0..1}, one per sausage boiling)
----------------------------------------------------------------
function Presentation.SetPot(potPart, entries)
	clear(potHolder)
	Presentation.SetLoopingSteam("pot", potPart, #entries > 0)
	local top = potPart.Position + Vector3.new(0, potPart.Size.Y * 0.2, 0)
	for i, e in ipairs(entries) do
		local angle = (i - 1) * (math.pi * 2 / math.max(#entries, 1))
		local r = potPart.Size.X * 0.22
		local pos = top + Vector3.new(math.cos(angle) * r, math.sin(os.clock() * 2 + i) * 0.05, math.sin(angle) * r)
		local color = (e.progress >= 1) and Color3.fromRGB(140, 70, 55) or Color3.fromRGB(210, 120, 120):Lerp(Color3.fromRGB(140, 70, 55), e.progress)
		local piece = spawnPiece(e.progress >= 1 and "CookedSausage" or "RawSausage", CFrame.new(pos), color)
		piece.Parent = potHolder
	end
end

----------------------------------------------------------------
-- PAN  (panState = {dish=..., progress=0..1} or nil)
----------------------------------------------------------------
function Presentation.SetPan(panPart, panState)
	clear(panHolder)
	Presentation.SetLoopingSteam("pan", panPart, panState ~= nil)
	if not panState then return end
	local top = panPart.Position + Vector3.new(0, panPart.Size.Y / 2, 0)
	local toasted = panState.progress >= 1
	local name = toasted and "ToastedBreadSlice" or "BreadSlice"
	local browning = Color3.fromRGB(222, 188, 130):Lerp(Color3.fromRGB(180, 120, 60), panState.progress)
	local color = toasted and nil or browning -- only tints the fallback shape; your own model keeps its own look
	local a = spawnPiece(name, CFrame.new(top + Vector3.new(-0.45, 0, 0)), color)
	a.Parent = panHolder
	local b = spawnPiece(name, CFrame.new(top + Vector3.new(0.45, 0, 0)), color)
	b.Parent = panHolder
end

return Presentation