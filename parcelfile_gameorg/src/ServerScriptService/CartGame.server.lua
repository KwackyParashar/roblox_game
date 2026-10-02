-- CartGame v4 | Script | ServerScriptService
-- Orders, cooking stations, dialogue, customers, food visuals, hand-animation triggers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")

local Dialogues = require(script.Parent:WaitForChild("Dialogues"))
local Presentation = require(script.Parent:WaitForChild("CartPresentation"))
local CartSave = require(script.Parent:WaitForChild("CartSave"))

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local SETTINGS = {
	CutTime = 1.2,             -- seconds to cut bread/bun (drives the knife animation length)
	SausageCookTime = 8,       -- seconds a sausage must boil
	ToastTime = 6,             -- seconds to toast a sandwich
	PotSlots = 4,
	PanPlaceVisualDelay = 0.6, -- roughly how long your placing animation takes; the pan waits this long before showing food

	MaxQueue = 3,
	MaxWaiting = 4,
	MaxEating = 3,
	MaxOpenOrders = 1,

	SpawnEveryMin = 6,
	SpawnEveryMax = 12,
	EatTimeMin = 12,
	EatTimeMax = 18,
	CustomerWalkSpeed = 9,
	BasePay = 10,
	PerExtraPay = 3,
	BeggarDelayMin = 10,  -- real seconds after the day starts before he can show up --60
	BeggarDelayMax = 30, --250
	PassportGlimpseDay = 2, -- which day this plays on; change freely
}

----------------------------------------------------------------
-- FIND THINGS IN THE SCENE
----------------------------------------------------------------
local cart = workspace:WaitForChild("Cart")
local stations = cart:WaitForChild("Stations")
local ticketFolder = cart:WaitForChild("TicketSlots")
local soundsFolder = cart:FindFirstChild("Sounds")

local world = workspace:WaitForChild("World")
local spawnPoint = world:WaitForChild("SpawnPoint")
local exitPoint = world:WaitForChild("ExitPoint")
local queueFolder = world:WaitForChild("QueueSpots")
local waitFolder = world:WaitForChild("WaitSpots")
local benchFolder = world:WaitForChild("Benches")
local customerRigs = ServerStorage:WaitForChild("Customers")
local function resolveRig(container)
	if not container then return nil end
	if container:FindFirstChildOfClass("Humanoid") then return container end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			return child
		end
	end
	return nil
end
local beggarRig = resolveRig(ServerStorage:FindFirstChild("BeggarRig"))
local beggarHome = (world:FindFirstChild("BeggarHome")) or (cart:FindFirstChild("BeggarHome"))

local function sortedByNumber(folder)
	local list = folder:GetChildren()
	table.sort(list, function(a, b)
		return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
	end)
	return list
end

local queueSpots = sortedByNumber(queueFolder)
local waitSpots = sortedByNumber(waitFolder)
local slots = sortedByNumber(ticketFolder)

local seats = {}
for _, d in ipairs(benchFolder:GetDescendants()) do
	if d:IsA("Seat") then table.insert(seats, d) end
end

local boardPart = stations:FindFirstChild("CuttingBoard")
local potPart = stations:FindFirstChild("Pot")
local panPart = stations:FindFirstChild("Pan")

local function stationPosition(inst)
	if not inst then return Vector3.new(0, 0, 0) end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then return inst:GetPivot().Position end
	return Vector3.new(0, 0, 0)
end

local function setLabel(part, text)
	local gui = part:FindFirstChild("StatusLabel")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "StatusLabel"
		gui.Size = UDim2.fromOffset(220, 50)
		gui.StudsOffset = Vector3.new(0, 1.8, 0)
		gui.AlwaysOnTop = true
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.4
		t.TextScaled = true
		t.Font = Enum.Font.GothamMedium
		t.Parent = gui
		gui.Parent = part
	end
	gui.Enabled = text ~= ""
	gui.Text.Text = text
end

Presentation.Init(stations)

local musicTrack = soundsFolder and soundsFolder:FindFirstChild("Music")
if musicTrack and musicTrack:IsA("Sound") then
	musicTrack.Looped = true
	musicTrack.Volume = 0.25 -- quiet, sits behind dialogue and sound effects
	if not musicTrack.IsPlaying then musicTrack:Play() end
end

