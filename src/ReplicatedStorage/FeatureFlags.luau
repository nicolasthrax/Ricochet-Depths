-- Switches for work that is not finished. Anything false here must be inert: no UI entry point,
-- no remote handler, no data written. Flipping one on is the only step needed to enable it.
local FeatureFlags = {}

-- Shipped and on.
FeatureFlags.CoopRuns = true
FeatureFlags.Persistence = true
FeatureFlags.AccessibilitySettings = true
FeatureFlags.Telemetry = true
-- Permanent upgrades and cosmetic trails bought with salvage earned in runs. Salvage cannot be
-- bought, so this is not monetization; CosmeticStore below (a paid storefront) stays off.
FeatureFlags.SalvageShop = true
-- Client-side multi-part enemy models over the server hitboxes. Off shows the plain boxes.
FeatureFlags.EnemyModels = true

-- Robux game passes and coin packs (MonetizationConfig). Nothing is offered until the owner
-- fills in real ids, so this is safe on with the shipped config.
FeatureFlags.Monetization = true

-- Sound effects, using the Roblox client's built-in sounds until original audio is uploaded
-- (SoundConfig).
FeatureFlags.Audio = true
-- Daily login rewards, daily quests and promo codes (MetaConfig, MetaService).
FeatureFlags.DailyRewards = true
-- Global leaderboards on the lobby wall (LeaderboardService).
FeatureFlags.Leaderboards = true
-- Rigs, the Depth Pact and the Journal (achievements and Codex): LoadoutService and its views.
-- Off hides the lobby buttons and unbinds the remotes; runs then use the Striker at Heat 0.
FeatureFlags.Loadouts = true

-- 2.0, the redesign. Each can be switched off on its own and the game plays as 1.3 did there.
-- Orbs: a limited number of shots that drop where they stop and must be picked up.
FeatureFlags.Orbs = true
-- The Surge meter and its mid-fight perks.
FeatureFlags.Surge = true
-- Combo multipliers on coins and experience (the combo count is always shown).
FeatureFlags.Combo = true
-- The dash (and its cards).
FeatureFlags.Dash = true
-- Doors after every room, and room challenges.
FeatureFlags.Doors = true
FeatureFlags.Challenges = true
-- Random room events (Treasure Runners).
FeatureFlags.RoomEvents = true
-- The haul at risk: a lost run keeps only part of its coins, and a Surface Lift door after each
-- mini-boss lets the group bank the haul and leave.
FeatureFlags.Haul = true
-- Depth pressure: hunters arrive in a normal room that drags on.
FeatureFlags.Pressure = true

-- Deferred until the vertical slice has been playtested.
FeatureFlags.CosmeticStore = false
FeatureFlags.BaseBuilding = false
FeatureFlags.Matchmaking = false
FeatureFlags.SecondBoss = false


function FeatureFlags.IsEnabled(name)
	return FeatureFlags[name] == true
end

return FeatureFlags
