-- Authoritative home base: building, upgrading and placing the twelve buildings, emptying the
-- offline workers, and friend-visit cheers. The client only ever names a building, a tile or a
-- player; prices, Hearth gates, what is waiting in the yard and whether the base can be changed
-- right now are all decided here. Coins move only through PlayerDataService: buildings through
-- its purchase path (re-checked against the store at commit), claims and cheers through
-- Payout.Grant under keys that make a repeat pay nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage:WaitForChild("BaseConfig"))
local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local Payout = require(script.Parent.Payout)

local BaseService = {}
BaseService.__index = BaseService

-- options:
--   canManage(player) -> bool: whether the base can be changed now (not mid-run).
--   extraCapHours(player) -> number: offline cap hours passes add.
--   wallClock() -> unix seconds (os.time by default; tests pin it).
--   onChanged(player): the base or balance changed (push the profile, rebuild the plot).
--   onFirstBuild(player): a building was bought for the first time ever (funnel step).
function BaseService.new(persistence, options)
	options = options or {}
	return setmetatable({
		_persistence = persistence,
		_canManage = options.canManage or function()
			return true
		end,
		_extraCapHours = options.extraCapHours or function()
			return 0
		end,
		_wallClock = options.wallClock or os.time,
		_onChanged = options.onChanged,
		_onFirstBuild = options.onFirstBuild,
	}, BaseService)
end

function BaseService:_profile(player)
	local session = self._persistence:GetSession(player)
	if not session or not session.loaded or session.failed then
		return nil
	end
	return session.profile
end

function BaseService:_changed(player, now)
	self._persistence:SaveInBackground(player, now or 0)
	if self._onChanged then
		self._onChanged(player)
	end
end

-- Building id -> shown level, for every building.
function BaseService:GetLevels(player)
	local stored = self._persistence:GetMetaLevels(player)
	local levels = {}
	for _, building in BaseConfig.Buildings do
		levels[building.Id] = BaseConfig.LevelOf(stored, building.Id)
	end
	return levels, stored
end

-- The saved layout, cleaned against what is actually built. Writes the cleaned copy back when it
-- differs, so a building bought on another server gets a tile here.
function BaseService:EnsureLayout(player)
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local _, stored = self:GetLevels(player)
	local layout = BaseConfig.NormaliseLayout(profile.Base.Layout, stored)
	local differs = false
	for id, tile in layout do
		if profile.Base.Layout[id] ~= tile then
			differs = true
		end
	end
	for id in profile.Base.Layout do
		if layout[id] == nil then
			differs = true
		end
	end
	if differs then
		self._persistence:Update(player, function(p)
			p.Base.Layout = table.clone(layout)
		end)
	end
	return layout
end

-- Everything the base panel shows. nil while the profile is unavailable.
function BaseService:GetState(player, now)
	local profile = self:_profile(player)
	if not profile then
		return nil
	end
	now = now or self._wallClock()
	local levels, stored = self:GetLevels(player)
	local extra = self._extraCapHours(player)
	local coins, fill = BaseConfig.OfflineCoins(stored, profile.Base.LastClaimAt, now, extra)
	return {
		Levels = levels,
		Layout = self:EnsureLayout(player),
		Hearth = levels.Hearth,
		Balance = self._persistence:GetBalance(player),
		Offline = {
			Coins = coins,
			Fill = fill,
			PerHour = BaseConfig.ProductionPerHour(stored),
			CapHours = BaseConfig.CapHours(stored, extra),
		},
		NextBuild = BaseConfig.NextBuild(stored),
		Theme = profile.Base.Theme,
		Sign = profile.Base.Sign,
		CheersReceived = profile.Base.Cheers.Day == MetaConfig.DayOf(now) and profile.Base.Cheers.Received or 0,
	}
end

-- Run stat deltas from the buildings: { [stat] = delta }.
function BaseService:GetRunBonuses(player)
	return BaseConfig.ComputeBonuses(self._persistence:GetMetaLevels(player))
