-- 2.0, the redesign: orbs, bounce power, the dash, combo, Surge, waves, objective rooms,
-- barrels, boost pads, portals, ricochet-aware enemies, mini-bosses, doors and challenges.
-- Everything runs through the real MatchService, RoomService, EnemyService and ProjectileService.
local ArsenalConfig = __require("ArsenalConfig")
local CoinDrops = __require("CoinDrops")
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local ObjectiveConfig = __require("ObjectiveConfig")
local OrbDrops = __require("OrbDrops")
local PlayerState = __require("PlayerState")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomConfig = __require("RoomConfig")
local RoomMechanics = __require("RoomMechanics")
local RoomService = __require("RoomService")
local RouteConfig = __require("RouteConfig")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local TelemetryService = __require("TelemetryService")
local UpgradeConfig = __require("UpgradeConfig")
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
	function remote:Kinds(kind)
		local count = 0
		for _, call in self.calls do
			local payload = call.args[1]
			if type(payload) == "table" and payload.Kind == kind then
				count += 1
			end
		end
		return count
	end
	return remote
end

-- A production-shaped match: orbs, Surge, combo, doors and challenges switched on.
local function build(options)
	options = options or {}
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local enemies = EnemyService.new(arena, PLANE_Y, options.seed or 4)
	local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(options.seed or 4), nil, Random.new(99))
	local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
	local upgrades = UpgradeService.new(options.seed or 4)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults",
		"EnemyDefeated", "Notify", "SurgeOffer", "SurgeResolved" } do
		net[name] = recorder()
	end
	local positions = {}
	local walkSpeeds = {}
	local world = {
		GetPosition = function(player)
			return positions[player] or Vector3.new(0, PLANE_Y, 0)
		end,
		Teleport = function(player, position)
			positions[player] = position
		end,
		SetWalkSpeed = function(player, speed)
			walkSpeeds[player] = speed
		end,
	}
	local orbDrops = OrbDrops.new(arena)
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
		orbDrops = orbDrops,
		seed = options.seed or 4,
		arsenal = { orbs = true, surge = true, combo = true, dash = true },
		route = options.route or {},
		planRun = options.planRun,
	})
	projectiles.OnImpact = function(result, entry)
		return match:HandleImpact(result, entry, Harness.now())
	end
	return {
		match = match, enemies = enemies, rooms = rooms, projectiles = projectiles, upgrades = upgrades,
		net = net, positions = positions, orbDrops = orbDrops, coins = coins, arena = arena, walkSpeeds = walkSpeeds,
	}
end

local clock = 0
local function step(ctx, seconds)
	for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
		clock += DT
		ctx.match:Step(DT, clock)
	end
end

local function startSolo(ctx, name, plan)
	clock = 0
	local player = { Name = name or "Hero", UserId = 77 }
	ctx.match:RegisterPlayer(player)
	ctx.match:RequestStart(player, clock)
	step(ctx, RunConfig.StartCountdown + DT)
	expect(ctx.match:GetState()).toBe(States.Combat)
	local _ = plan
	return player, ctx.match:GetPlayerState(player)
end

-- A real player with a character, for paths that go through FireValidator.
local function armed(ctx, player)
	local real = Harness.addPlayer(player.Name .. "Real")
	player.Character = Harness.giveCharacter(real, Vector3.new(0, 3, 0))
	return player
end

local function hit(ctx, enemy, shooter, extra)
	local entry = { direction = Vector3.new(0, 0, 1), damage = 1, damagePerBounce = 0, contacts = 1, shooter = shooter }
	for key, value in extra or {} do
		entry[key] = value
	end
	ctx.match:HandleImpact({ Position = enemy.position, Normal = Vector3.new(0, 0, -1), Instance = enemy.part }, entry, clock)
	return entry
end

local function fixed(ids)
	return function()
		return RunPlanner.Fixed(ids)
	end
end

--// orbs ---------------------------------------------------------------------------

