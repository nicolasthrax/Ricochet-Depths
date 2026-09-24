-- Shot effects (crits, burns, arcs, explosions, chill, Siphon, Hunter), champion enemies, the
-- Pact's enemy modifiers, evolutions in offers, and Second Wind. Damage runs through the real
-- MatchService impact path against a real EnemyService.
local CombatConfig = __require("CombatConfig")
local EnemyService = __require("EnemyService")
local MatchEffects = __require("MatchEffects")
local MatchService = __require("MatchService")
local PlayerState = __require("PlayerState")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local TelemetryService = __require("TelemetryService")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3

local function fakeRemote()
	local remote = { calls = {} }
	function remote:FireClient(player, ...)
		table.insert(self.calls, { player = player, args = table.pack(...) })
	end
	function remote:FireAllClients(...)
		table.insert(self.calls, { player = "all", args = table.pack(...) })
	end
	return remote
end

local function fakeEffects()
	local effects = { kinds = {} }
	function effects:Queue(_position, _normal, kind)
		table.insert(self.kinds, kind)
		return true
	end
	function effects:Count(kind)
		local count = 0
		for _, entry in self.kinds do
			if entry == kind then
				count += 1
			end
		end
		return count
	end
	return effects
end

local function build()
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local enemies = EnemyService.new(arena, PLANE_Y, 3)
	local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(3))
	local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated", "Notify" } do
		net[name] = fakeRemote()
	end
	local effects = fakeEffects()
	local match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = UpgradeService.new(3),
		projectiles = projectiles,
		rewards = RewardService.new(),
		telemetry = TelemetryService.new(nil),
		effects = effects,
		net = net,
		world = {
			GetPosition = function()
				return Vector3.new(0, PLANE_Y, 0)
			end,
			Teleport = function() end,
		},
		seed = 5,
	})
	local shooter = { Name = "Shooter", UserId = 42 }
	local state = match:RegisterPlayer(shooter)
	return { match = match, enemies = enemies, rooms = rooms, net = net, effects = effects, shooter = shooter, state = state }
end

local function give(state, cardId, times)
	for _ = 1, times or 1 do
		expect((state:AddUpgrade(UpgradeConfig.Get(cardId)))).toBe(true)
	end
end

-- A direct projectile contact on `enemy`, as ProjectileService would report it.
local function shoot(ctx, enemy, damage, contacts, now)
	local entry = {
		direction = Vector3.new(0, 0, 1),
		damage = damage or 1,
		damagePerBounce = 0,
		contacts = contacts or 1,
		shooter = ctx.shooter,
		stats = ctx.state.stats,
	}
	local result = { Position = enemy.position, Normal = Vector3.new(0, 0, -1), Instance = enemy.part }
	return ctx.match:HandleImpact(result, entry, now or 1)
end

local function spawn(ctx, archetype, x, z, options)
	local enemy = ctx.enemies:Spawn(archetype, Vector3.new(x, PLANE_Y, z), options)
	expect(enemy).toBeTruthy()
	return enemy
end

describe("shot damage maths", function()
	local drifter = { archetype = { IsBoss = false }, chillUntil = 0 }

	it("crits a trick shot with enough contacts, and never one without", function()
		local stats = { TrickShotContacts = 3, CritMultiplier = 2 }
		local damage, crit = MatchEffects.ShotDamage(stats, 2, 3, drifter, 0, Random.new(1))
		expect(crit).toBe(true)
		expect(damage).toBe(4)
		damage, crit = MatchEffects.ShotDamage(stats, 2, 2, drifter, 0, Random.new(1))
		expect(crit).toBe(false)
		expect(damage).toBe(2)
	end)

	it("rolls crit chance: always at 100%, never at 0%", function()
		expect(select(2, MatchEffects.ShotDamage({ CritChance = 1, CritMultiplier = 3 }, 1, 1, drifter, 0, Random.new(9)))).toBe(true)
		expect((MatchEffects.ShotDamage({ CritChance = 1, CritMultiplier = 3 }, 1, 1, drifter, 0, Random.new(9)))).toBe(3)
		expect(select(2, MatchEffects.ShotDamage({ CritChance = 0 }, 1, 1, drifter, 0, Random.new(9)))).toBe(false)
	end)

	it("adds Hunter against bosses and champions only, and the chill bonus against slowed targets", function()
		local stats = { HunterBonus = 0.5, ChillDamageBonus = 0.6 }
		expect(MatchEffects.TargetMultiplier(stats, drifter, 0)).toBe(1)
		expect(MatchEffects.TargetMultiplier(stats, { archetype = { IsBoss = true } }, 0)).toBe(1.5)
		expect(MatchEffects.TargetMultiplier(stats, { archetype = {}, champion = {} }, 0)).toBe(1.5)
		expect(MatchEffects.TargetMultiplier(stats, { archetype = {}, chillUntil = 5 }, 1)).toBeCloseTo(1.6, 1e-9)
	end)
end)

