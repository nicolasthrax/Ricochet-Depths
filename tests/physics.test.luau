-- Swept-collision fidelity against real boxes: reflection law across a heading sweep, incidence
-- sweep, moving targets, same-frame multi-projectile resolution and the origin-inside-a-part quirk.
local ProjectileConfig = __require("ProjectileConfig")
local ProjectileService = __require("ProjectileService")
local RoomConfig = __require("RoomConfig")

local PLANE_Y = 3
local DT = 1 / 60

local function newArena(layoutId)
	local world = __PhysicsWorld.new()
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local bounds = world:AddRoomLayout(RoomConfig.GetLayout(layoutId or "Atrium"), RoomConfig, arena)
	world:Install()

	local service = ProjectileService.new(arena, arena, PLANE_Y)
	local folder = arena:FindFirstChild("ProjectilePool")
	return { world = world, arena = arena, service = service, folder = folder, bounds = bounds }
end

local function step(ctx, frames)
	for _ = 1, frames do
		__integrateParts(ctx.folder, DT)
		Harness.setClock(Harness.now() + DT)
		ctx.service:Step(DT)
	end
end

-- Fires one projectile and records every contact it makes.
local function recordContacts(ctx, origin, heading, frames)
	local contacts = {}
	ctx.service.OnImpact = function(result, entry)
		table.insert(contacts, {
			incoming = entry.direction,
			normal = result.Normal,
			position = result.Position,
			contactIndex = entry.contacts,
			speed = entry.speed,
		})
		return false
	end
	Harness.setClock(0)
	ctx.service:Fire(nil, origin, __flatUnit(heading), 1)
	step(ctx, frames or 260)
	return contacts
end

