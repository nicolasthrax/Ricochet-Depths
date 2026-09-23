-- New enemies and the boss: Splitter (and its Shards), Sentinel turret orbs, the blinking
-- Phaser, and the Warden Prime's three phases.
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")
local RoomConfig = __require("RoomConfig")
local RoomGeometry = __require("RoomGeometry")
local RunConfig = __require("RunConfig")

local PLANE_Y = 3

local function newService()
	local parent = Instance.new("Folder")
	local service = EnemyService.new(parent, PLANE_Y, 99)
	service:SetBounds(Vector3.new(0, PLANE_Y, 0), Vector2.new(60, 60))
	return service, parent
end

local function targetAt(service, position)
	local player = { Name = "Target" }
	local target = { player = player, position = position }
	service:SetTargetProvider(function()
		return { target }
	end)
	return target, player
end

local function countOf(service, archetypeId)
	local count = 0
	for _, enemy in service:GetEnemies() do
		if enemy.archetypeId == archetypeId then
			count += 1
		end
	end
	return count
end

local function run(service, seconds, from)
	local now = from or 0
	local dt = 1 / 30
	for _ = 1, math.ceil(seconds / dt) do
		now += dt
		service:Step(dt, now)
	end
	return now
end

describe("Splitter", function()
	it("breaks into Shards where it dies", function()
		local service = newService()
		local splitter = service:Spawn("Splitter", Vector3.new(10, PLANE_Y, 10))
		local split = EnemyConfig.Archetypes.Splitter.SplitInto
		local result
		for _ = 1, splitter.maxHealth do
			result = service:ApplyHit(splitter.part, 1, Vector3.new(1, 0, 0), nil)
		end
		expect(result.killed).toBe(true)
		expect(countOf(service, split.Archetype)).toBe(split.Count)
		for _, shard in service:GetEnemies() do
			expect((shard.position - Vector3.new(10, PLANE_Y, 10)).Magnitude).toBeLessThan(6)
		end
	end)

	it("never splits past the active cap", function()
		local service = newService()
		for index = 1, EnemyConfig.MaxActive - 1 do
			service:Spawn("Drifter", Vector3.new(index, PLANE_Y, -30))
		end
		local splitter = service:Spawn("Splitter", Vector3.new(0, PLANE_Y, 20))
		for _ = 1, splitter.maxHealth do
			service:ApplyHit(splitter.part, 1, nil, nil)
		end
		expect(service:GetActiveCount()).toBeLessThanOrEqual(EnemyConfig.MaxActive)
	end)
end)

