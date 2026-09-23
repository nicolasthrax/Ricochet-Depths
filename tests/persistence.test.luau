-- Profile load/save, schema migration, retry/backoff, failure isolation and reward idempotency.
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")

-- Stand-in DataStore: records calls and can be told to fail a number of times or forever.
-- Serialises like a real DataStore, so an unsaved in-memory change can never look persisted.
local function fakeStore()
	return __FakeDataStore.new()
end

local function player(userId)
	return { Name = "P" .. userId, UserId = userId }
end

describe("profile normalisation", function()
	it("returns a complete profile from nothing", function()
		local profile = PlayerDataService.Normalise(nil)
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Currency.Salvage).toBe(0)
		expect(type(profile.GrantedRuns)).toBe("table")
		expect(profile.Flags.OnboardingSeen).toBe(false)
	end)

	it("fills in fields a newer schema added without losing existing values", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 1,
			Currency = { Salvage = 777 },
		})
		expect(profile.Currency.Salvage).toBe(777)
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Stats.RunsStarted).toBe(0)
		expect(type(profile.GrantedRuns)).toBe("table")
	end)

	it("is idempotent when applied twice", function()
		local once = PlayerDataService.Normalise({ SchemaVersion = 1, Currency = { Salvage = 5 } })
		local twice = PlayerDataService.Normalise(once)
		expect(twice.Currency.Salvage).toBe(5)
		expect(twice.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
	end)

	it("survives a corrupt stored value", function()
		expect(PlayerDataService.Normalise("not a table").Currency.Salvage).toBe(0)
		expect(PlayerDataService.Normalise(42).Stats.RunsStarted).toBe(0)
	end)
end)

describe("load and save", function()
	it("loads, mutates and persists", function()
		local store = fakeStore()
		local service = PlayerDataService.new(store)
		local subject = player(1)

		local profile = service:Load(subject)
		expect(service:IsLoaded(subject)).toBe(true)
		expect(profile.Currency.Salvage).toBe(0)

		service:GrantReward(subject, "run-1", 120)
		service:Update(subject, function(current)
			current.Flags.OnboardingSeen = true
		end)
		expect((service:Save(subject, 10))).toBe(true)
		expect(store.data["profile_1"].Currency.Salvage).toBe(120)
		expect(store.data["profile_1"].Flags.OnboardingSeen).toBe(true)
	end)

	it("skips a save when nothing changed", function()
		local store = fakeStore()
		local service = PlayerDataService.new(store)
		local subject = player(2)
		service:Load(subject)
		local callsAfterLoad = store.calls
		expect((service:Save(subject, 1))).toBe(true)
		expect(store.calls).toBe(callsAfterLoad)
	end)

	it("reloads what was written after a release and re-load", function()
		local store = fakeStore()
		local subject = player(3)

		local first = PlayerDataService.new(store)
		first:Load(subject)
		first:GrantReward(subject, "job-1", 250)
		first:Release(subject, 5)

		local second = PlayerDataService.new(store)
		local profile = second:Load(subject)
		expect(profile.Currency.Salvage).toBe(250)
	end)

	it("retries a flaky datastore and eventually succeeds", function()
		local store = fakeStore()
		store.failuresRemaining = 2
		local service = PlayerDataService.new(store)
		local subject = player(4)

		expect(service:IsLoaded(subject)).toBe(false)
		service:Load(subject)
		expect(service:IsLoaded(subject)).toBe(true)
		expect(service:GetStats().retries).toBeGreaterThanOrEqual(2)
	end)
end)

