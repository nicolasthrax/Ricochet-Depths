-- Full run loop against the real RoomService, EnemyService, UpgradeService and ProjectileService.
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local TelemetryService = __require("TelemetryService")
local UpgradeService = __require("UpgradeService")

local States = RunConfig.States
local PLANE_Y = 3
local DT = 1 / 30

local function fakeRemote()
	local remote = { calls = {} }
	function remote:FireClient(player, payload)
		table.insert(self.calls, { player = player, payload = payload })
	end
	function remote:FireAllClients(...)
		table.insert(self.calls, { player = "all", payload = table.pack(...) })
	end
	function remote:Last()
		return self.calls[#self.calls]
	end
	function remote:Clear()
		table.clear(self.calls)
	end
	return remote
end

local function build(seed, planRun)
	local arena = Instance.new("Folder")
	arena.Name = "Arena"

	local enemies = EnemyService.new(arena, PLANE_Y, seed or 1)
	local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(seed or 1))
	local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
	local upgrades = UpgradeService.new(seed or 1)
	local rewards = RewardService.new()
	local telemetry = TelemetryService.new(nil)

	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
		net[name] = fakeRemote()
	end

	local positions = {}
	local world = {
		GetPosition = function(player)
			return positions[player] or Vector3.new(0, PLANE_Y, 0)
		end,
		Teleport = function(player, position)
			positions[player] = position
		end,
	}

	local match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = upgrades,
		projectiles = projectiles,
		rewards = rewards,
		telemetry = telemetry,
		net = net,
		world = world,
		planRun = planRun,
	})

	return {
		match = match, rooms = rooms, enemies = enemies, projectiles = projectiles,
		upgrades = upgrades, rewards = rewards, net = net, world = world,
		arena = arena, positions = positions,
	}
end

local clock = 0
local function reset()
	clock = 0
end
local function step(ctx, seconds)
	local frames = math.max(1, math.floor(seconds / DT + 0.5))
	for _ = 1, frames do
		clock += DT
		ctx.match:Step(DT, clock)
	end
end

-- Kills every enemy alive in the current room through the real impact path.
local function wipeRoom(ctx, shooter)
	__clearRoom(ctx.rooms, function()
		local guard = 0
		while ctx.enemies:GetActiveCount() > 0 and guard < 500 do
			guard += 1
			local enemy = ctx.enemies:GetEnemies()[1]
			local entry = {
				direction = enemy.facing.Magnitude > 0 and enemy.facing or Vector3.new(0, 0, 1),
				damage = 100,
				damagePerBounce = 0,
				contacts = 3,
				-- Banked, so Mirrors (which shrug off straight shots) die too.
				wallBounces = 1,
				shooter = shooter,
			}
			local result = { Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part }
			ctx.match:HandleImpact(result, entry, clock)
		end
	end, function(seconds)
		step(ctx, seconds)
	end)
	expect(ctx.enemies:GetActiveCount()).toBe(0)
end

local function chooseFirstOffer(ctx, player)
	local offer = ctx.upgrades:GetOffer(player)
	expect(offer).toBeTruthy()
	local card = ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
	expect(card).toBeTruthy()
	return card
end

