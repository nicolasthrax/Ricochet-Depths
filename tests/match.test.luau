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

local function build(seed)
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
	local guard = 0
	while ctx.enemies:GetActiveCount() > 0 and guard < 500 do
		guard += 1
		local enemy = ctx.enemies:GetEnemies()[1]
		local entry = {
			direction = enemy.facing.Magnitude > 0 and enemy.facing or Vector3.new(0, 0, 1),
			damage = 100,
			damagePerBounce = 0,
			contacts = 3,
			shooter = shooter,
		}
		local result = { Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part }
		ctx.match:HandleImpact(result, entry, clock)
	end
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
		expect(ctx.positions[player]).toEqual(RunConfig.LobbyPosition)
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

		ctx.enemies:Clear() -- simulate enemies being cleaned up without ever being killed
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

	it("scales payout with the salvage multiplier and clamps to the cap", function()
		reset()
		local RewardConfig = __require("RewardConfig")
		local UpgradeConfig = __require("UpgradeConfig")
		local PlayerState = __require("PlayerState")

		local state = PlayerState.new({ Name = "Rich", UserId = 16 })
		state.roomsCleared = 4
		state.kills = 30
		local plain = RewardService.Compute(state, "Extracted", true)

		state:AddUpgrade(UpgradeConfig.Get("Scavenger"))
		local boosted = RewardService.Compute(state, "Extracted", true)
		expect(boosted).toBeGreaterThan(plain)

		state.kills = 10 ^ 9
		expect(RewardService.Compute(state, "Extracted", true)).toBe(RewardConfig.MaxPerRun)
	end)

	it("pays less for a defeat than for an extraction", function()
		reset()
		local PlayerState = __require("PlayerState")
		local state = PlayerState.new({ Name = "Loser", UserId = 17 })
		state.roomsCleared = 2
		state.kills = 10
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