describe("failure handling", function()
	it("enters a read-only session when the profile cannot be loaded", function()
		local store = fakeStore()
		store.alwaysFail = true
		local service = PlayerDataService.new(store)
		local subject = player(5)

		local profile, err = service:Load(subject)
		expect(profile).toBeTruthy() -- playable defaults
		expect(type(err)).toBe("string")
		expect(service:IsLoaded(subject)).toBe(false)
		expect(service:GetStats().loadFailures).toBe(1)
	end)

	it("never grants a reward into a failed session", function()
		local store = fakeStore()
		store.alwaysFail = true
		local service = PlayerDataService.new(store)
		local subject = player(6)
		service:Load(subject)

		local granted, reason = service:GrantReward(subject, "job-1", 500)
		expect(granted).toBe(0)
		expect(reason).toBe("profile not loaded")
	end)

	it("refuses updates and saves for an unloaded player", function()
		local service = PlayerDataService.new(fakeStore())
		local stranger = player(7)
		expect((service:Update(stranger, function() end))).toBeNil()
		expect((service:Save(stranger, 0))).toBe(false)
		expect((service:GrantReward(stranger, "job-1", 10))).toBe(0)
	end)

	it("reports a save failure without discarding the pending changes", function()
		local store = fakeStore()
		local service = PlayerDataService.new(store)
		local subject = player(8)
		service:Load(subject)
		service:GrantReward(subject, "job-1", 90)

		store.alwaysFail = true
		local ok, err = service:Save(subject, 1)
		expect(ok).toBe(false)
		expect(type(err)).toBe("string")
		expect(service:IsDirty(subject)).toBe(true) -- still queued for the next attempt

		store.alwaysFail = false
		expect((service:Save(subject, 2))).toBe(true)
		expect(store.data["profile_8"].Currency.Salvage).toBe(90)
	end)
end)

describe("reward ledger", function()
	it("pays a run key exactly once", function()
		local service = PlayerDataService.new(fakeStore())
		local subject = player(9)
		service:Load(subject)

		expect((service:GrantReward(subject, "job-7", 300))).toBe(300)
		local repeated, reason = service:GrantReward(subject, "job-7", 300)
		expect(repeated).toBe(0)
		expect(reason).toBe("already granted")
		expect(service:GetSession(subject).profile.Currency.Salvage).toBe(300)
	end)

	it("still pays a different run", function()
		local service = PlayerDataService.new(fakeStore())
		local subject = player(10)
		service:Load(subject)
		service:GrantReward(subject, "job-1", 100)
		expect((service:GrantReward(subject, "job-2", 100))).toBe(100)
		expect(service:GetSession(subject).profile.Currency.Salvage).toBe(200)
	end)

	it("refuses to pay a repeated run after a reconnect", function()
		local store = fakeStore()
		local subject = player(11)

		local first = PlayerDataService.new(store)
		first:Load(subject)
		first:GrantReward(subject, "job-9", 400)
		first:Release(subject, 1)

		-- Same player, new session, same run key: the persisted ledger blocks it.
		local second = PlayerDataService.new(store)
		second:Load(subject)
		expect((second:GrantReward(subject, "job-9", 400))).toBe(0)
		expect(second:GetSession(subject).profile.Currency.Salvage).toBe(400)
	end)

	it("rejects malformed amounts", function()
		local service = PlayerDataService.new(fakeStore())
		local subject = player(12)
		service:Load(subject)
		for _, amount in { -50, 0, 0 / 0, "500" } do
			local granted, reason = service:GrantReward(subject, "job-x", amount)
			expect(granted).toBe(0)
			expect(reason).toBe("invalid amount")
		end
		expect(service:GetSession(subject).profile.Currency.Salvage).toBe(0)
	end)

	it("keeps the ledger bounded", function()
		local service = PlayerDataService.new(fakeStore())
		local subject = player(13)
		service:Load(subject)
		for index = 1, PlayerDataConfig.RunLedgerSize + 20 do
			service:GrantReward(subject, string.format("job-%04d", index), 1)
		end

		local count = 0
		for _ in service:GetSession(subject).profile.GrantedRuns do
			count += 1
		end
		expect(count).toBeLessThanOrEqual(PlayerDataConfig.RunLedgerSize)
	end)

	it("unions the ledger on save so a concurrent write cannot resurrect a paid run", function()
		local store = fakeStore()
		local service = PlayerDataService.new(store)
		local subject = player(14)
		service:Load(subject)
		service:GrantReward(subject, "job-A", 100)

		-- Another server writes a different run between our read and write.
		store.conflicts = 1
		store.externalWrite = function(stored)
			stored = PlayerDataService.Normalise(stored)
			stored.GrantedRuns["job-B"] = { Amount = 50, At = 1 }
			return stored
		end
		service:Save(subject, 3)

		local saved = store.data["profile_14"]
		expect(saved.GrantedRuns["job-A"].Amount).toBe(100)
		expect(saved.GrantedRuns["job-B"].Amount).toBe(50)
		expect(saved.Currency.Salvage).toBe(100) -- job-B's 50 was never credited to this store
	end)
end)