local lookAnchor = cart:FindFirstChild("CameraPoint") or stations:FindFirstChildWhichIsA("BasePart")
local lookTarget = lookAnchor and lookAnchor.Position or Vector3.new(0, 0, 0)

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
local notify = Instance.new("RemoteEvent"); notify.Name = "Notify"; notify.Parent = ReplicatedStorage
local dialogueRemote = Instance.new("RemoteEvent"); dialogueRemote.Name = "Dialogue"; dialogueRemote.Parent = ReplicatedStorage
local cartFX = Instance.new("RemoteEvent"); cartFX.Name = "CartFX"; cartFX.Parent = ReplicatedStorage
local passportCutscene = Instance.new("RemoteEvent"); passportCutscene.Name = "PassportCutscene"; passportCutscene.Parent = ReplicatedStorage

local function say(text, duration) notify:FireAllClients("msg", text, duration) end

-- fx(action, data) tells CartHands what to animate.
-- data commonly includes: pos (Vector3), duration (seconds), item (string id)
local function fx(action, data)
	data = data or {}
	cartFX:FireAllClients(action, data)
end

local HELD_NAMES = {
	Bun = "Bun", Bread = "Bread loaf", RawSausage = "Raw sausage", CookedSausage = "Cooked sausage",
	PotatoStuff = "Potato filling",
}

----------------------------------------------------------------
-- COINS
----------------------------------------------------------------
local function setupPlayer(player)
	if player:FindFirstChild("leaderstats") then return end
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	local coins = Instance.new("IntValue"); coins.Name = "Coins"; coins.Parent = ls
end
Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end

local function addCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	if coins then coins.Value += amount end
end

----------------------------------------------------------------
-- SOUNDS
----------------------------------------------------------------
local function playSound(name)
	if not soundsFolder then return end
	local s = soundsFolder:FindFirstChild(name)
	if s and s:IsA("Sound") then
		s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * 0.05 -- ±5% pitch, so repeats don't feel robotic
		s:Play()
	end
end

local function setLoop(name, on)
	if not soundsFolder then return end
	local s = soundsFolder:FindFirstChild(name)
	if not (s and s:IsA("Sound")) then return end
	s.Looped = true
	if on and not s.IsPlaying then s:Play()
	elseif not on and s.IsPlaying then s:Stop() end
end

----------------------------------------------------------------
-- TICKETS
----------------------------------------------------------------
local function setTicket(slot, text)
	slot.Transparency = text and 0 or 1
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local name = "Note" .. face.Name
		local gui = slot:FindFirstChild(name)
		if not gui then
			gui = Instance.new("SurfaceGui"); gui.Name = name; gui.Face = face; gui.ZOffset = 1
			gui.Face = face
			gui.AlwaysOnTop = false -- keep it a real surface (not floating), but LightInfluence removes the glare
			gui.LightInfluence = 0
			local label = Instance.new("TextLabel")
			label.Name = "Text"; label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(255, 249, 220) -- solid paper color, not the part's material
			label.BackgroundTransparency = 0
			label.TextColor3 = Color3.fromRGB(50, 35, 20); label.Font = Enum.Font.PatrickHand
			label.TextScaled = true; label.TextWrapped = true; label.Parent = gui
			gui.Parent = slot
		end
		gui.Enabled = text ~= nil
		gui.Text.Text = text or ""
	end
end
for _, slot in ipairs(slots) do setTicket(slot, nil) end

----------------------------------------------------------------
-- STATION NAME → ACTION
----------------------------------------------------------------
local NAME_TO_ACTION = {
	BunCrate = "TakeBun", BreadBasket = "TakeBread", SausageTray = "TakeSausage", PotatoBin = "TakePotato",
	Pot = "Pot", CuttingBoard = "Board", Pan = "Pan", ServeSpot = "Serve", Trash = "Trash",
}
local function getAction(part)
	if NAME_TO_ACTION[part.Name] then return NAME_TO_ACTION[part.Name], nil end
	local kind, item = part.Name:match("^(%a+)_(.+)$")
	if kind == "Sauce" or kind == "Filling" then return kind, item end
	return nil, nil
end

local SAUCES, FILLINGS = {}, {}
for _, part in ipairs(stations:GetChildren()) do
	local action, item = getAction(part)
	if action == "Sauce" then table.insert(SAUCES, item) end
	if action == "Filling" then table.insert(FILLINGS, item) end
