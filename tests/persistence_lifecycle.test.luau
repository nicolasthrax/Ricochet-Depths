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
		expect(persistence:GetSession(player).dirty).toBe(true)
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