describe("orbs", function()
	it("spend one per throw, whatever the fan, and refuse a throw with an empty hand", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		armed(ctx, player)
		state:AddUpgrade(UpgradeConfig.Get("SplitShot"))
		local capacity = state:OrbCapacity()
		expect(state.orbsHeld).toBe(capacity)
		for throw = 1, capacity do
			Harness.setClock(100 + throw)
			expect((ctx.match:HandleFire(player, Vector3.new(0, 0, 1), 1, clock))).toBe(true)
		end
		expect(state.orbsHeld).toBe(0)
		Harness.setClock(200)
		local ok, reason = ctx.match:HandleFire(player, Vector3.new(0, 0, 1), 1, clock)
		expect(ok).toBe(false)
		expect(reason).toBe("no orbs")
		-- Two projectiles per throw, but only one of each pair carries the orb.
		local carriers = 0
		for _, entry in ctx.projectiles:GetActive() do
			if entry.carriesOrb then
				carriers += 1
			end
		end
		expect(carriers).toBe(capacity)
	end)

	it("drop where a shot stops, come back when walked over, and roll home if left", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		state:TakeOrb()
		local entry = { carriesOrb = true, shooter = player }
		ctx.match:_onShotExpired(entry, Vector3.new(30, PLANE_Y, 30))
		expect(ctx.orbDrops:GetActiveCount()).toBe(1)
		expect(state.orbsHeld).toBe(state:OrbCapacity() - 1)

		-- Standing far away: nothing until the orb has rested, then it rolls home.
		ctx.positions[player] = Vector3.new(-40, PLANE_Y, -40)
		step(ctx, ArsenalConfig.Orbs.ReturnDelay * 0.5)
		expect(ctx.orbDrops:GetActiveCount()).toBe(1)
		step(ctx, ArsenalConfig.Orbs.ReturnDelay + 4)
		expect(ctx.orbDrops:GetActiveCount()).toBe(0)
		expect(state.orbsHeld).toBe(state:OrbCapacity())

		-- Walking over a fresh one picks it up at once.
		state:TakeOrb()
		ctx.match:_onShotExpired({ carriesOrb = true, shooter = player }, Vector3.new(10, PLANE_Y, 0))
		ctx.positions[player] = Vector3.new(10, PLANE_Y, 1)
		step(ctx, DT)
		expect(state.orbsHeld).toBe(state:OrbCapacity())
	end)

	it("return straight to hand after a trick shot kill", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		state:TakeOrb()
		local mite = ctx.enemies:Spawn("Mite", Vector3.new(20, PLANE_Y, 20))
		local entry = hit(ctx, mite, player, { carriesOrb = true, wallBounces = ArsenalConfig.Orbs.TrickShotBounces })
		expect(mite.dead).toBe(true)
		expect(entry.orbReturned).toBe(true)
		expect(state.orbsHeld).toBe(state:OrbCapacity())
		expect(state.trickShots).toBe(1)
		-- Its flight ending later drops nothing: the orb is already home.
		ctx.match:_onShotExpired(entry, mite.position)
		expect(ctx.orbDrops:GetActiveCount()).toBe(0)
	end)

	it("all come home when a room starts, and a new orb arrives in hand", function()
		local ctx = build({ planRun = fixed({ "Atrium", "Cistern" }) })
		local _, state = startSolo(ctx)
		state:TakeOrb()
		state:TakeOrb()
		state:AddUpgrade(UpgradeConfig.Get("ExtraOrb"))
		expect(state:OrbCapacity()).toBe(UpgradeConfig.BaseStats.OrbCount + 1)
		expect(state.orbsHeld).toBe(UpgradeConfig.BaseStats.OrbCount - 1)
		ctx.match:_resetOrbs()
		expect(state.orbsHeld).toBe(state:OrbCapacity())
	end)
end)

--// bounce power ---------------------------------------------------------------------

describe("bounce power", function()
	it("makes each wall bounce add damage, speed and size", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		local part = Instance.new("Part")
		local entry = { direction = Vector3.new(0, 0, 1), damage = 1, damagePerBounce = 0, contacts = 1, shooter = player,
			stats = state.stats, speed = 100, baseSpeed = 100, part = part, wallBounces = 0 }
		local wall = Instance.new("Part")
		for _ = 1, 2 do
			ctx.match:HandleImpact({ Position = Vector3.zero, Normal = Vector3.new(0, 0, -1), Instance = wall }, entry, clock)
		end
		expect(entry.wallBounces).toBe(2)
		expect(entry.speed).toBeGreaterThan(100)
		expect(part.Size.X).toBeGreaterThan(0.9)
		local chaser = ctx.enemies:Spawn("Chaser", Vector3.new(30, PLANE_Y, 30))
		entry.contacts = 3
		ctx.match:HandleImpact({ Position = chaser.position, Normal = Vector3.new(0, 0, -1), Instance = chaser.part }, entry, clock)
		-- Base 1 damage, +50% per bounce, twice: 2.
		expect(chaser.health).toBe(chaser.maxHealth - 2)
	end)

	it("caps a shot's speed however often it bounces", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local entry = { speed = 100, baseSpeed = 100, wallBounces = 0 }
		for _ = 1, 40 do
			ctx.match:_onBounce(entry)
		end
		expect(entry.speed).toBeCloseTo(100 * ArsenalConfig.Bounce.MaxSpeedMultiplier, 1e-6)
	end)
end)

--// ricochet-aware enemies -----------------------------------------------------------

