-- The loop around the fighting: the haul at risk and the Surface Lift, depth pressure, and the
-- long-term sinks (the Deep Quiver and Deepen). Runs through the real MatchService, RoomService,
-- EnemyService, PlayerDataService and ShopService.
local CoinDrops = __require("CoinDrops")
local EnemyService = __require("EnemyService")
local FeatureFlags = __require("FeatureFlags")
local MatchService = __require("MatchService")
local OrbDrops = __require("OrbDrops")
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")
local PlayerState = __require("PlayerState")
local ProgressionConfig = __require("ProgressionConfig")
local ProjectileService = __require("ProjectileService")
local RewardConfig = __require("RewardConfig")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RouteConfig = __require("RouteConfig")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local ShopConfig = __require("ShopConfig")
local ShopService = __require("ShopService")
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

--// the haul ------------------------------------------------------------------------------

describe("the haul at risk", function()
	local function state(coins, roomsCleared)
		local playerState = PlayerState.new({ Name = "H", UserId = 1 })
		playerState.coins = coins
		playerState.roomsCleared = roomsCleared or 0
		return playerState
	end

	it("changes nothing when the haul is not at risk", function()
		expect(RewardService.Compute(state(100), "Defeated", false)).toBe(100)
		expect(RewardService.HaulValue(state(100), "Defeated", nil)).toBe(100)
	end)

	it("keeps only DefeatCoinKeep of it after a wipe or a run out of time", function()
		local haul = { depthMultiplier = 1.5 }
		local kept = math.floor(100 * RewardConfig.DefeatCoinKeep)
		expect(RewardService.Compute(state(100), "Defeated", false, 1, haul)).toBe(kept)
		expect(RewardService.Compute(state(100), "TimedOut", false, 1, haul)).toBe(kept)
	end)

	it("keeps it whole when the run collapsed or was abandoned", function()
		local haul = { depthMultiplier = 1.5 }
		expect(RewardService.HaulValue(state(100), "Aborted", haul)).toBe(100)
		expect(RewardService.HaulValue(state(100), "Abandoned", haul)).toBe(100)
	end)

	it("multiplies it by depth for getting out, and pays the extraction bonus only at the Throne", function()
		local haul = { depthMultiplier = RewardService.DepthMultiplier(3) }
		local rooms = 9 * RewardConfig.PerRoomCleared
		expect(RewardService.Compute(state(100, 9), "Extracted", true, 1, haul))
			.toBe(150 + rooms + RewardConfig.EliteBonus + RewardConfig.ExtractionBonus)
		local lift = { depthMultiplier = RewardService.DepthMultiplier(2) }
		-- The lift keeps the whole room bonus, not a defeat's share of it.
		expect(RewardService.Compute(state(100, 6), "Surfaced", false, 1, lift)).toBe(125 + 6 * RewardConfig.PerRoomCleared)
	end)

	it("grows the depth multiplier with each zone boss after the first", function()
		expect(RewardService.DepthMultiplier(0)).toBe(1)
		expect(RewardService.DepthMultiplier(1)).toBe(1)
		expect(RewardService.DepthMultiplier(2)).toBe(1 + RewardConfig.HaulDepthBonus)
		expect(RewardService.DepthMultiplier(3)).toBe(1 + 2 * RewardConfig.HaulDepthBonus)
	end)

	it("gives a lift no extraction experience", function()
		local surfaced = RewardService.Experience(state(0, 3), "Surfaced", false)
		local extracted = RewardService.Experience(state(0, 3), "Extracted", false)
		expect(extracted - surfaced).toBe(ProgressionConfig.Xp.Extracted)
	end)

	it("reports what a wipe cost on the results", function()
		local ctx = build({ route = { haul = true } })
		local player, playerState = startSolo(ctx)
		playerState.coins = 100
		ctx.match:HandlePlayerContact(player, 1e6, nil, clock + 10)
		step(ctx, DT)
		local results = lastResults(ctx)
		expect(results.Outcome).toBe("Defeated")
		expect(results.Haul).toBe(100)
		expect(results.HaulLost).toBe(100 - math.floor(100 * RewardConfig.DefeatCoinKeep))
		expect(results.Reward).toBe(math.floor(100 * RewardConfig.DefeatCoinKeep))
	end)

	it("shows the haul's multiplier in the run snapshot only when the haul is at risk", function()
		local on = build({ route = { haul = true } })
		startSolo(on)
		expect(on.match:GetRunSnapshot().Haul.Multiplier).toBe(1)
		local off = build()
		startSolo(off)
		expect(off.match:GetRunSnapshot().Haul).toBeNil()
	end)
end)

