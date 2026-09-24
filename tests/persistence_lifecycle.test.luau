-- Regression tests for docs/PERSISTENCE_SHUTDOWN_PLAN.md, one section per implementation step.
-- Each test was written to fail against the code as it stood before its step landed.
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local PlayerDataService = __require("PlayerDataService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3
local DT = 1 / 30

-- Serialising fake: counts writes, can be told to fail, and never shares a table with callers.
local function countingStore()
	return __FakeDataStore.new()
end

local function recordingRemote()
	local remote = { calls = {} }
	function remote:FireClient(player, payload)
		table.insert(self.calls, { player = player, payload = payload })
	end
	function remote:FireAllClients() end
	function remote:For(player)
		for index = #self.calls, 1, -1 do
			if self.calls[index].player == player then
				return self.calls[index].payload
			end
		end
		return nil
	end
	return remote
end

local function buildMatch(seed, persistence)
	local arena = Instance.new("Folder")
	local enemies = EnemyService.new(arena, PLANE_Y, seed)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
		net[name] = recordingRemote()
	end
	local upgrades = UpgradeService.new(seed)
	local match = MatchService.new({
		rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(seed)),
		enemies = enemies,
		upgrades = upgrades,
		projectiles = ProjectileService.new(arena, arena, PLANE_Y),
		rewards = RewardService.new(),
		net = net,
		persistence = persistence,
		runKeyPrefix = "lifecycle",
		world = {
			GetPosition = function()
				return Vector3.new(0, PLANE_Y, 0)
			end,
			Teleport = function() end,
		},
	})
	return { match = match, net = net, enemies = enemies, upgrades = upgrades }
end

-- Plays a full run to extraction through the real impact and upgrade paths.
local function playToExtraction(ctx, player)
	local clock = 0
	local function step(seconds)
		for _ = 1, math.max(1, math.ceil(seconds / DT)) do
			clock += DT
			ctx.match:Step(DT, clock)
		end
	end

	ctx.match:RegisterPlayer(player)
	ctx.match:RequestStart(player, clock)
	step(RunConfig.StartCountdown + DT)

	for roomIndex = 1, RunConfig.RoomCount() do
		__clearRoom(ctx.match._rooms, function()
			local guard = 0
			while ctx.enemies:GetActiveCount() > 0 and guard < 500 do
				guard += 1
				local enemy = ctx.enemies:GetEnemies()[1]
				ctx.match:HandleImpact(
					{ Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part },
					{ direction = Vector3.new(0, 0, 1), damage = 100, damagePerBounce = 0, contacts = 1, wallBounces = 1, shooter = player },
					clock
				)
			end
		end, step)
		step(DT)
		if roomIndex < RunConfig.RoomCount() then
			local offer = ctx.upgrades:GetOffer(player)
			ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
			step(RunConfig.TransitionDuration + DT * 2)
		end
	end

	expect(ctx.match:GetState()).toBe(RunConfig.States.Results)
	return ctx.net.RunResults:For(player), clock
end

--// Step 1: save on reward grant ---------------------------------------------

