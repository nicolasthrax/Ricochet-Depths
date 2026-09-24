-- Achievements: long goals that pay once each, and the Codex of every card and enemy a player
-- has found. Progress is read straight from the saved profile (lifetime Stats and Codex), so the
-- client can draw the Journal from its ProfileSync while the server re-checks every claim.
-- IDs are saved in profiles, so they never change.
local EnemyConfig = require(script.Parent:WaitForChild("EnemyConfig"))
local RigConfig = require(script.Parent:WaitForChild("RigConfig"))
local UpgradeConfig = require(script.Parent:WaitForChild("UpgradeConfig"))

local AchievementConfig = {}

-- Source says where progress comes from:
--   "Stat"    a number in profile.Stats (Key)
--   "Rigs"    how many rigs have extracted (profile.Stats.RigsExtracted)
--   "Cards"   how many cards are in the Codex
--   "Enemies" how many kinds of enemy are in the Codex
AchievementConfig.Achievements = {
	{ Id = "Slayer", Title = "Slayer", Description = "Defeat 250 enemies.", Source = "Stat", Key = "EnemiesDefeated", Target = 250, Coins = 200, Xp = 150 },
	{ Id = "Exterminator", Title = "Exterminator", Description = "Defeat 2,500 enemies.", Source = "Stat", Key = "EnemiesDefeated", Target = 2500, Coins = 800, Xp = 600 },
	{ Id = "OutAlive", Title = "Out Alive", Description = "Extract from the depths.", Source = "Stat", Key = "RunsExtracted", Target = 1, Coins = 150, Xp = 100 },
	{ Id = "Veteran", Title = "Veteran Diver", Description = "Extract 10 times.", Source = "Stat", Key = "RunsExtracted", Target = 10, Coins = 600, Xp = 400 },
	{ Id = "Geometry", Title = "Geometry Wizard", Description = "Land a 10-contact ricochet kill.", Source = "Stat", Key = "BestChain", Target = 10, Coins = 400, Xp = 300 },
	{ Id = "ChampionHunter", Title = "Champion Hunter", Description = "Defeat 25 champions.", Source = "Stat", Key = "ChampionsDefeated", Target = 25, Coins = 400, Xp = 300 },
	{ Id = "Wardenbreaker", Title = "Wardenbreaker", Description = "Defeat the Warden Prime 3 times.", Source = "Stat", Key = "BossesDefeated", Target = 3, Coins = 500, Xp = 400 },
	{ Id = "FieldMedic", Title = "Field Medic", Description = "Revive teammates 10 times.", Source = "Stat", Key = "Revives", Target = 10, Coins = 400, Xp = 300 },
	{ Id = "PactBreaker", Title = "Pact Breaker", Description = "Extract at Heat 4 or higher.", Source = "Stat", Key = "BestHeat", Target = 4, Coins = 500, Xp = 400 },
	{ Id = "IntoTheAbyss", Title = "Into the Abyss", Description = "Extract at Heat 10 or higher.", Source = "Stat", Key = "BestHeat", Target = 10, Coins = 1500, Xp = 1000 },
	{ Id = "Versatile", Title = "Versatile", Description = "Extract with 3 different rigs.", Source = "Rigs", Target = 3, Coins = 600, Xp = 400 },
	{ Id = "Archivist", Title = "Archivist", Description = "Take every upgrade card at least once.", Source = "Cards", Target = #UpgradeConfig.Cards, Coins = 1000, Xp = 800 },
	{ Id = "Naturalist", Title = "Naturalist", Description = "Defeat every kind of enemy.", Source = "Enemies", Target = 0, Coins = 600, Xp = 500 },
}

-- Every enemy the Codex can hold, in a stable order.
AchievementConfig.EnemyIds = {}
for archetypeId in EnemyConfig.Archetypes do
	table.insert(AchievementConfig.EnemyIds, archetypeId)
end
table.sort(AchievementConfig.EnemyIds)

local byId = {}
for _, achievement in AchievementConfig.Achievements do
	assert(byId[achievement.Id] == nil, "duplicate achievement id: " .. achievement.Id)
	byId[achievement.Id] = achievement
	if achievement.Source == "Enemies" then
		achievement.Target = #AchievementConfig.EnemyIds
	end
end

function AchievementConfig.Get(achievementId)
	return type(achievementId) == "string" and byId[achievementId] or nil
end

-- Current progress toward `achievement` for a profile (the saved profile or the public copy).
function AchievementConfig.Progress(achievement, profile)
	if type(profile) ~= "table" then
		return 0
	end
	local stats = type(profile.Stats) == "table" and profile.Stats or {}
	local codex = type(profile.Codex) == "table" and profile.Codex or {}
	if achievement.Source == "Stat" then
		return math.max(math.floor(tonumber(stats[achievement.Key]) or 0), 0)
	elseif achievement.Source == "Rigs" then
		local count = 0
		for rigId, extracted in type(stats.RigsExtracted) == "table" and stats.RigsExtracted or {} do
			if extracted and RigConfig.Get(rigId) then
				count += 1
			end
		end
		return count
	elseif achievement.Source == "Cards" then
		local count = 0
		for cardId, seen in type(codex.Cards) == "table" and codex.Cards or {} do
			if seen and UpgradeConfig.Get(cardId) then
				count += 1
			end
		end
		return count
	elseif achievement.Source == "Enemies" then
		local count = 0
		for archetypeId, kills in type(codex.Enemies) == "table" and codex.Enemies or {} do
			if (tonumber(kills) or 0) > 0 and EnemyConfig.Get(archetypeId) then
				count += 1
			end
		end
		return count
	end
	return 0
end

-- Every achievement as the Journal shows it.
function AchievementConfig.Describe(profile)
	local claimed = type(profile) == "table" and type(profile.Achievements) == "table" and profile.Achievements or {}
	local list = {}
	for _, achievement in AchievementConfig.Achievements do
		local progress = AchievementConfig.Progress(achievement, profile)
		table.insert(list, {
			Id = achievement.Id,
			Title = achievement.Title,
			Description = achievement.Description,
			Target = achievement.Target,
			Progress = math.min(progress, achievement.Target),
			Coins = achievement.Coins,
			Xp = achievement.Xp,
			Complete = progress >= achievement.Target,
			Claimed = claimed[achievement.Id] == true,
		})
	end
	return list
end

return AchievementConfig