end

----------------------------------------------------------------
-- ORDERS
----------------------------------------------------------------
local function pickSome(list, count)
	local pool = table.clone(list)
	local result = {}
	for _ = 1, math.min(count, #pool) do table.insert(result, table.remove(pool, math.random(#pool))) end
	return result
end

local function generateOrder()
	if math.random() < 0.5 then
		return {
			base = "Hotdog", sausage = true, toasted = false,
			fillings = {}, sauces = pickSome(SAUCES, math.random(1, 2)),
		}
	else
		return {
			base = "Sandwich", sausage = false, toasted = true, potato = true,
			fillings = pickSome(FILLINGS, math.random(1, 3)), sauces = pickSome(SAUCES, math.random(0, 2)),
		}
	end
end

local function orderText(order)
	local lines = { order.base == "Hotdog" and "HOTDOG" or "SANDWICH\n(toasted)" }
	for _, f in ipairs(order.fillings) do table.insert(lines, "+ " .. f) end
	for _, s in ipairs(order.sauces) do table.insert(lines, "~ " .. s) end
	return table.concat(lines, "\n")
end

local function joinNice(list)
	if #list == 1 then return list[1] end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function spokenOrder(order)
	local what = (order.base == "Hotdog") and "a hotdog" or "a toasted sandwich"
	local extras = {}
	for _, f in ipairs(order.fillings) do table.insert(extras, f:lower()) end
	for _, s in ipairs(order.sauces) do table.insert(extras, s:lower()) end
	if #extras == 0 then return ("Could I get %s, please?"):format(what) end
	return ("Could I get %s with %s, please?"):format(what, joinNice(extras))
end

local function sameList(a, b)
	if #a ~= #b then return false end
	local x, y = table.clone(a), table.clone(b)
	table.sort(x); table.sort(y)
	for i = 1, #x do if x[i] ~= y[i] then return false end end
	return true
end

local function dishMatches(dish, order, acceptsAnyDish)
	if acceptsAnyDish then return true end
	return dish.base == order.base
		and dish.sausage == order.sausage
		and dish.toasted == order.toasted
		and (dish.potato or false) == (order.potato or false)
		and sameList(dish.fillings, order.fillings)
		and sameList(dish.sauces, order.sauces)
end

----------------------------------------------------------------
-- GAME STATE
----------------------------------------------------------------
local state = { held = nil, board = nil, boardRaw = nil, pot = {}, pan = nil, busy = false, talking = false }

local queue, waiting = {}, {}
local slotOwner = {}
local seatTaken = {}
local eatingCount = 0
local visitCount = {}

local function setHeld(item)
	state.held = item
	notify:FireAllClients("held", item and HELD_NAMES[item] or "", item)
end

local function refreshBoard()
	Presentation.SetBoard(boardPart, state.board, state.boardRaw)
end

local function refreshPot()
	local now = os.clock()
	local entries = {}
	local nextReady, readyCount = math.huge, 0
	for _, s in ipairs(state.pot) do
		local total = SETTINGS.SausageCookTime
		local progress = math.clamp(1 - (s.readyAt - now) / total, 0, 1)
		table.insert(entries, { progress = progress })
		if s.readyAt <= now then
			readyCount += 1
		else
			nextReady = math.min(nextReady, s.readyAt - now)
		end
	end
	Presentation.SetPot(potPart, entries)
	if #state.pot == 0 then
		setLabel(potPart, "")
	elseif nextReady < math.huge then
		setLabel(potPart, ("Boiling... %ds  (%d ready)"):format(math.ceil(nextReady), readyCount))
	else
		setLabel(potPart, "All ready! Click to take")
	end
	setLoop("Boil", #state.pot > 0)
end

local function refreshPan()
	if state.pan then
		if os.clock() < (state.pan.visibleAt or 0) then
			Presentation.SetPan(panPart, nil) -- wait for the placing animation to finish before showing anything
		else
			local total = SETTINGS.ToastTime
			local left = state.pan.readyAt - os.clock()
			local progress = math.clamp(1 - left / total, 0, 1)
			Presentation.SetPan(panPart, { dish = state.pan.dish, progress = progress })
		end
		local left = state.pan.readyAt - os.clock()
		if left > 0 then
			setLabel(panPart, ("Toasting... %ds"):format(math.ceil(left)))
		else
			setLabel(panPart, "Toasted! Click to take")
		end
	else
		Presentation.SetPan(panPart, nil)
		setLabel(panPart, "")
	end
	setLoop("Sizzle", state.pan ~= nil)
end
task.spawn(function()
	while true do
		refreshPot()
		refreshPan()
		task.wait(0.2)
	end
end)

-- Lets other scripts (the beggar) safely take whatever's finished on the board,
-- going through the real game state instead of just touching the visuals.
local takeBoardDish = Instance.new("BindableFunction")
takeBoardDish.Name = "TakeBoardDish"
takeBoardDish.Parent = ServerStorage
takeBoardDish.OnInvoke = function()
	local dish = state.board
	if not dish then return nil end
	state.board = nil
	refreshBoard()
	return dish
end
----------------------------------------------------------------
-- SERVING
----------------------------------------------------------------
local function serveCustomer(player, c, dish)
	local idx = table.find(waiting, c)
	if idx then table.remove(waiting, idx) end
	if c.slotIndex then setTicket(slots[c.slotIndex], nil) end
	state.board = nil
	refreshBoard()
	c.state = "served"; c.served = true
	playSound("Serve")
	fx("serve", { pos = (stations.ServeSpot and stationPosition(stations.ServeSpot)) or stationPosition(boardPart) })
	Presentation.Burst("sparkle", stationPosition(boardPart) + Vector3.new(0, 1, 0))

	if c.isBeggar then
		local data = CartSave.Get(player)
		if data and not table.find(data.beggarFedDays, data.day) then
			table.insert(data.beggarFedDays, data.day)
		end
		say(c.displayName .. " thanks you and heads back to his spot.")
	else
		local pay = SETTINGS.BasePay + SETTINGS.PerExtraPay * (#dish.fillings + #dish.sauces)
		addCoins(player, pay)
		say(("Served %s!  +%d coins"):format(c.displayName, pay))
	end
end

local function tryServe(player, target)
	local dish = state.board
	if not dish then say("Put a finished dish on the board first") return end
	if target then
		if not target.order and not target.acceptsAnyDish then return end
		if dishMatches(dish, target.order, target.acceptsAnyDish) then serveCustomer(player, target, dish)
		else say(target.displayName .. ": \"Hmm, that's not quite what I ordered.\"") end
		return
	end
	for _, c in ipairs(waiting) do
		if dishMatches(dish, c.order, c.acceptsAnyDish) then serveCustomer(player, c, dish); return end
	end
	say("That doesn't match any of the orders")
end

----------------------------------------------------------------
-- STATION HANDLERS
----------------------------------------------------------------
local handlers = {}

local function takeItem(item, station)
	return function()
		if state.held then say("Your hands are full") return end
		setHeld(item)
		playSound("Pickup")
		playSound("Rustle")
		fx("pickup", { pos = stationPosition(station), item = item })
	end
end
handlers.TakeBun = takeItem("Bun", stations.BunCrate)
handlers.TakeBread = takeItem("Bread", stations.BreadBasket)
handlers.TakeSausage = takeItem("RawSausage", stations.SausageTray)
handlers.TakePotato = takeItem("PotatoStuff", stations:FindFirstChild("PotatoBin"))

handlers.Board = function()
	local held = state.held
	if held == "Bun" or held == "Bread" then
		if state.board or state.boardRaw then say("The board is busy") return end
		state.boardRaw = held
		setHeld(nil)
		playSound("Place")
		playSound("Rustle")
		fx("place", { pos = stationPosition(boardPart) })
		refreshBoard()
	elseif held == "CookedSausage" then
		local dish = state.board
		if not dish or dish.base ~= "Hotdog" then say("Cut a bun first") return end
		if dish.sausage then say("It already has a sausage") return end
		dish.sausage = true
		setHeld(nil)
		playSound("Place")
		playSound("Rustle")
		fx("place", { pos = stationPosition(boardPart) })
		refreshBoard()
	elseif held == "PotatoStuff" then
		local dish = state.board
		if not dish or dish.base ~= "Sandwich" then say("Only sandwiches take the potato filling") return end
		if not dish.toasted then say("Toast the bread first") return end
		if dish.potato then say("It's already got the potato filling") return end
		dish.potato = true
		setHeld(nil)
		playSound("Place")
		playSound("Rustle")
		fx("place", { pos = stationPosition(boardPart) })
		refreshBoard()
	elseif held == "RawSausage" then
		say("Boil the sausage first")
	elseif not held and state.boardRaw and not state.board then
		state.busy = true
		playSound("Knife")
		playSound("Rustle")
		fx("cut", { pos = stationPosition(boardPart), duration = SETTINGS.CutTime })
		Presentation.Burst("crumbs", stationPosition(boardPart) + Vector3.new(0, 0.3, 0))
		task.wait(SETTINGS.CutTime)
		state.board = { base = (state.boardRaw == "Bun") and "Hotdog" or "Sandwich",
			sausage = false, toasted = false, potato = false, fillings = {}, sauces = {} }
		state.boardRaw = nil
		state.busy = false
		refreshBoard()
	elseif state.board then
		say("Dish is on the board")
	elseif state.boardRaw then
		say("Click again to cut it")
	else
		say("Pick up a bun or bread to start")
	end
end

handlers.Pot = function()
	if state.held == "RawSausage" then
		if #state.pot >= SETTINGS.PotSlots then say("The pot is full") return end
		table.insert(state.pot, { readyAt = os.clock() + SETTINGS.SausageCookTime })
		setHeld(nil)
		playSound("Splash")
		fx("splash", { pos = potPart.Position })
	elseif not state.held then
		local now = os.clock()
		for i, s in ipairs(state.pot) do
			if now >= s.readyAt then
				table.remove(state.pot, i)
				setHeld("CookedSausage")
				playSound("Pickup")
				fx("pickup", { pos = potPart.Position, item = "CookedSausage" })
				refreshPot()
				return
			end
		end
		say(#state.pot > 0 and "Not ready yet, let them boil a little" or "The pot is empty")
	else
		say("Your hands are full")
	end
	refreshPot()
end

handlers.Pan = function()
	if state.pan then
		if os.clock() < state.pan.readyAt then say("Still toasting...") return end
		if state.board then say("Clear the board first") return end
		state.pan.dish.toasted = true
		state.board = state.pan.dish
		state.pan = nil
		playSound("Place")
		fx("panout", { pos = panPart.Position })
		refreshBoard()
	else
		local dish = state.board
		if not dish then say("Nothing to toast yet") return end
		if dish.base ~= "Sandwich" then say("Only sandwiches get toasted") return end
		if dish.toasted then say("Already toasted") return end
		state.pan = { dish = dish, readyAt = os.clock() + SETTINGS.ToastTime, visibleAt = os.clock() + SETTINGS.PanPlaceVisualDelay }
		state.board = nil
		playSound("PanPlace")
		playSound("Rustle")
		fx("panplace", { pos = stationPosition(panPart) })
		refreshBoard()
	end
	refreshPan()
end

local function addToDish(listName, fxKind)
	return function(item, station)
		local dish = state.board
		if not dish then say("Put a bun or bread on the board first") return end
		if table.find(dish[listName], item) then say("Already added " .. item) return end
		table.insert(dish[listName], item)
		playSound(fxKind == "sauce" and "Squeeze" or "Place")
		playSound("Rustle")
		fx(fxKind, { pos = stationPosition(station), item = item })
		Presentation.Burst(fxKind == "sauce" and "sauce" or "crumbs", boardPart.Position + Vector3.new(0, 0.4, 0))
		refreshBoard()
	end
end
local addSauce = addToDish("sauces", "sauce")
local addFilling = addToDish("fillings", "place")
handlers.Sauce = function(_, item)
	local dish = state.board
	if dish and dish.base == "Hotdog" and not dish.sausage then
		say("Add the sausage first")
		return
	end
	if dish and dish.base == "Sandwich" and not dish.potato then
		say("Add the potato filling first")
		return
	end
	addSauce(item, stations["Sauce_" .. item])
end

handlers.Filling = function(_, item)
	local dish = state.board
	if dish and dish.base == "Hotdog" then
		say("Hotdogs don't take fillings — try a sauce instead")
		return
	end
	if dish and dish.base == "Sandwich" and not dish.potato then
		say("Add the potato filling first")
		return
	end
	addFilling(item, stations["Filling_" .. item])
end

handlers.Trash = function()
	if state.held then setHeld(nil)
	elseif state.board then state.board = nil; refreshBoard()
	elseif state.boardRaw then state.boardRaw = nil; refreshBoard()
	else say("Nothing to throw away") end
end

handlers.Serve = function(player) tryServe(player, nil) end

for _, part in ipairs(stations:GetChildren()) do
	local action, item = getAction(part)
	if action and handlers[action] then
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 200
		cd.Parent = part
		cd.MouseClick:Connect(function(player)
			if state.busy or state.talking then return end
			handlers[action](player, item)
		end)
	else
		warn("[CartGame] Station name not recognised (ignored): " .. part.Name)
	end
end

----------------------------------------------------------------
-- DIALOGUE
----------------------------------------------------------------
local awaiting, awaitMax, reply = false, nil, nil

dialogueRemote.OnServerEvent:Connect(function(_, choice)
	if not awaiting then return end
	if awaitMax then
		if typeof(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > awaitMax then return end
	end
	reply = choice
	awaiting = false
end)

local function showLine(speaker, text)
	awaitMax, reply, awaiting = nil, nil, true
	dialogueRemote:FireAllClients("line", speaker, text)
	while awaiting do task.wait(0.05) end
end

local function showChoice(options)
	local texts = {}
	for i, o in ipairs(options) do texts[i] = o.text end
	if #texts == 0 then return nil end
	awaitMax, reply, awaiting = #texts, nil, true
	dialogueRemote:FireAllClients("choice", texts)
	while awaiting do task.wait(0.05) end
	return reply
end

local function placeOrder(c)
	if c.order or c.acceptsAnyDish then return end
	if c.isBeggar then
		c.acceptsAnyDish = true
		if c.slotIndex then setTicket(slots[c.slotIndex], "Anything\nis fine") end
		playSound("Ticket")
		return
	end
	c.order = generateOrder()
	setTicket(slots[c.slotIndex], orderText(c.order))
	playSound("Ticket")
end

local function runSteps(c, steps)
	for _, step in ipairs(steps) do
		if step.say then showLine(c.displayName, step.say)
		elseif step.you then showLine("You", step.you)
		elseif step.order then
			placeOrder(c)
			if c.order then showLine(c.displayName, spokenOrder(c.order)) end
		elseif step.choice then
			local idx = showChoice(step.choice)
			if idx and step.choice[idx].steps then runSteps(c, step.choice[idx].steps) end
		end
	end
end

local function startConversation(c)
	local steps
	local story = Dialogues.Characters[c.rigName]
	if story then
		local n = (visitCount[c.rigName] or 0) + 1
		visitCount[c.rigName] = n
		steps = story.Visits[n]
	end
	if not steps and #Dialogues.Random > 0 then steps = Dialogues.Random[math.random(#Dialogues.Random)] end
	runSteps(c, steps or {})
	if not c.order and not c.acceptsAnyDish then
		placeOrder(c)
		if c.order then showLine(c.displayName, spokenOrder(c.order)) end
	end
end

----------------------------------------------------------------
-- CUSTOMERS
----------------------------------------------------------------
local function moveTo(hum, pos, timeout)
	local finished = false
	local conn = hum.MoveToFinished:Connect(function() finished = true end)
	hum:MoveTo(pos)
	local t = 0
	while not finished and t < timeout do t += task.wait(0.1) end
	conn:Disconnect()
end

local function walkTo(hum, position)
	local root = hum.RootPart
	if not root then return end
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function() path:ComputeAsync(root.Position, position) end)
	if ok and path.Status == Enum.PathStatus.Success then
		for _, wp in ipairs(path:GetWaypoints()) do moveTo(hum, wp.Position, 4) end
	else
		moveTo(hum, position, 12)
	end
end

local function atSpot(hrp, spot)
	local d = (hrp.Position - spot.Position) * Vector3.new(1, 0, 1)
	return d.Magnitude < 3
end

local function faceToward(hrp, targetPos)
	local p = hrp.Position
	local flat = Vector3.new(targetPos.X, p.Y, targetPos.Z)
	if (flat - p).Magnitude < 0.1 then return end
	hrp.CFrame = CFrame.lookAt(p, flat)
end

local function setBubble(c, on)
	local head = c.model:FindFirstChild("Head")
	if not head then return end
	local gui = head:FindFirstChild("TalkBubble")
	if on and not gui then
		gui = Instance.new("BillboardGui"); gui.Name = "TalkBubble"
		gui.Size = UDim2.fromOffset(50, 50); gui.StudsOffset = Vector3.new(0, 2.5, 0); gui.AlwaysOnTop = true
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1; t.Text = "💬"; t.TextScaled = true
		t.Parent = gui
		gui.Parent = head
	elseif not on and gui then
		gui:Destroy()
	end
end

local function claimSlot(c)
	for i = 1, math.min(#slots, SETTINGS.MaxWaiting) do
		if not slotOwner[i] then slotOwner[i] = c; return i end
	end
	return nil
end

local function claimSeat()
	if eatingCount >= SETTINGS.MaxEating then return nil end
	local free = {}
	for _, s in ipairs(seats) do if not seatTaken[s] then table.insert(free, s) end end
	if #free == 0 then return nil end
	local s = free[math.random(#free)]
	seatTaken[s] = true
	eatingCount += 1
	return s
end

local function openOrders()
	return #waiting + (state.talking and 1 or 0)
end

local function onCustomerClicked(player, c)
	if state.talking then return end
	if c.state == "ready" then
		if openOrders() >= SETTINGS.MaxOpenOrders then say("Finish the current order first") return end
		state.talking = true
		c.state = "talking"
		setBubble(c, false)
		task.spawn(function()
			startConversation(c)
			dialogueRemote:FireAllClients("end")
			state.talking = false
			c.talked = true
		end)
	elseif c.state == "waiting" then
		tryServe(player, c)
	elseif c.state == "queueing" then
		say(c.displayName .. " is waiting in line")
	end
end

local function runCustomer(c)
	local hum, hrp = c.humanoid, c.hrp
	c.state = "queueing"

	while true do
		local idx = table.find(queue, c)
		local spot = queueSpots[idx]
		if not atSpot(hrp, spot) then walkTo(hum, spot.Position); faceToward(hrp, lookTarget) end
		if idx == 1 and atSpot(hrp, spot) then
			local slotIndex = claimSlot(c)
			if slotIndex then c.slotIndex = slotIndex; break end
		end
		task.wait(0.3)
	end

	c.state = "ready"
	local rang = false
	while not c.talked do
		local free = (c.state == "ready") and openOrders() < SETTINGS.MaxOpenOrders
		setBubble(c, free)
		if free and not rang then rang = true; playSound("Bell") end
		task.wait(0.2)
	end

	table.remove(queue, table.find(queue, c))
	table.insert(waiting, c)
	c.state = "waiting"
	local waitSpot = waitSpots[c.slotIndex] or waitSpots[#waitSpots]
	walkTo(hum, waitSpot.Position); faceToward(hrp, lookTarget)
	while not c.served do task.wait(0.3) end

	if c.slotIndex then slotOwner[c.slotIndex] = nil end

	if c.isBeggar then
		c.state = "leaving"
		if beggarHome then
			walkTo(hum, beggarHome.Position)
			faceToward(hrp, lookTarget)
		end
		return -- he's a permanent fixture now, holding his food, until tomorrow's conversation
	end

	local seat
	while true do
		seat = claimSeat()
		if seat or #seats == 0 then break end
		task.wait(1)
	end
	c.state = "eating"
	if seat then
		walkTo(hum, seat.Position)
		local ok = pcall(function() seat:Sit(hum) end)
		if not ok then hum.Sit = true end
	end
	task.wait(math.random(SETTINGS.EatTimeMin, SETTINGS.EatTimeMax))
	if seat then
		hum.Sit = false; hum.Jump = true; task.wait(0.8)
		seatTaken[seat] = nil; eatingCount -= 1
	end

	c.state = "leaving"
	walkTo(hum, exitPoint.Position)
	c.model:Destroy()
end

local function spawnCustomer()
	local rigs = customerRigs:GetChildren()
	if #rigs == 0 then warn("[CartGame] ServerStorage > Customers is empty. Add some rigs!") return end
	local template = rigs[math.random(#rigs)]
	local model = template:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then
		warn("[CartGame] Customer rig missing Humanoid/HumanoidRootPart: " .. template.Name)
		model:Destroy(); return
	end
	model.Name = "Customer"
	hum.WalkSpeed = SETTINGS.CustomerWalkSpeed
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0))
	model.Parent = workspace
	pcall(function() hrp:SetNetworkOwner(nil) end)
	playSound("DoorBell")

	local story = Dialogues.Characters[template.Name]
	local names = Dialogues.Names
	local c = {
		model = model, humanoid = hum, hrp = hrp, rigName = template.Name,
		displayName = (story and story.Name) or (#names > 0 and names[math.random(#names)]) or "Customer",
		served = false, talked = false,
	}

	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 200
	cd.Parent = model
	cd.MouseClick:Connect(function(player) onCustomerClicked(player, c) end)

	table.insert(queue, c)
	task.spawn(runCustomer, c)
end

----------------------------------------------------------------
-- THE BEGGAR — a persistent character who joins the queue once a day
----------------------------------------------------------------
local beggarModel, beggarHum, beggarHrp
local beggarActive = false


local function ensureBeggarModel()
	if beggarModel then return true end
	if not beggarRig then
		warn("[CartGame] No 'BeggarRig' found in ServerStorage — add one to enable the beggar.")
		return false
	end
	local model = beggarRig:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then
		warn("[CartGame] BeggarRig is missing a Humanoid or HumanoidRootPart.")
		model:Destroy()
		return false
	end
	model.Name = "Beggar"
	hum.WalkSpeed = SETTINGS.CustomerWalkSpeed
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model.Parent = workspace
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 200
	cd.Parent = model
	beggarModel, beggarHum, beggarHrp = model, hum, hrp
	model:PivotTo((beggarHome and beggarHome.CFrame) or spawnPoint.CFrame)
	return true
end

local function spawnBeggar()
	if beggarActive then return end
	if not ensureBeggarModel() then return end
	beggarActive = true

	beggarModel:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0))

	local story = Dialogues.Characters["Beggar"]
	local c = {
		model = beggarModel, humanoid = beggarHum, hrp = beggarHrp, rigName = "Beggar",
		displayName = (story and story.Name) or "the beggar",
		served = false, talked = false, isBeggar = true,
	}

	local cd = beggarModel:FindFirstChildOfClass("ClickDetector")
	local conn
	if cd then
		conn = cd.MouseClick:Connect(function(player) onCustomerClicked(player, c) end)
	end

	table.insert(queue, c)
	task.spawn(function()
		runCustomer(c)
		if conn then conn:Disconnect() end
		beggarActive = false
	end)
end

local function playPassportGlimpse(player)
	state.talking = true -- blocks station clicks, same as customer dialogue does
	passportCutscene:FireClient(player, "start")
	task.wait(0.8)
	fx("passportGlimpse", {})
	task.wait(0.5)
	say("I need to keep my passport safe.", 4)
	task.wait(3.5)
	fx("passportGlimpseEnd", {})
	task.wait(0.4)
	passportCutscene:FireClient(player, "end")
	state.talking = false
end

local dayStartedEvent = ServerStorage:WaitForChild("DayStarted", 10)
if dayStartedEvent then
	dayStartedEvent.Event:Connect(function(day)
		local player = Players:GetPlayers()[1]
		if not player then return end
		local data = CartSave.Get(player) -- the real saved table, not the copy the event carries
		if not data then return end
		if day >= SETTINGS.PassportGlimpseDay and not data.sawPassportGlimpse then
			data.sawPassportGlimpse = true
			CartSave.Save(player)
			task.spawn(playPassportGlimpse, player)
		end
	end)
end
if dayStartedEvent then
	dayStartedEvent.Event:Connect(function(_day, _data)
		task.delay(math.random(SETTINGS.BeggarDelayMin, SETTINGS.BeggarDelayMax), function()
			spawnBeggar()
		end)
	end)
else
	warn("[CartGame] No DayStarted event found — make sure CartDayCycle has run at least once.")
end

task.spawn(function()
	task.wait(2)
	spawnCustomer()
	while true do
		task.wait(math.random(SETTINGS.SpawnEveryMin, SETTINGS.SpawnEveryMax))
		if not ServerStorage:GetAttribute("SpawningPaused") and #queue < math.min(SETTINGS.MaxQueue, #queueSpots) then spawnCustomer() end
	end
end)

print("[CartGame v4] Ready. Sauces: " .. table.concat(SAUCES, ", ") .. " | Fillings: " .. table.concat(FILLINGS, ", "))