end

function BaseService:_guard(player)
	if not FeatureFlags.BaseBuilding then
		return "base disabled"
	end
	if not self._persistence:IsLoaded(player) then
		-- Includes read-only sessions: a purchase that can never be saved must not be taken.
		return "profile not loaded"
	end
	if not self._canManage(player) then
		return "in a run"
	end
	return nil
end

-- Buys the next level of a building. A building not yet built needs a free tile (or takes the
-- first free one when tile is nil). Returns true and { Id, Level, Cost, Tile, Balance }, or false
-- and a reason.
function BaseService:Upgrade(player, buildingId, tile, now)
	local refused = self:_guard(player)
	if refused then
		return false, refused
	end
	local building = type(buildingId) == "string" and BaseConfig.Get(buildingId) or nil
	if not building then
		return false, "unknown building"
	end
	local levels, stored = self:GetLevels(player)
	local nextLevel = levels[building.Id] + 1
	local cost = BaseConfig.CostFor(building, nextLevel)
	if not cost then
		return false, "max level"
	end
	if BaseConfig.HearthNeeded(building, nextLevel) > levels.Hearth then
		return false, "hearth too low"
	end
	if self._persistence:GetBalance(player) < cost then
		return false, "insufficient salvage"
	end

	local layout = self:EnsureLayout(player)
	local placeAt = layout[building.Id]
	if not placeAt then
		if tile ~= nil then
			if not BaseConfig.ValidTile(tile) then
				return false, "invalid tile"
			end
			if BaseConfig.BuildingAt(layout, tile) then
				return false, "tile taken"
			end
			placeAt = tile
		else
			for candidate = 1, BaseConfig.Tiles do
				if not BaseConfig.BuildingAt(layout, candidate) then
					placeAt = candidate
					break
				end
			end
		end
		if not placeAt then
			return false, "no free tile"
		end
	end

	-- More salvage capacity or a faster yard applies from now on: empty the yard first so the
	-- new rate is never paid backwards over time already spent.
	if building.Id == "SalvageYard" or building.Id == "Storehouse" then
		self:Claim(player, now, true)
	end

	local firstEver = self:_nothingBuilt(stored)
	local storedLevel = stored[building.Id] or 0
	local balance, reason = self._persistence:SpendOnUpgrade(player, building.Id, storedLevel + 1, cost)
	if not balance then
		return false, reason
	end

	self._persistence:Update(player, function(p)
		p.Base.Layout[building.Id] = placeAt
		-- The yard starts filling the moment it is built.
		if building.Id == "SalvageYard" and (p.Base.LastClaimAt or 0) <= 0 then
			p.Base.LastClaimAt = self._wallClock()
		end
	end)
	if firstEver and self._onFirstBuild then
		self._onFirstBuild(player)
	end
	self:_changed(player, now)
	return true, { Id = building.Id, Level = nextLevel, Cost = cost, Tile = placeAt, Balance = balance }
end

