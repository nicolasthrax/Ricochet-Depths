-- Wraps DataStoreService so the rest of the game depends on a two-method interface that tests
-- can substitute. Also degrades cleanly when API access is unavailable (Studio without
-- "Enable Studio Access to API Services", or a datastore outage).
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataConfig = require(ReplicatedStorage:WaitForChild("PlayerDataConfig"))

local DataStoreProvider = {}

-- Fails every call, which puts every session into the read-only state PlayerDataService
-- already handles. Nothing is written and no reward is persisted.
local UnavailableStore = {}
UnavailableStore.__index = UnavailableStore

function UnavailableStore.new(reason)
	return setmetatable({ reason = reason, Available = false }, UnavailableStore)
end

function UnavailableStore:UpdateAsync()
	error("datastore unavailable: " .. tostring(self.reason), 0)
end

-- scope keeps development writes in a namespace that can never reach live player data.
function DataStoreProvider.Get(useDevelopmentScope)
	local scope = useDevelopmentScope and PlayerDataConfig.DevelopmentScope or PlayerDataConfig.ProductionScope

	local ok, storeOrError = pcall(function()
		return DataStoreService:GetDataStore(PlayerDataConfig.StoreName, scope)
	end)
	if not ok then
		return UnavailableStore.new(storeOrError), scope
	end

	return storeOrError, scope
end

DataStoreProvider.UnavailableStore = UnavailableStore

return DataStoreProvider
