-- Enemy lifecycle, shielding arc, contact damage, bounds and cleanup.
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")

local PLANE_Y = 3

local function newService()
	local parent = Instance.new("Folder")
	local service = EnemyService.new(parent, PLANE_Y, 424242)
	service:SetBounds(Vector3.new(0, PLANE_Y, 0), Vector2.new(60, 60))
	return service, parent
end

local function targetsAt(position)
	local player = { Name = "Target" }
	return function()
		return { { player = player, position = position } }
	end, player
end

describe("EnemyService spawning", function()
	it("spawns on the travel plane and tracks the part", function()
		local service = newService()
		local enemy = service:Spawn("Drifter", Vector3.new(10, 99, -20))
		expect(enemy).toBeTruthy()
		expect(enemy.position.Y).toBe(PLANE_Y)
		expect(enemy.part.Position.Y).toBe(PLANE_Y)
		expect(enemy.part.CanQuery).toBe(true)
		expect(service:GetByPart(enemy.part)).toBe(enemy)
		expect(service:GetActiveCount()).toBe(1)
	end)

	it("rejects unknown archetypes without side effects", function()
		local service = newService()
		local enemy, reason = service:Spawn("Nonexistent", Vector3.zero)
		expect(enemy).toBeNil()
		expect(reason).toBe("unknown archetype")
		expect(service:GetActiveCount()).toBe(0)
	end)

	it("refuses to spawn past the active cap", function()
		local service = newService()
		local spawned = 0
		for index = 1, EnemyConfig.MaxActive + 10 do
			local enemy, reason = service:Spawn("Drifter", Vector3.new(index, PLANE_Y, 0))
			if enemy then
				spawned += 1
			else
				expect(reason).toBe("enemy cap reached")
			end
		end
		expect(spawned).toBe(EnemyConfig.MaxActive)
		expect(service:GetActiveCount()).toBe(EnemyConfig.MaxActive)
	end)
end)

describe("EnemyService damage", function()
	it("kills a one-hit enemy and reports the kill exactly once", function()
		local service = newService()
		local deaths = 0
		service.OnDeath = function()
			deaths += 1
		end
		local enemy = service:Spawn("Drifter", Vector3.new(0, PLANE_Y, 0))
		local part = enemy.part

		local result = service:ApplyHit(part, 1, Vector3.new(0, 0, 1), nil)
		expect(result.killed).toBe(true)
		expect(deaths).toBe(1)
		expect(service:GetActiveCount()).toBe(0)

		-- A second contact on the same (now recycled) part must not re-award the kill.
		expect(service:ApplyHit(part, 1, Vector3.new(0, 0, 1), nil)).toBeNil()
		expect(deaths).toBe(1)
	end)

	it("returns nil for parts that are not enemies", function()
		local service = newService()
		expect(service:ApplyHit(Instance.new("Part"), 1, Vector3.new(0, 0, 1), nil)).toBeNil()
	end)

	it("needs several hits to kill a durable enemy", function()
		local service = newService()
		local enemy = service:Spawn("Bulwark", Vector3.new(0, PLANE_Y, 0))
		enemy.facing = Vector3.new(0, 0, 1)
		local fromBehind = Vector3.new(0, 0, 1)
		for _ = 1, EnemyConfig.Archetypes.Bulwark.Health - 1 do
			local result = service:ApplyHit(enemy.part, 1, fromBehind, nil)
			expect(result.blocked).toBe(false)
			expect(result.killed).toBe(false)
		end
		expect(service:ApplyHit(enemy.part, 1, fromBehind, nil).killed).toBe(true)
	end)
end)

describe("Bulwark shield arc", function()
	local service = newService()
	local enemy = service:Spawn("Bulwark", Vector3.new(0, PLANE_Y, 0))
	enemy.facing = Vector3.new(0, 0, 1) -- facing +Z, i.e. looking at a player to its +Z side

	local function hitFrom(direction)
		enemy.health = enemy.maxHealth
		return service:ApplyHit(enemy.part, 1, direction, nil)
	end

	it("blocks a shot arriving dead-on", function()
		expect(hitFrom(Vector3.new(0, 0, -1)).blocked).toBe(true)
	end)

	it("blocks shallow-angle shots inside the shield arc", function()
		local halfAngle = math.rad(EnemyConfig.Archetypes.Bulwark.Shield.HalfAngleDegrees)
		local inside = halfAngle - math.rad(5)
		expect(hitFrom(Vector3.new(math.sin(inside), 0, -math.cos(inside))).blocked).toBe(true)
	end)

	it("lets a flanking ricochet through", function()
		expect(hitFrom(Vector3.new(1, 0, 0)).blocked).toBe(false)
	end)

	it("lets a shot from behind through", function()
		expect(hitFrom(Vector3.new(0, 0, 1)).blocked).toBe(false)
	end)

	it("takes damage when no direction is known rather than becoming invulnerable", function()
		expect(hitFrom(Vector3.zero).blocked).toBe(false)
	end)
end)

