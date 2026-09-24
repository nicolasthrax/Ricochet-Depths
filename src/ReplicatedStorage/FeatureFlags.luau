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

-- Deferred until the vertical slice has been playtested.
FeatureFlags.CosmeticStore = false
FeatureFlags.BaseBuilding = false
FeatureFlags.Matchmaking = false
FeatureFlags.SecondBoss = false


function FeatureFlags.IsEnabled(name)
	return FeatureFlags[name] == true
end

return FeatureFlags