describe("step 1: a run's payout is written as soon as it is granted", function()
	it("persists the payout without waiting for autosave, leave or shutdown", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Earner", UserId = 5001 }
		persistence:Load(player)

		local summary = playToExtraction(buildMatch(501, persistence), player)
		expect(summary.Reward).toBeGreaterThan(0)

		-- Nothing has called Save, StepAutosave, Release or SaveAll. The store must already
		-- hold the payout, or a crash before the player leaves would lose it.
		local stored = store.data["profile_5001"]
		expect(stored.Currency.Salvage).toBe(summary.Reward + summary.LevelReward)
		expect(stored.GrantedRuns[summary.RunKey].Amount).toBe(summary.Reward + summary.LevelReward)
		expect(stored.Progression.Xp).toBe(summary.XpEarned)
	end)

	it("writes the payout and the run's stats together in one request", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Frugal", UserId = 5002 }
		persistence:Load(player)
		local writesAfterLoad = store.writes

		playToExtraction(buildMatch(502, persistence), player)

		expect(store.writes - writesAfterLoad).toBe(1)
		local stored = store.data["profile_5002"]
		expect(stored.Stats.RunsExtracted).toBe(1)
		expect(stored.Stats.BestRoomsCleared).toBe(RunConfig.RoomCount())
	end)

	it("leaves a shutdown straight after the run with nothing to write", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Closer", UserId = 5003 }
		persistence:Load(player)

		playToExtraction(buildMatch(503, persistence), player)
		local writesBeforeShutdown = store.writes

		expect(#persistence:SaveAll(999)).toBe(0)
		-- The payout was already durable, so the shutdown path has no work left to do.
		expect(store.writes).toBe(writesBeforeShutdown)
	end)

	it("finishes the run and keeps the payout pending when that write fails", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Unlucky", UserId = 5004 }
		persistence:Load(player)
		store.failing = true -- the store dies after the profile loaded

		local summary = playToExtraction(buildMatch(504, persistence), player)
		expect(summary.Reward).toBeGreaterThan(0)

		-- The failure must not break the run, and the payout must stay queued so leave,
		-- autosave or shutdown can still write it once the store recovers.
		expect(persistence:IsDirty(player)).toBe(true)
		store.failing = false
		expect((persistence:Save(player, 1000))).toBe(true)
		expect(store.data["profile_5004"].Currency.Salvage).toBe(summary.Reward + summary.LevelReward)
	end)

	it("never writes for a player whose profile failed to load", function()
		local store = countingStore()
		store.failing = true
		local persistence = PlayerDataService.new(store)
		local player = { Name = "ReadOnly", UserId = 5005 }
		persistence:Load(player)
		store.failing = false -- recovers mid-run, but the session is already read-only

		local summary = playToExtraction(buildMatch(505, persistence), player)
		expect(summary.Reward).toBe(0)
		expect(store.writes).toBe(0)
		expect(store.data["profile_5005"]).toBeNil()
	end)
end)

--// Step 2: one save in flight per session, change counter -------------------

describe("step 2 (P3): a change made while a save is in flight is kept", function()
	local function loadedWithSlowWrites(userId)
		local store = countingStore()
		store.writeLatency = 1 -- each save sits in flight for one second of virtual time
		local persistence = PlayerDataService.new(store)
		local player = { Name = "P" .. userId, UserId = userId }
		persistence:Load(player)
		Harness.setClock(0)
		return store, persistence, player, "profile_" .. userId
	end

	it("does not lose a reward granted while the previous save is in flight", function()
		local store, persistence, player, key = loadedWithSlowWrites(6001)
		persistence:GrantReward(player, "run-1", 100)
		task.spawn(function()
			persistence:Save(player, 0) -- captures the profile, then waits on the store
		end)
		expect(store.inFlight[key]).toBe(1)

		persistence:GrantReward(player, "run-2", 50) -- arrives mid-write
		Harness.settle()

		-- In memory: the completing save must not roll the profile back to what it captured.
		local profile = persistence:GetSession(player).profile
		expect(profile.Currency.Salvage).toBe(150)
		expect(profile.GrantedRuns["run-2"].Amount).toBe(50)
		-- In the store: the late change is written by a follow-up, with no further request.
		local stored = store:Peek(key)
		expect(stored.Currency.Salvage).toBe(150)
		expect(stored.GrantedRuns["run-2"].Amount).toBe(50)
	end)

	it("does not lose a settings change made while a save is in flight", function()
		local store, persistence, player, key = loadedWithSlowWrites(6002)
		persistence:GrantReward(player, "run-1", 10)
		task.spawn(function()
			persistence:Save(player, 0)
		end)
		persistence:ApplySettings(player, { ReducedFlash = true })
		Harness.settle()

		expect(persistence:GetSession(player).profile.Settings.ReducedFlash).toBe(true)
		expect(store:Peek(key).Settings.ReducedFlash).toBe(true)
	end)

	it("keeps a mid-flight change pending if its follow-up write fails", function()
		local store, persistence, player, key = loadedWithSlowWrites(6003)
		persistence:GrantReward(player, "run-1", 100)
		task.spawn(function()
			persistence:Save(player, 0)
		end)
		persistence:GrantReward(player, "run-2", 50)
		store.failing = true -- the first write already got through; the follow-up will not
		Harness.settle()

		expect(store:Peek(key).Currency.Salvage).toBe(100)
		expect(persistence:GetSession(player).profile.Currency.Salvage).toBe(150)

		-- Still pending, so the next save once the store recovers carries it.
		store.failing = false
		expect((persistence:Save(player, 10))).toBe(true)
		expect(store:Peek(key).Currency.Salvage).toBe(150)
	end)
end)

describe("step 2 (P2): concurrent save requests coalesce", function()
	local function loadedWithSlowWrites(userId)
		local store = countingStore()
		store.writeLatency = 1
		local persistence = PlayerDataService.new(store)
		local player = { Name = "P" .. userId, UserId = userId }
		persistence:Load(player)
		Harness.setClock(0)
		return store, persistence, player, "profile_" .. userId
	end

	it("joins a leave onto the save already in flight instead of writing twice", function()
		local store, persistence, player, key = loadedWithSlowWrites(6101)
		local writesAfterLoad = store.writes
		persistence:GrantReward(player, "run-1", 100)

		persistence:SaveInBackground(player, 0) -- e.g. the post-run save
		expect(store.inFlight[key]).toBe(1)
		local ok = persistence:Release(player, 0) -- the player leaves while it is in flight

		expect(ok).toBe(true)
		expect(store.writes - writesAfterLoad).toBe(1)
		expect(store.peakInFlight[key]).toBe(1)
		expect(store:Peek(key).Currency.Salvage).toBe(100)
		-- The session goes only after the write it was waiting on has landed.
		expect(persistence:GetSession(player)).toBeNil()
	end)

	it("turns a burst of requests into at most one follow-up write", function()
		local store, persistence, player, key = loadedWithSlowWrites(6102)
		local writesAfterLoad = store.writes
		persistence:GrantReward(player, "run-1", 100)

		persistence:SaveInBackground(player, 0) -- in flight
		for _ = 1, 4 do
			persistence:SaveInBackground(player, 0) -- post-run, autosave, leave, shutdown...
		end
		persistence:GrantReward(player, "run-2", 50) -- one real change arrives mid-flight
		persistence:SaveAll(0)
		Harness.settle()

		-- The first write, plus exactly one to carry the change. Never two at once.
		expect(store.writes - writesAfterLoad).toBe(2)
		expect(store.peakInFlight[key]).toBe(1)
		expect(store:Peek(key).Currency.Salvage).toBe(150)
	end)

	it("never has two writes in flight for one player, even across players at shutdown", function()
		local store = countingStore()
		store.writeLatency = 1
		local persistence = PlayerDataService.new(store)
		local players = {}
		for index = 1, 4 do
			local player = { Name = "S" .. index, UserId = 6200 + index }
			persistence:Load(player)
			persistence:GrantReward(player, "run-1", 10 * index)
			table.insert(players, player)
		end
		Harness.setClock(0)

		-- The post-run saves are in flight when the server starts closing and players leave.
		for _, player in players do
			persistence:SaveInBackground(player, 0)
		end
		for _, player in players do
			task.spawn(function()
				persistence:Release(player, 0)
			end)
		end
		persistence:SaveAll(0)
		Harness.settle()

		for index, player in players do
			local key = "profile_" .. player.UserId
			expect(store.peakInFlight[key]).toBe(1)
			expect(store:Peek(key).Currency.Salvage).toBe(10 * index)
		end
	end)
end)

describe("step 2: autosave and the write chain", function()
	it("never blocks the frame or doubles a write when autosave fires mid-save", function()
		local PlayerDataConfig = __require("PlayerDataConfig")
		local store = countingStore()
		store.writeLatency = 1
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Auto", UserId = 6301 }
		persistence:Load(player)
		persistence:GrantReward(player, "run-1", 40)
		local writesAfterLoad = store.writes

		-- Autosave is called from Heartbeat every frame. Drive it frame by frame through the
		-- whole time a slow write is in flight.
		local now = PlayerDataConfig.AutosaveInterval + 1
		Harness.setClock(now)
		for _ = 1, 90 do
			local before = Harness.now()
			persistence:StepAutosave(now)
			-- Returns within the same frame: it must never wait on the DataStore itself.
			expect(Harness.now()).toBe(before)
			Harness.advance(1 / 60)
			now = Harness.now()
		end
		Harness.settle()

		expect(store.writes - writesAfterLoad).toBe(1)
		expect(store.peakInFlight["profile_6301"]).toBe(1)
		expect(store:Peek("profile_6301").Currency.Salvage).toBe(40)
	end)

	it("stops chaining after the cap and leaves the rest pending", function()
		local PlayerDataConfig = __require("PlayerDataConfig")
		local store = countingStore()
		store.writeLatency = 1
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Busy", UserId = 6302 }
		persistence:Load(player)
		local writesAfterLoad = store.writes

		-- A new change lands during every single write, so the chain can never catch up.
		local runIndex = 0
		local function change()
			runIndex += 1
			persistence:GrantReward(player, "run-" .. runIndex, 1)
		end
		change()
		task.spawn(function()
			persistence:Save(player, 0)
		end)
		for _ = 1, PlayerDataConfig.MaxChainedWrites + 2 do
			change()
			Harness.advance(1)
		end
		Harness.settle()

		expect(store.writes - writesAfterLoad).toBe(PlayerDataConfig.MaxChainedWrites)
		expect(persistence:IsDirty(player)).toBe(true) -- not lost, just deferred
		expect((persistence:Save(player, 99))).toBe(true)
		expect(store:Peek("profile_6302").Currency.Salvage).toBe(runIndex)
	end)
end)

--// Step 3: stale loads are discarded; one session per UserId -----------------

describe("step 3 (P4): a load that finishes after its player left is discarded", function()
	it("returns stale, marks nothing loaded and leaves no session when the player leaves mid-load", function()
		local store = countingStore()
		store.readLatency = 1 -- the load sits in the network layer for a second
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Leaver", UserId = 7001 }
		Harness.setClock(0)

		local result = {}
		task.spawn(function()
			result.profile, result.err = persistence:Load(player)
		end)
		local pending = persistence:GetSession(player) -- the half-built session, mid-load
		expect(pending).toBeTruthy()

		persistence:Release(player, 0) -- the player disconnects before the load resolves
		Harness.settle()

		expect(result.profile).toBeNil()
		expect(result.err).toBe("stale load")
		expect(persistence:GetSession(player)).toBeNil()
		expect(persistence:IsLoaded(player)).toBe(false)
		-- The orphaned session must not be brought back to life by the late result.
		expect(pending.loaded).toBe(false)
		expect(persistence:GetStats().loads).toBe(0)
	end)

	it("stops retrying a failing load once its player has gone", function()
		local PlayerDataConfig = __require("PlayerDataConfig")
		local store = countingStore()
		store.failing = true
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Gone", UserId = 7002 }
		Harness.setClock(0)

		local result = {}
		task.spawn(function()
			result.profile, result.err = persistence:Load(player)
		end)
		persistence:Release(player, 0)
		Harness.settle()

		expect(result.profile).toBeNil()
		expect(result.err).toBe("stale load")
		-- No read-only session is left behind, and the retries stop rather than burning budget.
		expect(persistence:GetSession(player)).toBeNil()
		expect(store.calls).toBeLessThan(PlayerDataConfig.MaxRetries)
	end)
end)

describe("step 3: a rapid rejoin keeps the newest load authoritative", function()
	local function rejoinSetup(firstLatency, secondLatency)
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		-- Same account, two Player objects: Roblox gives a rejoining player a new one.
		local first = { Name = "Hopper", UserId = 7101 }
		local second = { Name = "Hopper", UserId = 7101 }
		Harness.setClock(0)

		local results = { first = {}, second = {} }
		store.readLatency = firstLatency
		task.spawn(function()
			results.first.profile, results.first.err = persistence:Load(first)
		end)
		persistence:Release(first, 0) -- leaves while load #1 is still in flight
		store.readLatency = secondLatency
		task.spawn(function()
			results.second.profile, results.second.err = persistence:Load(second)
		end)
		return store, persistence, first, second, results
	end

	it("discards load #1 when it resolves after load #2 has finished", function()
		local _store, persistence, first, second, results = rejoinSetup(3, 1)

		Harness.advance(1.5) -- load #2 done; load #1 still in flight
		expect(persistence:IsLoaded(second)).toBe(true)
		persistence:GrantReward(second, "run-1", 50) -- the rejoined player plays on

		Harness.settle() -- now load #1 resolves, late
		expect(results.first.profile).toBeNil()
		expect(results.first.err).toBe("stale load")
		expect(results.second.profile).toBeTruthy()
		-- Load #2's session is untouched, including the change made after it loaded.
		expect(persistence:GetSession(second).profile.Currency.Salvage).toBe(50)
		expect(persistence:IsLoaded(first)).toBe(false)
	end)

	it("discards load #1 when it resolves after load #2 began but before it finished", function()
		local _store, persistence, first, second, results = rejoinSetup(2, 3)

		Harness.advance(2.5) -- load #1 resolves here, with load #2 still in flight
		expect(results.first.err).toBe("stale load")
		expect(persistence:IsLoaded(second)).toBe(false)

		Harness.settle()
		expect(results.second.profile).toBeTruthy()
		expect(persistence:IsLoaded(second)).toBe(true)
		expect(persistence:IsLoaded(first)).toBe(false)
	end)
end)

describe("step 3: rejoining while the old session is still saving (same-server P5)", function()
	it("keeps a payout that was still being written when the player rejoined", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local first = { Name = "Quick", UserId = 7201 }
		local second = { Name = "Quick", UserId = 7201 }
		persistence:Load(first)
		persistence:GrantReward(first, "run-1", 120)
		Harness.setClock(0)

		store.writeLatency = 2 -- the leave-save is slow to land
		task.spawn(function()
			persistence:Release(first, 0)
		end)
		store.writeLatency = 0

		-- Rejoins before that save lands. Reading the store now would return the profile from
		-- before the payout, and the next save would overwrite it.
		local rejoined = persistence:Load(second)
		expect(rejoined.Currency.Salvage).toBe(120)

		persistence:ApplySettings(second, { ReducedFlash = true })
		Harness.settle()
		expect((persistence:Save(second, 10))).toBe(true)

		local stored = store:Peek("profile_7201")
		expect(stored.Currency.Salvage).toBe(120)
		expect(stored.Settings.ReducedFlash).toBe(true)
		-- The old leave must not tear down the session the rejoined player is now using.
		expect(persistence:IsLoaded(second)).toBe(true)
	end)

	it("makes the old Player handle inert once the session belongs to the rejoin", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local first = { Name = "Twice", UserId = 7202 }
		local second = { Name = "Twice", UserId = 7202 }
		persistence:Load(first)
		Harness.setClock(0)
		store.writeLatency = 2
		persistence:GrantReward(first, "run-1", 10)
		task.spawn(function()
			persistence:Release(first, 0)
		end)
		store.writeLatency = 0
		persistence:Load(second)

		-- A late call through the departed player's handle must not touch the live session.
		local granted, reason = persistence:GrantReward(first, "run-2", 999)
		expect(granted).toBe(0)
		expect(reason).toBe("profile not loaded")
		Harness.settle()
		expect(persistence:GetSession(second).profile.Currency.Salvage).toBe(10)
	end)
end)

describe("step 3: session lifecycle guards", function()
	it("still releases a taken-over session when the rejoined player leaves", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local first = { Name = "Loop", UserId = 7301 }
		local second = { Name = "Loop", UserId = 7301 }
		persistence:Load(first)
		persistence:GrantReward(first, "run-1", 30)
		Harness.setClock(0)
		store.writeLatency = 1
		task.spawn(function()
			persistence:Release(first, 0)
		end)
		store.writeLatency = 0
		persistence:Load(second) -- takes the session over mid-save
		Harness.settle()
		expect(persistence:IsLoaded(second)).toBe(true)

		expect((persistence:Release(second, 5))).toBe(true)
		expect(persistence:GetSession(second)).toBeNil()
		expect(store:Peek("profile_7301").Currency.Salvage).toBe(30)
	end)

	it("keeps only the newest of two loads from the same player", function()
		local store = countingStore()
		store.readLatency = 2
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Double", UserId = 7302 }
		Harness.setClock(0)

		local results = { {}, {} }
		task.spawn(function()
			results[1].profile, results[1].err = persistence:Load(player)
		end)
		Harness.advance(0.5)
		task.spawn(function()
			results[2].profile, results[2].err = persistence:Load(player)
		end)
		Harness.settle()

		expect(results[1].err).toBe("stale load")
		expect(results[2].profile).toBeTruthy()
		expect(persistence:IsLoaded(player)).toBe(true)
		expect(persistence:GetStats().staleLoads).toBe(1)
	end)
end)

--// Step 4: grant-based currency and a timestamp-ordered, capped ledger ----------

local function countKeys(map)
	local count = 0
	for _ in map do
		count += 1
	end
	return count
end

-- A wall clock the test controls. Ledger timestamps must come from a clock that means the same
-- thing on every server, and os.clock() does not.
local function manualClock(start)
	local clock = { now = start or 1000 }
	function clock.read()
		return clock.now
	end
	return clock
end

describe("step 4 (P5): currency survives a cross-server race", function()
	it("keeps A's committed payout when B, loaded before that commit, saves its own", function()
		local store = countingStore()
		local wall = manualClock()
		local serverA = PlayerDataService.new(store, { wallClock = wall.read })
		local serverB = PlayerDataService.new(store, { wallClock = wall.read })
		-- One account, one Player object per server.
		local onA = { Name = "Roamer", UserId = 8001 }
		local onB = { Name = "Roamer", UserId = 8001 }
		Harness.setClock(0)

		serverA:Load(onA)
		serverA:GrantReward(onA, "run-A", 100) -- A prepares +100
		store.writeLatency = 2
		task.spawn(function()
			serverA:Save(onA, 0) -- ...and yields before committing
		end)
		store.writeLatency = 0

		local loadedOnB = serverB:Load(onB) -- B loads before A commits
		expect(loadedOnB.Currency.Salvage).toBe(0)
		Harness.settle() -- A commits 100
		expect(store:Peek("profile_8001").Currency.Salvage).toBe(100)

		wall.now += 60
		serverB:GrantReward(onB, "run-B", 50) -- B earns +50
		expect((serverB:Save(onB, 10))).toBe(true)

		local stored = store:Peek("profile_8001")
		expect(stored.Currency.Salvage).toBe(150) -- not 50
		expect(stored.GrantedRuns["run-A"]).never().toBeNil()
		expect(stored.GrantedRuns["run-B"]).never().toBeNil()
		-- And B's own view catches up with what the store now holds.
		expect(serverB:GetSession(onB).profile.Currency.Salvage).toBe(150)
	end)

	it("counts every grant when four servers pay the same account at once", function()
		local store = countingStore()
		local wall = manualClock()
		local servers, players = {}, {}
		for index = 1, 4 do
			servers[index] = PlayerDataService.new(store, { wallClock = wall.read })
			players[index] = { Name = "Everywhere", UserId = 8002 }
			servers[index]:Load(players[index]) -- all load the empty profile first
		end

		for index = 1, 4 do
			for run = 1, 10 do
				wall.now += 1
				servers[index]:GrantReward(players[index], string.format("s%d-run-%02d", index, run), 1)
			end
		end
		for index = 1, 4 do
			expect((servers[index]:Save(players[index], 1))).toBe(true)
		end

		expect(store:Peek("profile_8002").Currency.Salvage).toBe(40) -- not 10
	end)

	it("never applies a run twice, even when two servers each hold it as pending", function()
		-- Guard, not a regression: the old absolute-balance code also ends at 100 here, by
		-- coincidence. Without the ledger check, the new delta code would reach 200.
		local store = countingStore()
		local wall = manualClock()
		local serverA = PlayerDataService.new(store, { wallClock = wall.read })
		local serverB = PlayerDataService.new(store, { wallClock = wall.read })
		local onA = { Name = "Dup", UserId = 8003 }
		local onB = { Name = "Dup", UserId = 8003 }
		serverA:Load(onA)
		serverB:Load(onB)

		serverA:GrantReward(onA, "run-X", 100)
		serverB:GrantReward(onB, "run-X", 100) -- the same run, credited on both
		serverA:Save(onA, 1)
		serverB:Save(onB, 2)

		expect(store:Peek("profile_8003").Currency.Salvage).toBe(100)
		expect(serverB:GetSession(onB).profile.Currency.Salvage).toBe(100)
	end)
end)

describe("step 4: the ledger is pruned oldest-first, by time", function()
	local PlayerDataConfig = __require("PlayerDataConfig")

	-- Fills the ledger to its cap with runs whose keys sort AFTER the newest one, then adds the
	-- newest. Alphabetical pruning would throw away the run that was just paid.
	local function fillThenAddNewest()
		local store = countingStore()
		local wall = manualClock(1)
		local persistence = PlayerDataService.new(store, { wallClock = wall.read })
		local player = { Name = "Ledger", UserId = 8101 }
		persistence:Load(player)

		persistence:GrantReward(player, "zzz-oldest", 1)
		for index = 1, PlayerDataConfig.RunLedgerSize - 1 do
			wall.now += 1
			persistence:GrantReward(player, string.format("mmm-%02d", index), 1)
		end
		wall.now += 100
		local granted = persistence:GrantReward(player, "aaa-newest", 7)
		return store, persistence, player, granted
	end

	it("drops the oldest run in memory, never the one just paid", function()
		local _store, persistence, player, granted = fillThenAddNewest()
		expect(granted).toBe(7)

		local ledger = persistence:GetSession(player).profile.GrantedRuns
		expect(ledger["aaa-newest"]).never().toBeNil()
		expect(ledger["zzz-oldest"]).toBeNil()
		expect(countKeys(ledger)).toBe(PlayerDataConfig.RunLedgerSize)
	end)

	it("refuses to pay the newest run a second time", function()
		local _store, persistence, player = fillThenAddNewest()
		local before = persistence:GetSession(player).profile.Currency.Salvage
		local again, reason = persistence:GrantReward(player, "aaa-newest", 7)
		expect(again).toBe(0)
		expect(reason).toBe("already granted")
		expect(persistence:GetSession(player).profile.Currency.Salvage).toBe(before)
	end)

	it("prunes the stored copy oldest-first too", function()
		local store, persistence, player = fillThenAddNewest()
		expect((persistence:Save(player, 1))).toBe(true)

		local stored = store:Peek("profile_8101").GrantedRuns
		expect(stored["aaa-newest"]).never().toBeNil()
		expect(stored["zzz-oldest"]).toBeNil()
		expect(countKeys(stored)).toBe(PlayerDataConfig.RunLedgerSize)
	end)

	it("keeps the stored ledger within its cap however many servers write to it", function()
		local store = countingStore()
		local wall = manualClock()
		local servers, players = {}, {}
		for index = 1, 4 do
			servers[index] = PlayerDataService.new(store, { wallClock = wall.read })
			players[index] = { Name = "Busy", UserId = 8102 }
			servers[index]:Load(players[index])
		end
		local newest
		for index = 1, 4 do
			for run = 1, 10 do
				wall.now += 1
				newest = string.format("s%d-run-%02d", index, run)
				servers[index]:GrantReward(players[index], newest, 1)
			end
			servers[index]:Save(players[index], index)
		end

		local stored = store:Peek("profile_8102").GrantedRuns
		expect(countKeys(stored)).toBeLessThanOrEqual(PlayerDataConfig.RunLedgerSize)
		expect(stored[newest]).never().toBeNil() -- the most recent run of all survives
		expect(stored["s1-run-01"]).toBeNil() -- the oldest are the ones gone
	end)

	it("migrates a numeric ledger from schema v3 into timestamped records", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 3,
			Currency = { Salvage = 30 },
			GrantedRuns = { ["job-1"] = 10, ["job-2"] = 20 },
		})
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Currency.Salvage).toBe(30)
		expect(profile.GrantedRuns["job-1"].Amount).toBe(10)
		expect(type(profile.GrantedRuns["job-2"].At)).toBe("number")
	end)