describe("EnemyService stepping", function()
	it("moves a chaser toward the player and stops at its standoff distance", function()
		local service = newService()
		local provider = targetsAt(Vector3.new(0, PLANE_Y, 40))
		service:SetTargetProvider(provider)
		local enemy = service:Spawn("Chaser", Vector3.new(0, PLANE_Y, -40))

		for frame = 1, 600 do
			service:Step(1 / 60, frame / 60)
		end
		local gap = math.abs(40 - enemy.position.Z)
		expect(gap).toBeLessThanOrEqual(EnemyConfig.Archetypes.Chaser.StandoffDistance + 0.5)
		expect(gap).toBeGreaterThan(0)
	end)

	it("keeps a sentry near its spawn anchor", function()
		local service = newService()
		service:SetTargetProvider(targetsAt(Vector3.new(0, PLANE_Y, 500)))
		local enemy = service:Spawn("Drifter", Vector3.new(20, PLANE_Y, 20))
		for frame = 1, 1200 do
			service:Step(1 / 60, frame / 60)
		end
		local drift = (enemy.position - enemy.anchor).Magnitude
		expect(drift).toBeLessThanOrEqual(EnemyConfig.Archetypes.Drifter.WanderRadius + 0.5)
	end)

	it("never lets an enemy leave the arena bounds", function()
		local service = newService()
		service:SetTargetProvider(targetsAt(Vector3.new(500, PLANE_Y, 500)))
		for index = 1, 10 do
			service:Spawn("Chaser", Vector3.new(index * 4 - 20, PLANE_Y, 0))
		end
		for frame = 1, 900 do
			service:Step(1 / 60, frame / 60)
			for _, enemy in service:GetEnemies() do
				expect(math.abs(enemy.position.X)).toBeLessThanOrEqual(60.001)
				expect(math.abs(enemy.position.Z)).toBeLessThanOrEqual(60.001)
			end
		end
	end)

	it("applies contact damage on a cooldown, not every frame", function()
		local service = newService()
		local provider, player = targetsAt(Vector3.new(0, PLANE_Y, 0))
		service:SetTargetProvider(provider)
		local hits = 0
		service.OnPlayerContact = function(contactPlayer, damage)
			expect(contactPlayer).toBe(player)
			expect(damage).toBe(EnemyConfig.Archetypes.Chaser.ContactDamage)
			hits += 1
		end
		service:Spawn("Chaser", Vector3.new(0, PLANE_Y, 1))

		local seconds = 5
		for frame = 1, seconds * 60 do
			service:Step(1 / 60, frame / 60)
		end
		local cooldown = EnemyConfig.Archetypes.Chaser.ContactCooldown
		expect(hits).toBeLessThanOrEqual(math.ceil(seconds / cooldown) + 1)
		expect(hits).toBeGreaterThanOrEqual(math.floor(seconds / cooldown) - 1)
	end)

	it("telegraphs before a lunge instead of closing instantly", function()
		local service = newService()
		service:SetTargetProvider(targetsAt(Vector3.new(0, PLANE_Y, 30)))
		local enemy = service:Spawn("Bulwark", Vector3.new(0, PLANE_Y, -30))
		local sawTelegraph, sawLunge = false, false
		for frame = 1, 900 do
			service:Step(1 / 60, frame / 60)
			if enemy.phase == "Telegraph" then
				sawTelegraph = true
				expect(enemy.color).toBe(EnemyConfig.Archetypes.Bulwark.Lunge.TelegraphColor)
			elseif enemy.phase == "Lunging" then
				sawLunge = true
			end
		end
		expect(sawTelegraph).toBe(true)
		expect(sawLunge).toBe(true)
	end)
end)

describe("EnemyService cleanup", function()
	it("returns every part to the pool on Clear with no dangling registry entries", function()
		local service, parent = newService()
		service:SetTargetProvider(targetsAt(Vector3.new(0, PLANE_Y, 0)))
		local parts = {}
		for index = 1, 12 do
			table.insert(parts, service:Spawn("Drifter", Vector3.new(index, PLANE_Y, 0)).part)
		end
		expect(service:GetActiveCount()).toBe(12)

		service:Clear()
		expect(service:GetActiveCount()).toBe(0)
		for _, part in parts do
			expect(service:GetByPart(part)).toBeNil()
			expect(part.Transparency).toBe(1)
			expect(part.CanQuery).toBe(false)
		end
		expect(#parent:FindFirstChild("EnemyPool"):GetChildren()).toBe(EnemyConfig.PoolSize)
	end)

	it("survives many spawn/clear cycles without growing the instance count", function()
		local service, parent = newService()
		service:SetTargetProvider(targetsAt(Vector3.new(0, PLANE_Y, 0)))
		local folder = parent:FindFirstChild("EnemyPool")
		for cycle = 1, 40 do
			for index = 1, 15 do
				service:Spawn("Chaser", Vector3.new(index, PLANE_Y, cycle))
			end
			for frame = 1, 10 do
				service:Step(1 / 60, frame / 60)
			end
			service:Clear()
			expect(#folder:GetChildren()).toBe(EnemyConfig.PoolSize)
		end
		expect(service:GetActiveCount()).toBe(0)
	end)
end)
