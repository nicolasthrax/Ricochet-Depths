-- 2-4 player co-op: shared run ownership, independent fire, per-player offers, leave/join rules.
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local TelemetryService = __require("TelemetryService")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local States = RunConfig.States
local PLANE_Y = 3
local DT = 1 / 30
local clock = 0

local function fakeRemote()
	local remote = { calls = {} }
	function remote:FireClient(player, payload)
		table.insert(self.calls, { player = player, payload = payload })
	end
	function remote:FireAllClients(...)
		table.insert(self.calls, { player = "all", payload = table.pack(...) })
	end
	function remote:CountFor(target)
		local total = 0
		for _, call in self.calls do
			if call.player == target then
				total += 1
			end
		end
		return total
	end
	return remote
end

local function build(seed)
	local arena = Instance.new("Folder")
	local enemies = EnemyService.new(arena, PLANE_Y, seed)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
		net[name] = fakeRemote()
	end
	local positions = {}
	local upgrades = UpgradeService.new(seed)
	local match = MatchService.new({
		rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(seed)),
		enemies = enemies,
		upgrades = upgrades,
		projectiles = ProjectileService.new(arena, arena, PLANE_Y),
		rewards = RewardService.new(),
		telemetry = TelemetryService.new(nil),
		net = net,
		world = {
			GetPosition = function(player)
				return positions[player] or Vector3.new(0, PLANE_Y, 0)
			end,
			Teleport = function(player, position)
				positions[player] = position
			end,
		},
	})
	return { match = match, enemies = enemies, upgrades = upgrades, net = net, positions = positions }
end

local function step(ctx, seconds)
	for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
		clock += DT
		ctx.match:Step(DT, clock)
	end
end

local function makePlayers(count)
	local players = {}
	for index = 1, count do
		table.insert(players, { Name = "P" .. index, UserId = 100 + index })
	end
	return players
end

local function wipeRoom(ctx, shooter)
	local guard = 0
	while ctx.enemies:GetActiveCount() > 0 and guard < 800 do
		guard += 1
		local enemy = ctx.enemies:GetEnemies()[1]
		ctx.match:HandleImpact(
			{ Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part },
			{ direction = Vector3.new(0, 0, 1), damage = 100, damagePerBounce = 0, contacts = 2, shooter = shooter },
			clock
		)
	end
end

local function resolveAllOffers(ctx, players)
	for _, player in players do
		local offer = ctx.upgrades:GetOffer(player)
		if offer then
			ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
		end
	end
end