end)

describe("step 4: money changes only through grants", function()
	it("refuses a direct currency edit through Update instead of dropping it silently", function()
		local persistence = PlayerDataService.new(countingStore())
		local player = { Name = "Spender", UserId = 8201 }
		persistence:Load(player)
		persistence:GrantReward(player, "run-1", 100)

		local ok = pcall(function()
			persistence:Update(player, function(profile)
				profile.Currency.Salvage -= 40
			end)
		end)
		expect(ok).toBe(false)
		-- Rolled back, so memory never disagrees with what a save would write.
		expect(persistence:GetSession(player).profile.Currency.Salvage).toBe(100)
	end)

	it("refuses a direct ledger edit through Update", function()
		local persistence = PlayerDataService.new(countingStore())
		local player = { Name = "Forger", UserId = 8202 }
		persistence:Load(player)
		local ok = pcall(function()
			persistence:Update(player, function(profile)
				profile.GrantedRuns["forged"] = { Amount = 9999, At = 1 }
			end)
		end)
		expect(ok).toBe(false)
		expect(persistence:GetSession(player).profile.GrantedRuns["forged"]).toBeNil()
	end)

	it("still accepts ordinary Update changes", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Normal", UserId = 8203 }
		persistence:Load(player)
		persistence:Update(player, function(profile)
			profile.Flags.OnboardingSeen = true
		end)
		expect((persistence:Save(player, 1))).toBe(true)
		expect(store:Peek("profile_8203").Flags.OnboardingSeen).toBe(true)
	end)
end)