describe("ricochet-aware enemies", function()
	it("Mirrors shrug off a straight shot but not a banked one", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player = startSolo(ctx)
		local mirror = ctx.enemies:Spawn("Mirror", Vector3.new(20, PLANE_Y, 0))
		hit(ctx, mirror, player, { damage = 5 })
		expect(mirror.health).toBe(mirror.maxHealth)
		hit(ctx, mirror, player, { damage = 1, wallBounces = 1 })
		expect(mirror.health).toBeLessThan(mirror.maxHealth)
	end)

	it("Sponges soak up a shot's remaining bounces", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player = startSolo(ctx)
		local sponge = ctx.enemies:Spawn("Sponge", Vector3.new(20, PLANE_Y, 0))
		local entry = hit(ctx, sponge, player, { bouncesLeft = 5 })
		expect(entry.bouncesLeft).toBe(0)
	end)

	it("Magnets bend a passing shot toward themselves", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		startSolo(ctx)
		local magnet = ctx.enemies:Spawn("Magnet", Vector3.new(10, PLANE_Y, 10))
		ctx.enemies:Step(DT, clock)
		expect(#ctx.enemies:GetMagnets()).toBe(1)
		local entry = { direction = Vector3.new(0, 0, 1), speed = 60 }
		ctx.match:_steerShot(entry, Vector3.new(0, PLANE_Y, 0), Vector3.new(0, PLANE_Y, 2))
		expect(entry.direction.X).toBeGreaterThan(0)
		expect(entry.direction.Magnitude).toBeCloseTo(1, 1e-6)
		local _ = magnet
	end)

	it("a Treasure Runner never holds a room open, and gets away if not caught", function()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		local escaped = false
		enemies.OnEscape = function()
			escaped = true
		end
		enemies:SetTargetProvider(function()
			return { { player = "p", position = Vector3.new(0, PLANE_Y, 0) } }
		end)
		local runner = enemies:Spawn("TreasureRunner", Vector3.new(5, PLANE_Y, 0))
		expect(enemies:GetRequiredCount()).toBe(0)
		enemies:Step(DT, DT)
		local start = runner.position
		for frame = 2, 30 do
			enemies:Step(DT, frame * DT)
		end
		-- It runs from the player.
		expect(runner.position.Magnitude).toBeGreaterThan(start.Magnitude)
		enemies:Step(DT, EnemyConfig.Archetypes.TreasureRunner.EscapeAfter + 1)
		expect(runner.dead).toBe(true)
		expect(escaped).toBe(true)
	end)
end)

--// mini-bosses ----------------------------------------------------------------------

describe("mini-bosses", function()
	local function spawnAt(archetype)
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		local hits = {}
		enemies.OnPlayerContact = function(player, damage)
			table.insert(hits, { player = player, damage = damage })
		end
		local positions = { near = Vector3.new(3, PLANE_Y, 0), far = Vector3.new(40, PLANE_Y, 0) }
		enemies:SetTargetProvider(function()
			return {
				{ player = "near", position = positions.near },
				{ player = "far", position = positions.far },
			}
		end)
		return enemies, enemies:Spawn(archetype, Vector3.new(0, PLANE_Y, 0)), hits
	end

	it("the Forge Press flashes its slam zone, then slams only whoever is under it", function()
		local enemies, press, hits = spawnAt("ForgePress")
		local slam = press.archetype.Slam
		local now = 0
		while press.phase ~= "Telegraph" and now < slam.Interval + 1 do
			now += DT
			enemies:Step(DT, now)
		end
		expect(press.part:GetAttribute("SlamRadius")).toBe(slam.Radius)
		local before = enemies:GetOrbsFired()
		now += slam.TelegraphTime + DT
		enemies:Step(DT, now)
		enemies:Step(DT, now + DT)
		local nearHit = false
		for _, contact in hits do
			expect(contact.player).never().toBe("far")
			nearHit = nearHit or contact.player == "near"
		end
		expect(nearHit).toBe(true)
		expect(enemies:GetOrbsFired() - before).toBe(slam.RingCount)
		expect(press.part:GetAttribute("SlamRadius")).toBeNil()
	end)

	it("the Colossus stomps out rings, and shakes Mites loose once hurt", function()
		local enemies, colossus = spawnAt("Colossus")
		local stomp = colossus.archetype.Stomp
		local now = 0
		for _ = 1, math.ceil((stomp.Interval + stomp.TelegraphTime + 0.5) / DT) do
			now += DT
			enemies:Step(DT, now)
		end
		expect(enemies:GetOrbsFired()).toBeGreaterThanOrEqual(stomp.RingCount)
		colossus.health = colossus.maxHealth * 0.3
		for _ = 1, math.ceil((stomp.Interval + stomp.TelegraphTime + 0.5) / DT) do
			now += DT
			enemies:Step(DT, now)
		end
		local mites = 0
		for _, enemy in enemies:GetEnemies() do
			if enemy.archetypeId == "Mite" then
				mites += 1
			end
		end
		expect(mites).toBeGreaterThan(0)
	end)

	it("show on the boss bar", function()
		local ctx = build({ planRun = fixed({ "ColossusHall" }) })
		startSolo(ctx)
		local boss = ctx.match:GetRunSnapshot().Boss
		expect(boss).toBeTruthy()
		expect(boss.Name).toBe("The Colossus")
	end)
end)

--// the dash --------------------------------------------------------------------------

describe("the dash", function()
	it("grants a moment of invulnerability and keeps its cooldown", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		clock += 5
		expect((ctx.match:HandleDash(player, Vector3.new(1, 0, 0), clock))).toBe(true)
		local health = state.health
		ctx.match:HandlePlayerContact(player, 20, nil, clock + 0.1)
		expect(state.health).toBe(health)
		expect((ctx.match:HandleDash(player, Vector3.new(1, 0, 0), clock + 0.5))).toBe(false)
		expect((ctx.match:HandleDash(player, Vector3.new(1, 0, 0), clock + ArsenalConfig.Dash.Cooldown))).toBe(true)
	end)

	it("Blink Strike hits enemies along the path, and Recall calls orbs home", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		state:AddUpgrade(UpgradeConfig.Get("BlinkStrike"))
		state:AddUpgrade(UpgradeConfig.Get("Recall"))
		ctx.positions[player] = Vector3.new(0, PLANE_Y, 0)
		local inPath = ctx.enemies:Spawn("Chaser", Vector3.new(8, PLANE_Y, 0))
		local aside = ctx.enemies:Spawn("Chaser", Vector3.new(0, PLANE_Y, 30))
		state:TakeOrb()
		ctx.match:_onShotExpired({ carriesOrb = true, shooter = player }, Vector3.new(-40, PLANE_Y, 40))
		clock += 5
		ctx.match:HandleDash(player, Vector3.new(1, 0, 0), clock)
		expect(inPath.health).toBe(inPath.maxHealth - 2)
		expect(aside.health).toBe(aside.maxHealth)
		step(ctx, 1)
		expect(state.orbsHeld).toBe(state:OrbCapacity())
	end)

	it("is refused outside combat and for the downed", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player = { Name = "Early", UserId = 5 }
		ctx.match:RegisterPlayer(player)
		expect((ctx.match:HandleDash(player, Vector3.new(1, 0, 0), 1))).toBe(false)
	end)
end)

--// combo ----------------------------------------------------------------------------

describe("combo", function()
	it("builds on kills, counts ricochet kills double, halves on a hit and runs out", function()
		local state = PlayerState.new({ Name = "C", UserId = 1 })
		state:AddCombo(1, 0)
		state:AddCombo(2, 1)
		expect(state.combo).toBe(3)
		state:DamageCombo()
		expect(state.combo).toBe(1)
		expect(state:ExpireCombo(1 + ArsenalConfig.Combo.Window + 0.01)).toBe(true)
		expect(state.combo).toBe(0)
		expect(state.bestCombo).toBe(3)
	end)

	it("multiplies the coins its kills drop once a tier is reached, and announces the tier", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		local tier2 = ArsenalConfig.Combo.Tiers[2]
		state.combo = tier2.At
		state.comboExpiresAt = clock + 10
		local chaser = ctx.enemies:Spawn("Chaser", Vector3.new(30, PLANE_Y, 30))
		local before = 0
		for _, coin in ctx.coins:GetActive() do
			before += coin.value
		end
		hit(ctx, chaser, player, { damage = 99 })
		local after = 0
		for _, coin in ctx.coins:GetActive() do
			after += coin.value
		end
		expect(after - before).toBe(math.floor(chaser.archetype.Coins * tier2.Multiplier + 0.5))
		expect(state.comboXp).toBeGreaterThan(0)
	end)
end)

--// Surge ----------------------------------------------------------------------------

describe("Surge", function()
	it("fills from kills and offers three perks from its own pool", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		local needed = ArsenalConfig.SurgeNeeded(1)
		for index = 1, needed do
			local mite = ctx.enemies:Spawn("Mite", Vector3.new(10 + index, PLANE_Y, 30))
			hit(ctx, mite, player)
		end
		local offers = ctx.net.SurgeOffer.calls
		expect(#offers).toBe(1)
		local payload = offers[1].args[1]
		expect(#payload.Cards).toBe(ArsenalConfig.Surge.Offers)
		for _, card in payload.Cards do
			expect(UpgradeConfig.IsMinor(UpgradeConfig.Get(card.Id))).toBe(true)
		end
		local chosen = ctx.match:ChooseSurge(player, payload.OfferId, payload.Cards[2].Id, clock)
		expect(chosen.Id).toBe(payload.Cards[2].Id)
		expect(state.surgeLevel).toBe(2)
		-- Perks never show up in the card list.
		for _, upgrade in state:ToSnapshot().Upgrades do
			expect(UpgradeConfig.IsMinor(UpgradeConfig.Get(upgrade.Id))).toBe(false)
		end
	end)

	it("picks for you when ignored, and never lets a perk into a room offer", function()
		local ctx = build({ planRun = fixed({ "Atrium" }) })
		local player, state = startSolo(ctx)
		state.surge = ArsenalConfig.SurgeNeeded(1)
		ctx.match:_grantSurge(player, 0, clock)
		expect(#ctx.net.SurgeOffer.calls).toBe(1)
		step(ctx, ArsenalConfig.Surge.ChoiceTimeout + 0.2)
		local resolved = ctx.net.SurgeResolved.calls
		expect(#resolved).toBe(1)
		expect(resolved[1].args[1].Auto).toBe(true)
		for _ = 1, 30 do
			for _, card in ctx.upgrades:BuildOffer("x", state, 0).cards do
				expect(UpgradeConfig.IsMinor(card)).toBe(false)
			end
		end
	end)
end)

--// room mechanics ---------------------------------------------------------------------

describe("barrels, boost pads, portals and loot", function()
	local function buildRoom(layoutId)
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 1)
		local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(1))
		for _, room in RunConfig.Rooms do
			if room.Layout == layoutId then
				rooms:Load(room, 0)
				return rooms, enemies
			end
		end
		error("no room uses " .. layoutId)
	end

	it("sets a barrel off with one shot, and it sets off its neighbours", function()
		local ctx = build({ planRun = fixed({ "ForgeHall" }) })
		local player = startSolo(ctx)
		local room = ctx.arena:FindFirstChild("Room")
		local mechanics = ctx.rooms:GetMechanics()
		local barrel = room:FindFirstChild("Barrel1")
		expect(barrel).toBeTruthy()
		local victim = ctx.enemies:Spawn("Chaser", barrel.Position + Vector3.new(4, 0, 0))
		ctx.match:HandleImpact({ Position = barrel.Position, Normal = Vector3.new(0, 0, 1), Instance = barrel },
			{ direction = Vector3.new(0, 0, 1), damage = 1, damagePerBounce = 0, contacts = 1, shooter = player }, clock)
		expect(barrel.CanQuery).toBe(false)
		expect(victim.health).toBeLessThan(victim.maxHealth)
		-- Spent: a second shot finds nothing to set off.
		expect(mechanics:HandleImpact(barrel)).toBeNil()
	end)

	it("chains barrels that stand within each other's blast", function()
		local layout = {
			InteriorSize = Vector2.new(100, 100),
			Mechanics = {
				{ Kind = "Barrel", Offset = Vector2.new(0, 0), Size = Vector2.new(4, 4) },
				{ Kind = "Barrel", Offset = Vector2.new(8, 0), Size = Vector2.new(4, 4) },
				{ Kind = "Barrel", Offset = Vector2.new(60, 0), Size = Vector2.new(4, 4) },
			},
		}
		local room = Instance.new("Folder")
		for index, spec in layout.Mechanics do
			local part = Instance.new("Part")
			part.Name = "Barrel" .. index
			part.Position = Vector3.new(spec.Offset.X, 2, spec.Offset.Y)
			part.Parent = room
		end
		local mechanics = RoomMechanics.new(room, layout, Vector3.zero)
		local what, blast = mechanics:HandleImpact(room:FindFirstChild("Barrel1"))
		expect(what).toBe("Exploded")
		local chained = mechanics:DetonateNear(blast.position, blast.radius)
		expect(#chained).toBe(1)
		expect(#mechanics:DetonateNear(chained[1].position, chained[1].radius)).toBe(0)
	end)

	it("boosts a shot once per pad, and portals move it to the partner", function()
		local rooms = buildRoom("Conveyor")
		local mechanics = rooms:GetMechanics()
		local entry = { speed = 100, bouncesLeft = 2, direction = Vector3.new(1, 0, 0) }
		mechanics:ApplySegment(entry, Vector3.new(-45, PLANE_Y, 0), Vector3.new(-35, PLANE_Y, 0))
		expect(entry.speed).toBeCloseTo(100 * RoomConfig.Mechanics.BoostSpeed, 1e-6)
		expect(entry.bouncesLeft).toBe(2 + RoomConfig.Mechanics.BoostBounces)
		mechanics:ApplySegment(entry, Vector3.new(-45, PLANE_Y, 0), Vector3.new(-35, PLANE_Y, 0))
		expect(entry.bouncesLeft).toBe(2 + RoomConfig.Mechanics.BoostBounces)

		local rift = buildRoom("Rift"):GetMechanics()
		local shot = { direction = Vector3.new(1, 0, 0) }
		rift:ApplySegment(shot, Vector3.new(-55, PLANE_Y, 30), Vector3.new(-45, PLANE_Y, 30))
		expect(shot.teleportTo).toBeTruthy()
		expect(shot.teleportTo.X).toBeGreaterThan(50)
		expect(shot.teleportTo.Z).toBeCloseTo(-30, 1e-6)
	end)

	it("keeps every portal's exit clear of cover, so a shot can never come out inside a wall", function()
		for layoutId, layout in RoomConfig.Layouts do
			for _, mechanic in layout.Mechanics or {} do
				if mechanic.Kind == "Portal" then
					for _, solid in __require("RoomGeometry").Footprints(layout, RoomConfig) do
						local clearance = __require("RoomGeometry").Clearance(solid, mechanic.Offset.X, mechanic.Offset.Y)
						if clearance < 8 then
							error(("%s portal at %s is %.1f from %s"):format(layoutId, tostring(mechanic.Offset), clearance, solid.Name))
						end
					end
					expect(math.abs(mechanic.Offset.X)).toBeLessThan(layout.InteriorSize.X / 2 - 8)
					expect(math.abs(mechanic.Offset.Y)).toBeLessThan(layout.InteriorSize.Y / 2 - 8)
				end
			end
		end
	end)

	it("spills coins from a loot crate when it breaks", function()
		local ctx = build({ planRun = fixed({ "Forgeworks" }) })
		local player = startSolo(ctx)
		local crate = ctx.arena:FindFirstChild("Room"):FindFirstChild("Breakable1")
		local before = #ctx.coins:GetActive()
		for _ = 1, 4 do
			ctx.match:HandleImpact({ Position = crate.Position, Normal = Vector3.new(0, 0, 1), Instance = crate },
				{ direction = Vector3.new(0, 0, 1), damage = 1, damagePerBounce = 0, contacts = 1, shooter = player }, clock)
		end
		expect(#ctx.coins:GetActive()).toBeGreaterThan(before)
	end)
end)

--// objective rooms ---------------------------------------------------------------------

describe("objective rooms", function()
	local function load(roomId)
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 1)
		local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(1))
		rooms:Load(roomId == "TrickRange" and RouteConfig.GalleryRoom or RunConfig.GetRoomById(roomId), 0)
		return rooms, enemies, arena
	end

	it("Crystal Hunt: straight shots glance off; banked ones crack, then shatter; the last wins", function()
		local rooms, enemies, arena = load("Reliquary")
		local objective = rooms:GetObjective()
		local crystals = {}
		for _, part in arena:FindFirstChild("Room"):FindFirstChild("Objective"):GetChildren() do
			table.insert(crystals, part)
		end
		expect(#crystals).toBe(4)
		expect(objective:HandleImpact(crystals[1], { wallBounces = 0 })).toBe("Deflected")
		for index, crystal in crystals do
			expect(objective:HandleImpact(crystal, { wallBounces = 1 })).toBe("Cracked")
			local result = objective:HandleImpact(crystal, { wallBounces = 1 })
			expect(result).toBe("Shattered")
			expect(objective:IsComplete()).toBe(index == #crystals)
		end
		-- Won: whatever is left flees and the room clears, waves or no waves.
		expect(enemies:GetActiveCount()).toBeGreaterThan(0)
		expect(rooms:IsCleared(1)).toBe(true)
		expect(enemies:GetActiveCount()).toBe(0)
	end)

	it("Hold the Beacon: charges while someone stands in it, drains when nobody does", function()
		local rooms = load("SignalTower")
		local objective = rooms:GetObjective()
		local spot = RunConfig.GetRoomById("SignalTower").Objective.Spot
		local inside = { Vector3.new(spot.X, PLANE_Y, spot.Y) }
		objective:Step(5, 5, inside)
		local charged = objective:Snapshot(5).Progress
		expect(charged).toBe(5)
		objective:Step(4, 9, { Vector3.new(500, PLANE_Y, 500) })
		expect(objective:Snapshot(9).Progress).toBeLessThan(charged)
		objective:Step(ObjectiveConfig.Beacon.Seconds, 40, inside)
		expect(objective:IsComplete()).toBe(true)
	end)

	it("Trick Shot Gallery: bounces double a target's points; targets pop back up; the clock ends it", function()
		local rooms, _, arena = load("TrickRange")
		local objective = rooms:GetObjective()
		local targets = {}
		for _, part in arena:FindFirstChild("Room"):FindFirstChild("Objective"):GetChildren() do
			if part.CanQuery then
				table.insert(targets, part)
			end
		end
		expect(#targets).toBe(ObjectiveConfig.Gallery.LiveTargets)
		local shooter = "p"
		local _, straight = objective:HandleImpact(targets[1], { wallBounces = 0, shooter = shooter })
		local _, banked = objective:HandleImpact(targets[2], { wallBounces = 2, shooter = shooter })
		expect(straight).toBe(ObjectiveConfig.Gallery.Points)
		expect(banked).toBe(ObjectiveConfig.Gallery.Points * 4)
		expect(objective:Scores()[shooter]).toBe(straight + banked)
		objective:Step(1, 1, {})
		expect(targets[1].CanQuery).toBe(true)
		-- A bonus room with no enemies is not cleared until its clock runs out.
		expect(rooms:IsCleared(2)).toBe(false)
		objective:Step(1, ObjectiveConfig.Gallery.Duration + 1, {})
		expect(rooms:IsCleared(ObjectiveConfig.Gallery.Duration + 1)).toBe(true)
	end)
end)

--// doors and challenges -----------------------------------------------------------------

describe("doors", function()
	local function toDoors(route)
		local ctx = build({ route = route or { doors = true } })
		local player, state = startSolo(ctx)
		__clearRoom(ctx.rooms, function()
			for _, enemy in ctx.enemies:GetEnemies() do
				hit(ctx, enemy, player, { damage = 999, wallBounces = 1 })
			end
		end, function(seconds)
			step(ctx, seconds)
		end)
		step(ctx, DT)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
		return ctx, player, state
	end

	it("offers two doors to the next slot's rooms, each with a different promise", function()
		local ctx = toDoors()
		local doors = ctx.match:GetRunSnapshot().Doors
		expect(doors).toBeTruthy()
		expect(#doors.Doors).toBe(RouteConfig.Doors)
		expect(doors.Doors[1].Reward).never().toBe(doors.Doors[2].Reward)
		for _, door in doors.Doors do
			local room = RunConfig.GetRoomById(door.RoomId) or RouteConfig.GalleryRoom
			expect(room.Zone == "Ruins" or room.Kind == "Bonus").toBe(true)
		end
	end)

	it("waits for the vote after the card, then takes the chosen door", function()
		local ctx, player = toDoors()
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
		step(ctx, DT * 2)
		-- The card is in, but the door vote is still open.
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
		local doors = ctx.match:GetRunSnapshot().Doors.Doors
		expect(ctx.match:ChooseDoor(player, 2, clock)).toBe(true)
		expect(ctx.match:ChooseDoor(player, 9, clock)).toBe(false)
		step(ctx, DT * 2)
		expect(ctx.match:GetState()).toBe(States.Transition)
		step(ctx, RunConfig.TransitionDuration + DT)
		local entered = ctx.match:GetRunSnapshot()
		if doors[2].Reward == "Gallery" then
			expect(entered.RoomName).toBe(RouteConfig.GalleryRoom.DisplayName)
		else
			expect(entered.RoomName).toBe(doors[2].RoomName)
		end
	end)

	it("closes the vote at the deadline and takes door 1 when nobody voted", function()
		local ctx, player = toDoors()
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
		local first = ctx.match:GetRunSnapshot().Doors.Doors[1]
		step(ctx, RunConfig.DoorVoteSeconds + DT)
		expect(ctx.match:GetState()).never().toBe(States.UpgradeChoice)
		step(ctx, RunConfig.TransitionDuration + DT)
		local name = ctx.match:GetRunSnapshot().RoomName
		expect(name == first.RoomName or name == RouteConfig.GalleryRoom.DisplayName).toBe(true)
	end)

	it("delivers what a door promised", function()
		local ctx, player, state = toDoors()
		local nextIndex = ctx.match._roomIndex + 1
		ctx.match._roomRewards[nextIndex] = "Heal"
		ctx.match._doors = nil
		state.health = 20
		local offer = ctx.upgrades:GetOffer(player)
		ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
		step(ctx, RunConfig.TransitionDuration + DT * 3)
		expect(ctx.match:GetState()).toBe(States.Combat)
		expect(state.health).toBeGreaterThanOrEqual(20 + state.maxHealth * RouteConfig.Rewards.Heal.HealFraction - 1)
	end)
end)

describe("challenges", function()
	local function inTrial(id)
		local ctx = build({ planRun = fixed({ "Atrium", "Cistern" }), route = { challenges = true } })
		local player, state = startSolo(ctx)
		ctx.match._challenge = { def = RouteConfig.Challenges[id], state = "Active", startedAt = clock }
		return ctx, player, state
	end

	it("Untouchable fails the moment anyone is hit", function()
		local ctx, player = inTrial("Untouchable")
		ctx.match:HandlePlayerContact(player, 5, nil, clock + 10)
		expect(ctx.match:GetRunSnapshot().Challenge.State).toBe("Failed")
	end)

	it("Trick shots only fails on a straight kill, not a banked one", function()
		local ctx, player = inTrial("BankOnly")
		hit(ctx, ctx.enemies:Spawn("Mite", Vector3.new(20, PLANE_Y, 20)), player, { wallBounces = 1 })
		expect(ctx.match:GetRunSnapshot().Challenge.State).toBe("Active")
		hit(ctx, ctx.enemies:Spawn("Mite", Vector3.new(22, PLANE_Y, 20)), player)
		expect(ctx.match:GetRunSnapshot().Challenge.State).toBe("Failed")
	end)

	it("pays coins and a Surge perk when beaten", function()
		local ctx, player, state = inTrial("Untouchable")
		local coins = state.coins
		__clearRoom(ctx.rooms, function()
			for _, enemy in ctx.enemies:GetEnemies() do
				hit(ctx, enemy, player, { damage = 999, wallBounces = 1 })
			end
		end, function(seconds)
			step(ctx, seconds)
		end)
		step(ctx, DT)
		expect(state.coins).toBeGreaterThan(coins)
		expect(#ctx.net.SurgeOffer.calls + #ctx.net.SurgeResolved.calls).toBeGreaterThan(0)
	end)
end)

--// everything at once -----------------------------------------------------------------

describe("a full 2.0 descent", function()
	it("runs from the first room to the Throne with every system on, voting at every door", function()
		local ctx = build({ route = { doors = true, challenges = true, events = true }, seed = 12 })
		local player = startSolo(ctx)
		local rooms = 0
		for _ = 1, 40 do
			if ctx.match:GetState() == States.Results then
				break
			end
			__clearRoom(ctx.rooms, function()
				for _, enemy in ctx.enemies:GetEnemies() do
					hit(ctx, enemy, player, { damage = 999, wallBounces = 1 })
				end
			end, function(seconds)
				step(ctx, seconds)
			end)
			step(ctx, DT)
			rooms += 1
			if ctx.match:GetState() == States.UpgradeChoice then
				local offer = ctx.upgrades:GetOffer(player)
				ctx.match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
				ctx.match:ChooseDoor(player, 1, clock)
				step(ctx, RunConfig.TransitionDuration + DT * 3)
			end
		end
		expect(ctx.match:GetState()).toBe(States.Results)
		expect(rooms).toBeGreaterThanOrEqual(#RunConfig.RunShape)
		local results = ctx.net.RunResults.calls
		expect(results[#results].args[1].Outcome).toBe("Extracted")
	end)
end)

--// the client's new views -----------------------------------------------------------------

describe("2.0 views", function()
	local CardPickerView = __require("CardPickerView")
	local HudView = __require("HudView")
	local RoomFx = __require("RoomFx")
	local SurgePickerView = __require("SurgePickerView")

	it("the Surge picker takes one perk by key or tap, then locks", function()
		local picks = {}
		local view = SurgePickerView.new(Instance.new("Folder"), function(offerId, cardId)
			table.insert(picks, { offerId, cardId })
		end)
		view:Show({ OfferId = 7, SecondsRemaining = 8, Level = 2, Cards = {
			{ Id = "Sharpen", Title = "Sharpen", Description = "x" },
			{ Id = "Rebound", Title = "Rebound", Description = "y" },
			{ Id = "Stride", Title = "Stride", Description = "z" },
		} })
		expect(view:IsOpen()).toBe(true)
		expect(view:Choose(2)).toBe(true)
		expect(view:Choose(3)).toBe(false)
		expect(#picks).toBe(1)
		expect(picks[1][2]).toBe("Rebound")
		view:Hide()
		expect(view:IsOpen()).toBe(false)
	end)

	it("the card picker moves on to the doors, shows votes, and sends one vote per door change", function()
		local votes = {}
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function(doorId)
			table.insert(votes, doorId)
		end)
		expect(view:ShowDoors()).toBe(false)
		view:SetDoors({ SecondsLeft = 9, Doors = {
			{ Id = 1, RoomName = "Cold Smelter", Zone = "Foundry", Kind = "Normal", RewardTitle = "Mending Spring", RewardText = "Heal", Votes = 0 },
			{ Id = 2, RoomName = "Forgeworks", Zone = "Foundry", Kind = "Normal", RewardTitle = "Armoury", RewardText = "Cards", Votes = 1 },
		} })
		expect(view:ShowDoors()).toBe(true)
		expect(view.title.Text).toBe("Choose your path")
		local second = view.row:FindFirstChild("Door2")
		expect(second:FindFirstChild("Votes").Text).toBe("1 vote")
		second.Activated:Fire()
		view.row:FindFirstChild("Door2").Activated:Fire()
		expect(#votes).toBe(1)
		expect(votes[1]).toBe(2)
		view:Hide()
		expect(view.gui.Enabled).toBe(false)
	end)

	it("the HUD shows orbs, the Surge meter, the combo, waves, objectives and trials", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:SetDashHandler(function() end, true)
		hud:UpdatePlayer({ Health = 90, MaxHealth = 100, Alive = true, Coins = 0, Upgrades = {},
			Orbs = 1, OrbsMax = 3, Surge = 5, SurgeNeeded = 10, Combo = 7, ComboWindow = 3.5 })
		expect(hud._pips[1].BackgroundColor3).toBe(ArsenalConfig.Orbs.Color)
		expect(hud._pips[2].BackgroundColor3).never().toBe(ArsenalConfig.Orbs.Color)
		expect(hud.surgeFill.Size.X.Scale).toBeCloseTo(0.5, 1e-6)
		expect(hud.comboFrame.Visible).toBe(true)
		expect(hud.comboCount.Text).toBe("7 COMBO")
		hud:UpdatePlayer({ Health = 90, MaxHealth = 100, Alive = true, Coins = 0, Upgrades = {}, Orbs = 0, OrbsMax = 3 })
		expect(hud.orbLabel.Text).toBe("PICK UP ORBS")

		local combat = { State = States.Combat, RoomIndex = 1, RoomCount = 9, RoomName = "Collapsed Atrium", Zone = "Ruins", EnemiesRemaining = 3 }
		combat.Wave = { Wave = 1, Waves = 2, Incoming = true }
		hud:UpdateRun(combat)
		expect(hud.objectiveLabel.Text).toBe("WAVE 2 / 2 INCOMING!")
		expect(hud.dashButton.Visible).toBe(true)
		combat.Wave = nil
		combat.Objective = { Kind = "Beacon", Text = "Hold the beacon  40%" }
		combat.Challenge = { Text = "Untouchable: nobody takes damage", State = "Failed" }
		hud:UpdateRun(combat)
		expect(hud.objectiveLabel.Text).toBe("Hold the beacon  40%")
		expect(string.find(hud.challengeLabel.Text, "TRIAL FAILED", 1, true)).toBeTruthy()
		hud:UpdateRun({ State = States.Lobby, RoomIndex = 0, RoomCount = 0, RoomName = "", EnemiesRemaining = 0 })
		expect(hud.dashButton.Visible).toBe(false)
		expect(hud.challengeLabel.Visible).toBe(false)
	end)

	it("the room-clear stamp shows, then goes", function()
		Harness.setClock(500)
		local fx = RoomFx.new(Instance.new("Folder"))
		fx:RoomCleared()
		expect(fx.stamp.Visible).toBe(true)
		fx:Step(500 + RoomFx.StampSeconds + 0.1)
		expect(fx.stamp.Visible).toBe(false)
		expect(fx.flash.BackgroundTransparency).toBe(1)
	end)
end)

describe("Surge at the end of a run", function()
	it("leaves nothing waiting to carry into the next run", function()
		local ctx = build({ planRun = fixed({ "WardenVault" }) })
		local player, state = startSolo(ctx)
		state.surge = ArsenalConfig.SurgeNeeded(1) * 3
		ctx.match:_grantSurge(player, 0, clock)
		expect(ctx.match._surges:GetOffer(player)).toBeTruthy()
		__clearRoom(ctx.rooms, function()
			for _, enemy in ctx.enemies:GetEnemies() do
				hit(ctx, enemy, player, { damage = 999, wallBounces = 1 })
			end
		end, function(seconds)
			step(ctx, seconds)
		end)
		step(ctx, DT)
		expect(ctx.match:GetState()).toBe(States.Results)
		expect(ctx.match._surges:HasPendingOffers()).toBe(false)
	end)
end)