-- Whether no building has been bought yet (the Hearth's free level does not count).
function BaseService:_nothingBuilt(stored)
	for _, building in BaseConfig.Buildings do
		if (stored[building.Id] or 0) > 0 then
			return false
		end
	end
	return true
end

-- Moves a built building to another tile, swapping with whatever stands there. Free.
function BaseService:Move(player, buildingId, tile, now)
	local refused = self:_guard(player)
	if refused then
		return false, refused
	end
	if type(buildingId) ~= "string" or not BaseConfig.Get(buildingId) then
		return false, "unknown building"
	end
	if not BaseConfig.ValidTile(tile) then
		return false, "invalid tile"
	end
	local layout = self:EnsureLayout(player)
	local from = layout[buildingId]
	if not from then
		return false, "not built"
	end
	if from == tile then
		return true, { Id = buildingId, Tile = tile }
	end
	local occupant = BaseConfig.BuildingAt(layout, tile)
	self._persistence:Update(player, function(p)
		p.Base.Layout[buildingId] = tile
		if occupant then
			p.Base.Layout[occupant] = from
		end
	end)
	self:_changed(player, now)
	return true, { Id = buildingId, Tile = tile, Swapped = occupant }
end

-- Empties the Salvage Yard. The payout key is the previous claim time, so two servers claiming
-- the same stretch of time pay it once. Returns true and { Coins }, or false and a reason.
-- quiet: called on the player's behalf (before a yard upgrade); nothing to claim is not an error.
function BaseService:Claim(player, now, quiet)
	if not quiet then
		local refused = self:_guard(player)
		if refused then
			return false, refused
		end
	end
	local profile = self:_profile(player)
	if not profile then
		return false, "profile not loaded"
	end
	local wall = self._wallClock()
	local stored = self._persistence:GetMetaLevels(player)
	local last = profile.Base.LastClaimAt
	local coins = BaseConfig.OfflineCoins(stored, last, wall, self._extraCapHours(player))
	if coins < BaseConfig.Offline.MinClaim then
		return false, "nothing to claim"
	end
	local paid, _, _, _, _, reason = Payout.Grant(self._persistence, player, "offline:" .. tostring(last), coins, 0)
	if reason and reason ~= "already granted" then
		return false, reason
	end
	self._persistence:Update(player, function(p)
		p.Base.LastClaimAt = wall
	end)
	if not quiet then
		self:_changed(player, now)
	end
	return true, { Coins = paid }
end

local function resetCheers(profile, today)
	if profile.Base.Cheers.Day ~= today then
		profile.Base.Cheers = { Day = today, Given = {}, Received = 0 }
	end
end

-- A visitor cheers an owner's base: once a day per pair. The owner is paid for up to
-- MaxPaidCheers cheers a day and the visitor for up to MaxPaidVisits. Both must be on this
-- server with their profiles loaded. Returns true and { OwnerCoins, VisitorCoins }, or false and
-- a reason.
function BaseService:Cheer(visitor, owner, now)
	if not FeatureFlags.BaseBuilding then
		return false, "base disabled"
	end
	if visitor == owner or not owner or not visitor then
		return false, "own base"
	end
	local visitorProfile, ownerProfile = self:_profile(visitor), self:_profile(owner)
	if not visitorProfile or not ownerProfile then
		return false, "profile not loaded"
	end
	local today = MetaConfig.DayOf(self._wallClock())
	local visits = BaseConfig.Visits
	local ownerKey = tostring(owner.UserId)
	if visitorProfile.Base.Cheers.Day == today and visitorProfile.Base.Cheers.Given[ownerKey] then
		return false, "already cheered"
	end

	local paidVisits = 0
	if visitorProfile.Base.Cheers.Day == today then
		for _ in visitorProfile.Base.Cheers.Given do
			paidVisits += 1
		end
	end
	local visitorCoins = 0
	if paidVisits < visits.MaxPaidVisits then
		visitorCoins = select(1, Payout.Grant(self._persistence, visitor,
			string.format("visit:%d:%s", today, ownerKey), visits.VisitCoins, 0))
	end
	local received = ownerProfile.Base.Cheers.Day == today and ownerProfile.Base.Cheers.Received or 0
	local ownerCoins = 0
	if received < visits.MaxPaidCheers then
		ownerCoins = select(1, Payout.Grant(self._persistence, owner,
			string.format("cheer:%d:%d", today, visitor.UserId), visits.CheerCoins, 0))
	end

	self._persistence:Update(visitor, function(p)
		resetCheers(p, today)
		p.Base.Cheers.Given[ownerKey] = true
	end)
	self._persistence:Update(owner, function(p)
		resetCheers(p, today)
		p.Base.Cheers.Received += 1
	end)
	self:_changed(visitor, now)
	self:_changed(owner, now)
	return true, { OwnerCoins = ownerCoins, VisitorCoins = visitorCoins }
end

return BaseService