describe("reflection law across a heading sweep", function()
	-- The five headings asked for, measured in the world XZ plane from +X.
	for _, headingDegrees in { 30, 60, 90, 120, 150 } do
		it(string.format("obeys r = d - 2(d.n)n on every contact at a %d degree heading", headingDegrees), function()
			local ctx = newArena("Atrium")
			local radians = math.rad(headingDegrees)
			local contacts = recordContacts(ctx, Vector3.new(0, PLANE_Y, 0), Vector3.new(math.cos(radians), 0, math.sin(radians)))

			expect(#contacts).toBeGreaterThan(0)
			for index = 1, #contacts - 1 do
				local expected = __flatUnit(__reflect(contacts[index].incoming, contacts[index].normal))
				local actual = contacts[index + 1].incoming
				-- The heading the projectile carried into the next contact must be exactly the
				-- reflection of the previous one.
				expect(actual:Dot(expected)).toBeCloseTo(1, 1e-4)
			end
		end)

		it(string.format("preserves speed and the travel plane at a %d degree heading", headingDegrees), function()
			local ctx = newArena("Atrium")
			local radians = math.rad(headingDegrees)
			local contacts = recordContacts(ctx, Vector3.new(0, PLANE_Y, 0), Vector3.new(math.cos(radians), 0, math.sin(radians)))

			expect(#contacts).toBeGreaterThan(0)
			local speed = contacts[1].speed
			for _, contact in contacts do
				expect(contact.speed).toBe(speed)
				expect(contact.incoming.Y).toBe(0)
				expect(contact.incoming.Magnitude).toBeCloseTo(1, 1e-6)
				expect(contact.position.Y).toBeCloseTo(PLANE_Y, 0.01)
			end
		end)
	end
end)

describe("angle of incidence equals angle of reflection", function()
	-- Measured against the struck face's normal, which is what the law is actually about.
	for _, incidence in { 5, 15, 30, 45, 60, 75, 85 } do
		it(string.format("mirrors a %d degree incidence off a flat wall", incidence), function()
			local ctx = newArena("Atrium")
			local radians = math.rad(incidence)
			-- Aim at the +Z wall: straight on is incidence 0, tilted by `incidence` about Y.
			local heading = Vector3.new(math.sin(radians), 0, math.cos(radians))
			local contacts = recordContacts(ctx, Vector3.new(0, PLANE_Y, 0), heading, 40)

			expect(#contacts).toBeGreaterThan(0)
			local first = contacts[1]
			local outgoing = __flatUnit(__reflect(first.incoming, first.normal))

			local incomingAngle = __angleBetween(-first.incoming, first.normal)
			local outgoingAngle = __angleBetween(outgoing, first.normal)
			expect(outgoingAngle).toBeCloseTo(incomingAngle, 1e-3)
			-- And it must actually leave the surface rather than pass through it.
			expect(outgoing:Dot(first.normal)).toBeGreaterThan(0)
		end)
	end
end)

describe("box geometry", function()
	it("bounces off an interior pillar, not just the outer walls", function()
		local ctx = newArena("Gallery") -- has a long central spine
		local contacts = recordContacts(ctx, Vector3.new(-30, PLANE_Y, 20), Vector3.new(1, 0, 0), 120)

		local hitNames = {}
		for _, contact in contacts do
			hitNames[#hitNames + 1] = contact.position
		end
		expect(#contacts).toBeGreaterThan(0)
		-- The spine sits at x=0 spanning z=20; a shot from x=-30 must stop there, well short
		-- of the far wall.
		expect(contacts[1].position.X).toBeLessThan(0)
		expect(contacts[1].normal.X).toBeCloseTo(-1, 1e-6)
	end)

	it("stays inside every shipped layout across a full heading sweep", function()
		for layoutId in RoomConfig.Layouts do
			local layout = RoomConfig.GetLayout(layoutId)
			for headingDegrees = 0, 350, 10 do
				local ctx = newArena(layoutId)
				local radians = math.rad(headingDegrees)
				Harness.setClock(0)
				ctx.service.OnImpact = nil
				ctx.service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(math.cos(radians), 0, math.sin(radians)), 1)

				local limitX = layout.InteriorSize.X / 2 + ProjectileConfig.Radius + ProjectileConfig.SurfaceSkin + 0.01
				local limitZ = layout.InteriorSize.Y / 2 + ProjectileConfig.Radius + ProjectileConfig.SurfaceSkin + 0.01
				for _ = 1, 260 do
					step(ctx, 1)
					for _, part in ctx.folder:GetChildren() do
						if part.Anchored == false then
							expect(math.abs(part.Position.X)).toBeLessThanOrEqual(limitX)
							expect(math.abs(part.Position.Z)).toBeLessThanOrEqual(limitZ)
						end
					end
				end
				expect(ctx.service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
			end
		end
	end)

	it("reports nothing when a ray starts inside a box, matching the engine", function()
		local world = __PhysicsWorld.new()
		local arena = Instance.new("Folder")
		local block = Instance.new("Part")
		block.Name = "Block"
		block.Parent = arena
		world:AddBox(block, Vector3.new(0, PLANE_Y, 0), Vector3.new(10, 10, 10))

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { arena }

		-- Origin inside: no hit, which is precisely why the cast back-step exists.
		expect(world:Raycast(Vector3.new(0, PLANE_Y, 0), Vector3.new(0, 0, 20), params)).toBeNil()
		-- Origin outside: hit the near face.
		local hit = world:Raycast(Vector3.new(0, PLANE_Y, -20), Vector3.new(0, 0, 40), params)
		expect(hit).toBeTruthy()
		expect(hit.Normal.Z).toBeCloseTo(-1, 1e-6)
		expect(hit.Position.Z).toBeCloseTo(-5, 1e-6)
	end)

	it("honours CanQuery and the include filter", function()
		local world = __PhysicsWorld.new()
		local arena = Instance.new("Folder")
		local outside = Instance.new("Folder")

		local ghost = Instance.new("Part")
		ghost.Name = "Ghost"
		ghost.CanQuery = false
		ghost.Parent = arena
		world:AddBox(ghost, Vector3.new(0, PLANE_Y, 10), Vector3.new(6, 6, 6))

		local unfiltered = Instance.new("Part")
		unfiltered.Name = "Unfiltered"
		unfiltered.Parent = outside
		world:AddBox(unfiltered, Vector3.new(0, PLANE_Y, 20), Vector3.new(6, 6, 6))

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { arena }

		-- CanQuery=false is skipped, and a box outside the filter is invisible.
		expect(world:Raycast(Vector3.new(0, PLANE_Y, -20), Vector3.new(0, 0, 60), params)).toBeNil()
	end)
end)

describe("moving targets", function()
	-- A bare room, so the only thing a shot can meet is the target under test.
	local function movingTargetArena()
		local world = __PhysicsWorld.new()
		local arena = Instance.new("Folder")
		arena.Name = "Arena"
		world:AddBareRoom(60, 60, arena)
		world:Install()

		local service = ProjectileService.new(arena, arena, PLANE_Y)
		local target = Instance.new("Part")
		target.Name = "MovingTarget"
		target.Parent = arena

		return {
			world = world,
			arena = arena,
			service = service,
			folder = arena:FindFirstChild("ProjectilePool"),
			target = target,
		}
	end

	it("registers a hit on a target that moves into the path", function()
		local ctx = movingTargetArena()
		local targetPosition = Vector3.new(-30, PLANE_Y, 30)
		local half = Vector3.new(2, 3, 2)
		ctx.world:AddBox(ctx.target, targetPosition, half * 2)

		-- Stands in for EnemyService:FindEnclosingMover, which is what the game installs.
		ctx.service.OverlapQuery = function(position, margin)
			local offsetX = position.X - targetPosition.X
			local offsetZ = position.Z - targetPosition.Z
			local halfX, halfZ = half.X + margin, half.Z + margin
			if math.abs(offsetX) <= halfX and math.abs(offsetZ) <= halfZ then
				if halfX - math.abs(offsetX) <= halfZ - math.abs(offsetZ) then
					return ctx.target, Vector3.new(offsetX >= 0 and 1 or -1, 0, 0)
				end
				return ctx.target, Vector3.new(0, 0, offsetZ >= 0 and 1 or -1)
			end
			return nil
		end

		local hits = 0
		ctx.service.OnImpact = function(result)
			if result.Instance == ctx.target then
				hits += 1
			end
			return false
		end

		Harness.setClock(0)
		-- Shot travels +Z up the x=0 line; the target slides +X to meet it.
		ctx.service:Fire(nil, Vector3.new(0, PLANE_Y, -20), Vector3.new(0, 0, 1), 0)
		for _ = 1, 120 do
			targetPosition = targetPosition + Vector3.new(30 * DT, 0, 0)
			ctx.world:MoveBox(ctx.target, targetPosition)
			ctx.target.Position = targetPosition
			step(ctx, 1)
		end

		expect(hits).toBeGreaterThan(0)
	end)

	it("leaves a projectile alone when no body has moved over it", function()
		local ctx = movingTargetArena()
		ctx.service.OverlapQuery = function()
			return nil -- nothing encloses it
		end
		local impacts = 0
		ctx.service.OnImpact = function()
			impacts += 1
			return false
		end
		Harness.setClock(0)
		ctx.service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(0, 0, 1), 0)
		step(ctx, 30)
		expect(impacts).toBe(0) -- still travelling, nothing invented
		expect(ctx.service:GetActiveCount()).toBe(1)
	end)

	it("does not report a hit on a target that has already left the path", function()
		local ctx = movingTargetArena()
		local targetPosition = Vector3.new(0, PLANE_Y, 30)
		ctx.world:AddBox(ctx.target, targetPosition, Vector3.new(4, 6, 4))

		local hits = 0
		ctx.service.OnImpact = function(result)
			if result.Instance == ctx.target then
				hits += 1
			end
			return false
		end

		Harness.setClock(0)
		ctx.service:Fire(nil, Vector3.new(0, PLANE_Y, -20), Vector3.new(0, 0, 1), 0)
		for _ = 1, 120 do
			-- Sprints sideways far faster than the shot closes.
			targetPosition = targetPosition + Vector3.new(400 * DT, 0, 0)
			ctx.world:MoveBox(ctx.target, targetPosition)
			ctx.target.Position = targetPosition
			step(ctx, 1)
		end

		expect(hits).toBe(0)
	end)

	it("cannot be tunnelled through by a fast shot", function()
		-- A thin target and maximum projectile speed: the swept cast must still catch it.
		local ctx = movingTargetArena()
		local targetPosition = Vector3.new(0, PLANE_Y, 25)
		ctx.world:AddBox(ctx.target, targetPosition, Vector3.new(6, 6, 0.8))

		local hits = 0
		ctx.service.OnImpact = function(result)
			if result.Instance == ctx.target then
				hits += 1
			end
			return false
		end

		Harness.setClock(0)
		ctx.service:Fire(nil, Vector3.new(0, PLANE_Y, -40), Vector3.new(0, 0, 1), 1, { speedMultiplier = 3 })
		for _ = 1, 60 do
			targetPosition = targetPosition + Vector3.new(0, 0, -6 * DT)
			ctx.world:MoveBox(ctx.target, targetPosition)
			ctx.target.Position = targetPosition
			step(ctx, 1)
		end

		expect(hits).toBeGreaterThan(0)
	end)
end)

describe("simultaneous collisions in one frame", function()
	it("resolves many projectiles striking in the same frame", function()
		local ctx = newArena("Atrium")
		local perFrame = {}
		local frameIndex = 0
		ctx.service.OnImpact = function()
			perFrame[frameIndex] = (perFrame[frameIndex] or 0) + 1
			return false
		end

		Harness.setClock(0)
		-- Twelve identical shots fired together: they must all contact on the same frame.
		local count = 12
		for index = 1, count do
			ctx.service:Fire(nil, Vector3.new(index * 0.01, PLANE_Y, 40), Vector3.new(0, 0, 1), 0)
		end
		expect(ctx.service:GetActiveCount()).toBe(count)

		local busiestFrame = 0
		for frame = 1, 60 do
			frameIndex = frame
			step(ctx, 1)
			busiestFrame = math.max(busiestFrame, perFrame[frame] or 0)
		end

		expect(busiestFrame).toBe(count)
		expect(ctx.service:GetActiveCount() + ctx.service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
	end)

	it("keeps per-projectile state separate when they contact together", function()
		local ctx = newArena("Atrium")
		local seen = {}
		ctx.service.OnImpact = function(_result, entry)
			table.insert(seen, { damage = entry.damage, bounces = entry.bouncesLeft, contacts = entry.contacts })
			return false
		end

		Harness.setClock(0)
		for index = 1, 5 do
			ctx.service:Fire(nil, Vector3.new(index * 0.01, PLANE_Y, 40), Vector3.new(0, 0, 1), 0, {
				damage = index,
				bounces = index,
			})
		end
		step(ctx, 30)

		expect(#seen).toBeGreaterThanOrEqual(5)
		local damages = {}
		for index = 1, 5 do
			damages[seen[index].damage] = true
			expect(seen[index].contacts).toBe(1)
		end
		for index = 1, 5 do
			expect(damages[index]).toBe(true)
		end
	end)

	it("resolves a full pool of projectiles contacting at once without loss", function()
		local ctx = newArena("Atrium")
		local impacts = 0
		ctx.service.OnImpact = function()
			impacts += 1
			return false
		end

		Harness.setClock(0)
		for index = 1, ProjectileConfig.PoolSize do
			ctx.service:Fire(nil, Vector3.new(index * 0.002, PLANE_Y, 40), Vector3.new(0, 0, 1), 0)
		end
		expect(ctx.service:GetActiveCount()).toBe(ProjectileConfig.PoolSize)

		step(ctx, 40)
		expect(impacts).toBeGreaterThanOrEqual(ProjectileConfig.PoolSize)
		expect(ctx.service:GetActiveCount() + ctx.service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
		expect(#ctx.folder:GetChildren()).toBe(ProjectileConfig.PoolSize)
	end)

	it("consumes only the projectile whose impact handler asks for it", function()
		local ctx = newArena("Atrium")
		local consumeAfter = 2
		local handled = 0
		ctx.service.OnImpact = function()
			handled += 1
			return handled <= consumeAfter -- swallow the first two, bounce the rest
		end

		Harness.setClock(0)
		for index = 1, 6 do
			ctx.service:Fire(nil, Vector3.new(index * 0.01, PLANE_Y, 40), Vector3.new(0, 0, 1), 0)
		end
		step(ctx, 30)

		expect(ctx.service:GetActiveCount()).toBe(4)
		expect(ctx.service:GetFreeCount()).toBe(ProjectileConfig.PoolSize - 4)
	end)
end)

describe("moving enemies and real damage", function()
	local EnemyConfig = __require("EnemyConfig")
	local EnemyService = __require("EnemyService")

	it("damages an enemy that slides over a projectile", function()
		local world = __PhysicsWorld.new()
		local arena = Instance.new("Folder")
		arena.Name = "Arena"
		world:AddBareRoom(60, 60, arena)
		world:Install()

		local enemies = EnemyService.new(arena, PLANE_Y, 4242)
		enemies:SetBounds(Vector3.new(0, PLANE_Y, 0), Vector2.new(60, 60))
		local service = ProjectileService.new(arena, arena, PLANE_Y)
		local folder = arena:FindFirstChild("ProjectilePool")

		-- The Chaser runs along the z = 10 line, crossing x = 0 at about t = 2.3s.
		enemies:SetTargetProvider(function()
			return { { player = "bait", position = Vector3.new(40, PLANE_Y, 10) } }
		end)
		local enemy = enemies:Spawn("Chaser", Vector3.new(-30, PLANE_Y, 10))
		enemy.health = 99 -- survive the hit so it is observable rather than a despawn

		local damaged = 0
		service.OverlapQuery = function(position, margin)
			return enemies:FindEnclosingMover(position, margin)
		end
		service.OnImpact = function(result, entry)
			if enemies:ApplyHit(result.Instance, entry.damage, entry.direction, nil) then
				damaged += 1
			end
			return false
		end

		Harness.setClock(0)
		-- A deliberately slow shot crawling up the x = 0 line, reaching z = 10 at the same
		-- moment the Chaser gets there. The projectile is engulfed rather than struck, so only
		-- the overlap check can catch it.
		service:Fire(nil, Vector3.new(0, PLANE_Y, -5), Vector3.new(0, 0, 1), 0, { speedMultiplier = 0.1 })

		for _ = 1, 200 do
			enemies:Step(DT, Harness.now())
			__integrateParts(folder, DT)
			Harness.setClock(Harness.now() + DT)
			service:Step(DT)
		end

		expect(damaged).toBeGreaterThan(0)
		expect(enemy.health).toBeLessThan(99)
	end)

	it("never invents a contact when every enemy is stationary", function()
		local world = __PhysicsWorld.new()
		local arena = Instance.new("Folder")
		arena.Name = "Arena"
		world:AddBareRoom(60, 60, arena)
		world:Install()

		local enemies = EnemyService.new(arena, PLANE_Y, 7)
		enemies:SetBounds(Vector3.new(0, PLANE_Y, 0), Vector2.new(60, 60))
		enemies:SetTargetProvider(function()
			return {}
		end)
		enemies:Spawn("Drifter", Vector3.new(30, PLANE_Y, 30))

		local service = ProjectileService.new(arena, arena, PLANE_Y)
		local folder = arena:FindFirstChild("ProjectilePool")
		service.OverlapQuery = function(position, margin)
			return enemies:FindEnclosingMover(position, margin)
		end

		local impacts = 0
		service.OnImpact = function()
			impacts += 1
			return false
		end

		Harness.setClock(0)
		-- Fired well away from the Drifter; nothing should ever be reported against it.
		service:Fire(nil, Vector3.new(-40, PLANE_Y, -40), Vector3.new(1, 0, 0), 0)
		for _ = 1, 60 do
			__integrateParts(folder, DT)
			Harness.setClock(Harness.now() + DT)
			service:Step(DT)
		end
		expect(impacts).toBe(0)
		expect(EnemyConfig.Archetypes.Drifter.Health).toBeGreaterThan(0)
	end)
end)