describe("shot effects in a match", function()
	it("arcs a hit to the nearest other enemy, ignoring shields, but never the far one", function()
		local ctx = build()
		give(ctx.state, "ChainArc")
		local first = spawn(ctx, "Chaser", 0, 0)
		local near = spawn(ctx, "Bulwark", 6, 0)
		local far = spawn(ctx, "Chaser", 60, 0)
		shoot(ctx, first, 1)
		expect(first.health).toBe(1)
		-- Half of 1 rounds up to the 1-damage floor; the Bulwark's shield does not stop an arc.
		expect(near.health).toBe(near.maxHealth - 1)
		expect(far.health).toBe(far.maxHealth)
		expect(ctx.effects:Count("Arc")).toBe(1)
	end)

	it("chains kill explosions through a cluster and credits every kill", function()
		local ctx = build()
		give(ctx.state, "Volatile")
		local a = spawn(ctx, "Drifter", 0, 0)
		spawn(ctx, "Drifter", 3, 0)
		spawn(ctx, "Drifter", 0, 3)
		local lone = spawn(ctx, "Drifter", 80, 0)
		shoot(ctx, a, 1)
		expect(ctx.enemies:GetActiveCount()).toBe(1)
		expect(lone.dead).toBe(false)
		expect(ctx.state.kills).toBe(3)
		expect(ctx.state.killsByArchetype.Drifter).toBe(3)
		expect(#ctx.net.EnemyDefeated.calls).toBeGreaterThanOrEqual(3)
		expect(ctx.effects:Count("Blast")).toBeGreaterThanOrEqual(1)
	end)

	it("burns a survivor to death over time, and the burn kill counts", function()
		local ctx = build()
		give(ctx.state, "Ignite")
		local chaser = spawn(ctx, "Chaser", 0, 0)
		shoot(ctx, chaser, 1, 1, 0)
		expect(chaser.dead).toBe(false)
		expect(chaser.burn).toBeTruthy()
		local now = 0
		while not chaser.dead and now < CombatConfig.BurnDuration + 1 do
			now += 1 / 30
			ctx.enemies:Step(1 / 30, now)
		end
		expect(chaser.dead).toBe(true)
		expect(ctx.state.kills).toBe(1)
		expect(ctx.effects:Count("Burn") + ctx.effects:Count("Kill")).toBeGreaterThanOrEqual(1)
	end)

	it("lets a burn run out rather than tick forever", function()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		local ticks = 0
		enemies.OnStatusDamage = function()
			ticks += 1
		end
		local bulwark = enemies:Spawn("Bulwark", Vector3.new(0, PLANE_Y, 0))
		enemies:ApplyStatus(bulwark, 1, 0, nil, 0)
		for frame = 1, 300 do
			enemies:Step(1 / 30, frame / 30)
		end
		expect(ticks).toBe(math.floor(CombatConfig.BurnDuration / CombatConfig.BurnTick))
		expect(bulwark.burn).toBeNil()
		expect(bulwark.part:GetAttribute("Burning")).toBeNil()
	end)

	it("slows a chilled enemy and marks it for clients", function()
		local function travelled(chill)
			local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
			enemies:SetTargetProvider(function()
				return { { player = "p", position = Vector3.new(100, PLANE_Y, 0) } }
			end)
			local chaser = enemies:Spawn("Chaser", Vector3.new(0, PLANE_Y, 0))
			if chill then
				enemies:ApplyStatus(chaser, 0, 10, nil, 0)
			end
			enemies:Step(1 / 30, 1 / 30)
			local start = chaser.position.X
			for frame = 2, 31 do
				enemies:Step(1 / 30, frame / 30)
			end
			return chaser.position.X - start, chaser.part:GetAttribute("Chilled")
		end
		local normal = travelled(false)
		local slowed, marked = travelled(true)
		expect(slowed).toBeCloseTo(normal * CombatConfig.ChillSpeedFactor, 0.05)
		expect(marked).toBe(true)
	end)

	it("heals the shooter on a kill with Siphon", function()
		local ctx = build()
		give(ctx.state, "Siphon")
		ctx.state.health = 50
		shoot(ctx, spawn(ctx, "Drifter", 0, 0), 1)
		expect(ctx.state.health).toBe(53)
	end)

	it("counts crits from Trick Shot and doubles their damage", function()
		local ctx = build()
		give(ctx.state, "TrickShot")
		local bulwark = spawn(ctx, "WardenCore", 0, 0)
		bulwark.shieldOff = true
		shoot(ctx, bulwark, 1, 3)
		expect(bulwark.health).toBe(bulwark.maxHealth - 2)
		expect(ctx.state.crits).toBe(1)
		expect(ctx.effects:Count("Crit")).toBe(1)
	end)
end)

describe("champions", function()
	it("spawn tougher, richer and tagged, and lose the tag when their body is reused", function()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		local chaser = enemies:Spawn("Chaser", Vector3.new(0, PLANE_Y, 0), { champion = "Armored" })
		expect(chaser.maxHealth).toBe(math.ceil(2 * CombatConfig.Champions.Armored.HealthMultiplier))
		expect(chaser.coins).toBe(2 * CombatConfig.ChampionCoinMultiplier)
		expect(chaser.part:GetAttribute("Champion")).toBe("Armored")
		enemies:Despawn(chaser, "test")
		expect(chaser.part:GetAttribute("Champion")).toBeNil()
	end)

	it("bursts into a ring of orbs when a Volatile champion dies", function()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		local drifter = enemies:Spawn("Drifter", Vector3.new(0, PLANE_Y, 0), { champion = "Volatile" })
		local before = enemies:GetOrbsFired()
		enemies:ApplyHit(drifter.part, 100, nil, nil)
		expect(enemies:GetOrbsFired() - before).toBe(CombatConfig.Champions.Volatile.DeathRing.Count)
	end)

	it("regenerates a Mending champion toward full", function()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		local bulwark = enemies:Spawn("Bulwark", Vector3.new(0, PLANE_Y, 0), { champion = "Mending" })
		bulwark.health = 1
		for frame = 1, 30 * 6 do
			enemies:Step(1 / 30, frame / 30)
		end
		expect(bulwark.health).toBeGreaterThan(1)
		expect(bulwark.health).toBeLessThanOrEqual(bulwark.maxHealth)
	end)

	it("never appear in the Ruins by default, and appear everywhere normal once the bonus is certain", function()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		local rooms = RoomService.new(Instance.new("Folder"), enemies, PLANE_Y, Random.new(1))
		rooms:Load(RunConfig.GetRoomById("Atrium"), 0)
		for _, enemy in enemies:GetEnemies() do
			expect(enemy.champion).toBeNil()
		end
		rooms:SetChampionBonus(1)
		rooms:Load(RunConfig.GetRoomById("Gallery"), 0)
		for _, enemy in enemies:GetEnemies() do
			expect(enemy.champion).toBeTruthy()
		end
		rooms:Load(RunConfig.GetRoomById("Throne"), 0)
		for _, enemy in enemies:GetEnemies() do
			expect(enemy.champion).toBeNil()
		end
	end)
end)

describe("enemy modifiers", function()
	it("scale health up (rounding up) and hit harder", function()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 1)
		enemies:SetModifiers({ Health = 1.3, Damage = 1.5 })
		expect(enemies:Spawn("Drifter", Vector3.new(0, PLANE_Y, 0)).maxHealth).toBe(2)
		local hits = {}
		enemies.OnPlayerContact = function(_player, damage)
			table.insert(hits, damage)
		end
		enemies:SetTargetProvider(function()
			return { { player = "p", position = Vector3.new(0, PLANE_Y, 1) } }
		end)
		enemies:Spawn("Chaser", Vector3.new(0, PLANE_Y, 0))
		enemies:Step(1 / 30, 1)
		expect(hits[1]).toBe(15)
	end)
end)

