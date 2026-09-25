-- Computes run payouts. Rewards are derived only from server-tracked counters; nothing the
-- client sends ever reaches this maths.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local RewardConfig = require(ReplicatedStorage:WaitForChild("RewardConfig"))

local RewardService = {}
RewardService.__index = RewardService

function RewardService.new()
	return setmetatable({ _granted = {} }, RewardService)
end

-- Whether an outcome got the group out alive: the Throne ("Extracted") or a Surface Lift
-- ("Surfaced").
function RewardService.GotOut(outcome)
	return outcome == "Extracted" or outcome == "Surfaced"
end

-- Whether an outcome loses part of an at-risk haul: a wipe, or a run out of time. A run that
-- collapsed or was abandoned is nobody's failure and keeps it.
function RewardService.LosesHaul(outcome)
	return outcome == "Defeated" or outcome == "TimedOut"
end

-- The haul multiplier for getting out after `zonesCleared` zone bosses (RewardConfig).
function RewardService.DepthMultiplier(zonesCleared)
	return 1 + RewardConfig.HaulDepthBonus * math.max((tonumber(zonesCleared) or 0) - 1, 0)
end

-- The coins a run's haul is worth for this outcome, before any multipliers. `haul` is nil
-- unless the haul is at risk, as { depthMultiplier }.
function RewardService.HaulValue(playerState, outcome, haul)
	local coins = playerState.coins or 0
	if not haul then
		return coins
	end
	if RewardService.GotOut(outcome) then
		return math.floor(coins * (haul.depthMultiplier or 1))
	elseif RewardService.LosesHaul(outcome) then
		return math.floor(coins * RewardConfig.DefeatCoinKeep)
	end
	return coins
end

-- Coins collected, plus the clear bonus, times the player's multipliers (Fortune and cards via
-- RewardMultiplier, the 2x Coins pass via CoinMultiplier). Only "Extracted" earns the whole
-- bonus; a Surface Lift keeps the clear bonus but not the extraction's; every other outcome
-- keeps a share of the bonus. heatMultiplier is the Depth Pact's reward multiplier (1 at Heat 0).
-- haul, when given, puts the collected coins at risk (see HaulValue).
function RewardService.Compute(playerState, outcome, eliteCleared, heatMultiplier, haul)
	local bonus = playerState.roomsCleared * RewardConfig.PerRoomCleared
	if eliteCleared then
		bonus += RewardConfig.EliteBonus
	end
	if outcome == "Extracted" then
		bonus += RewardConfig.ExtractionBonus
	elseif outcome ~= "Surfaced" then
		bonus = math.floor(bonus * RewardConfig.DefeatMultiplier)
	end
	local coins = RewardService.HaulValue(playerState, outcome, haul)
	return RewardService.Multiply(playerState, (coins + bonus) * (heatMultiplier or 1))
end

-- Experience for a run. Every outcome keeps what the kills and clears earned; only extracting
-- adds the extraction award. Coin multipliers never touch experience; the Pact's Heat does.
function RewardService.Experience(playerState, outcome, eliteCleared, heatMultiplier)
	local rates = ProgressionConfig.Xp
	local xp = (playerState.kills or 0) * rates.PerKill + (playerState.roomsCleared or 0) * rates.PerRoomCleared
		+ (playerState.championKills or 0) * CombatConfig.ChampionXp
		+ (playerState.comboXp or 0)
	if eliteCleared then
		xp += rates.EliteCleared
	end
	if outcome == "Extracted" then
		xp += rates.Extracted
	end
	return math.max(math.floor(xp * (heatMultiplier or 1)), 0)
end

-- `amount` after the player's multipliers, floored and capped.
function RewardService.Multiply(playerState, amount)
	local stats = playerState.stats
	local total = math.floor(amount * (stats.RewardMultiplier or 1) * (stats.CoinMultiplier or 1))
	return math.clamp(total, 0, RewardConfig.MaxPerRun)
end

-- Idempotency guard: a given run id can only ever pay a given player once, however many
-- completion events or reconnects fire.
function RewardService:Grant(runId, playerKey, amount)
	local ledgerKey = tostring(runId) .. "|" .. tostring(playerKey)
	if self._granted[ledgerKey] then
		return 0, "already granted"
	end
	self._granted[ledgerKey] = amount
	return amount
end

function RewardService:WasGranted(runId, playerKey)
	return self._granted[tostring(runId) .. "|" .. tostring(playerKey)] ~= nil
end

return RewardService
