-- Persistence schema and policy. Only data that genuinely needs to survive a session lives here.
local PlayerDataConfig = {}

PlayerDataConfig.SchemaVersion = 2

PlayerDataConfig.StoreName = "PlayerProfiles"
-- Development builds write to a completely separate namespace, so test data can never touch
-- live player data. GameBootstrap picks the scope from DebugConfig.
PlayerDataConfig.DevelopmentScope = "dev_v1"
PlayerDataConfig.ProductionScope = "live_v1"
PlayerDataConfig.KeyPrefix = "profile_"

PlayerDataConfig.MaxRetries = 5
PlayerDataConfig.RetryBaseDelay = 0.5
PlayerDataConfig.RetryMaxDelay = 8
PlayerDataConfig.AutosaveInterval = 120
-- A run can only be paid once; this many recent run keys are remembered per profile.
PlayerDataConfig.RunLedgerSize = 25

-- Every field a profile may contain, with its safe default. Load fills in anything missing,
-- so adding a field here is always backwards compatible.
function PlayerDataConfig.DefaultProfile()
	return {
		SchemaVersion = PlayerDataConfig.SchemaVersion,
		Currency = { Salvage = 0 },
		Unlocks = {},
		Flags = { OnboardingSeen = false },
		Stats = {
			RunsStarted = 0,
			RunsExtracted = 0,
			EnemiesDefeated = 0,
			BestChain = 0,
			BestRoomsCleared = 0,
		},
		GrantedRuns = {},
		LastSaved = 0,
	}
end

-- Ordered migration steps, applied in sequence from the profile's stored version.
PlayerDataConfig.Migrations = {
	-- v1 -> v2: run ledger and per-profile stats were introduced.
	[1] = function(profile)
		profile.GrantedRuns = profile.GrantedRuns or {}
		profile.Stats = profile.Stats or {
			RunsStarted = 0,
			RunsExtracted = 0,
			EnemiesDefeated = 0,
			BestChain = 0,
			BestRoomsCleared = 0,
		}
		return profile
	end,
}

return PlayerDataConfig
