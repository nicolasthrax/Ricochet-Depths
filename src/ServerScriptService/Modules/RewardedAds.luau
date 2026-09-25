-- Rewarded video: after a run, a player may watch an ad for a fixed bonus (coins, maybe rerolls),
-- a few times a day. Fixed, never random, so there are no odds to disclose. Everything Roblox's
-- AdService does is wrapped in pcall: ads are unavailable in Studio, in many regions and for
-- many accounts, and none of that may break the results screen.
--
-- The bonus is paid here, through Payout.Grant under a per-day key, when the ad reports it was
-- watched to the end; the developer product Roblox ties the ad to is acknowledged without paying
-- (MonetizationService). Limits.AdDay / AdCount cap it per day.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))
local Payout = require(script.Parent.Payout)

local RewardedAds = {}
RewardedAds.__index = RewardedAds

-- options: ads (Roblox's AdService or a stand-in), persistence, config (MonetizationConfig.Ads),
-- wallClock (os.time), completed (the ShowAdResult value that means "watched to the end").
function RewardedAds.new(options)
	options = options or {}
	return setmetatable({
		_ads = options.ads,
		_persistence = options.persistence,
		_config = options.config or MonetizationConfig.Ads,
		_wallClock = options.wallClock or os.time,
		_completed = options.completed,
		_reward = nil,
	}, RewardedAds)
end

function RewardedAds:_today()
	return MetaConfig.DayOf(self._wallClock())
end

-- Ads watched today by this player, from the profile.
function RewardedAds:WatchedToday(player)
	local session = self._persistence:GetSession(player)
	local limits = session and session.profile and session.profile.Limits
	if not limits or limits.AdDay ~= self:_today() then
		return 0
	end
	return limits.AdCount or 0
end

-- Whether this player could watch one now: the flag, a configured reward, today's cap, a
-- writable profile, and Roblox saying an ad is available.
function RewardedAds:CanWatch(player)
	if not FeatureFlags.RewardedVideo or not self._ads then
		return false, "ads disabled"
	end
	if (tonumber(self._config.RewardProductId) or 0) <= 0 then
		return false, "ads disabled"
	end
	if not self._persistence:IsLoaded(player) then
		return false, "profile not loaded"
	end
	if self:WatchedToday(player) >= self._config.MaxPerDay then
		return false, "daily limit"
	end
	-- The result is read defensively: a bare enum item, or an object carrying one.
	local ok, available = pcall(function()
		local result = self._ads:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
		local isAvailable = Enum.AdAvailabilityResult.IsAvailable
		if result == isAvailable then
			return true
		end
		return result ~= nil and result.AdAvailabilityResult == isAvailable
	end)
	if not ok or not available then
		return false, "no ad"
	end
	return true
end

-- Shows the ad and, if it was watched to the end, pays the fixed bonus. Yields while the ad
-- plays: call it off the run loop. Returns the coins paid, or nil and a reason.
function RewardedAds:Watch(player)
	local can, reason = self:CanWatch(player)
	if not can then
		return nil, reason
	end
	local ok, result = pcall(function()
		self._reward = self._reward or self._ads:CreateAdRewardFromDevProductId(self._config.RewardProductId)
		return self._ads:ShowRewardedVideoAdAsync(player, self._reward)
	end)
	local completed = self._completed or Enum.ShowAdResult.ShowCompleted
	if not ok or result ~= completed then
		return nil, "not watched"
	end

	local day = self:_today()
	local count = self:WatchedToday(player) + 1
	self._persistence:Update(player, function(profile)
		profile.Limits.AdDay = day
		profile.Limits.AdCount = count
	end)
	local extras = (self._config.Rerolls or 0) > 0 and { Rerolls = self._config.Rerolls } or nil
	local coins, _, _, _, _, payReason = Payout.Grant(self._persistence, player, string.format("ad:%d:%d", day, count),
		self._config.Coins, 0, extras)
	if payReason and payReason ~= "already granted" then
		return nil, payReason
	end
	return coins
end

return RewardedAds
