-- The lobby's pre-run choices and long goals: which rig to descend with, the Depth Pact, and
-- claiming achievements. Server-only and authoritative: the client names a rig, a pact or an
-- achievement id, and every rule (unlock level, first extraction, completion, one claim each)
-- is checked here against the saved profile. Payouts go through Payout.Grant like every other.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementConfig = require(ReplicatedStorage:WaitForChild("AchievementConfig"))
local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local PactConfig = require(ReplicatedStorage:WaitForChild("PactConfig"))
local Payout = require(script.Parent.Payout)
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local RigConfig = require(ReplicatedStorage:WaitForChild("RigConfig"))

local LoadoutService = {}
LoadoutService.__index = LoadoutService

-- options.canChange(player) -> bool: whether loadout changes are allowed now (the lobby only).
-- options.extraPresets(player) -> number: preset slots passes add.
-- options.ownsTrail(player, itemId) -> bool: whether a preset's trail may be worn.
-- options.wearTrail(player, itemId): equips a trail (ShopService's path).
function LoadoutService.new(persistence, options)
	options = options or {}
	return setmetatable({
		_persistence = persistence,
		_canChange = options.canChange or function()
			return true
		end,
		_extraPresets = options.extraPresets or function()
			return 0
		end,
		_ownsTrail = options.ownsTrail or function()
			return false
		end,
		_wearTrail = options.wearTrail,
	}, LoadoutService)
end

function LoadoutService:_profile(player)
	local session = self._persistence:GetSession(player)
	if not session or not session.loaded or session.failed then
		return nil
	end
	return session.profile
end

function LoadoutService:_level(player)
	return ProgressionConfig.LevelFor(Payout.XpOf(self._persistence, player))
end

-- Returns the rig now selected, or nil and a reason.
function LoadoutService:SelectRig(player, rigId)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	if not self._canChange(player) then
		return nil, "in a run"
	end
	local rig = RigConfig.Get(rigId)
	if not rig then
		return nil, "unknown rig"
	end
	if not RigConfig.IsUnlocked(rig, self:_level(player)) then
		return nil, "locked"
	end
	self._persistence:Update(player, function(stored)
		stored.SelectedRig = rig.Id
	end)
	return rig
end

-- Returns the sanitised pact now saved and its Heat, or nil and a reason.
function LoadoutService:SetPact(player, incoming)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	if not self._canChange(player) then
		return nil, "in a run"
	end
	local pact = PactConfig.Sanitise(incoming)
	if next(pact) ~= nil and not PactConfig.IsUnlocked(profile.Stats.RunsExtracted) then
		return nil, "locked"
	end
	self._persistence:Update(player, function(stored)
		stored.Pact = pact
	end)
	return pact, PactConfig.Heat(pact)
end

-- What a run starting now uses. Nothing locked ever leaks through: a rig that is no longer
-- unlocked falls back to the default, and a pact from before the unlock counts for nothing.
function LoadoutService:GetRig(player)
	local profile = self:_profile(player)
	return RigConfig.Resolve(profile and profile.SelectedRig, self:_level(player))
end

function LoadoutService:GetPact(player)
	local profile = self:_profile(player)
	if not profile or not PactConfig.IsUnlocked(profile.Stats.RunsExtracted) then
		return {}
	end
	return PactConfig.Sanitise(profile.Pact)
end

-- Returns { Coins, Xp, LevelCoins, Title } or nil and a reason.
function LoadoutService:ClaimAchievement(player, achievementId)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	local achievement = AchievementConfig.Get(achievementId)
	if not achievement then
		return nil, "unknown achievement"
	end
	if profile.Achievements[achievement.Id] then
		return nil, "already claimed"
	end
	if AchievementConfig.Progress(achievement, profile) < achievement.Target then
		return nil, "not complete"
	end
	local coins, xp, levelCoins, _, _, reason =
		Payout.Grant(self._persistence, player, "ach:" .. achievement.Id, achievement.Coins, achievement.Xp)
	if reason and reason ~= "already granted" then
		return nil, reason
	end
	self._persistence:Update(player, function(stored)
		stored.Achievements[achievement.Id] = true
	end)
	if reason == "already granted" then
		return nil, "already claimed"
	end
	return { Coins = coins, Xp = xp, LevelCoins = levelCoins, Title = achievement.Title }
end

-- How many preset slots this player has.
function LoadoutService:PresetSlots(player)
	local presets = MetaConfig.Presets
	return math.clamp(presets.FreeSlots + math.floor(tonumber(self._extraPresets(player)) or 0), 0, presets.MaxSlots)
end

-- A preset slot number from the client, or nil.
function LoadoutService:_slot(player, slot)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > self:PresetSlots(player) then
		return nil
	end
	return tostring(slot) -- stored under string keys: a DataStore table with holes is not an array
end

-- Saves the current rig, trail and Pact into a slot. Returns the preset, or nil and a reason.
function LoadoutService:SavePreset(player, slot)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	local key = self:_slot(player, slot)
	if not key then
		return nil, "no such slot"
	end
	local preset = { Rig = profile.SelectedRig, Trail = profile.EquippedTrail, Pact = table.clone(profile.Pact) }
	self._persistence:Update(player, function(stored)
		stored.Presets[key] = preset
	end)
	return preset
end

-- Puts a saved preset back on: its rig if still unlocked, its trail if still owned, its Pact if
-- unlocked. Returns the preset, or nil and a reason.
function LoadoutService:ApplyPreset(player, slot)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	if not self._canChange(player) then
		return nil, "in a run"
	end
	local key = self:_slot(player, slot)
	local preset = key and profile.Presets[key]
	if type(preset) ~= "table" then
		return nil, "empty slot"
	end
	if type(preset.Rig) == "string" then
		self:SelectRig(player, preset.Rig)
	end
	if type(preset.Trail) == "string" and (preset.Trail == "" or self._ownsTrail(player, preset.Trail)) and self._wearTrail then
		self._wearTrail(player, preset.Trail)
	end
	if type(preset.Pact) == "table" then
		self:SetPact(player, preset.Pact)
	end
	return preset
end

-- How many completed achievements are waiting to be claimed, for the menu's dot.
function LoadoutService:ClaimableCount(player)
	local profile = self:_profile(player)
	if not profile then
		return 0
	end
	local count = 0
	for _, entry in AchievementConfig.Describe(profile) do
		if entry.Complete and not entry.Claimed then
			count += 1
		end
	end
	return count
end

return LoadoutService