describe("run loop", function()
	it("starts, clears every room, extracts and returns to the lobby", function()
		reset()
		local ctx = build(11)
		local player = { Name = "Solo", UserId = 7 }
		ctx.match:RegisterPlayer(player)

		expect(ctx.match:GetState()).toBe(States.Lobby)
		expect((ctx.match:RequestStart(player, clock))).toBe(true)
		expect(ctx.match:GetState()).toBe(States.Starting)

		step(ctx, RunConfig.StartCountdown + DT)
		expect(ctx.match:GetState()).toBe(States.Combat)
		expect(ctx.match:GetRunSnapshot().RoomIndex).toBe(1)
		expect(ctx.enemies:GetActiveCount()).toBeGreaterThan(0)

		for roomIndex = 1, RunConfig.RoomCount() do
			expect(ctx.match:GetRunSnapshot().RoomIndex).toBe(roomIndex)
			wipeRoom(ctx, player)
			step(ctx, DT)

			if roomIndex < RunConfig.RoomCount() then
				expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
				chooseFirstOffer(ctx, player)
				step(ctx, DT)
				expect(ctx.match:GetState()).toBe(States.Transition)
				step(ctx, RunConfig.TransitionDuration + DT)
				expect(ctx.match:GetState()).toBe(States.Combat)
			end
		end

		expect(ctx.match:GetState()).toBe(States.Results)
		local results = ctx.net.RunResults:Last().payload
		expect(results.Outcome).toBe("Extracted")
		expect(results.RoomsCleared).toBe(RunConfig.RoomCount())
		expect(results.EnemiesDefeated).toBeGreaterThan(0)
		expect(results.BestChain).toBe(3)
		expect(#results.Upgrades).toBe(RunConfig.RoomCount() - 1)
		expect(results.Reward).toBeGreaterThan(0)

		step(ctx, RunConfig.ResultsDuration + DT * 2)
		expect(ctx.match:GetState()).toBe(States.Lobby)
		expect(ctx.enemies:GetActiveCount()).toBe(0)
		expect(ctx.projectiles:GetActiveCount()).toBe(0)
		expect(ctx.positions[player]).toEqual(RunConfig.LobbyReturnPosition)
		expect(ctx.match:GetPlayerState(player).roomsCleared).toBe(0)
	end)

	it("can be replayed immediately with fully reset state", function()
		reset()
		local ctx = build(3)
		local player = { Name = "Repeat", UserId = 8 }
		ctx.match:RegisterPlayer(player)

		for run = 1, 3 do
			expect((ctx.match:RequestStart(player, clock))).toBe(true)
			step(ctx, RunConfig.StartCountdown + DT)
			for roomIndex = 1, RunConfig.RoomCount() do
				wipeRoom(ctx, player)
				step(ctx, DT)
				if roomIndex < RunConfig.RoomCount() then
					chooseFirstOffer(ctx, player)
					step(ctx, RunConfig.TransitionDuration + DT * 2)
				end
			end
			expect(ctx.match:GetState()).toBe(States.Results)
			step(ctx, RunConfig.ResultsDuration + DT * 2)
			expect(ctx.match:GetState()).toBe(States.Lobby)

			local state = ctx.match:GetPlayerState(player)
			expect(state.kills).toBe(0)
			expect(#state.upgradeOrder).toBe(0)
			expect(state.health).toBe(state.maxHealth)
			expect(ctx.enemies:GetActiveCount()).toBe(0)
			expect(run).toBe(run)
		end

		expect(#ctx.arena:FindFirstChild("EnemyPool"):GetChildren()).toBeGreaterThan(0)
	end)

	it("refuses to start a second run while one is in progress", function()
		reset()
		local ctx = build(5)
		local player = { Name = "Solo", UserId = 9 }
		ctx.match:RegisterPlayer(player)
		expect((ctx.match:RequestStart(player, clock))).toBe(true)
		local ok, reason = ctx.match:RequestStart(player, clock)
		expect(ok).toBe(false)
		expect(reason).toBe("a run is already in progress")
	end)

	it("ends in defeat when every participant is down", function()
		reset()
		local ctx = build(6)
		local player = { Name = "Doomed", UserId = 10 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)

		local state = ctx.match:GetPlayerState(player)
		state.invulnerableUntil = 0
		ctx.match:HandlePlayerContact(player, 9999, nil, clock)
		expect(state.alive).toBe(false)

		step(ctx, DT * 2)
		expect(ctx.match:GetState()).toBe(States.Results)
		local results = ctx.net.RunResults:Last().payload
		expect(results.Outcome).toBe("Defeated")
		expect(results.Survived).toBe(false)
	end)
end)

describe("soft-lock guards", function()
	it("clears a room whose enemies all vanish outside the damage path", function()
		reset()
		local ctx = build(12)
		local player = { Name = "Solo", UserId = 11 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		expect(ctx.match:GetState()).toBe(States.Combat)

		-- Enemies cleaned up without ever being killed: later waves still arrive (and can vanish
		-- the same way), and the room still clears.
		__clearRoom(ctx.rooms, function()
			ctx.enemies:Clear()
		end, function(seconds)
			step(ctx, seconds)
		end)
		step(ctx, DT * 2)
		expect(ctx.match:GetState()).never().toBe(States.Combat)
	end)

	it("force-clears a room that outlives the room time limit", function()
		reset()
		local ctx = build(13)
		local player = { Name = "Idle", UserId = 12 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)

		local state = ctx.match:GetPlayerState(player)
		local guard = 0
		while ctx.match:GetState() == States.Combat and guard < 20000 do
			guard += 1
			state.health = state.maxHealth -- never dies, never shoots
			state.alive = true
			step(ctx, DT)
		end
		expect(ctx.match:GetState()).never().toBe(States.Combat)
		expect(guard).toBeLessThan(20000)
	end)

	it("auto-picks an upgrade when nobody chooses, instead of stalling", function()
		reset()
		local ctx = build(14)
		local player = { Name = "Afk", UserId = 13 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		wipeRoom(ctx, player)
		step(ctx, DT)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)

		step(ctx, __require("UpgradeConfig").ChoiceTimeout + DT * 2)
		expect(ctx.match:GetState()).never().toBe(States.UpgradeChoice)
		expect(#ctx.match:GetPlayerState(player).upgradeOrder).toBe(1)
		expect(ctx.net.UpgradeResolved:Last().payload.Auto).toBe(true)
	end)

	it("ends the run when the last participant leaves", function()
		reset()
		local ctx = build(15)
		local player = { Name = "Leaver", UserId = 14 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		expect(ctx.match:IsRunActive()).toBe(true)

		ctx.match:UnregisterPlayer(player, clock)
		expect(ctx.match:IsRunActive()).toBe(false)
		expect(ctx.enemies:GetActiveCount()).toBe(0)
	end)
end)

describe("reward integrity", function()
	it("pays a completed run exactly once, however many completion events fire", function()
		reset()
		local ctx = build(16)
		local player = { Name = "Banker", UserId = 15 }
		ctx.match:RegisterPlayer(player)
		local state = ctx.match:RegisterPlayer(player)
		state.roomsCleared = 4
		state.kills = 20

		local first = ctx.rewards:Grant(1, player, 500)
		expect(first).toBe(500)
		local second, reason = ctx.rewards:Grant(1, player, 500)
		expect(second).toBe(0)
		expect(reason).toBe("already granted")
		expect(ctx.rewards:WasGranted(1, player)).toBe(true)
		expect(ctx.rewards:WasGranted(2, player)).toBe(false)
	end)

	it("scales payout with the coin multiplier and clamps to the cap", function()
		reset()
		local RewardConfig = __require("RewardConfig")
		local UpgradeConfig = __require("UpgradeConfig")
		local PlayerState = __require("PlayerState")

		local state = PlayerState.new({ Name = "Rich", UserId = 16 })
		state.roomsCleared = 4
		state.coins = 30
		local plain = RewardService.Compute(state, "Extracted", true)

		state:AddUpgrade(UpgradeConfig.Get("Scavenger"))
		local boosted = RewardService.Compute(state, "Extracted", true)
		expect(boosted).toBeGreaterThan(plain)

		state.coins = 10 ^ 9
		expect(RewardService.Compute(state, "Extracted", true)).toBe(RewardConfig.MaxPerRun)
	end)

	it("pays less for a defeat than for an extraction", function()
		reset()
		local PlayerState = __require("PlayerState")
		local state = PlayerState.new({ Name = "Loser", UserId = 17 })
		state.roomsCleared = 2
		state.coins = 10
		expect(RewardService.Compute(state, "Defeated", false))
			.toBeLessThan(RewardService.Compute(state, "Extracted", false))
	end)
end)

describe("fire gating", function()
	it("only accepts fire during combat", function()
		reset()
		local ctx = build(17)
		local player = { Name = "Gunner", UserId = 18 }
		ctx.match:RegisterPlayer(player)
		expect(ctx.match:IsAcceptingFire()).toBe(false)

		ctx.match:RequestStart(player, clock)
		expect(ctx.match:IsAcceptingFire()).toBe(false)
		step(ctx, RunConfig.StartCountdown + DT)
		expect(ctx.match:IsAcceptingFire()).toBe(true)

		wipeRoom(ctx, player)
		step(ctx, DT)
		expect(ctx.match:IsAcceptingFire()).toBe(false)
	end)

	it("rejects upgrade choices outside the choice state", function()
		reset()
		local ctx = build(18)
		local player = { Name = "Eager", UserId = 19 }
		ctx.match:RegisterPlayer(player)
		local card, reason = ctx.match:ChooseUpgrade(player, 1, "SharpEdge", clock)
		expect(card).toBeNil()
		expect(reason).toBe("not choosing upgrades")
	end)
end)

describe("persisted rewards", function()
	it("credits a completed run to the profile exactly once", function()
		reset()
		local PlayerDataService = __require("PlayerDataService")

		local store = __FakeDataStore.new()

		local persistence = PlayerDataService.new(store)
		local ctx = build(77)
		-- Rebuild the match with persistence attached, reusing the same collaborators.
		local MatchServiceModule = __require("MatchService")
		local match = MatchServiceModule.new({
			rooms = ctx.rooms,
			enemies = ctx.enemies,
			upgrades = ctx.upgrades,
			projectiles = ctx.projectiles,
			rewards = ctx.rewards,
			telemetry = nil,
			net = ctx.net,
			world = ctx.world,
			persistence = persistence,
			runKeyPrefix = "testjob",
		})
		ctx.match = match

		local player = { Name = "Saver", UserId = 4242 }
		persistence:Load(player)
		match:RegisterPlayer(player)
		match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)

		for roomIndex = 1, RunConfig.RoomCount() do
			wipeRoom(ctx, player)
			step(ctx, DT)
			if roomIndex < RunConfig.RoomCount() then
				chooseFirstOffer(ctx, player)
				step(ctx, RunConfig.TransitionDuration + DT * 2)
			end
		end

		local summary = ctx.net.RunResults:Last().payload
		expect(summary.Outcome).toBe("Extracted")
		expect(summary.Reward).toBeGreaterThan(0)
		expect(summary.RunKey).toBe("testjob-1")

		local profile = persistence:GetSession(player).profile
		-- The balance is the run's coins plus the coins for every level the run's experience passed.
		expect(summary.XpEarned).toBeGreaterThan(0)
		expect(profile.Progression.Xp).toBe(summary.XpEarned)
		expect(summary.Progress.Level).toBeGreaterThan(1)
		expect(summary.Progress.LeveledUp).toBe(true)
		expect(summary.LevelReward).toBeGreaterThan(0)
		expect(profile.Currency.Salvage).toBe(summary.Reward + summary.LevelReward)
		expect(profile.Stats.RunsExtracted).toBe(1)

		-- A replayed completion for the same run key pays nothing more, coins or experience.
		expect((persistence:GrantReward(player, "testjob-1", summary.Reward, summary.XpEarned))).toBe(0)
		expect(profile.Currency.Salvage).toBe(summary.Reward + summary.LevelReward)
		expect(profile.Progression.Xp).toBe(summary.XpEarned)
	end)

	it("still finishes a run when the profile failed to load", function()
		reset()
		local PlayerDataService = __require("PlayerDataService")
		local failingStore = {}
		function failingStore:UpdateAsync()
			error("datastore down", 0)
		end

		local persistence = PlayerDataService.new(failingStore)
		local ctx = build(78)
		local MatchServiceModule = __require("MatchService")
		ctx.match = MatchServiceModule.new({
			rooms = ctx.rooms, enemies = ctx.enemies, upgrades = ctx.upgrades,
			projectiles = ctx.projectiles, rewards = ctx.rewards, net = ctx.net,
			world = ctx.world, persistence = persistence, runKeyPrefix = "testjob",
		})

		local player = { Name = "Offline", UserId = 4243 }
		persistence:Load(player)
		expect(persistence:IsLoaded(player)).toBe(false)

		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		wipeRoom(ctx, player)
		step(ctx, DT)
		chooseFirstOffer(ctx, player)
		step(ctx, RunConfig.TransitionDuration + DT * 2)

		local state = ctx.match:GetPlayerState(player)
		state.invulnerableUntil = 0
		ctx.match:HandlePlayerContact(player, 9999, nil, clock)
		step(ctx, DT * 2)

		-- The run completes and reports a controlled zero payout rather than erroring.
		local summary = ctx.net.RunResults:Last().payload
		expect(summary.Outcome).toBe("Defeated")
		expect(summary.Reward).toBe(0)
	end)
end)

describe("MatchService run plans", function()
	it("plays the rooms its plan names, in order, and tells clients the zone", function()
		reset()
		local RunPlanner = __require("RunPlanner")
		local plans = 0
		local ctx = build(3, function()
			plans += 1
			return RunPlanner.Fixed({ "Cistern", "Smelter", "Rift" })
		end)
		local player = Harness.addPlayer("Planner")
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)

		local expected = { { "Drowned Cistern", "Ruins" }, { "Cold Smelter", "Foundry" }, { "The Rift", "Abyss" } }
		for index, room in expected do
			local snapshot = ctx.match:GetRunSnapshot()
			expect(snapshot.RoomIndex).toBe(index)
			expect(snapshot.RoomCount).toBe(3)
			expect(snapshot.RoomName).toBe(room[1])
			expect(snapshot.Zone).toBe(room[2])
			wipeRoom(ctx, player)
			step(ctx, DT)
			if index < 3 then
				chooseFirstOffer(ctx, player)
				step(ctx, DT)
				step(ctx, RunConfig.TransitionDuration + DT)
			end
		end
		expect(ctx.match:GetState()).toBe(States.Results)
		expect(ctx.net.RunResults:Last().payload.Outcome).toBe("Extracted")
		expect(plans).toBe(1)
		Harness.removePlayer(player)
	end)
end)

describe("room hazards in a run", function()
	it("burns a player standing in a laser gate, at most once per tick", function()
		reset()
		local RunPlanner = __require("RunPlanner")
		local RoomConfig = __require("RoomConfig")
		local ctx = build(5, function()
			return RunPlanner.Fixed({ "Conveyor" })
		end)
		local player = { Name = "Gated", UserId = 91 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		expect(ctx.match:GetState()).toBe(States.Combat)

		local gate = RoomConfig.GetLayout("Conveyor").Mechanics[1]
		ctx.positions[player] = Vector3.new((gate.From.X + gate.To.X) / 2, PLANE_Y, gate.From.Y)
		local state = ctx.match:GetPlayerState(player)
		local before = state.health
		-- Past spawn protection and through at least one full on period.
		step(ctx, RunConfig.SpawnInvulnerability + gate.OnTime + gate.OffTime + 0.5)
		local lost = before - state.health
		expect(lost).toBeGreaterThan(0)
		local maxBurns = math.ceil(gate.OnTime / RoomConfig.Mechanics.GateTick) + 1
		expect(lost).toBeLessThanOrEqual(maxBurns * RoomConfig.Mechanics.GateDamage)
	end)
end)

describe("boss room", function()
	it("reports the boss's health to clients and gives orbs the room's cover", function()
		reset()
		local RunPlanner = __require("RunPlanner")
		local RoomConfig = __require("RoomConfig")
		local RoomGeometry = __require("RoomGeometry")
		local ctx = build(8, function()
			return RunPlanner.Fixed({ "Throne" })
		end)
		local player = { Name = "Challenger", UserId = 92 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)

		local snapshot = ctx.match:GetRunSnapshot()
		expect(snapshot.Boss).toBeTruthy()
		expect(snapshot.Boss.Name).toBe("Warden Prime")
		expect(snapshot.Boss.Health).toBe(snapshot.Boss.MaxHealth)
		expect(snapshot.Boss.Phase).toBe(1)
		local footprints = RoomGeometry.Footprints(RoomConfig.GetLayout("Throne"), RoomConfig)
		expect(#ctx.enemies:GetObstacles()).toBe(#footprints)

		wipeRoom(ctx, player)
		step(ctx, DT)
		expect(ctx.match:GetRunSnapshot().Boss).toBeNil()
	end)

	it("ends out of time, not extracted, when the boss is outlasted rather than beaten", function()
		reset()
		local RunPlanner = __require("RunPlanner")
		local ctx = build(9, function()
			return RunPlanner.Fixed({ "Throne" })
		end)
		local player = { Name = "Hider", UserId = 96 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		local state = ctx.match:GetPlayerState(player)
		-- Past the ordinary room limit the fight goes on.
		state.invulnerableUntil = math.huge
		step(ctx, RunConfig.RoomTimeLimit + 1)
		expect(ctx.match:GetState()).toBe(RunConfig.States.Combat)
		expect(ctx.match:GetRunSnapshot().Boss).toBeTruthy()

		step(ctx, RunConfig.BossRoomTimeLimit - RunConfig.RoomTimeLimit)
		expect(ctx.match:GetState()).toBe(RunConfig.States.Results)
		local results = {}
		for _, call in ctx.net.RunResults.calls do
			table.insert(results, call.payload)
		end
		expect(results[#results].Outcome).toBe("TimedOut")
	end)
end)

describe("health regeneration", function()
	local function running()
		reset()
		local RunPlanner = __require("RunPlanner")
		local ctx = build(12, function()
			return RunPlanner.Fixed({ "Atrium", "Cistern" })
		end)
		local player = { Name = "Mender", UserId = 93 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		-- Park the player far from every enemy so nothing interrupts the regen.
		ctx.positions[player] = Vector3.new(0, PLANE_Y, -500)
		return ctx, ctx.match:GetPlayerState(player)
	end

	it("waits after a hit, then heals steadily, never past the maximum", function()
		local ctx, state = running()
		state.invulnerableUntil = 0
		state:ApplyDamage(40, clock)
		local hurt = state.health
		step(ctx, RunConfig.Regen.Delay - 0.5)
		expect(state.health).toBe(hurt)
		step(ctx, 2)
		expect(state.health).toBeGreaterThan(hurt)
		expect(state.health).toBeLessThanOrEqual(hurt + RunConfig.Regen.PerSecond * 2 + 0.01)
		step(ctx, 60)
		expect(state.health).toBe(state.maxHealth)
	end)

	it("heals faster with Mending, and never heals a downed player", function()
		local ctx, state = running()
		state.invulnerableUntil = 0
		state.stats.RegenBonus = 2
		state:ApplyDamage(50, clock)
		local hurt = state.health
		step(ctx, RunConfig.Regen.Delay + 1)
		expect(state.health - hurt).toBeGreaterThan(RunConfig.Regen.PerSecond + 1)

		state.alive = false
		state.health = 0
		step(ctx, 5)
		expect(state.health).toBe(0)
	end)
end)

describe("falling out of the world", function()
	it("puts a player who drops far below the floor back on the spawn pad", function()
		reset()
		local RunPlanner = __require("RunPlanner")
		local ctx = build(14, function()
			return RunPlanner.Fixed({ "Atrium", "Cistern" })
		end)
		local player = { Name = "Faller", UserId = 95 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		local landed = ctx.positions[player]

		-- A short hop below the floor is left alone; a real fall is caught.
		ctx.positions[player] = Vector3.new(landed.X, -5, landed.Z)
		step(ctx, DT)
		expect(ctx.positions[player].Y).toBe(-5)
		ctx.positions[player] = Vector3.new(landed.X + 40, -RunConfig.FallRescueDepth - 10, landed.Z)
		step(ctx, DT)
		local rescued = ctx.positions[player]
		expect(rescued.Y).toBeGreaterThan(0)
		expect((Vector3.new(rescued.X, 0, rescued.Z) - Vector3.new(landed.X, 0, landed.Z)).Magnitude).toBeLessThan(20)
		expect(ctx.match:GetPlayerState(player).alive).toBe(true)
	end)
end)

describe("WorldAdapter against a real character", function()
	it("teleports by CFrame, reads the same spot back as Position, and stops the fall", function()
		local WorldAdapter = __require("WorldAdapter")
		local player = Harness.addPlayer("Teleported")
		Harness.giveCharacter(player, Vector3.new(0, 3, 0))
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		root.AssemblyLinearVelocity = Vector3.new(0, -80, 0)
		expect(WorldAdapter.Teleport(player, Vector3.new(500, 5, 0))).toBe(true)
		expect((WorldAdapter.GetPosition(player) - Vector3.new(500, 8, 0)).Magnitude).toBeCloseTo(0)
		expect(root.AssemblyLinearVelocity).toBe(Vector3.zero)
		Harness.removePlayer(player)
	end)
end)

describe("heal before the boss", function()
	it("restores every live player to full when the Warden Vault is cleared", function()
		reset()
		local RunPlanner = __require("RunPlanner")
		local ctx = build(21, function()
			return RunPlanner.Fixed({ "WardenVault", "Throne" })
		end)
		local player = { Name = "Weary", UserId = 94 }
		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)
		local state = ctx.match:GetPlayerState(player)
		state.invulnerableUntil = 0
		state:ApplyDamage(70, clock)
		wipeRoom(ctx, player)
		step(ctx, DT)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
		expect(state.health).toBe(state.maxHealth)
	end)
end)
