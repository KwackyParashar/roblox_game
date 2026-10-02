-- CartSave | ModuleScript | ServerScriptService
-- Wraps all the saved-progress data for a player: coins, day count, and
-- (starting next update) beggar/story state.

local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("CartGameSave_v1")

local CartSave = {}
local cache = {} -- cache[userId] = data table, kept in memory while they're in the server

local DEFAULT_DATA = {
	coins = 0,
	day = 1,
	beggarFedDays = {},       -- which day numbers the beggar was fed (for the "4 of the last 7 days" check)
	sawPassportGlimpse = false,
	passportMissing = false,
	passportReturned = true,
	country = "NewYork",
}

local function freshDefaults()
	local d = table.clone(DEFAULT_DATA)
	d.beggarFedDays = {}
	return d
end

function CartSave.Load(player)
	if cache[player.UserId] then return cache[player.UserId] end -- already loaded this session; never replace it
	local key = "player_" .. player.UserId
	local ok, data = pcall(function() return store:GetAsync(key) end)
	if ok and data then
		for k, v in pairs(DEFAULT_DATA) do
			if data[k] == nil then
				data[k] = (type(v) == "table") and table.clone(v) or v
			end
		end
		cache[player.UserId] = data
	else
		if not ok then warn("[CartSave] Load failed for " .. player.Name .. ": " .. tostring(data)) end
		cache[player.UserId] = freshDefaults()
	end
	return cache[player.UserId]
end

function CartSave.Get(player)
	return cache[player.UserId]
end

function CartSave.Save(player)
	local data = cache[player.UserId]
	if not data then return end
	local key = "player_" .. player.UserId
	local ok, err = pcall(function() store:SetAsync(key, data) end)
	if not ok then warn("[CartSave] Save failed for " .. player.Name .. ": " .. tostring(err)) end
end

function CartSave.Release(player)
	cache[player.UserId] = nil
end

return CartSave