describe("co-op run ownership", function()
	for _, count in { 2, 3, 4 } do
		it(string.format("runs a full descent with %d players", count), function()
			clock = 0
			local ctx = build(50 + count)
			local players = makePlayers(count)
			for _, player in players do
				ctx.match:RegisterPlayer(player)
			end

			-- One player starting pulls in everyone registered in the lobby.
			expect((ctx.match:RequestStart(players[1], clock))).toBe(true)
			expect(#ctx.match:GetParticipants()).toBe(count)
			step(ctx, RunConfig.StartCountdown + DT)
			expect(ctx.match:GetState()).toBe(States.Combat)

			for roomIndex = 1, RunConfig.RoomCount() do
				wipeRoom(ctx, players[1])
				step(ctx, DT)
				if roomIndex < RunConfig.RoomCount() then
					expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
					-- Policy A: every player gets their own offer.
					for _, player in players do
						expect(ctx.upgrades:GetOffer(player)).toBeTruthy()
					end
					resolveAllOffers(ctx, players)
					step(ctx, RunConfig.TransitionDuration + DT * 2)
					expect(ctx.match:GetState()).toBe(States.Combat)
				end
			end

			expect(ctx.match:GetState()).toBe(States.Results)
			for _, player in players do
				expect(ctx.net.RunResults:CountFor(player)).toBe(1)
				expect(ctx.match:GetPlayerState(player).roomsCleared).toBe(RunConfig.RoomCount())
			end
		end)
	end

	it("waits for every player's choice before advancing", function()
		clock = 0
		local ctx = build(61)
		local players = makePlayers(3)
		for _, player in players do
			ctx.match:RegisterPlayer(player)
		end
		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)
		wipeRoom(ctx, players[1])
		step(ctx, DT)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)

		local first = ctx.upgrades:GetOffer(players[1])
		ctx.match:ChooseUpgrade(players[1], first.id, first.cards[1].Id, clock)
		step(ctx, DT)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice) -- two still owe a choice

		local second = ctx.upgrades:GetOffer(players[2])
		ctx.match:ChooseUpgrade(players[2], second.id, second.cards[1].Id, clock)
		step(ctx, DT)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)

		-- The third never answers; the timeout resolves it rather than deadlocking the run.
		step(ctx, UpgradeConfig.ChoiceTimeout + DT * 2)
		expect(ctx.match:GetState()).never().toBe(States.UpgradeChoice)
		expect(#ctx.match:GetPlayerState(players[3]).upgradeOrder).toBe(1)
	end)

	it("keeps each player's upgrades separate", function()
		clock = 0
		local ctx = build(62)
		local players = makePlayers(2)
		for _, player in players do
			ctx.match:RegisterPlayer(player)
		end
		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)
		wipeRoom(ctx, players[1])
		step(ctx, DT)

		local offerA = ctx.upgrades:GetOffer(players[1])
		local offerB = ctx.upgrades:GetOffer(players[2])
		expect(offerA.id).never().toBe(offerB.id)

		ctx.match:ChooseUpgrade(players[1], offerA.id, offerA.cards[1].Id, clock)
		-- A player cannot spend someone else's offer.
		local stolen, reason = ctx.match:ChooseUpgrade(players[1], offerB.id, offerB.cards[1].Id, clock)
		expect(stolen).toBeNil()
		expect(reason).toBe("no pending offer")
		expect(#ctx.match:GetPlayerState(players[2]).upgradeOrder).toBe(0)
	end)
end)

describe("co-op membership changes", function()
	it("continues the run when one of several players leaves", function()
		clock = 0
		local ctx = build(63)
		local players = makePlayers(3)
		for _, player in players do
			ctx.match:RegisterPlayer(player)
		end
		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)

		ctx.match:UnregisterPlayer(players[3], clock)
		expect(ctx.match:IsRunActive()).toBe(true)
		expect(#ctx.match:GetParticipants()).toBe(2)
		expect(ctx.match:GetPlayerState(players[3])).toBeNil()

		step(ctx, DT * 3)
		expect(ctx.match:GetState()).toBe(States.Combat)
	end)

	it("ends the run only when the last player leaves", function()
		clock = 0
		local ctx = build(64)
		local players = makePlayers(2)
		for _, player in players do
			ctx.match:RegisterPlayer(player)
		end
		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)

		ctx.match:UnregisterPlayer(players[1], clock)
		expect(ctx.match:IsRunActive()).toBe(true)
		ctx.match:UnregisterPlayer(players[2], clock)
		expect(ctx.match:IsRunActive()).toBe(false)
		expect(ctx.enemies:GetActiveCount()).toBe(0)
	end)

	it("admits a late joiner at the next room boundary, not mid-fight", function()
		clock = 0
		local ctx = build(65)
		local players = makePlayers(2)
		ctx.match:RegisterPlayer(players[1])
		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)
		expect(ctx.match:GetState()).toBe(States.Combat)

		local latecomer = players[2]
		ctx.match:RegisterPlayer(latecomer)
		expect(ctx.match:IsPendingJoin(latecomer)).toBe(true)
		expect(ctx.match:IsParticipant(latecomer)).toBe(false)

		step(ctx, DT * 5)
		expect(ctx.match:IsParticipant(latecomer)).toBe(false) -- still waiting, mid-fight

		wipeRoom(ctx, players[1])
		step(ctx, DT)
		resolveAllOffers(ctx, { players[1] })
		step(ctx, RunConfig.TransitionDuration + DT * 2)

		expect(ctx.match:IsParticipant(latecomer)).toBe(true)
		expect(ctx.match:IsPendingJoin(latecomer)).toBe(false)
		local state = ctx.match:GetPlayerState(latecomer)
		expect(#state.upgradeOrder).toBe(0)
		expect(state.health).toBe(state.maxHealth)
		expect(ctx.positions[latecomer]).toBeTruthy() -- teleported into the new room
	end)

	it("keeps the run alive while one player is down", function()
		clock = 0
		local ctx = build(66)
		local players = makePlayers(2)
		for _, player in players do
			ctx.match:RegisterPlayer(player)
		end
		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)

		local downed = ctx.match:GetPlayerState(players[2])
		downed.invulnerableUntil = 0
		ctx.match:HandlePlayerContact(players[2], 9999, nil, clock)
		expect(downed.alive).toBe(false)

		step(ctx, DT * 3)
		expect(ctx.match:GetState()).toBe(States.Combat)

		-- The downed player comes back at the start of the next room.
		wipeRoom(ctx, players[1])
		step(ctx, DT)
		resolveAllOffers(ctx, players)
		step(ctx, RunConfig.TransitionDuration + DT * 2)
		expect(downed.alive).toBe(true)
		expect(downed.health).toBe(downed.maxHealth)
	end)

	it("ends in defeat only when every participant is down", function()
		clock = 0
		local ctx = build(67)
		local players = makePlayers(3)
		for _, player in players do
			ctx.match:RegisterPlayer(player)
		end
		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)

		for index, player in players do
			local state = ctx.match:GetPlayerState(player)
			state.invulnerableUntil = 0
			ctx.match:HandlePlayerContact(player, 9999, nil, clock)
			step(ctx, DT)
			if index < #players then
				expect(ctx.match:GetState()).toBe(States.Combat)
			end
		end

		step(ctx, DT * 2)
		expect(ctx.match:GetState()).toBe(States.Results)
	end)