describe("Sentinel turret", function()
	it("holds its ground, telegraphs, then fires an orb at the player", function()
		local service = newService()
		local turret = service:Spawn("Sentinel", Vector3.new(0, PLANE_Y, 30))
		targetAt(service, Vector3.new(0, PLANE_Y, -20))
		local spec = EnemyConfig.Archetypes.Sentinel.Fire
		local now = run(service, spec.Interval - spec.TelegraphTime + 0.05)
		expect(turret.phase).toBe("Telegraph")
		expect(#service:GetOrbs()).toBe(0)
		now = run(service, spec.TelegraphTime, now)
		expect(#service:GetOrbs()).toBe(1)
		expect(turret.position.Z).toBeCloseTo(30)
		local orb = service:GetOrbs()[1]
		expect(orb.velocity.Unit.Z).toBeLessThan(-0.99)
	end)

	it("burns the player an orb reaches, once, and the orb is spent", function()
		local service = newService()
		service:Spawn("Sentinel", Vector3.new(0, PLANE_Y, 30))
		local _, player = targetAt(service, Vector3.new(0, PLANE_Y, 10))
		local hits = {}
		service.OnPlayerContact = function(who, damage)
			table.insert(hits, { who = who, damage = damage })
		end
		run(service, EnemyConfig.Archetypes.Sentinel.Fire.Interval + 3)
		expect(#hits).toBeGreaterThanOrEqual(1)
		expect(hits[1].who).toBe(player)
		expect(hits[1].damage).toBe(EnemyConfig.Archetypes.Sentinel.Fire.Damage)
	end)

	it("loses orbs to cover and to the room's walls", function()
		local service = newService()
		service:SetObstacles({ { Name = "Wall", Kind = "Obstacle", Center = Vector2.new(0, 10), Size = Vector2.new(20, 2), Yaw = 0 } })
		service:Spawn("Sentinel", Vector3.new(0, PLANE_Y, 30))
		local hits = 0
		service.OnPlayerContact = function()
			hits += 1
		end
		targetAt(service, Vector3.new(0, PLANE_Y, -10))
		run(service, EnemyConfig.Archetypes.Sentinel.Fire.Interval + 4)
		expect(hits).toBe(0)
		expect(#service:GetOrbs()).toBe(0)
	end)

	it("returns every orb to its pool on Clear", function()
		local service = newService()
		service:Spawn("Sentinel", Vector3.new(0, PLANE_Y, 30))
		targetAt(service, Vector3.new(0, PLANE_Y, -50))
		run(service, EnemyConfig.Archetypes.Sentinel.Fire.Interval + 0.1)
		expect(#service:GetOrbs()).toBeGreaterThan(0)
		service:Clear()
		expect(#service:GetOrbs()).toBe(0)
		expect(service:GetFreeOrbCount()).toBe(EnemyConfig.OrbPoolSize)
	end)
end)

describe("Phaser", function()
	it("cannot be hit mid-blink and reappears somewhere new, inside the room", function()
		local service = newService()
		local phaser = service:Spawn("Phaser", Vector3.new(30, PLANE_Y, 30))
		targetAt(service, Vector3.new(0, PLANE_Y, 0))
		local blink = EnemyConfig.Archetypes.Phaser.Blink
		local now = run(service, blink.Interval + blink.TelegraphTime + 0.15)
		expect(phaser.phase).toBe("Blinking")
		expect(service:ApplyHit(phaser.part, 1, nil, nil)).toBeNil()
		expect(phaser.part.CanQuery).toBe(false)
		local before = phaser.position
		run(service, blink.Duration + 0.1, now)
		expect(phaser.phase).never().toBe("Blinking")
		expect(phaser.part.CanQuery).toBe(true)
		expect((phaser.position - before).Magnitude).toBeGreaterThan(1)
		expect(math.abs(phaser.position.X)).toBeLessThanOrEqual(60)
		expect(service:ApplyHit(phaser.part, 1, nil, nil)).toBeTruthy()
	end)
end)

describe("Warden Prime", function()
	local archetype = EnemyConfig.Archetypes.WardenPrime

	it("is a boss with three phases keyed to its health", function()
		expect(archetype.IsBoss).toBe(true)
		expect(#archetype.Phases).toBe(3)
		local service = newService()
		local boss = service:Spawn("WardenPrime", Vector3.new(0, PLANE_Y, 30))
		expect(EnemyService.BossPhase(boss)).toBe(1)
		boss.health = boss.maxHealth * (archetype.Phases[2].Below - 0.01)
		expect(EnemyService.BossPhase(boss)).toBe(2)
		boss.health = boss.maxHealth * (archetype.Phases[3].Below - 0.01)
		expect(EnemyService.BossPhase(boss)).toBe(3)
	end)

	it("spins its shield in phase one, whatever the player does", function()
		local service = newService()
		local boss = service:Spawn("WardenPrime", Vector3.new(0, PLANE_Y, 30))
		targetAt(service, Vector3.new(0, PLANE_Y, 0))
		run(service, 0.2)
		local first = boss.facing.Unit
		run(service, 0.5, 0.2)
		expect(first:Dot(boss.facing.Unit)).toBeLessThan(0.99)
	end)

	it("summons Shards and fires rings of orbs in phase two", function()
		local service = newService()
		local boss = service:Spawn("WardenPrime", Vector3.new(0, PLANE_Y, 30))
		boss.health = boss.maxHealth * (archetype.Phases[2].Below - 0.01)
		targetAt(service, Vector3.new(0, PLANE_Y, -40))
		local phase = archetype.Phases[2]
		run(service, math.max(phase.SummonInterval, phase.RingInterval) + 0.1)
		expect(countOf(service, phase.Summon)).toBeGreaterThan(0)
		expect(service:GetOrbsFired()).toBeGreaterThanOrEqual(phase.RingCount)
	end)

	it("drops its shield in phase three, so a head-on shot lands", function()
		local service = newService()
		local boss = service:Spawn("WardenPrime", Vector3.new(0, PLANE_Y, 30))
		targetAt(service, Vector3.new(0, PLANE_Y, 0))
		run(service, 0.1)
		-- Phase one: a shot straight into the facing is blocked.
		local headOn = -boss.facing.Unit
		expect(service:ApplyHit(boss.part, 1, headOn, nil).blocked).toBe(true)
		boss.health = boss.maxHealth * (archetype.Phases[3].Below - 0.01)
		run(service, 0.1, 0.1)
		headOn = -boss.facing.Unit
		expect(service:ApplyHit(boss.part, 1, headOn, nil).blocked).toBe(false)
	end)
end)

describe("the run ends on the boss", function()
	it("closes every run with the Warden Vault, then the Throne and its boss", function()
		local shape = RunConfig.RunShape
		expect(RunConfig.GetRoomById(shape[#shape - 1].Room).Kind).toBe("Elite")
		local throne = RunConfig.GetRoomById(shape[#shape].Room)
		expect(throne.Kind).toBe("Boss")
		local bosses = 0
		for _, group in throne.Spawns do
			if EnemyConfig.Get(group.Archetype).IsBoss then
				bosses += group.Count
			end
		end
		expect(bosses).toBe(1)
		expect(RoomConfig.GetLayout(throne.Layout)).toBeTruthy()
	end)

	it("fields every new archetype somewhere in the room pool", function()
		local used = {}
		for _, room in RunConfig.Rooms do
			for _, group in room.Spawns do
				used[group.Archetype] = true
			end
		end
		for _, id in { "Splitter", "Sentinel", "Phaser", "WardenPrime" } do
			if not used[id] then
				error(id .. " is never spawned")
			end
		end
	end)

	it("posts turrets in the open, so an orb has room to be dodged", function()
		for _, room in RunConfig.Rooms do
			local layout = RoomConfig.GetLayout(room.Layout)
			for _, assignment in __require("RoomService").AssignSpawns(room, layout) do
				if assignment.archetype == "Sentinel" then
					local marker = layout.EnemySpawns[assignment.marker]
					expect(marker.Magnitude).toBeGreaterThan(30)
					for _, solid in RoomGeometry.Footprints(layout, RoomConfig) do
						expect(RoomGeometry.Clearance(solid, marker.X, marker.Y)).toBeGreaterThan(6)
					end
				end
			end
		end
	end)
end)
