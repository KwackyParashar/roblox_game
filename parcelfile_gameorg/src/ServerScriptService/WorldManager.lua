local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Countries = require(ReplicatedStorage:WaitForChild("Countries"))

local WorldManager = {}

local worldsFolder = Workspace:WaitForChild("Worlds")
local storageFolder = ServerStorage:WaitForChild("Worlds")

local WorldChanged = ReplicatedStorage:FindFirstChild("WorldChanged")
if not WorldChanged then
	WorldChanged = Instance.new("RemoteEvent")
	WorldChanged.Name = "WorldChanged"
	WorldChanged.Parent = ReplicatedStorage
end

local unlocked = { Home = true } -- countries the server has already paid for
local currentId = "Home"

function WorldManager.GetCurrentId()
	return currentId
end

function WorldManager.GetActiveCountryModel()
	return worldsFolder:FindFirstChild(currentId)
end

function WorldManager.GetActiveCart()
	local country = WorldManager.GetActiveCountryModel()
	return country and country:FindFirstChild("Cart")
end

-- swaps the shared scene to targetId. Returns ok:boolean, reason:string?
function WorldManager.TravelTo(targetId, coinsAvailable)
	if targetId == currentId then
		return false, "already there"
	end
	local data = Countries.Get(targetId)
	if not data then
		return false, "unknown country"
	end
	if not unlocked[targetId] and coinsAvailable < data.Cost then
		return false, "not enough coins"
	end

	-- archive the current world
	local activeModel = worldsFolder:FindFirstChild(currentId)
	if activeModel then
		activeModel.Parent = storageFolder
	end

	-- bring in the target world
	local targetModel = storageFolder:FindFirstChild(targetId)
	if not targetModel then
		-- something's missing in Studio setup; roll back
		if activeModel then activeModel.Parent = worldsFolder end
		return false, "target world not built"
	end
	targetModel.Parent = worldsFolder

	unlocked[targetId] = true
	local previousId = currentId
	currentId = targetId

	local newCart = targetModel:FindFirstChild("Cart")
	local camPoint = newCart and newCart:FindFirstChild("CameraPoint")
	WorldChanged:FireAllClients(targetId, camPoint and camPoint.CFrame)

	return true, previousId
end

return WorldManager