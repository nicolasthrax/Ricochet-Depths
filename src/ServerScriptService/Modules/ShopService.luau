-- Authoritative lobby shop (Armory and Cosmetics). The client only ever names an item; price, level, affordability
-- and whether the shop is open are all decided here, and the money moves through
-- PlayerDataService's purchase path, which re-checks the stored balance when the save commits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))

local ShopService = {}
ShopService.__index = ShopService

-- options.canShop(player) -> bool: whether purchases are allowed right now (the lobby only).
-- options.onChanged(player): called after anything the player's profile view shows changes.
-- options.ownsPass(player, passKey) -> bool: game-pass ownership, for pass-only items.
function ShopService.new(persistence, options)
	options = options or {}
	return setmetatable({
		_ownsPass = options.ownsPass or function()
			return false
		end,
		_persistence = persistence,
		_canShop = options.canShop or function()
			return false
		end,
		_onChanged = options.onChanged,
	}, ShopService)
end

function ShopService:_changed(player, now)
	self._persistence:SaveInBackground(player, now or 0)
	if self._onChanged then
		self._onChanged(player)
	end
end

-- Returns true and { ItemId, Level, Cost, Balance }, or false and a reason.
function ShopService:Purchase(player, itemId, now)
	if not FeatureFlags.SalvageShop then
		return false, "shop disabled"
	end
	local item = type(itemId) == "string" and ShopConfig.Get(itemId) or nil
	if not item then
		return false, "unknown item"
	end
	local persistence = self._persistence
	if not persistence:IsLoaded(player) then
		-- Includes read-only sessions: a purchase that can never be saved must not be taken.
		return false, "profile not loaded"
	end
	if not self._canShop(player) then
		return false, "shop closed"
	end

	if item.RequiresPass and not self._ownsPass(player, item.RequiresPass) then
		return false, "requires " .. item.RequiresPass
	end

	local level = (persistence:GetMetaLevels(player)[item.Id] or 0) + 1
	if level > ShopConfig.MaxLevel(item) then
		return false, "max level"
	end
	local cost = ShopConfig.CostFor(item, level)
	if persistence:GetBalance(player) < cost then
		return false, "insufficient salvage"
	end

	local balance, reason = persistence:SpendOnUpgrade(player, item.Id, level, cost)
	if not balance then
		return false, reason
	end
	if item.Kind == "Trail" then
		-- A trail you just bought is the one you want to see.
		persistence:SetEquippedTrail(player, item.Id)
	end
	self:_changed(player, now)
	return true, { ItemId = item.Id, Level = level, Cost = cost, Balance = balance }
end

-- Equips an owned trail, or clears it with "".
function ShopService:Equip(player, itemId, now)
	if not FeatureFlags.SalvageShop then
		return false, "shop disabled"
	end
	if not self._persistence:IsLoaded(player) then
		return false, "profile not loaded"
	end
	if itemId ~= "" then
		local item = type(itemId) == "string" and ShopConfig.Get(itemId) or nil
		if not item or item.Kind ~= "Trail" then
			return false, "not a trail"
		end
		if (self._persistence:GetMetaLevels(player)[item.Id] or 0) < 1 then
			return false, "not owned"
		end
	end
	self._persistence:SetEquippedTrail(player, itemId)
	self:_changed(player, now)
	return true
end

-- What a run starting now gets from the shop: { stats = { [stat] = delta }, trail = def|nil }.
function ShopService:GetRunBonuses(player)
	local levels = self._persistence:GetMetaLevels(player)
	local trail = nil
	local profile = self._persistence:GetPublicProfile(player)
	local equipped = profile and profile.EquippedTrail or ""
	local item = equipped ~= "" and ShopConfig.Get(equipped) or nil
	if item and item.Kind == "Trail" and (levels[item.Id] or 0) >= 1 then
		trail = item.Trail
	end
	return { stats = ShopConfig.ComputeBonuses(levels), trail = trail }
end

-- Tells the player about any purchase the store refused at commit time (another server spent
-- the salvage first). Called after saves; each refusal is reported once.
function ShopService:DrainRejections(player)
	return self._persistence:TakePurchaseRejections(player)
end

return ShopService
