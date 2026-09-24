-- Daily login rewards, daily quests, promo codes and badges. Server-only and authoritative:
-- the client can only ask to claim or redeem, and every payout goes through Payout.Grant, whose
-- ledger key makes a repeated request pay nothing. The claim markers (Daily, Quests,
-- RedeemedCodes) are ordinary profile fields and are checked before any grant is attempted.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local Payout = require(script.Parent.Payout)
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

local MetaService = {}
MetaService.__index = MetaService

-- options.wallClock() -> unix seconds (os.time by default; tests pin it).
-- options.awardBadge(player, badgeId) awards a Roblox badge; optional.
function MetaService.new(persistence, options)
	options = options or {}
	return setmetatable({
		_persistence = persistence,
		_wallClock = options.wallClock or os.time,
		_awardBadge = options.awardBadge,
		_badgesAwarded = {}, -- player -> { [badgeKey] = true } for this server session
	}, MetaService)
end

function MetaService:_profile(player)
	local session = self._persistence:GetSession(player)
	if not session or not session.loaded or session.failed then
		return nil
	end
	return session.profile
end

function MetaService:_today()
	return MetaConfig.DayOf(self._wallClock())
end

-- Makes sure the profile's quests are today's, redrawing them when the day has changed.
-- Returns the day's quest ids.
function MetaService:_ensureQuests(player, profile)
	local today = self:_today()
	if profile.Quests.Day ~= today then
		self._persistence:Update(player, function(stored)
			stored.Quests = { Day = today, Progress = {}, Claimed = {} }
		end)
	end
	return MetaConfig.QuestsFor(today, player.UserId)
end

-- What the client shows: the daily streak and today's quests. nil while the profile is
-- unavailable (loading, or read-only).
function MetaService:GetState(player)
	local profile = self:_profile(player)
	if not profile then
		return nil
	end
	local now = self._wallClock()
	local today = MetaConfig.DayOf(now)
	local daily = profile.Daily
	local canClaim = daily.LastClaimDay ~= today
	-- While a claim is waiting, show the streak it would continue (0 once a day was missed) and
	-- the reward it would pay; after claiming, the streak and reward just earned.
	local streak, dayIndex, _
	if canClaim then
		streak = daily.LastClaimDay == today - 1 and daily.Streak or 0
		_, dayIndex = MetaConfig.DailyRewardFor(streak + 1)
	else
		streak = daily.Streak
		_, dayIndex = MetaConfig.DailyRewardFor(streak)
	end

	local quests = {}
	for _, questId in self:_ensureQuests(player, profile) do
		local quest = MetaConfig.QuestById[questId]
		local progress = math.min(profile.Quests.Progress[questId] or 0, quest.Target)
		table.insert(quests, {
			Id = quest.Id,
			Title = quest.Title,
			Target = quest.Target,
			Progress = progress,
			Coins = quest.Coins,
			Xp = quest.Xp,
			Claimed = profile.Quests.Claimed[questId] == true,
			Complete = progress >= quest.Target,
		})
	end

	return {
		Daily = {
			CanClaim = canClaim,
			Streak = streak,
			DayIndex = dayIndex, -- 1..7: which reward is next (or was just claimed)
		},
		Quests = quests,
		ResetsIn = MetaConfig.SecondsUntilReset(now),
	}
end

-- Whether anything is waiting to be claimed, for the menu's notification dot.
function MetaService:HasClaimable(player)
	local state = self:GetState(player)
	if not state then
		return false, false
	end
	local questReady = false
	for _, quest in state.Quests do
		if quest.Complete and not quest.Claimed then
			questReady = true
		end
	end
	return state.Daily.CanClaim, questReady
end

-- Returns { Coins, Xp, LevelCoins, Streak } or nil and a reason.
function MetaService:ClaimDaily(player)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	local today = self:_today()
	local daily = profile.Daily
	if daily.LastClaimDay == today then
		return nil, "already claimed"
	end
	local streak = daily.LastClaimDay == today - 1 and daily.Streak + 1 or 1
	local reward = MetaConfig.DailyRewardFor(streak)
	local coins, xp, levelCoins, _, _, reason =
		Payout.Grant(self._persistence, player, "daily:" .. today, reward.Coins or 0, reward.Xp or 0)
	if reason and reason ~= "already granted" then
		return nil, reason
	end
	self._persistence:Update(player, function(stored)
		stored.Daily = { LastClaimDay = today, Streak = streak }
	end)
	return { Coins = coins, Xp = xp, LevelCoins = levelCoins, Streak = streak }
