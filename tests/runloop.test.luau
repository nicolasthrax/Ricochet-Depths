-- 3.0 run changes: the haul at risk and "Bank loot" extract points, the daily biome modifier and
-- its once-a-day bonus, the scripted first descent, card labels / recommendation / reroll /
-- respec / gradual unlocks, and the party and friend bonus. Real MatchService, RoomService,
-- EnemyService, UpgradeService and PlayerDataService throughout.
local CoinDrops = __require("CoinDrops")
local DailyModifierConfig = __require("DailyModifierConfig")
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")
local FriendCache = __require("FriendCache")
local MatchService = __require("MatchService")
local MetaConfig = __require("MetaConfig")
local PlayerDataService = __require("PlayerDataService")
local PlayerState = __require("PlayerState")
local ProjectileService = __require("ProjectileService")
local RewardConfig = __require("RewardConfig")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RouteConfig = __require("RouteConfig")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local States = RunConfig.States
local PLANE_Y = 3
local DT = 1 / 30
-- A wall-clock day whose modifier is known: day % 7 picks DailyModifierConfig.Modifiers[n + 1].
local function dayFor(modifierId)
	for index, modifier in DailyModifierConfig.Modifiers do
		if modifier.Id == modifierId then
			return 20000 * 7 + (index - 1)
		end
	end
	error("no modifier " .. modifierId)
end

local function recorder()
	local remote = { calls = {} }
	function remote:FireClient(player, ...)
		table.insert(self.calls, { player = player, args = table.pack(...) })
	end
	function remote:FireAllClients(...)
		table.insert(self.calls, { player = "all", args = table.pack(...) })
	end
	function remote:Last(player)
		for index = #self.calls, 1, -1 do
			if player == nil or self.calls[index].player == player then
				return self.calls[index].args[1]
			end
		end
		return nil
	end
	return remote
end

-- options: plan (room ids), doors, dailyModifiers, day (UTC day number), persistence,
-- areFriends, metaProvider.
local function build(options)
	options = options or {}
	local arena = Instance.new("Folder")
	local enemies = EnemyService.new(arena, PLANE_Y, 5)
	local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(5), nil, Random.new(5))
	local upgrades = UpgradeService.new(5)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults",
		"EnemyDefeated", "Notify", "SurgeOffer", "SurgeResolved" } do
		net[name] = recorder()
	end
	local positions = {}
	local clock = { day = options.day or dayFor("GoldRush") }
	local match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = upgrades,
		projectiles = ProjectileService.new(arena, arena, PLANE_Y),
		rewards = RewardService.new(),
		net = net,
		world = {
			GetPosition = function(player)
				return positions[player] or Vector3.new(0, PLANE_Y, 0)
			end,
			Teleport = function(player, position)
				positions[player] = position
			end,
		},
		coins = CoinDrops.new(arena, Random.new(5)),
		persistence = options.persistence,
		route = { doors = options.doors ~= false },
		dailyModifiers = options.dailyModifiers == true,
		wallClock = function()
			return clock.day * MetaConfig.SecondsPerDay + 3600
		end,
		areFriends = options.areFriends,
		metaProvider = options.metaProvider,
		planRun = options.plan and function()
			return RunPlanner.Fixed(options.plan)
		end or nil,
	})
	return {
		match = match, rooms = rooms, enemies = enemies, upgrades = upgrades, net = net,
		positions = positions, clock = clock,
	}
end

local now = 0
local function step(ctx, seconds)
	for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
		now += DT
		ctx.match:Step(DT, now)
	end
end

local nextUserId = 5000
local function newPlayer(name)
	nextUserId += 1
	return { Name = name or ("P" .. nextUserId), UserId = nextUserId }
end

local function start(ctx, players, options)
	now = 0
	for _, player in players do
		ctx.match:RegisterPlayer(player)
	end
	expect((ctx.match:RequestStart(players[1], now, options))).toBe(true)
	step(ctx, RunConfig.StartCountdown + DT)
	expect(ctx.match:GetState()).toBe(States.Combat)
end