describe("autosave and shutdown", function()
	it("autosaves only dirty sessions past the interval", function()
		local store = fakeStore()
		local service = PlayerDataService.new(store)
		local subject = player(15)
		service:Load(subject)
		service:GrantReward(subject, "job-1", 10)

		expect(service:StepAutosave(PlayerDataConfig.AutosaveInterval - 1)).toBe(0)
		expect(service:StepAutosave(PlayerDataConfig.AutosaveInterval + 1)).toBe(1)
		expect(service:StepAutosave(PlayerDataConfig.AutosaveInterval * 3)).toBe(0) -- clean now
	end)

	it("flushes every session on shutdown", function()
		local store = fakeStore()
		local service = PlayerDataService.new(store)
		for index = 20, 23 do
			local subject = player(index)
			service:Load(subject)
			service:GrantReward(subject, "job-shutdown", 25)
		end
		expect(#service:SaveAll(99)).toBe(0)
		for index = 20, 23 do
			expect(store.data["profile_" .. index].Currency.Salvage).toBe(25)
		end
	end)

	it("reports which sessions failed to flush", function()
		local store = fakeStore()
		local service = PlayerDataService.new(store)
		local subject = player(30)
		service:Load(subject)
		service:GrantReward(subject, "job-1", 5)
		store.alwaysFail = true
		expect(#service:SaveAll(1)).toBe(1)
	end)
end)

describe("run statistics", function()
	it("accumulates bests across runs", function()
		local service = PlayerDataService.new(fakeStore())
		local subject = player(40)
		service:Load(subject)

		service:RecordRunEnd(subject, { Outcome = "Defeated", EnemiesDefeated = 8, BestChain = 3, RoomsCleared = 1 })
		service:RecordRunEnd(subject, { Outcome = "Extracted", EnemiesDefeated = 20, BestChain = 6, RoomsCleared = 4 })

		local stats = service:GetSession(subject).profile.Stats
		expect(stats.RunsStarted).toBe(2)
		expect(stats.RunsExtracted).toBe(1)
		expect(stats.EnemiesDefeated).toBe(28)
		expect(stats.BestChain).toBe(6)
		expect(stats.BestRoomsCleared).toBe(4)
	end)
end)

describe("settings", function()
	local function loadedService()
		local store = __FakeDataStore.new()
		local service = PlayerDataService.new(store)
		local subject = player(60)
		service:Load(subject)
		return service, subject, store
	end

	it("starts every player on the documented defaults", function()
		local service, subject = loadedService()
		local settings = service:GetPublicProfile(subject).Settings
		for name, spec in PlayerDataConfig.SettingSpecs do
			expect(settings[name]).toBe(spec.Default)
		end
	end)

	it("accepts valid changes and persists them", function()
		local service, subject, store = loadedService()
		local applied = service:ApplySettings(subject, { ReducedFlash = true, EffectIntensity = 0.5 })
		expect(applied.ReducedFlash).toBe(true)
		expect(applied.EffectIntensity).toBe(0.5)
		service:Save(subject, 1)
		expect(store.data["profile_60"].Settings.ReducedFlash).toBe(true)
	end)

	it("clamps out-of-range numbers instead of trusting them", function()
		local service, subject = loadedService()
		local applied = service:ApplySettings(subject, { EffectIntensity = 99, ScreenShake = -12 })
		expect(applied.EffectIntensity).toBe(1)
		expect(applied.ScreenShake).toBe(0)
	end)

	it("discards mistyped, missing and unknown fields", function()
		local service, subject = loadedService()
		service:ApplySettings(subject, { ReducedFlash = true })
		local applied = service:ApplySettings(subject, {
			ReducedFlash = "yes",
			EffectIntensity = 0 / 0,
			ScreenShake = math.huge,
			Cheat = true,
			Salvage = 99999,
		})
		expect(applied.ReducedFlash).toBe(true) -- kept its previous valid value
		expect(applied.EffectIntensity).toBe(1)
		expect(applied.ScreenShake).toBe(1)
		expect(applied.Cheat).toBeNil()
		expect(service:GetPublicProfile(subject).Salvage).toBe(0)
	end)

	it("survives a non-table payload", function()
		local service, subject = loadedService()
		expect(service:ApplySettings(subject, "drop tables").ReducedFlash).toBe(false)
		expect(service:ApplySettings(subject, nil).EffectIntensity).toBe(1)
	end)

	it("refuses settings for a session that failed to load", function()
		local failing = {}
		function failing:UpdateAsync()
			error("down", 0)
		end
		local service = PlayerDataService.new(failing)
		local subject = player(61)
		service:Load(subject)
		local applied, reason = service:ApplySettings(subject, { ReducedFlash = true })
		expect(applied).toBeNil()
		expect(reason).toBe("profile not loaded")
	end)

	it("migrates a v2 profile forward with default settings", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 2,
			Currency = { Salvage = 42 },
			GrantedRuns = { ["job-1"] = 10 },
		})
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Currency.Salvage).toBe(42)
		expect(profile.GrantedRuns["job-1"].Amount).toBe(10)
		expect(profile.Settings.EffectIntensity).toBe(1)
	end)

	it("marks onboarding complete after the first finished run", function()
		local service, subject = loadedService()
		expect(service:GetPublicProfile(subject).Flags.OnboardingSeen).toBe(false)
		service:RecordRunEnd(subject, { Outcome = "Defeated", EnemiesDefeated = 1, BestChain = 1, RoomsCleared = 0 })
		expect(service:GetPublicProfile(subject).Flags.OnboardingSeen).toBe(true)
	end)
