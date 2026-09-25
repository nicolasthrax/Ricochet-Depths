-- Persistence schema and policy. Only data that genuinely needs to survive a session lives here.
local PlayerDataConfig = {}

PlayerDataConfig.SchemaVersion = 10

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

-- Shutdown. Roblox allows BindToClose handlers 30 seconds; saves share this budget, leaving a
-- 5-second cushion before the engine cuts the process off.
PlayerDataConfig.ShutdownBudget = 25
-- How often the shutdown handler checks whether every save has finished.
PlayerDataConfig.ShutdownPollInterval = 0.05
-- Roughly how long one UpdateAsync takes. A retry is not started unless its backoff plus this
-- much still fits inside the deadline; a write that cannot finish in time is not worth starting.
PlayerDataConfig.ExpectedWriteSeconds = 1
-- A run can only be paid once; this many recent runs are remembered per profile, both in memory
-- and in the stored copy. Pruning is strictly oldest-first by the wall-clock time of the grant.
-- At one run every six to eight minutes, 25 covers roughly the last three hours: far longer than
-- any reconnect or duplicate completion event could take to arrive.
PlayerDataConfig.RunLedgerSize = 25

-- Every balance a profile holds. Salvage is the coin balance (kept under its original name so
-- older balances carry over); Rerolls and ReviveTokens are consumables. All three are
-- store-owned: they change only through grants and spends applied inside the save transform.
PlayerDataConfig.Currencies = { "Salvage", "Rerolls", "ReviveTokens" }

-- The Armory's permanent stat upgrades (1.0-2.0). v9 moved earnable power into home-base
-- buildings, so the v8 -> v9 migration refunds every coin spent here. Ids and prices exactly as
-- they were sold; never edit.
PlayerDataConfig.LegacyArmoryCosts = {
	Vitality = { 80, 160, 260, 380, 520 },
	Stride = { 60, 140, 240 },
	Velocity = { 40, 55, 70, 90, 110, 135, 160, 190, 220, 250 },
	Mending = { 120, 240, 400, 600 },
	CoinMagnet = { 100, 220, 380 },
	Fortune = { 250, 500, 900 },
	-- Sold only by the 2.x haul build (its schema v9), never alongside the rest; see [9] below.
	Quiver = { 1500, 4000 },
}

-- Every field a profile may contain, with its safe default. Load fills in anything missing,
-- so adding a field here is always backwards compatible.
function PlayerDataConfig.DefaultProfile()
	return {
		SchemaVersion = PlayerDataConfig.SchemaVersion,
		Currency = { Salvage = 0, Rerolls = 0, ReviveTokens = 0 },
		Unlocks = {},
		-- OnboardingSeen: finished a run. FirstDescentDone: finished the first-60-seconds descent.
		-- Funnel: onboarding-funnel step id -> true once logged, so each is reported once ever.
		Flags = { OnboardingSeen = false, FirstDescentDone = false, Funnel = {} },
		Stats = {
			RunsStarted = 0,
			RunsExtracted = 0,
			EnemiesDefeated = 0,
			BestChain = 0,
			BestRoomsCleared = 0,
			CoinsEarned = 0,
			ChampionsDefeated = 0,
			BossesDefeated = 0,
			Revives = 0,
			-- The highest Depth Pact Heat this player has extracted at.
			BestHeat = 0,
			-- rig id -> true, for every rig this player has extracted with.
			RigsExtracted = {},
			-- 2.0: the longest combo ever, and kills that sent an orb straight home.
			BestCombo = 0,
			TrickShots = 0,
		},
		GrantedRuns = {},
		-- Permanent salvage-shop purchases: item id -> level owned. Store-owned, like currency:
		-- changed only by purchases applied inside the save transform.
		MetaUpgrades = {},
		-- The cosmetic trail shown on this player's shots; "" for none. A player preference.
		EquippedTrail = "",
		-- Lifetime experience; the level is derived from it (ProgressionConfig). Store-owned,
		-- like currency: it only ever grows, through run grants applied inside the save.
		Progression = { Xp = 0 },
		-- Daily login streak: the UTC day last claimed (MetaConfig.DayOf) and the streak it made.
		Daily = { LastClaimDay = 0, Streak = 0 },
		-- Today's quests: the day they were drawn for, and per quest id its progress and whether
		-- its reward was claimed. Redrawn when the day changes.
		Quests = { Day = 0, Progress = {}, Claimed = {} },
		-- Promo codes this account has redeemed: code -> true.
		RedeemedCodes = {},
		-- The rig this player descends with (RigConfig). A preference.
		SelectedRig = "Striker",
		-- Depth Pact condition id -> rank (PactConfig). A preference, sanitised on every write.
		Pact = {},
		-- Achievement id -> true once its reward has been claimed.
		Achievements = {},
		-- What this player has found: card id -> true, and enemy id -> lifetime kills.
		Codex = { Cards = {}, Enemies = {} },
		-- The home base (BaseConfig, BaseService). Building levels are store-owned and live in
		-- MetaUpgrades under each building's id; everything here is a preference or a timestamp.
		--   Layout: building id -> grid tile (1..BaseConfig.Tiles) it stands on.
		--   LastClaimAt: wall-clock time the offline workers were last emptied (0: never built).
		--   Theme / Sign: equipped cosmetic ids ("" for the defaults).
		--   Cheers: today's friend visits: the UTC day, who this player cheered, and how many
		--   cheers this player received (and was paid for).
		Base = {
			Layout = {},
			LastClaimAt = 0,
			Theme = "",
			Sign = "",
			Cheers = { Day = 0, Given = {}, Received = 0 },
		},
		-- Loadout presets: slot -> { Rig, Trail }. How many slots are usable depends on passes.
		Presets = {},
		-- Equipped identity cosmetics ("" for the defaults).
		Nameplate = "",
		-- Once-a-day allowances, by UTC day: the daily-modifier bonus, rewarded-video bonuses
		-- and friend-visit rewards (count per day).
		Limits = { ModifierDay = 0, AdDay = 0, AdCount = 0, VisitDay = 0, Visits = 0 },
		Settings = PlayerDataConfig.DefaultSettings(),
		LastSaved = 0,
	}