local function clear(ctx, player)
	__clearRoom(ctx.rooms, function()
		for _, enemy in ctx.enemies:GetEnemies() do
			ctx.match:HandleImpact({ Position = enemy.position, Normal = Vector3.new(0, 0, -1), Instance = enemy.part },
				{ direction = Vector3.new(0, 0, 1), damage = 999, damagePerBounce = 0, contacts = 1, shooter = player, wallBounces = 1 },
				now)
		end
	end, function(seconds)
		step(ctx, seconds)
	end)
	step(ctx, DT)
end

-- Clears the room, takes the recommended card and votes for `door` (1 by default).
local function advance(ctx, player, door)
	clear(ctx, player)
	expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
	local offer = ctx.upgrades:GetOffer(player)
	ctx.match:ChooseUpgrade(player, offer.id, offer.recommended, now)
	ctx.match:ChooseDoor(player, door or 1, now)
	step(ctx, DT * 2)
end

--// the haul at risk ------------------------------------------------------------------

describe("Bank loot", function()
	it("offers a Bank loot door, last, after an extract point, and none after a normal room", function()
		local ctx = build({ plan = { "Atrium", "ColossusHall", "Cistern" } })
		local player = newPlayer()
		start(ctx, { player })
		clear(ctx, player)
		for _, door in ctx.match:GetRunSnapshot().Doors.Doors do
			expect(door.Reward).never().toBe("BankLoot")
		end
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, now)
		ctx.match:ChooseDoor(player, 1, now)
		step(ctx, DT * 2)
		step(ctx, RunConfig.TransitionDuration + DT)
		expect(ctx.match:GetRunSnapshot().RoomName).toBe(RunConfig.GetRoomById("ColossusHall").DisplayName)

		clear(ctx, player)
		local doors = ctx.match:GetRunSnapshot().Doors.Doors
		local last = doors[#doors]
		expect(last.Reward).toBe(RouteConfig.BankLoot.Id)
		expect(last.Kind).toBe("Extract")
		expect(#doors).toBe(RouteConfig.Doors + 1)
	end)

	it("banks the whole haul and a depth bonus when the Bank loot door wins", function()
		local ctx = build({ plan = { "ColossusHall", "Atrium" } })
		local player = newPlayer()
		start(ctx, { player })
		local state = ctx.match:GetPlayerState(player)
		clear(ctx, player)
		state.coins = 80
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, now)
		local doors = ctx.match:GetRunSnapshot().Doors.Doors
		ctx.match:ChooseDoor(player, #doors, now)
		step(ctx, DT * 2)
		expect(ctx.match:GetState()).toBe(States.Results)
		local summary = ctx.net.RunResults:Last(player)
		expect(summary.Outcome).toBe("Extracted")
		expect(summary.Banked).toBe(true)
		expect(summary.HaulLost).toBe(0)
		local expected = RewardService.Multiply(state, 80 + RewardConfig.PerRoomCleared + RewardConfig.BankBonusByZone.Ruins)
		expect(summary.Reward).toBe(expected)
	end)

	it("keeps descending on a tied or empty vote", function()
		local ctx = build({ plan = { "ColossusHall", "Atrium" } })
		local player = newPlayer()
		start(ctx, { player })
		clear(ctx, player)
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, now)
		step(ctx, RunConfig.DoorVoteSeconds + 1)
		expect(ctx.match:GetState()).never().toBe(States.Results)
	end)

	it("loses half the haul on defeat, and says how much", function()
		local ctx = build({ plan = { "Atrium", "Cistern" } })
		local player = newPlayer()
		start(ctx, { player })
		local state = ctx.match:GetPlayerState(player)
		state.coins = 40
		state.invulnerableUntil = 0
		state:ApplyDamage(10 ^ 6, now)
		step(ctx, DT)
		local summary = ctx.net.RunResults:Last(player)
		expect(summary.Outcome).toBe("Defeated")
		expect(summary.Haul).toBe(40)
		expect(summary.HaulLost).toBe(40 - math.floor(40 * RewardConfig.DefeatHaulShare))
		expect(summary.Banked).toBe(false)
	end)
end)