end)

describe("per-player fire authority", function()
	it("rate limits each player independently", function()
		clock = 0
		local ctx = build(68)
		local players = makePlayers(2)
		local characters = {}
		for _, player in players do
			ctx.match:RegisterPlayer(player)
			-- FireValidator needs a live character, which the harness can build.
			local harnessPlayer = Harness.addPlayer(player.Name .. "Real")
			characters[player] = Harness.giveCharacter(harnessPlayer, Vector3.new(0, 3, 0))
			player.Character = characters[player]
		end

		ctx.match:RequestStart(players[1], clock)
		step(ctx, RunConfig.StartCountdown + DT)
		expect(ctx.match:IsAcceptingFire()).toBe(true)

		Harness.setClock(1000)
		expect((ctx.match:HandleFire(players[1], Vector3.new(0, 0, 1), 1, clock))).toBe(true)
		-- Same player again immediately: refused.
		expect((ctx.match:HandleFire(players[1], Vector3.new(0, 0, 1), 1, clock))).toBe(false)
		-- A different player is unaffected by the first player's cooldown.
		expect((ctx.match:HandleFire(players[2], Vector3.new(0, 0, 1), 1, clock))).toBe(true)
	end)

	it("refuses fire from a downed player", function()
		clock = 0
		local ctx = build(69)
		local player = { Name = "Down", UserId = 500 }
		local harnessPlayer = Harness.addPlayer("DownReal")
		player.Character = Harness.giveCharacter(harnessPlayer, Vector3.new(0, 3, 0))

		ctx.match:RegisterPlayer(player)
		ctx.match:RequestStart(player, clock)
		step(ctx, RunConfig.StartCountdown + DT)

		local state = ctx.match:GetPlayerState(player)
		state.alive = false
		Harness.setClock(2000)
		local ok, reason = ctx.match:HandleFire(player, Vector3.new(0, 0, 1), 1, clock)
		expect(ok).toBe(false)
		expect(reason).toBe("player is down")
	end)
end)