end)

describe("every profile field survives a save", function()
	-- Save writes back an explicit list of fields. A field added to the schema but not to that
	-- list is silently dropped on every save. Settings went unsaved this way for a whole schema
	-- version, hidden by a fake store that shared its table with the session.
	it("round-trips every top-level field through a real save", function()
		local store = __FakeDataStore.new()
		local service = PlayerDataService.new(store)
		local subject = player(70)
		service:Load(subject)

		local profile = service:GetSession(subject).profile
		-- Store-owned fields are written by the transform itself, never copied from memory; their
		-- own tests cover them. Everything else must round-trip.
		local skipped = PlayerDataService.STORE_OWNED_FIELDS
		local marked = {}
		for field, value in PlayerDataConfig.DefaultProfile() do
			if not skipped[field] then
				expect(type(value)).toBe("table")
				profile[field] = profile[field] or {}
				profile[field].__roundTripMarker = field
				marked[field] = true
			end
		end
		service:Update(subject, function() end) -- mark it changed through the real path
		expect((service:Save(subject, 1))).toBe(true)

		local stored = store:Peek("profile_70")
		for field in marked do
			expect(stored[field]).toBeTruthy()
			if stored[field].__roundTripMarker ~= field then
				error(string.format("profile field %q is not written by Save", field), 0)
			end
		end
	end)

	it("persists a settings change across a reload", function()
		local store = __FakeDataStore.new()
		local subject = player(71)

		local first = PlayerDataService.new(store)
		first:Load(subject)
		first:ApplySettings(subject, { ReducedFlash = true, EffectIntensity = 0.5 })
		first:Release(subject, 1)

		local second = PlayerDataService.new(store)
		local profile = second:Load(subject)
		expect(profile.Settings.ReducedFlash).toBe(true)
		expect(profile.Settings.EffectIntensity).toBe(0.5)
	end)
end)
