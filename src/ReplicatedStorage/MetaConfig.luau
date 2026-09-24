-- The reasons to come back: a daily login streak, three daily quests, promo codes and badges.
-- Pure data plus a few pure helpers; MetaService (server) is the only thing that pays out, and
-- every payout goes through the profile's idempotent grant ledger.
local MetaConfig = {}

-- One "day" is a UTC calendar day. Everything daily resets at 00:00 UTC.
MetaConfig.SecondsPerDay = 86400

function MetaConfig.DayOf(unixTime)
	return math.floor((tonumber(unixTime) or 0) / MetaConfig.SecondsPerDay)
end

function MetaConfig.SecondsUntilReset(unixTime)
	local now = tonumber(unixTime) or 0
	return (MetaConfig.DayOf(now) + 1) * MetaConfig.SecondsPerDay - now
end

--// Daily login -----------------------------------------------------------------
-- Claim once per day. Claiming on consecutive days grows the streak; missing a day starts it
-- again from day 1. The seven rewards cycle, so a long streak keeps paying the week's rewards.
MetaConfig.DailyRewards = {
	{ Coins = 50 },
	{ Coins = 75 },
	{ Coins = 100, Xp = 50 },
	{ Coins = 150 },
	{ Coins = 200, Xp = 100 },
	{ Coins = 250 },
	{ Coins = 500, Xp = 250 },
}

-- The reward for the `streak`th consecutive day (1-based).
function MetaConfig.DailyRewardFor(streak)
	local count = #MetaConfig.DailyRewards
	local index = ((math.max(math.floor(tonumber(streak) or 1), 1) - 1) % count) + 1
	return MetaConfig.DailyRewards[index], index
end

--// Daily quests ----------------------------------------------------------------
-- Each day every player gets QuestsPerDay of these, drawn by a seed of the day and their user
-- id, so the draw is the same on every server. Stat names are what OnRunEnd counts:
--   Kills, Rooms, Runs, Extractions, Coins add up across runs; BestChain keeps the best.
MetaConfig.QuestsPerDay = 3
MetaConfig.Quests = {
	{ Id = "Kills40", Title = "Defeat 40 enemies", Stat = "Kills", Target = 40, Coins = 100, Xp = 80 },
	{ Id = "Kills100", Title = "Defeat 100 enemies", Stat = "Kills", Target = 100, Coins = 220, Xp = 160 },
	{ Id = "Rooms6", Title = "Clear 6 rooms", Stat = "Rooms", Target = 6, Coins = 100, Xp = 80 },
	{ Id = "Rooms15", Title = "Clear 15 rooms", Stat = "Rooms", Target = 15, Coins = 220, Xp = 160 },
	{ Id = "Runs3", Title = "Play 3 descents", Stat = "Runs", Target = 3, Coins = 90, Xp = 70 },
	{ Id = "Extract1", Title = "Extract from the depths", Stat = "Extractions", Target = 1, Coins = 250, Xp = 200 },
	{ Id = "Chain4", Title = "Land a 4-contact ricochet kill", Stat = "BestChain", Target = 4, Coins = 120, Xp = 90 },
	{ Id = "Chain7", Title = "Land a 7-contact ricochet kill", Stat = "BestChain", Target = 7, Coins = 260, Xp = 180 },
	{ Id = "Coins250", Title = "Earn 250 coins in runs", Stat = "Coins", Target = 250, Coins = 120, Xp = 90 },
}

MetaConfig.QuestById = {}
for _, quest in MetaConfig.Quests do
	MetaConfig.QuestById[quest.Id] = quest
end

-- The day's quest ids for one player: QuestsPerDay distinct quests, never two with the same
-- stat, the same on every server.
function MetaConfig.QuestsFor(day, userId)
	local random = Random.new((math.floor(tonumber(day) or 0) * 7919 + math.floor(tonumber(userId) or 0)) % 2147483647)
	local pool = table.clone(MetaConfig.Quests)
	local picked, usedStats = {}, {}
	while #picked < MetaConfig.QuestsPerDay and #pool > 0 do
		local index = random:NextInteger(1, #pool)
		local quest = table.remove(pool, index)
		if not usedStats[quest.Stat] then
			usedStats[quest.Stat] = true
			table.insert(picked, quest.Id)
		end
	end
	return picked
end

--// Promo codes -----------------------------------------------------------------
-- Each code pays once per account. Expires is an optional unix time after which it stops
-- working. Add new codes here and republish; post them on your group wall and socials.
MetaConfig.Codes = {
	RICOCHET = { Coins = 150 },
	DEPTHS = { Coins = 100, Xp = 100 },
	LAUNCH = { Coins = 300, Xp = 150 },
	BANKSHOT = { Coins = 200 },
}

-- Upper case, letters and digits only; nil for anything that cannot be a code.
function MetaConfig.NormaliseCode(text)
	if type(text) ~= "string" or #text == 0 or #text > 40 then
		return nil
	end
	local code = string.upper((string.gsub(text, "[^%w]", "")))
	if #code == 0 or #code > 24 then
		return nil
	end
	return code
end

--// Badges ----------------------------------------------------------------------
-- Create each badge on the Creator Hub (Experience > Engagement > Badges) and paste its id.
-- A badge left at 0 is never awarded, so this ships safely before the ids exist.
MetaConfig.Badges = {
	Welcome = { Id = 0, Title = "Welcome to the Depths" },
	FirstDescent = { Id = 0, Title = "First Descent" },
	FirstExtraction = { Id = 0, Title = "Extracted" },
	Chain8 = { Id = 0, Title = "Bank Shot Artist" },
	Level10 = { Id = 0, Title = "Level 10" },
	Level25 = { Id = 0, Title = "Level 25" },
	Level50 = { Id = 0, Title = "Level 50" },
}

-- Which badges a finished run (and the level after it) earns.
function MetaConfig.BadgesForRun(summary, level)
	local earned = { "FirstDescent" }
	if type(summary) == "table" then
		if summary.Outcome == "Extracted" then
			table.insert(earned, "FirstExtraction")
		end
		if (tonumber(summary.BestChain) or 0) >= 8 then
			table.insert(earned, "Chain8")
		end
	end
	for _, threshold in { 10, 25, 50 } do
		if (tonumber(level) or 1) >= threshold then
			table.insert(earned, "Level" .. threshold)
		end
	end
	return earned
end

--// Social ----------------------------------------------------------------------
-- Roblox Premium members earn this much extra coin multiplier on every run.
MetaConfig.PremiumCoinBonus = 0.1

return MetaConfig