end

-- Player-facing accessibility and comfort options, with the range each one is clamped to.
PlayerDataConfig.SettingSpecs = {
	ReducedFlash = { Kind = "boolean", Default = false },
	EffectIntensity = { Kind = "number", Default = 1, Min = 0, Max = 1 },
	ScreenShake = { Kind = "number", Default = 1, Min = 0, Max = 1 },
	SfxVolume = { Kind = "number", Default = 1, Min = 0, Max = 1 },
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
	-- v3 -> v4: ledger entries become { Amount, At } records so pruning can go by time instead of
	-- by key. Migrated runs have no known time, so they get At = 0 and are the first to be pruned,
	-- which is correct: they predate every run recorded from here on. Entries that are already
	-- records pass through, so a profile an older server wrote back mid-rollout migrates cleanly.
	[3] = function(profile)
		local ledger = {}
		for runKey, entry in profile.GrantedRuns or {} do
			if type(entry) == "number" then
				ledger[runKey] = { Amount = entry, At = 0 }
			elseif type(entry) == "table" then
				ledger[runKey] = entry
			end
		end
		profile.GrantedRuns = ledger
		return profile
	end,
	-- v4 -> v5: the salvage shop. Nothing is owned yet and no trail is equipped.
	[4] = function(profile)
		profile.MetaUpgrades = type(profile.MetaUpgrades) == "table" and profile.MetaUpgrades or {}
		profile.EquippedTrail = type(profile.EquippedTrail) == "string" and profile.EquippedTrail or ""
		return profile
	end,
	-- v5 -> v6: levels. Everyone starts at level 1 with no experience.
	[5] = function(profile)
		local progression = type(profile.Progression) == "table" and profile.Progression or {}
		local xp = tonumber(progression.Xp) or 0
		profile.Progression = { Xp = math.max(math.floor(xp), 0) }
		return profile
	end,
	-- v6 -> v7: daily rewards, quests, promo codes and the sound volume setting. Nothing has
	-- been claimed yet; defaults fill every new field.
	[6] = function(profile)
		profile.Daily = type(profile.Daily) == "table" and profile.Daily or { LastClaimDay = 0, Streak = 0 }
		profile.Quests = type(profile.Quests) == "table" and profile.Quests or { Day = 0, Progress = {}, Claimed = {} }
		profile.RedeemedCodes = type(profile.RedeemedCodes) == "table" and profile.RedeemedCodes or {}
		profile.Settings = PlayerDataConfig.SanitiseSettings(profile.Settings, profile.Settings)
		return profile
	end,
	-- v7 -> v8: rigs, the Depth Pact, achievements and the Codex. Everyone starts as a Striker
	-- with no Pact and nothing claimed; the new lifetime stats start at zero.
	[7] = function(profile)
		profile.SelectedRig = type(profile.SelectedRig) == "string" and profile.SelectedRig or "Striker"
		profile.Pact = type(profile.Pact) == "table" and profile.Pact or {}
		profile.Achievements = type(profile.Achievements) == "table" and profile.Achievements or {}
		local codex = type(profile.Codex) == "table" and profile.Codex or {}
		profile.Codex = {
			Cards = type(codex.Cards) == "table" and codex.Cards or {},
			Enemies = type(codex.Enemies) == "table" and codex.Enemies or {},
		}
		return profile
	end,
	-- v8 -> v9: the home base. Armory stat levels are refunded in coins (power now comes from
	-- buildings); the consumable balances, base, presets and funnel flags start empty. Runs
	-- inside the save transform on the stored copy, so the refund lands exactly once.
	[8] = function(profile)
		local currency = type(profile.Currency) == "table" and profile.Currency or {}
		local levels = type(profile.MetaUpgrades) == "table" and profile.MetaUpgrades or {}
		local refund = 0
		for itemId, costs in PlayerDataConfig.LegacyArmoryCosts do
			local owned = tonumber(levels[itemId]) or 0
			owned = math.clamp(math.floor(owned), 0, #costs)
			for level = 1, owned do
				refund += costs[level]
			end
			levels[itemId] = nil
		end
		currency.Salvage = (tonumber(currency.Salvage) or 0) + refund
		currency.Rerolls = math.max(math.floor(tonumber(currency.Rerolls) or 0), 0)
		currency.ReviveTokens = math.max(math.floor(tonumber(currency.ReviveTokens) or 0), 0)
		profile.Currency = currency
		profile.MetaUpgrades = levels
		local flags = type(profile.Flags) == "table" and profile.Flags or {}
		flags.Funnel = type(flags.Funnel) == "table" and flags.Funnel or {}
		-- Anyone who already played is past the first descent.
		flags.FirstDescentDone = flags.FirstDescentDone == true or flags.OnboardingSeen == true
		profile.Flags = flags
		return profile
	end,
	-- v9 -> v10: a profile saved by the 2.x haul build also called itself v9, but that v9 kept
	-- the Armory (with Deep Quiver) and added DepthRank. Deepen is retired with the Armory, so
	-- the rank is dropped and any Armory levels still held are refunded by re-running the v9
	-- step, which leaves a profile that was already this build's v9 unchanged.
	[9] = function(profile)
		profile.DepthRank = nil
		return PlayerDataConfig.Migrations[8](profile)
	end,
}

return PlayerDataConfig
