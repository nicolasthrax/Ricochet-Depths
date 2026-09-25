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

-- The share of the coins collected an outcome keeps. Extracting keeps the whole haul, and so does
-- an aborted run (the server failed it, not the player); anything else keeps DefeatHaulShare.
function RewardService.HaulShare(outcome)
	if outcome == "Extracted" or outcome == "Aborted" then
		return 1
	end
	return RewardConfig.DefeatHaulShare
end

-- The coins of a haul an outcome keeps, before multipliers.
function RewardService.HaulKept(playerState, outcome)
	return math.floor((playerState.coins or 0) * RewardService.HaulShare(outcome))
end

-- Coins kept, plus the clear bonus, times the player's multipliers (buildings and cards via
-- RewardMultiplier, party, premium and the daily modifier via CoinMultiplier). Only "Extracted"
-- earns the whole bonus and keeps the whole haul. heatMultiplier is the Depth Pact's reward
-- multiplier (1 at Heat 0). extractionBonus replaces ExtractionBonus for a run banked early.
function RewardService.Compute(playerState, outcome, eliteCleared, heatMultiplier, extractionBonus)
	local bonus = playerState.roomsCleared * RewardConfig.PerRoomCleared
	if eliteCleared then
		bonus += RewardConfig.EliteBonus
	end
	if outcome == "Extracted" then
		bonus += extractionBonus or RewardConfig.ExtractionBonus
	else
		bonus = math.floor(bonus * RewardConfig.DefeatMultiplier)
	end
	local kept = RewardService.HaulKept(playerState, outcome)
	return RewardService.Multiply(playerState, (kept + bonus) * (heatMultiplier or 1))
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
