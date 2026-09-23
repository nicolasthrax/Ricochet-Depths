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

-- Deferred until the vertical slice has been playtested.
FeatureFlags.Monetization = false -- no game passes, products or premium currency exist in code
FeatureFlags.CosmeticStore = false
FeatureFlags.BaseBuilding = false
FeatureFlags.Matchmaking = false
FeatureFlags.SecondBoss = false
FeatureFlags.Audio = false -- sound hooks are stubbed but no assets are wired

function FeatureFlags.IsEnabled(name)
	return FeatureFlags[name] == true
end

return FeatureFlags