describe("the Surface Lift", function()
	local function toMiniBossDoors(route)
		local ctx = build({ route = route, plan = { "ColossusHall", "Smelter" } })
		local player, playerState = startSolo(ctx)
		clearRoom(ctx, player)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
		return ctx, player, playerState
	end

	it("is offered last after a mini-boss, at the depth it pays", function()
		local ctx = toMiniBossDoors({ doors = true, haul = true })
		local doors = ctx.match:GetRunSnapshot().Doors.Doors
		expect(#doors).toBe(RouteConfig.Doors + 1)
		local lift = doors[#doors]
		expect(lift.Kind).toBe("Lift")
		expect(lift.Reward).toBe("Lift")
		expect(string.find(lift.RewardText, "haul x1)", 1, true)).toBeTruthy()
	end)

	it("never appears without the haul at risk, or after an ordinary room", function()
		local ctx = toMiniBossDoors({ doors = true })
		expect(#ctx.match:GetRunSnapshot().Doors.Doors).toBe(RouteConfig.Doors)

		local ordinary = build({ route = { doors = true, haul = true } })
		local player = startSolo(ordinary)
		clearRoom(ordinary, player)
		for _, door in ordinary.match:GetRunSnapshot().Doors.Doors do
			expect(door.Kind).never().toBe("Lift")
		end
	end)

	it("ends the run as Surfaced and banks the whole haul when the group takes it", function()
		local ctx, player, playerState = toMiniBossDoors({ doors = true, haul = true })
		playerState.coins = 120
		local doors = ctx.match:GetRunSnapshot().Doors.Doors
		expect(ctx.match:ChooseDoor(player, #doors, clock)).toBe(true)
		step(ctx, DT * 2)
		expect(ctx.match:GetState()).toBe(States.Results)
		local results = lastResults(ctx)
		expect(results.Outcome).toBe("Surfaced")
		expect(results.HaulLost).toBe(0)
		expect(results.Reward).toBe(120 + RewardConfig.PerRoomCleared)
	end)

	it("is not taken by a silent group: the vote defaults to pushing on", function()
		local ctx = toMiniBossDoors({ doors = true, haul = true })
		step(ctx, RunConfig.DoorVoteSeconds + DT)
		expect(ctx.match:GetState()).toBe(States.Transition)
	end)
end)

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

--// the Deep Quiver and Deepen -----------------------------------------------------------

local function subject(userId)
	return { Name = "D" .. userId, UserId = userId }
end

local function funded(persistence, player, salvage)
	persistence:Load(player)
	persistence:GrantReward(player, "seed-" .. player.UserId, salvage)
	persistence:Save(player, 0)
	return player
end

local function newShop(persistence)
	return ShopService.new(persistence, { canShop = function()
		return true
	end })
end

local function armoryCost()
	local total = 0
	for itemId in ShopConfig.DeepenRequirements(FeatureFlags) do
		for _, cost in ShopConfig.Get(itemId).Costs do
			total += cost
		end
	end
	return total
end

local function maxArmory(shop, player)
	for itemId, level in ShopConfig.DeepenRequirements(FeatureFlags) do
		for _ = 1, level do
			expect((shop:Purchase(player, itemId, 0))).toBe(true)
		end
	end
end

describe("the Deep Quiver", function()
	it("adds an orb to every run per level", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(301), 6000)
		local shop = newShop(persistence)
		expect((shop:Purchase(player, "Quiver", 0))).toBe(true)
		local bonuses = shop:GetRunBonuses(player).stats
		expect(bonuses.OrbCount).toBe(1)

		local state = PlayerState.new(player)
		state:SetMeta({ stats = bonuses })
		state:ResetRun()
		expect(state:OrbCapacity()).toBe(4)
	end)
end)

describe("Deepen", function()
	it("is refused until every Armory upgrade is maxed", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(310), 500)
		local ok, reason = newShop(persistence):Deepen(player, 0)
		expect(ok).toBe(false)
		expect(reason).toBe("not ready")
		expect(persistence:GetDepthRank(player)).toBe(0)
	end)

	it("resets the Armory, keeps trails, and adds its coin bonus to every run from then on", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(311), armoryCost() + 150)
		local shop = newShop(persistence)
		maxArmory(shop, player)
		expect((shop:Purchase(player, "TrailEmber", 0))).toBe(true)

		local ok, result = shop:Deepen(player, 0)
		expect(ok).toBe(true)
		expect(result.Rank).toBe(1)
		persistence:Save(player, 1)

		local levels = persistence:GetMetaLevels(player)
		expect(levels.Vitality).toBeNil()
		expect(levels.Fortune).toBeNil()
		expect(levels.TrailEmber).toBe(1)
		expect(shop:GetRunBonuses(player).stats.RewardMultiplier).toBeCloseTo(ShopConfig.Deepen.RewardPerRank, 1e-9)

		local saved = store:Peek(PlayerDataConfig.KeyPrefix .. "311")
		expect(saved.DepthRank).toBe(1)
		expect(saved.MetaUpgrades.Vitality).toBeNil()
		expect(saved.MetaUpgrades.TrailEmber).toBe(1)
		expect(saved.Currency.Salvage).toBe(0)
	end)

	it("survives a reload on another server", function()
		local store = __FakeDataStore.new()
		local first = PlayerDataService.new(store)
		local player = funded(first, subject(312), armoryCost())
		local shop = newShop(first)
		maxArmory(shop, player)
		expect((shop:Deepen(player, 0))).toBe(true)
		first:Release(player, 1)

		local second = PlayerDataService.new(store)
		second:Load(player)
		expect(second:GetDepthRank(player)).toBe(1)
		expect(second:GetPublicProfile(player).DepthRank).toBe(1)
		expect(second:GetMetaLevels(player).Vitality).toBeNil()
	end)

	it("commits in order with purchases around it, even the same level bought again, in one save", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(313), armoryCost() + 500)
		local requires = ShopConfig.DeepenRequirements(FeatureFlags)
		-- Straight through the persistence layer, so nothing saves in between.
		for itemId, level in requires do
			local item = ShopConfig.Get(itemId)
			for owned = 1, level do
				expect(persistence:SpendOnUpgrade(player, itemId, owned, ShopConfig.CostFor(item, owned))).toBeTruthy()
			end
		end
		expect(persistence:Deepen(player, 1, requires)).toBe(1)
		local vitality = ShopConfig.Get("Vitality")
		expect(persistence:SpendOnUpgrade(player, "Vitality", 1, ShopConfig.CostFor(vitality, 1))).toBeTruthy()
		expect((persistence:Save(player, 1))).toBe(true)

		local saved = store:Peek(PlayerDataConfig.KeyPrefix .. "313")
		expect(saved.DepthRank).toBe(1)
		expect(saved.MetaUpgrades.Vitality).toBe(1)
		expect(saved.MetaUpgrades.Fortune).toBeNil()
		expect(saved.Currency.Salvage).toBe(500 - ShopConfig.CostFor(vitality, 1))
		expect(persistence:GetMetaLevels(player).Vitality).toBe(1)
		expect(persistence:GetBalance(player)).toBe(saved.Currency.Salvage)
	end)

	it("is undone and reported when the store no longer backs it", function()
		local store = __FakeDataStore.new()
		local serverA, serverB = PlayerDataService.new(store), PlayerDataService.new(store)
		local player = subject(314)
		funded(serverA, player, armoryCost())
		serverB:Load(player)
		-- Another server spends coins the Armory needed, so the last upgrade cannot commit.
		expect((newShop(serverB):Purchase(player, "TrailEmber", 0))).toBe(true)
		serverB:Save(player, 1)

		local requires = ShopConfig.DeepenRequirements(FeatureFlags)
		for itemId, level in requires do
			local item = ShopConfig.Get(itemId)
			for owned = 1, level do
				serverA:SpendOnUpgrade(player, itemId, owned, ShopConfig.CostFor(item, owned))
			end
		end
		expect(serverA:Deepen(player, 1, requires)).toBe(1)
		serverA:Save(player, 2)

		expect(serverA:GetDepthRank(player)).toBe(0)
		expect(store:Peek(PlayerDataConfig.KeyPrefix .. "314").DepthRank).toBe(0)
		local reported = false
		for _, rejection in serverA:TakePurchaseRejections(player) do
			if rejection.ItemId == "Deepen" then
				reported = true
			end
		end
		expect(reported).toBe(true)
	end)

	it("cannot be written through Update", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(315), 0 + 1)
		local ok = pcall(function()
			persistence:Update(player, function(profile)
				profile.DepthRank = 5
			end)
		end)
		expect(ok).toBe(false)
		expect(persistence:GetDepthRank(player)).toBe(0)
	end)

	it("stops at the deepest rank", function()
		expect(ShopConfig.CanDeepen({}, ShopConfig.Deepen.MaxRank, FeatureFlags)).toBe(false)
		expect(ShopConfig.ComputeBonuses({}, ShopConfig.Deepen.MaxRank + 5).RewardMultiplier)
			.toBeCloseTo(ShopConfig.Deepen.MaxRank * ShopConfig.Deepen.RewardPerRank, 1e-9)
	end)

	it("migrates a v8 profile to rank 0", function()
		local profile = PlayerDataService.Normalise({ SchemaVersion = 8, Currency = { Salvage = 12 } })
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.DepthRank).toBe(0)
		expect(profile.Currency.Salvage).toBe(12)
	end)