--// daily modifiers -------------------------------------------------------------------

describe("daily modifiers", function()
	it("has seven distinct modifiers, one per day of the week, the same everywhere", function()
		expect(#DailyModifierConfig.Modifiers).toBe(7)
		local seen = {}
		for day = 0, 6 do
			local modifier = DailyModifierConfig.ForDay(day)
			expect(seen[modifier.Id]).toBeNil()
			seen[modifier.Id] = true
			expect(type(modifier.Title)).toBe("string")
			expect(type(modifier.Text)).toBe("string")
			for stat in modifier.Stats or {} do
				expect(__require("UpgradeConfig").BaseStats[stat]).never().toBeNil()
			end
		end
		expect(DailyModifierConfig.ForDay(7).Id).toBe(DailyModifierConfig.ForDay(0).Id)
		local day = dayFor("SurgeDay")
		expect(DailyModifierConfig.Today(day * MetaConfig.SecondsPerDay + 5).Id).toBe("SurgeDay")
	end)

	it("bends every player's starting stats and shows on the HUD snapshot", function()
		local ctx = build({ dailyModifiers = true, day = dayFor("BouncyWalls"), plan = { "Atrium" } })
		local player = newPlayer()
		start(ctx, { player })
		local state = ctx.match:GetPlayerState(player)
		expect(state.stats.BounceBudget).toBe(UpgradeConfig.BaseStats.BounceBudget + 2)
		expect(ctx.match:GetRunSnapshot().Modifier.Id).toBe("BouncyWalls")
	end)

	it("changes enemies and champions on the days that say so", function()
		local glass = build({ dailyModifiers = true, day = dayFor("GlassDepths"), plan = { "Atrium" } })
		start(glass, { newPlayer() })
		expect(glass.enemies:GetModifiers().Health).toBeCloseTo(0.75)
		expect(glass.match:GetPlayerState(glass.match:GetParticipants()[1]).maxHealth).toBe(RunConfig.BaseHealth - 25)

		local hunt = build({ dailyModifiers = true, day = dayFor("ChampionHunt"), plan = { "Atrium" } })
		start(hunt, { newPlayer() })
		expect(hunt.rooms._championBonus).toBeCloseTo(0.25)
	end)

	it("is off unless the match asks for it", function()
		local ctx = build({ dailyModifiers = false, day = dayFor("BouncyWalls"), plan = { "Atrium" } })
		local player = newPlayer()
		start(ctx, { player })
		expect(ctx.match:GetPlayerState(player).stats.BounceBudget).toBe(UpgradeConfig.BaseStats.BounceBudget)
		expect(ctx.match:GetRunSnapshot().Modifier).toBeNil()
	end)

	it("pays its bonus to the first run of the day that clears a room, once", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local ctx = build({ dailyModifiers = true, persistence = persistence, plan = { "Atrium", "Cistern" } })
		local player = newPlayer()
		persistence:Load(player)
		local function runOnce()
			start(ctx, { player })
			clear(ctx, player)
			local state = ctx.match:GetPlayerState(player)
			state.invulnerableUntil = 0
			ctx.match:ChooseUpgrade(player, ctx.upgrades:GetOffer(player).id, ctx.upgrades:GetOffer(player).cards[1].Id, now)
			ctx.match:_finish("Defeated", now)
			local summary = ctx.net.RunResults:Last(player)
			step(ctx, RunConfig.ResultsDuration + 1)
			step(ctx, DT)
			return summary
		end
		expect(runOnce().DailyBonus).toBe(DailyModifierConfig.Bonus.Coins)
		expect(runOnce().DailyBonus).toBe(0)
		ctx.clock.day += 1
		expect(runOnce().DailyBonus).toBe(DailyModifierConfig.Bonus.Coins)
	end)

	it("pays nothing to a run that clears no room", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local ctx = build({ dailyModifiers = true, persistence = persistence, plan = { "Atrium" } })
		local player = newPlayer()
		persistence:Load(player)
		start(ctx, { player })
		ctx.match:_finish("Defeated", now)
		expect(ctx.net.RunResults:Last(player).DailyBonus).toBeNil()
	end)
end)

--// the first descent -----------------------------------------------------------------

describe("first descent", function()
	it("runs the scripted opening, then a normal run, with no modifier", function()
		local ctx = build({ dailyModifiers = true })
		local player = newPlayer()
		start(ctx, { player }, { firstDescent = true })
		local plan = ctx.match._plan
		expect(plan[1].Id).toBe("FirstPit")
		expect(plan[2].Id).toBe("FirstPair")
		expect(plan[3].Id).toBe("FirstElite")
		expect(#plan).toBe(3 + #RunConfig.RunShape)
		expect(ctx.match._slots[1]).toBe(false)
		expect(ctx.match:GetRunSnapshot().Modifier).toBeNil()
		expect(ctx.match:GetRunSnapshot().FirstDescent).toBe(true)
		-- The banner is the first thing they read.
		local banner = false
		for _, call in ctx.net.Notify.calls do
			if call.args[1].Text == RunConfig.FirstDescent.Banner then
				banner = true
			end
		end
		expect(banner).toBe(true)
	end)

	it("opens on a tight pack of harmless Drifters close to the spawn", function()
		local ctx = build()
		local player = newPlayer()
		start(ctx, { player }, { firstDescent = true })
		local spawnPoint = ctx.rooms:GetSpawnPoint()
		local enemies = ctx.enemies:GetEnemies()
		expect(#enemies).toBe(6)
		local centre = Vector3.zero
		for _, enemy in enemies do
			expect(enemy.archetype.Id).toBe("Drifter")
			expect(EnemyConfig.Archetypes.Drifter.ContactDamage).toBe(0)
			centre += enemy.position / #enemies
		end
		for _, enemy in enemies do
			expect((enemy.position - centre).Magnitude).toBeLessThan(8)
		end
		-- Close enough that the first shot lands in a few seconds.
		expect((centre - spawnPoint).Magnitude).toBeLessThan(60)
	end)

	it("offers Split Shot twice, and the duplicate brings Fusillade at once, before the Hoard Keeper", function()
		local ctx = build()
		local player = newPlayer()
		start(ctx, { player }, { firstDescent = true })
		for round = 1, 2 do
			clear(ctx, player)
			local offer = ctx.upgrades:GetOffer(player)
			local ids = {}
			for _, card in offer.cards do
				ids[card.Id] = true
			end
			expect(ids.SplitShot).toBe(true)
			ctx.match:ChooseUpgrade(player, offer.id, "SplitShot", now)
			if round == 2 then
				-- Try it now: the fusion, alone, straight after the duplicate.
				local fusion = ctx.upgrades:GetOffer(player)
				expect(#fusion.cards).toBe(1)
				expect(fusion.cards[1].Id).toBe("Fusillade")
				expect(ctx.net.UpgradeOffer:Last(player).Fusion).toBe(true)
				ctx.match:ChooseUpgrade(player, fusion.id, "Fusillade", now)
				expect(ctx.match:GetPlayerState(player):GetStacks("Fusillade")).toBe(1)
			end
			ctx.match:ChooseDoor(player, 1, now)
			step(ctx, DT * 2)
			step(ctx, RunConfig.TransitionDuration + DT)
			for _, room in ctx.match._plan do
				expect(room.Id).never().toBe(RouteConfig.GalleryRoom.Id)
			end
		end
		expect(ctx.match:GetRunSnapshot().RoomName).toBe("The Hoard Keeper")
		clear(ctx, player)
		local doors = ctx.match:GetRunSnapshot().Doors.Doors
		expect(doors[#doors].Reward).toBe("BankLoot")
	end)

	it("never offers a follow-up fusion outside the first descent", function()
		local ctx = build({ plan = { "Atrium", "Cistern", "Gallery" } })
		local player = newPlayer()
		start(ctx, { player })
		local state = ctx.match:GetPlayerState(player)
		state:AddUpgrade(UpgradeConfig.Get("SplitShot"))
		clear(ctx, player)
		local offer = ctx.upgrades:_open(player, state, { UpgradeConfig.Get("SplitShot") }, now)
		ctx.match:ChooseUpgrade(player, offer.id, "SplitShot", now)
		expect(ctx.upgrades:GetOffer(player)).toBeNil()
	end)

	it("bursts the Hoard Keeper's room into coins", function()
		local room = RunConfig.GetRoomById("FirstElite")
		expect(room.CoinBurst).toBeGreaterThan(0)
		expect(room.ExtractPoint).toBe(true)
		expect(room.Kind).toBe("Elite")
	end)

	it("marks the first descent done however it ends", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local ctx = build({ persistence = persistence })
		local player = newPlayer()
		persistence:Load(player)
		expect(persistence:GetPublicProfile(player).Flags.FirstDescentDone).toBe(false)
		start(ctx, { player }, { firstDescent = true })
		ctx.match:_finish("Defeated", now)
		expect(persistence:GetPublicProfile(player).Flags.FirstDescentDone).toBe(true)
	end)

	it("never marks a normal run as a first descent", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local ctx = build({ persistence = persistence, plan = { "Atrium" } })
		local player = newPlayer()
		persistence:Load(player)
		start(ctx, { player })
		ctx.match:_finish("Defeated", now)
		expect(persistence:GetPublicProfile(player).Flags.FirstDescentDone).toBe(false)
	end)
end)

--// cards -----------------------------------------------------------------------------

describe("card faces", function()
	it("gives every card a label of three words or fewer and an icon", function()
		for _, card in UpgradeConfig.Cards do
			expect(type(card.Label)).toBe("string")
			expect(#card.Label).toBeGreaterThan(0)
			expect(#string.split(card.Label, " ")).toBeLessThanOrEqual(3)
			expect(type(card.Icon)).toBe("string")
			expect(#card.Icon).toBeGreaterThan(0)
		end
	end)

	it("sends the label, icon and one RECOMMENDED tag to the client", function()
		local service = UpgradeService.new(3)
		local state = PlayerState.new(newPlayer())
		local offer = service:BuildOffer("p", state, 0)
		local payload = UpgradeService.ToClientPayload(offer, 0)
		local recommended = 0
		for _, card in payload.Cards do
			expect(card.Label).toBeTruthy()
			expect(card.Icon).toBeTruthy()
			if card.Recommended then
				recommended += 1
				expect(card.Id).toBe(offer.recommended)
			end
		end
		expect(recommended).toBe(1)
	end)

	it("recommends a fusion first, then a fusion's part, then the rarer card", function()
		local state = PlayerState.new(newPlayer())
		local get = UpgradeConfig.Get
		expect(UpgradeService.Recommend({ get("Plating"), get("Fusillade"), get("SplitShot") }, state).Id).toBe("Fusillade")
		expect(UpgradeService.Recommend({ get("Plating"), get("SplitShot") }, state).Id).toBe("SplitShot")
		expect(UpgradeService.Recommend({ get("Plating"), get("Hunter") }, state).Id).toBe("Hunter")
		expect(UpgradeService.Recommend({ get("Plating"), get("Scavenger") }, state).Id).toBe("Plating") -- a tie: the first
	end)
end)

describe("gradual unlocks", function()
	it("keeps a card out of the pool below its unlock level, and never gates an unknown level", function()
		local ignite = UpgradeConfig.Get("Ignite")
		expect(ignite.UnlockLevel).toBeGreaterThan(1)
		local state = PlayerState.new(newPlayer())
		expect(UpgradeService.IsEligible(ignite, state)).toBe(true) -- level unknown
		state:SetMeta({ level = 1 })
		expect(UpgradeService.IsEligible(ignite, state)).toBe(false)
		state:SetMeta({ level = ignite.UnlockLevel })
		expect(UpgradeService.IsEligible(ignite, state)).toBe(true)
	end)

	it("still offers a full hand at level 1", function()
		local state = PlayerState.new(newPlayer())
		state:SetMeta({ level = 1 })
		local offer = UpgradeService.new(9):BuildOffer("p", state, 0)
		expect(#offer.cards).toBe(UpgradeConfig.OffersPerEvent)
		for _, card in offer.cards do
			expect((card.UnlockLevel or 1) <= 1).toBe(true)
		end
	end)
end)

describe("respec", function()
	local function toRound(plan)
		local ctx = build({ plan = plan or { "Atrium", "Cistern", "Gallery", "Crossing" } })
		local player = newPlayer()
		start(ctx, { player })
		clear(ctx, player)
		return ctx, player
	end

	it("undoes the card just taken and reopens the same offer, once a run", function()
		local ctx, player = toRound()
		local state = ctx.match:GetPlayerState(player)
		local offer = ctx.upgrades:GetOffer(player)
		local ids = {}
		for _, card in offer.cards do
			table.insert(ids, card.Id)
		end
		local taken = offer.cards[1].Id
		ctx.match:ChooseUpgrade(player, offer.id, taken, now)
		expect(state:GetStacks(taken)).toBe(1)
		expect(ctx.net.UpgradeOffer:Last(player).CanRespec).toBe(true)

		expect((ctx.match:RespecCard(player, now))).toBe(true)
		expect(state:GetStacks(taken)).toBe(0)
		expect(table.find(state.upgradeOrder, taken)).toBeNil()
		local reopened = ctx.upgrades:GetOffer(player)
		expect(#reopened.cards).toBe(#ids)
		for index, card in reopened.cards do
			expect(card.Id).toBe(ids[index])
		end
		expect(ctx.net.UpgradeOffer:Last(player).CanRespec).toBe(false)

		ctx.match:ChooseUpgrade(player, reopened.id, reopened.cards[2].Id, now)
		expect(select(2, ctx.match:RespecCard(player, now))).toBe("respec spent")
	end)

	it("refuses while the offer is still open, and after the early rounds", function()
		local ctx, player = toRound()
		expect(select(2, ctx.match:RespecCard(player, now))).toBe("still choosing")
		ctx.match._upgradeRound = RunConfig.Cards.RespecRounds + 1
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, now)
		expect(select(2, ctx.match:RespecCard(player, now))).toBe("respec spent")
	end)

	it("recomputes stats when a card comes back off", function()
		local state = PlayerState.new(newPlayer())
		local before = state.maxHealth
		state:AddUpgrade(UpgradeConfig.Get("Plating"))
		expect(state.maxHealth).toBeGreaterThan(before)
		expect(state:RemoveUpgrade("Plating")).toBe(true)
		expect(state.maxHealth).toBe(before)
		expect(state:RemoveUpgrade("Plating")).toBe(false)
	end)
end)

describe("reroll", function()
	it("is free once a run, then spends a Reroll token through the purchase path", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local ctx = build({ persistence = persistence, plan = { "Atrium", "Cistern" } })
		local player = newPlayer()
		persistence:Load(player)
		start(ctx, { player })
		clear(ctx, player)
		local first = ctx.upgrades:GetOffer(player)
		expect(ctx.net.UpgradeOffer:Last(player).FreeRerolls).toBe(1)

		expect((ctx.match:RerollOffer(player, now))).toBe(true)
		local second = ctx.upgrades:GetOffer(player)
		expect(second.id).never().toBe(first.id)
		expect(ctx.net.UpgradeOffer:Last(player).FreeRerolls).toBe(0)

		-- No tokens: refused, the offer stands, and the player is told.
		local ok, reason = ctx.match:RerollOffer(player, now)
		expect(ok).toBe(false)
		expect(reason).toBe("insufficient rerolls")
		expect(ctx.upgrades:GetOffer(player).id).toBe(second.id)
		expect(ctx.net.Notify:Last(player).Kind).toBe("Error")

		persistence:GrantReward(player, "bundle", 0, 0, { Rerolls = 2 })
		expect((ctx.match:RerollOffer(player, now))).toBe(true)
		expect(persistence:GetBalance(player, "Rerolls")).toBe(1)
		expect(persistence:GetMetaLevels(player)[RunConfig.Cards.RerollUseId]).toBe(1)
		expect(ctx.net.UpgradeOffer:Last(player).Rerolls).toBe(1)
		persistence:Save(player, 1)
		expect(store:Peek("profile_" .. player.UserId).Currency.Rerolls).toBe(1)
	end)

	it("avoids the cards just shown where the pool allows", function()
		local service = UpgradeService.new(12)
		local state = PlayerState.new(newPlayer())
		local offer = service:BuildOffer("p", state, 0)
		local shown = {}
		for _, card in offer.cards do
			shown[card.Id] = true
		end
		local rerolled = service:Reroll("p", state, 0)
		for _, card in rerolled.cards do
			expect(shown[card.Id]).toBeNil()
		end
	end)
end)

--// party and friends -----------------------------------------------------------------

describe("party bonus", function()
	it("never touches a solo run, and adds coins per extra member up to the cap", function()
		local solo = build({ plan = { "Atrium" } })
		local alone = newPlayer()
		start(solo, { alone })
		expect(solo.match:GetPlayerState(alone).stats.CoinMultiplier).toBe(1)
		expect(solo.enemies:GetModifiers().Health).toBe(1)

		local party = build({ plan = { "Atrium" } })
		local members = { newPlayer(), newPlayer(), newPlayer(), newPlayer() }
		start(party, members)
		local bonus = math.min(3 * RewardConfig.Party.PerExtraMember, RewardConfig.Party.MaxBonus)
		expect(party.match:GetPlayerState(members[1]).stats.CoinMultiplier).toBeCloseTo(1 + bonus)
		expect(party.enemies:GetModifiers().Health).toBeCloseTo(1 + 3 * RunConfig.PartyScaling.EnemyHealthPerExtra)
	end)

	it("adds the friend bonus when a Roblox friend is in the party", function()
		local a, b, c = newPlayer(), newPlayer(), newPlayer()
		local ctx = build({
			plan = { "Atrium" },
			areFriends = function(x, y)
				return (x == a and y == b) or (x == b and y == a)
			end,
		})
		start(ctx, { a, b, c })
		local base = 2 * RewardConfig.Party.PerExtraMember
		expect(ctx.match:GetPlayerState(a).stats.CoinMultiplier).toBeCloseTo(1 + base + RewardConfig.Party.FriendBonus)
		expect(ctx.match:GetPlayerState(c).stats.CoinMultiplier).toBeCloseTo(1 + base)
	end)

	it("caches friendships looked up in the background, and forgets a player who leaves", function()
		local calls = 0
		local cache = FriendCache.new(function(x, y)
			calls += 1
			task.wait(1) -- a web call
			return x.UserId + y.UserId == 3
		end)
		local one, two, three = { UserId = 1 }, { UserId = 2 }, { UserId = 5 }
		cache:Learn(two, { one, two, three })
		expect(cache:AreFriends(one, two)).toBe(false) -- not known yet
		Harness.advance(2)
		expect(calls).toBe(2)
		expect(cache:AreFriends(one, two)).toBe(true)
		expect(cache:AreFriends(two, one)).toBe(true)
		expect(cache:AreFriends(two, three)).toBe(false)
		cache:Forget(one)
		expect(cache:AreFriends(one, two)).toBe(false)
	end)

	it("survives a lookup that throws", function()
		local cache = FriendCache.new(function()
			error("web call failed")
		end)
		cache:Learn({ UserId = 1 }, { { UserId = 2 } })
		expect(cache:AreFriends({ UserId = 1 }, { UserId = 2 })).toBe(false)
	end)
end)

describe("arrival", function()
	it("turns a teleported character to face the room", function()
		local WorldAdapter = __require("WorldAdapter")
		local player = Harness.addPlayer("Facer")
		Harness.giveCharacter(player, Vector3.new(0, 3, 0))
		expect(WorldAdapter.Teleport(player, Vector3.new(0, 0, 50), Vector3.new(0, 0, 0))).toBe(true)
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		expect(root.CFrame.LookVector.Z).toBeLessThan(-0.99)
		-- Without a target it simply lands.
		expect(WorldAdapter.Teleport(player, Vector3.new(5, 0, 5))).toBe(true)
		Harness.removePlayer(player)
	end)
end)