describe("evolutions", function()
	it("are always offered once a build qualifies, and never before", function()
		local service = UpgradeService.new(77)
		local state = PlayerState.new({ Name = "E", UserId = 1 })
		for _ = 1, 20 do
			for _, card in service:BuildOffer("p", state, 0).cards do
				expect(card.Id).never().toBe("Wildfire")
			end
		end
		give(state, "Ignite", 2)
		give(state, "Volatile")
		for _ = 1, 10 do
			local offered = false
			for _, card in service:BuildOffer("p", state, 0).cards do
				offered = offered or card.Id == "Wildfire"
			end
			expect(offered).toBe(true)
		end
	end)

	it("can build a smaller offer for the Pact's Narrow Path", function()
		local service = UpgradeService.new(5)
		expect(#service:BuildOffer("p", PlayerState.new({ Name = "N", UserId = 2 }), 0, 2).cards).toBe(2)
	end)

	it("every evolution names real cards whose stacks are reachable", function()
		for _, card in UpgradeConfig.Cards do
			if card.Rarity == "Fused" then
				for requiredId, needed in card.Requires.Cards do
					local required = UpgradeConfig.Get(requiredId)
					expect(required).toBeTruthy()
					expect(required.MaxStacks).toBeGreaterThanOrEqual(needed)
				end
			end
		end
	end)
end)

describe("Second Wind", function()
	it("turns one fatal blow into half health, then the next one downs you", function()
		local state = PlayerState.new({ Name = "W", UserId = 3 })
		give(state, "SecondWind")
		expect(state:ToSnapshot().ExtraLivesLeft).toBe(1)
		local _, fatal, saved = state:ApplyDamage(500, 10)
		expect(fatal).toBe(false)
		expect(saved).toBe(true)
		expect(state.alive).toBe(true)
		expect(state.health).toBe(math.floor(state.maxHealth * CombatConfig.ExtraLifeHealth))
		expect(state:ToSnapshot().ExtraLivesLeft).toBe(0)
		_, fatal = state:ApplyDamage(500, 100)
		expect(fatal).toBe(true)
		expect(state.alive).toBe(false)
	end)

	it("tells the player through the match", function()
		local ctx = build()
		give(ctx.state, "SecondWind")
		ctx.match:HandlePlayerContact(ctx.shooter, 999, nil, 10)
		local last = ctx.net.Notify.calls[#ctx.net.Notify.calls]
		expect(last).toBeTruthy()
		expect(last.args[1].Kind).toBe("SecondWind")
	end)
end)
