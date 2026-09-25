-- Builds the end-of-run summary shown on the results screen. Pure data assembly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardConfig = require(ReplicatedStorage:WaitForChild("RewardConfig"))
local RewardService = require(script.Parent.RewardService)
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))

local RunSummary = {}

local function upgradeList(playerState)
	local taken = {}
	for _, cardId in playerState.upgradeOrder do
		local card = UpgradeConfig.Get(cardId)
		if UpgradeConfig.IsMinor(card) then
			continue -- Surge perks are counted as the Surge level, not listed
		end
		table.insert(taken, {
			Id = cardId,
			Title = card and card.Title or cardId,
			Category = card and card.Category or "Projectile",
		})
	end
	return taken
end

function RunSummary.ForPlayer(playerState, context)
	local reward = RewardService.Compute(playerState, context.outcome, context.eliteCleared, context.rewardMultiplier,
		context.extractionBonus)
	local haul = math.floor(playerState.coins or 0)
	return {
		RunId = context.runId,
		Outcome = context.outcome,
		DurationSeconds = math.floor(context.duration * 10) / 10,
		RoomsCleared = playerState.roomsCleared,
		JoinedAtRoom = playerState.joinedAtRoom,
		RoomCount = context.roomCount,
		EnemiesDefeated = playerState.kills,
		BestChain = playerState.bestChain,
		ShotsFired = playerState.shotsFired,
		DamageTaken = math.floor(playerState.damageTaken),
		Survived = playerState.alive,
		Upgrades = upgradeList(playerState),
		Reward = reward,
		-- The haul at risk: coins picked up, and how many of them were lost with the run.
		Haul = haul,
		HaulLost = haul - RewardService.HaulKept(playerState, context.outcome),
		Banked = context.banked == true,
		CurrencyName = RewardConfig.CurrencyName,
		XpEarned = RewardService.Experience(playerState, context.outcome, context.eliteCleared, context.rewardMultiplier),
		Heat = context.heat or 0,
		Rig = playerState.meta and playerState.meta.rig or nil,
		ChampionsDefeated = playerState.championKills or 0,
		BossesDefeated = playerState.bossKills or 0,
		Crits = playerState.crits or 0,
		RevivesGiven = playerState.revivesGiven or 0,
		BestCombo = playerState.bestCombo or 0,
		SurgeLevel = math.max((playerState.surgeLevel or 1) - 1, 0),
		TrickShots = playerState.trickShots or 0,
		-- archetype id -> kills, for the Codex.
		KillsByArchetype = table.clone(playerState.killsByArchetype or {}),
		-- Filled in once the payout lands (MatchFlow): level-up coins and the level progress.
		LevelReward = 0,
	}
end

return RunSummary
