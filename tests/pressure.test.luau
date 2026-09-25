-- Depth pressure: hunters come for a normal room that drags on. Runs through the real
-- MatchService, RoomService and EnemyService. (The haul at risk is in runloop.test.luau.)
local CoinDrops = __require("CoinDrops")
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local OrbDrops = __require("OrbDrops")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local TelemetryService = __require("TelemetryService")
local UpgradeService = __require("UpgradeService")

local States = RunConfig.States
local PLANE_Y = 3
local DT = 1 / 30

local function recorder()
	local remote = { calls = {} }
	function remote:FireClient(player, ...)
		table.insert(self.calls, { player = player, args = table.pack(...) })
	end
	function remote:FireAllClients(...)
		table.insert(self.calls, { player = "all", args = table.pack(...) })
	end
	function remote:Texts(kind)
		local texts = {}
		for _, call in self.calls do
			local payload = call.args[1]
			if type(payload) == "table" and payload.Kind == kind then
				table.insert(texts, payload.Text)
			end
		end
		return texts
	end
	return remote
end

local function build(options)
	options = options or {}
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local enemies = EnemyService.new(arena, PLANE_Y, 4)
	local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(4), nil, Random.new(99))
	local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
	local upgrades = UpgradeService.new(4)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults",
		"EnemyDefeated", "Notify", "SurgeOffer", "SurgeResolved" } do
		net[name] = recorder()
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
	local coins = CoinDrops.new(arena, Random.new(1))
	local match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = upgrades,
		projectiles = projectiles,
		rewards = RewardService.new(),
		telemetry = TelemetryService.new(nil),
		net = net,
		world = world,
		coins = coins,
		orbDrops = OrbDrops.new(arena),
		seed = 4,
		arsenal = { orbs = true, surge = true, combo = true, dash = true },
		route = options.route or {},
		planRun = function()
			return RunPlanner.Fixed(options.plan or { "Atrium", "Cistern" })
		end,
	})
	projectiles.OnImpact = function(result, entry)
		return match:HandleImpact(result, entry, Harness.now())
	end
	return { match = match, enemies = enemies, rooms = rooms, upgrades = upgrades, net = net, coins = coins }
end

local clock = 0
local function step(ctx, seconds)
	for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
		clock += DT
		ctx.enemies:Step(DT, clock)
		ctx.match:Step(DT, clock)
	end
end

local function startSolo(ctx)
	clock = 0
	local player = { Name = "Diver", UserId = 88 }
	ctx.match:RegisterPlayer(player)
	ctx.match:RequestStart(player, clock)
	step(ctx, RunConfig.StartCountdown + DT)
	expect(ctx.match:GetState()).toBe(States.Combat)
	return player, ctx.match:GetPlayerState(player)
end

local function hit(ctx, enemy, shooter)
	local entry = { direction = Vector3.new(0, 0, 1), damage = 999, damagePerBounce = 0, contacts = 1, shooter = shooter,
		wallBounces = 1 }
	ctx.match:HandleImpact({ Position = enemy.position, Normal = Vector3.new(0, 0, -1), Instance = enemy.part }, entry, clock)
end

local function clearRoom(ctx, player)
	__clearRoom(ctx.rooms, function()
		for _, enemy in ctx.enemies:GetEnemies() do
			if not enemy.hunter then
				hit(ctx, enemy, player)
			end
		end
	end, function(seconds)
		step(ctx, seconds)
	end)
	step(ctx, DT)
end

