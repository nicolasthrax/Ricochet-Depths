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

-- Coins collected, plus the clear bonus, times the player's multipliers (Fortune and cards via
-- RewardMultiplier, the 2x Coins pass via CoinMultiplier). Only "Extracted" earns the whole
-- bonus; every other outcome keeps the coins and a share of the bonus. heatMultiplier is the
-- Depth Pact's reward multiplier (1 at Heat 0).
function RewardService.Compute(playerState, outcome, eliteCleared, heatMultiplier)
	local bonus = playerState.roomsCleared * RewardConfig.PerRoomCleared
	if eliteCleared then
		bonus += RewardConfig.EliteBonus
	end
	if outcome == "Extracted" then
		bonus += RewardConfig.ExtractionBonus
	else
		bonus = math.floor(bonus * RewardConfig.DefeatMultiplier)
	end
	return RewardService.Multiply(playerState, ((playerState.coins or 0) + bonus) * (heatMultiplier or 1))
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
	local stats = playerState.stats or {}
	return math.max(math.floor(xp * (heatMultiplier or 1) * (stats.XpMultiplier or 1)), 0)
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
