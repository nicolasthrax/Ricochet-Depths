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
		local guard = 0
		while ctx.enemies:GetActiveCount() > 0 and guard < 500 do
			guard += 1
			local enemy = ctx.enemies:GetEnemies()[1]
			ctx.match:HandleImpact(
				{ Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part },
				{ direction = Vector3.new(0, 0, 1), damage = 100, damagePerBounce = 0, contacts = 1, shooter = player },
				clock
			)
		end
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
		expect(stored.Currency.Salvage).toBe(summary.Reward)
		expect(stored.GrantedRuns[summary.RunKey]).toBe(summary.Reward)
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
		expect(store.data["profile_5004"].Currency.Salvage).toBe(summary.Reward)
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
		expect(profile.GrantedRuns["run-2"]).toBe(50)
		-- In the store: the late change is written by a follow-up, with no further request.
		local stored = store:Peek(key)
		expect(stored.Currency.Salvage).toBe(150)
		expect(stored.GrantedRuns["run-2"]).toBe(50)
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