end

-- Returns { Coins, Xp, LevelCoins, Title } or nil and a reason.
function MetaService:ClaimQuest(player, questId)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	if type(questId) ~= "string" or not table.find(self:_ensureQuests(player, profile), questId) then
		return nil, "unknown quest"
	end
	local quest = MetaConfig.QuestById[questId]
	if profile.Quests.Claimed[questId] then
		return nil, "already claimed"
	end
	if (profile.Quests.Progress[questId] or 0) < quest.Target then
		return nil, "not complete"
	end
	local key = string.format("quest:%d:%s", profile.Quests.Day, questId)
	local coins, xp, levelCoins, _, _, reason = Payout.Grant(self._persistence, player, key, quest.Coins, quest.Xp)
	if reason and reason ~= "already granted" then
		return nil, reason
	end
	self._persistence:Update(player, function(stored)
		stored.Quests.Claimed[questId] = true
	end)
	return { Coins = coins, Xp = xp, LevelCoins = levelCoins, Title = quest.Title }
end

-- Returns { Coins, Xp, LevelCoins, Code } or nil and a reason.
function MetaService:RedeemCode(player, text)
	local profile = self:_profile(player)
	if not profile then
		return nil, "profile not loaded"
	end
	local code = MetaConfig.NormaliseCode(text)
	local entry = code and MetaConfig.Codes[code]
	if not entry then
		return nil, "invalid code"
	end
	if entry.Expires and self._wallClock() > entry.Expires then
		return nil, "expired"
	end
	if profile.RedeemedCodes[code] then
		return nil, "already redeemed"
	end
	local coins, xp, levelCoins, _, _, reason = Payout.Grant(self._persistence, player, "code:" .. code, entry.Coins, entry.Xp)
	if reason and reason ~= "already granted" then
		return nil, reason
	end
	self._persistence:Update(player, function(stored)
		stored.RedeemedCodes[code] = true
	end)
	if reason == "already granted" then
		return nil, "already redeemed"
	end
	return { Coins = coins, Xp = xp, LevelCoins = levelCoins, Code = code }
end

local QUEST_STATS = {
	Kills = function(summary)
		return summary.EnemiesDefeated or 0
	end,
	Rooms = function(summary)
		return summary.RoomsCleared or 0
	end,
	Runs = function()
		return 1
	end,
	Extractions = function(summary)
		return summary.Outcome == "Extracted" and 1 or 0
	end,
	Coins = function(summary)
		return summary.Reward or 0
	end,
}

-- A finished run: advance today's quests and award any badges it earned. Returns the titles
-- of quests this run completed, so the player can be told.
function MetaService:OnRunEnd(player, summary)
	local profile = self:_profile(player)
	if not profile or type(summary) ~= "table" then
		return {}
	end
	local completed = {}
	local questIds = self:_ensureQuests(player, profile)
	self._persistence:Update(player, function(stored)
		for _, questId in questIds do
			local quest = MetaConfig.QuestById[questId]
			local before = stored.Quests.Progress[questId] or 0
			local after
			if quest.Stat == "BestChain" then
				after = math.max(before, tonumber(summary.BestChain) or 0)
			else
				after = before + math.max(tonumber(QUEST_STATS[quest.Stat](summary)) or 0, 0)
			end
			stored.Quests.Progress[questId] = after
			if before < quest.Target and after >= quest.Target then
				table.insert(completed, quest.Title)
			end
		end
	end)

	local level = ProgressionConfig.LevelFor(Payout.XpOf(self._persistence, player))
	for _, badgeKey in MetaConfig.BadgesForRun(summary, level) do
		self:AwardBadge(player, badgeKey)
	end
	return completed
end

-- Awards a badge once per server session; badges with no id yet are skipped.
function MetaService:AwardBadge(player, badgeKey)
	local badge = MetaConfig.Badges[badgeKey]
	if not badge or badge.Id <= 0 or not self._awardBadge then
		return false
	end
	local awarded = self._badgesAwarded[player]
	if not awarded then
		awarded = {}
		self._badgesAwarded[player] = awarded
	end
	if awarded[badgeKey] then
		return false
	end
	awarded[badgeKey] = true
	self._awardBadge(player, badge.Id)
	return true
end

function MetaService:ClearPlayer(player)
	self._badgesAwarded[player] = nil
end

return MetaService
