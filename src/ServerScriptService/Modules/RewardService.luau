-- Computes run payouts. Rewards are derived only from server-tracked counters; nothing the
-- client sends ever reaches this maths.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardConfig = require(ReplicatedStorage:WaitForChild("RewardConfig"))

local RewardService = {}
RewardService.__index = RewardService

function RewardService.new()
	return setmetatable({ _granted = {} }, RewardService)
end

-- Only "Extracted" pays in full; every other outcome (Defeated, TimedOut, Abandoned, Aborted)
-- pays the defeat fraction.
function RewardService.Compute(playerState, outcome, eliteCleared)
	local base = playerState.roomsCleared * RewardConfig.PerRoomCleared + playerState.kills * RewardConfig.PerKill
	if eliteCleared then
		base += RewardConfig.EliteBonus
	end
	if outcome == "Extracted" then
		base += RewardConfig.ExtractionBonus
	else
		base *= RewardConfig.DefeatMultiplier
	end

	local total = math.floor(base * (playerState.stats.RewardMultiplier or 1))
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
