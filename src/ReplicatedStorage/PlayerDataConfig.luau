-- Persistence schema and policy. Only data that genuinely needs to survive a session lives here.
local PlayerDataConfig = {}

PlayerDataConfig.SchemaVersion = 3

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
-- Writes one save chain may make for a single request, to catch changes that land mid-write.
PlayerDataConfig.MaxChainedWrites = 3
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
		Settings = PlayerDataConfig.DefaultSettings(),
		LastSaved = 0,
	}
end

-- Player-facing accessibility and comfort options, with the range each one is clamped to.
PlayerDataConfig.SettingSpecs = {
	ReducedFlash = { Kind = "boolean", Default = false },
	EffectIntensity = { Kind = "number", Default = 1, Min = 0, Max = 1 },
	ScreenShake = { Kind = "number", Default = 1, Min = 0, Max = 1 },
}

function PlayerDataConfig.DefaultSettings()
	local settings = {}
	for name, spec in PlayerDataConfig.SettingSpecs do
		settings[name] = spec.Default
	end
	return settings
end

-- Returns a sanitised settings table. Anything unknown, mistyped or out of range is discarded
-- rather than trusted, since this arrives from the client.
function PlayerDataConfig.SanitiseSettings(incoming, current)
	local result = {}
	for name, spec in PlayerDataConfig.SettingSpecs do
		local fallback = (current and current[name] ~= nil) and current[name] or spec.Default
		local value = type(incoming) == "table" and incoming[name] or nil

		if spec.Kind == "boolean" then
			result[name] = type(value) == "boolean" and value or fallback
		elseif spec.Kind == "number" then
			if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
				result[name] = math.clamp(value, spec.Min, spec.Max)
			else
				result[name] = fallback
			end
		end
	end
	return result
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
	-- v2 -> v3: accessibility settings were introduced.
	[2] = function(profile)
		profile.Settings = PlayerDataConfig.SanitiseSettings(profile.Settings, nil)
		return profile
	end,
}

return PlayerDataConfig