local function lastResults(ctx)
	local calls = ctx.net.RunResults.calls
	return calls[#calls] and calls[#calls].args[1]
end

-- Enemies still bite in these tests; a diver that cannot fall keeps a long room going.
local function unkillable(state)
	state.maxHealth = 1e7
	state.health = 1e7
end


--// depth pressure ----------------------------------------------------------------------

describe("depth pressure", function()
	local pressure = RunConfig.Pressure

	local function hunters(ctx)
		local list = {}
		for _, enemy in ctx.enemies:GetEnemies() do
			if enemy.hunter then
				table.insert(list, enemy)
			end
		end
		return list
	end

	it("counts down, then sends Swift hunters that drop nothing and never hold the room", function()
		local ctx = build({ route = { pressure = true } })
		local player, playerState = startSolo(ctx)
		unkillable(playerState)
		step(ctx, pressure.After - 2)
		expect(#hunters(ctx)).toBe(0)
		expect(ctx.match:GetRunSnapshot().Pressure.In).toBeLessThan(pressure.WarnSeconds + 1)

		step(ctx, 3)
		local first = hunters(ctx)
		expect(#first).toBe(1)
		expect(first[1].champion.Id).toBe(pressure.Champion)
		expect(first[1].coins).toBe(0)
		expect(ctx.match:GetRunSnapshot().Pressure.Active).toBe(true)
		expect(#ctx.net.Notify:Texts("Callout")).toBeGreaterThan(0)

		local required = ctx.enemies:GetRequiredCount()
		expect(required).toBe(#ctx.enemies:GetEnemies() - 1)

		-- Killing one earns no champion credit and drops no coins.
		local coinsBefore = #ctx.coins:GetActive()
		hit(ctx, first[1], player)
		expect(playerState.championKills).toBe(0)
		expect(#ctx.coins:GetActive()).toBe(coinsBefore)
	end)

	it("keeps sending them every Delay seconds, up to MaxAlive", function()
		local ctx = build({ route = { pressure = true } })
		local _, playerState = startSolo(ctx)
		unkillable(playerState)
		step(ctx, pressure.After + pressure.Delay * (pressure.MaxAlive + 2))
		expect(#hunters(ctx)).toBe(pressure.MaxAlive)
	end)

	it("sends the hunters away when the room clears", function()
		local ctx = build({ route = { pressure = true } })
		local player, playerState = startSolo(ctx)
		unkillable(playerState)
		step(ctx, pressure.After + 1)
		expect(#hunters(ctx)).toBe(1)
		clearRoom(ctx, player)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
		expect(#hunters(ctx)).toBe(0)
	end)

	it("leaves objective rooms and mini-bosses alone", function()
		local ctx = build({ route = { pressure = true }, plan = { "Reliquary", "Cistern" } })
		startSolo(ctx)
		expect(ctx.match:GetRunSnapshot().Pressure).toBeNil()
		local boss = build({ route = { pressure = true }, plan = { "ColossusHall", "Cistern" } })
		startSolo(boss)
		expect(boss.match:GetRunSnapshot().Pressure).toBeNil()
	end)

	it("takes a timed-out room's door reward away", function()
		local ctx = build({ route = { pressure = true } })
		local _, playerState = startSolo(ctx)
		unkillable(playerState)
		ctx.match._activeReward = "Treasure"
		step(ctx, RunConfig.RoomTimeLimit + 1)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
		expect(playerState.coins).toBe(0)
		expect(#ctx.net.Notify:Texts("Error")).toBeGreaterThan(0)
	end)

	it("is off unless the route asks for it", function()
		local ctx = build()
		local _, playerState = startSolo(ctx)
		unkillable(playerState)
		step(ctx, pressure.After + pressure.Delay)
		expect(#hunters(ctx)).toBe(0)
		expect(ctx.match:GetRunSnapshot().Pressure).toBeNil()
	end)
end)

describe("the pressure countdown on the HUD", function()
	local HudView = __require("HudView")

	it("counts down to the hunters, then warns while they come", function()
		local hud = HudView.new(Instance.new("Folder"))
		local combat = { State = States.Combat, RoomIndex = 4, RoomCount = 9, RoomName = "Cold Smelter", Zone = "Foundry",
			EnemiesRemaining = 3, Pressure = { In = RunConfig.Pressure.WarnSeconds + 5 } }
		hud:UpdateRun(combat)
		expect(hud.objectiveLabel.Text).toBe("3 targets left")
		combat.Pressure = { In = 5 }
		hud:UpdateRun(combat)
		expect(hud.objectiveLabel.Text).toBe("3 targets left  -  hunters in 5s")
		combat.Pressure = { Active = true }
		hud:UpdateRun(combat)
		expect(hud.objectiveLabel.Text).toBe("HUNTED!  -  3 targets left")
	end)
end)