--// Step 5: parallel shutdown saves under a shared deadline ---------------------

describe("step 5 (P1): shutdown saves run in parallel under a deadline", function()
	local function dirtyPlayers(store, count, firstUserId)
		local persistence = PlayerDataService.new(store)
		local players = {}
		for index = 1, count do
			local player = { Name = "Shut" .. index, UserId = firstUserId + index }
			persistence:Load(player)
			persistence:GrantReward(player, "run-final", 10 * index)
			table.insert(players, player)
		end
		Harness.setClock(0)
		return persistence, players
	end

	it("takes about as long as the slowest save, not the sum of all of them", function()
		local store = countingStore()
		local persistence, players = dirtyPlayers(store, 4, 9000)
		store.writeLatency = 3 -- every save sits in flight for three seconds

		local started = Harness.now()
		local failures = persistence:SaveAll(0)
		local elapsed = Harness.now() - started

		-- Serial: 4 x 3s = 12s. Parallel: bounded by the slowest single write.
		expect(elapsed).toBeGreaterThanOrEqual(3)
		expect(elapsed).toBeLessThan(3.2)
		expect(#failures).toBe(0)
		for index, player in players do
			expect(store:Peek("profile_" .. player.UserId).Currency.Salvage).toBe(10 * index)
		end
	end)

	it("returns at the 25s deadline when one write hangs, and names the one that timed out", function()
		local store = countingStore()
		local persistence, players = dirtyPlayers(store, 4, 9100)
		store.writeLatency = 1
		local hanging = players[2]
		store.keyWriteLatency["profile_" .. hanging.UserId] = 40 -- would outlive Roblox's 30s cutoff

		local started = Harness.now()
		local failures = persistence:SaveAll(0)
		local elapsed = Harness.now() - started

		expect(elapsed).toBeGreaterThanOrEqual(25)
		expect(elapsed).toBeLessThan(25.2) -- not 43s, and not waiting on the hung write
		expect(#failures).toBe(1)
		expect(failures[1].player).toBe(hanging)
		expect(string.find(failures[1].error, "deadline", 1, true)).never().toBeNil()
		for _, player in players do
			if player ~= hanging then
				expect(store:Peek("profile_" .. player.UserId).Currency.Salvage).toBeGreaterThan(0)
			end
		end
	end)

	it("keeps one player's failure from stopping anyone else's save", function()
		local store = countingStore()
		local persistence, players = dirtyPlayers(store, 3, 9200)
		store.writeLatency = 1
		-- Corrupt player 1's session so saving it raises outside any retry: a stand-in for any
		-- unexpected error in one worker.
		persistence:GetSession(players[1]).revision = nil

		local ok, failures = pcall(function()
			return persistence:SaveAll(0)
		end)

		expect(ok).toBe(true) -- the shutdown handler itself must never throw
		expect(#failures).toBe(1)
		expect(failures[1].player).toBe(players[1])
		for index = 2, 3 do
			expect(store:Peek("profile_" .. players[index].UserId).Currency.Salvage).toBe(10 * index)
		end
	end)

	it("does not start a retry that could not finish before the deadline", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Doomed", UserId = 9301 }
		persistence:Load(player)
		persistence:GrantReward(player, "run-final", 5)
		store.failing = true -- every write fails from here on
		Harness.setClock(0)
		local callsBefore = store.calls

		-- A 3s budget. Backoff is 0.5s, then 1s, then 2s: that third pause would end past the
		-- deadline, so the worker has to stop there rather than sleep into the cutoff.
		local started = Harness.now()
		local failures = persistence:SaveAll(0, 3)
		local elapsed = Harness.now() - started

		expect(#failures).toBe(1)
		expect(elapsed).toBeLessThan(3)
		expect(store.calls - callsBefore).toBe(3)
	end)
end)

describe("step 5: the shutdown report", function()
	it("skips clean sessions, flags a timeout as one, and reports elapsed time", function()
		local store = countingStore()
		local persistence = PlayerDataService.new(store)
		local clean = { Name = "Clean", UserId = 9401 }
		local fast = { Name = "Fast", UserId = 9402 }
		local stuck = { Name = "Stuck", UserId = 9403 }
		for _, player in { clean, fast, stuck } do
			persistence:Load(player)
		end
		persistence:GrantReward(fast, "run-final", 1)
		persistence:GrantReward(stuck, "run-final", 1)
		store.writeLatency = 1
		store.keyWriteLatency["profile_9403"] = 60
		Harness.setClock(0)
		local writesBefore = store.writes

		local report = persistence:SaveAllOnShutdown(0)

		expect(report.attempted).toBe(2) -- nothing to write for the clean session, so no request
		expect(report.saved).toBe(1)
		expect(#report.failures).toBe(1)
		expect(report.failures[1].player).toBe(stuck)
		expect(report.failures[1].timedOut).toBe(true)
		expect(report.elapsed).toBeCloseTo(25, 0.1)
		expect(store.writes - writesBefore).toBe(1)
	end)
end)