end)

--// the views ----------------------------------------------------------------------------

describe("haul, lift, pressure and Deepen views", function()
	local CardPickerView = __require("CardPickerView")
	local HudView = __require("HudView")
	local ResultsView = __require("ResultsView")
	local ShopView = __require("ShopView")

	it("the HUD calls run coins the haul, with its multiplier, and warns of hunters", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:UpdatePlayer({ Health = 90, MaxHealth = 100, Alive = true, Coins = 40, Upgrades = {} })
		expect(hud.coinLabel.Text).toBe("+40  Coins 40")
		local combat = { State = States.Combat, RoomIndex = 4, RoomCount = 9, RoomName = "Cold Smelter", Zone = "Foundry",
			EnemiesRemaining = 3, Haul = { Multiplier = 1.25 }, Pressure = { In = 5 } }
		hud:UpdateRun(combat)
		expect(hud.coinLabel.Text).toBe("Haul 40  x1.25")
		expect(hud.objectiveLabel.Text).toBe("3 targets left  -  hunters in 5s")
		combat.Pressure = { Active = true }
		hud:UpdateRun(combat)
		expect(hud.objectiveLabel.Text).toBe("HUNTED!  -  3 targets left")
		hud:UpdateRun({ State = States.Lobby, RoomIndex = 0, RoomCount = 0, RoomName = "", EnemiesRemaining = 0 })
		expect(hud.coinLabel.Text).toBe("Coins 40")
	end)

	it("the card picker fits a third door for the lift and marks it as the way out", function()
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end)
		view:SetDoors({ SecondsLeft = 9, Doors = {
			{ Id = 1, RoomName = "Cold Smelter", Zone = "Foundry", Kind = "Normal", RewardTitle = "Mending Spring", RewardText = "Heal" },
			{ Id = 2, RoomName = "Forgeworks", Zone = "Foundry", Kind = "Normal", RewardTitle = "Armoury", RewardText = "Cards" },
			{ Id = 3, RoomName = "Surface Lift", Kind = "Lift", RewardTitle = "Bank the haul", RewardText = "Leave" },
		} })
		expect(view:ShowDoors()).toBe(true)
		local lift = view.row:FindFirstChild("Door3")
		expect(lift:FindFirstChild("Kind").Text).toBe("LEAVE THE RUN")
		expect(lift.Size.X.Scale * 3).toBeLessThan(1)
	end)

	it("the results say what the depths took, or what depth paid", function()
		local function texts(view)
			local list = {}
			for _, row in view._rows do
				table.insert(list, row.Text)
			end
			return table.concat(list, "\n")
		end
		local base = { RoomsCleared = 3, RoomCount = 9, EnemiesDefeated = 20, BestChain = 2, ShotsFired = 30,
			DamageTaken = 50, DurationSeconds = 100, CurrencyName = "Coins", Upgrades = {} }
		local view = ResultsView.new(Instance.new("Folder"), function() end)
		local lost = table.clone(base)
		lost.Outcome, lost.Reward, lost.Haul, lost.HaulLost = "Defeated", 40, 100, 60
		view:Show(lost)
		expect(string.find(texts(view), "Haul lost to the depths: 60 of 100", 1, true)).toBeTruthy()
		local surfaced = table.clone(base)
		surfaced.Outcome, surfaced.Reward, surfaced.Haul, surfaced.HaulBonus = "Surfaced", 150, 100, 25
		view:Show(surfaced)
		expect(view.title.Text).toBe("Surfaced")
		expect(string.find(texts(view), "Depth bonus on the haul: +25", 1, true)).toBeTruthy()
	end)

	it("the shop's Deepen row locks until the Armory is maxed, then needs a second tap", function()
		local deepened = 0
		local view = ShopView.new(Instance.new("Folder"), function() end, function() end, nil, function()
			deepened += 1
		end)
		local button = view._rows.Deepen.button
		view:SetProfile({ Salvage = 0, MetaUpgrades = {}, DepthRank = 0 })
		expect(button.Text).toBe("Locked")
		button.Activated:Fire()
		expect(deepened).toBe(0)

		view:SetProfile({ Salvage = 0, MetaUpgrades = ShopConfig.DeepenRequirements(FeatureFlags), DepthRank = 2 })
		expect(button.Text).toBe("Deepen")
		expect(string.find(view._rows.Deepen.level.Text, "Depth Rank 2", 1, true)).toBeTruthy()
		button.Activated:Fire()
		expect(button.Text).toBe("Confirm?")
		expect(deepened).toBe(0)
		button.Activated:Fire()
		expect(deepened).toBe(1)
	end)
end)
