-- Authoritative Cosmetics shop. The client only ever names an item; price, level, affordability
-- and whether the shop is open are all decided here, and the money moves through
-- PlayerDataService's purchase path, which re-checks the stored balance when the save commits.
-- Everything sold is cosmetic (ShopConfig): trails, base themes and signs, emotes and nameplate
-- titles, each bought with coins, reached at a level, or included in a pass.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local Payout = require(script.Parent.Payout)
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))

local ShopService = {}
ShopService.__index = ShopService

-- options.canShop(player) -> bool: whether purchases are allowed right now (the lobby only).
-- options.onChanged(player): called after anything the player's profile view shows changes.
-- options.ownsPass(player, passKey) -> bool: game-pass ownership, for pass items.
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

function ShopService:_level(player)
	return ProgressionConfig.LevelFor(Payout.XpOf(self._persistence, player))
end

-- Whether the player owns an item, however it was earned.
function ShopService:Owns(player, item)
	return ShopConfig.Owns(item, self._persistence:GetMetaLevels(player), self:_level(player), function(passKey)
		return self._ownsPass(player, passKey)
	end)
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
	if ShopConfig.MaxLevel(item) == 0 then
		-- Reached by level or included in a pass: there is nothing to buy.
		return false, "not for sale"
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
	if ShopConfig.Equippable[item.Kind] then
		-- A cosmetic you just bought is the one you want to see.
		self:_wear(player, item.Kind, item.Id)
	end
	self:_changed(player, now)
	return true, { ItemId = item.Id, Level = level, Cost = cost, Balance = balance }
end

-- Writes the equipped id for a kind into the profile.
function ShopService:_wear(player, kind, itemId)
	if kind == "Trail" then
		self._persistence:SetEquippedTrail(player, itemId)
		return
	end
	self._persistence:Update(player, function(profile)
		if kind == "Theme" then
			profile.Base.Theme = itemId
		elseif kind == "Sign" then
			profile.Base.Sign = itemId
		elseif kind == "Nameplate" then
			profile.Nameplate = itemId
		end
	end)
end

-- Equips an owned cosmetic, or clears a slot with "" (kind names the slot; Trail by default).
function ShopService:Equip(player, itemId, now, kind)
	if not FeatureFlags.SalvageShop then
		return false, "shop disabled"
	end
	if not self._persistence:IsLoaded(player) then
		return false, "profile not loaded"
	end
	if itemId == "" then
		kind = type(kind) == "string" and kind or "Trail"
		if not ShopConfig.Equippable[kind] then
			return false, "not equippable"
		end
	else
		local item = type(itemId) == "string" and ShopConfig.Get(itemId) or nil
		if not item or not ShopConfig.Equippable[item.Kind] then
			return false, "not equippable"
		end
		if not self:Owns(player, item) then
			return false, "not owned"
		end
		kind = item.Kind
	end
	self:_wear(player, kind, itemId)
	self:_changed(player, now)
	return true
end

-- The equipped item of a kind, if it is still owned (a lapsed pass or a tampered profile shows
-- the default instead).
function ShopService:_wornItem(player, kind)
	local session = self._persistence:GetSession(player)
	local profile = session and session.profile
	if not profile then
		return nil
	end
	local id
	if kind == "Trail" then
		id = profile.EquippedTrail
	elseif kind == "Theme" then
		id = profile.Base.Theme
	elseif kind == "Sign" then
		id = profile.Base.Sign
	elseif kind == "Nameplate" then
		id = profile.Nameplate
	end
	local item = type(id) == "string" and id ~= "" and ShopConfig.Get(id) or nil
	if item and item.Kind == kind and self:Owns(player, item) then
		return item
	end
	return nil
end

-- The trail a run starting now draws behind this player's shots, or nil.
function ShopService:GetTrail(player)
	local item = self:_wornItem(player, "Trail")
	return item and item.Trail or nil
end

-- The worn theme and sign ids ("" for the defaults), for the plot.
function ShopService:GetBaseStyle(player)
	local theme, sign = self:_wornItem(player, "Theme"), self:_wornItem(player, "Sign")
	return theme and theme.Id or "", sign and sign.Id or ""
end

-- The worn nameplate title, or nil.
function ShopService:GetNameplate(player)
	local item = self:_wornItem(player, "Nameplate")
	return item and item.Title or nil
end

-- An owned emote to play (the lobby only). Returns its definition, or nil and a reason.
function ShopService:PlayEmote(player, emoteId)
	local item = type(emoteId) == "string" and ShopConfig.Get(emoteId) or nil
	if not item or item.Kind ~= "Emote" then
		return nil, "unknown emote"
	end
	if not self._canShop(player) then
		return nil, "in a run"
	end
	if not self:Owns(player, item) then
		return nil, "not owned"
	end
	return item
end

-- Tells the player about any purchase the store refused at commit time (another server spent
-- the salvage first). Called after saves; each refusal is reported once.
function ShopService:DrainRejections(player)
	return self._persistence:TakePurchaseRejections(player)
end

return ShopService
