-- One way to pay a player: coins and experience together, under one ledger key, plus the coins
-- for any level the experience crosses. Used by runs, daily rewards, quests and codes alike, so
-- every source of experience levels a player up the same way.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

local Payout = {}

-- Lifetime experience, for a persistence layer that tracks it (test doubles may not).
function Payout.XpOf(persistence, player)
	return persistence.GetXp and persistence:GetXp(player) or 0
end

-- Returns the coins credited (not counting level-up coins), the experience credited, the
-- level-up coins, the level before and the level after. Everything is 0 (and the levels equal)
-- when nothing was paid: the key was already paid, or the profile is read-only. The fifth
-- value on failure is the reason.
function Payout.Grant(persistence, player, key, coins, xp)
	coins = math.max(math.floor(tonumber(coins) or 0), 0)
	xp = math.max(math.floor(tonumber(xp) or 0), 0)
	local xpBefore = Payout.XpOf(persistence, player)
	local levelCoins, levelBefore, levelAfter = ProgressionConfig.RewardBetween(xpBefore, xpBefore + xp)
	if coins + levelCoins <= 0 and xp <= 0 then
		return 0, 0, 0, levelBefore, levelBefore, "nothing to pay"
	end
	local granted, reason, xpGranted = persistence:GrantReward(player, key, coins + levelCoins, xp)
	if reason then
		return 0, 0, 0, levelBefore, levelBefore, reason
	end
	return granted - levelCoins, xpGranted or xp, levelCoins, levelBefore, levelAfter
end

return Payout
