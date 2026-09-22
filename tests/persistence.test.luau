-- Profile load/save, schema migration, retry/backoff, failure isolation and reward idempotency.
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")

-- Stand-in DataStore: records calls and can be told to fail a number of times or forever.
local function fakeStore()
	local store = { data = {}, calls = 0, failuresRemaining = 0, alwaysFail = false, conflicts = 0 }

	function store:UpdateAsync(key, transform)
		self.calls += 1
		if self.alwaysFail or self.failuresRemaining > 0 then
			self.failuresRemaining -= 1
			error("simulated datastore failure", 0)
		end
		-- Simulate another server writing between read and write.
		if self.conflicts > 0 then
			self.conflicts -= 1
			self.data[key] = self.externalWrite and self.externalWrite(self.data[key]) or self.data[key]
		end
		local updated = transform(self.data[key])
		self.data[key] = updated
		return updated
	end

	return store
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

		service:Update(subject, function(current)
			current.Currency.Salvage += 120
		end)
		expect((service:Save(subject, 10))).toBe(true)
		expect(store.data["profile_1"].Currency.Salvage).toBe(120)
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
		expect(service:GetSession(subject).dirty).toBe(true) -- still queued for the next attempt

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
			stored.GrantedRuns["job-B"] = 50
			return stored
		end
		service:Save(subject, 3)

		local saved = store.data["profile_14"]
		expect(saved.GrantedRuns["job-A"]).toBe(100)
		expect(saved.GrantedRuns["job-B"]).toBe(50)
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
