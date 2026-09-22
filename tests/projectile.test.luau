-- Exercises the real ProjectileService/ProjectilePool/FireValidator against a stub box room.
local ProjectileConfig = __require("ProjectileConfig")
local ProjectilePool = __require("ProjectilePool")
local ProjectileService = __require("ProjectileService")
local FireValidator = __require("FireValidator")

local HALF = 60
local wallPart = Instance.new("Part")
wallPart.Name = "TestWall"

-- Nearest intersection with the four interior wall planes of a box room.
local function boxRoomRaycast(origin, delta)
	local length = delta.Magnitude
	if length <= 0 then
		return nil
	end
	local direction = delta.Unit
	local planes = {
		{ axis = "X", at = HALF, normal = Vector3.new(-1, 0, 0) },
		{ axis = "X", at = -HALF, normal = Vector3.new(1, 0, 0) },
		{ axis = "Z", at = HALF, normal = Vector3.new(0, 0, -1) },
		{ axis = "Z", at = -HALF, normal = Vector3.new(0, 0, 1) },
	}
	local bestT, bestNormal
	for _, plane in planes do
		local component = direction[plane.axis]
		if math.abs(component) > 1e-9 then
			local t = (plane.at - origin[plane.axis]) / component
			if t > 1e-6 and t <= length and (not bestT or t < bestT) then
				bestT, bestNormal = t, plane.normal
			end
		end
	end
	if not bestT then
		return nil
	end
	return { Position = origin + direction * bestT, Normal = bestNormal, Instance = wallPart, Distance = bestT }
end

__raycastHandler = boxRoomRaycast

local PLANE_Y = 3
local DT = 1 / 60

local function newService()
	local parent = Instance.new("Folder")
	parent.Name = "TestWorkspace"
	return ProjectileService.new(parent, parent, PLANE_Y), parent
end

-- Mirrors Roblox frame order: physics integrates velocity, then Heartbeat runs game logic.
local function advance(service, poolFolder, frames)
	for _ = 1, frames do
		for _, part in poolFolder:GetChildren() do
			if part.Anchored == false then
				part.Position = part.Position + part.AssemblyLinearVelocity * DT
			end
		end
		Harness.setClock(Harness.now() + DT)
		service:Step(DT)
	end
end

local function poolFolderOf(parent)
	return parent:FindFirstChild("ProjectilePool")
end

describe("ProjectilePool", function()
	it("pre-warms exactly PoolSize parts and never allocates beyond it", function()
		local parent = Instance.new("Folder")
		local pool = ProjectilePool.new(parent)
		expect(pool:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
		expect(#parent:FindFirstChild("ProjectilePool"):GetChildren()).toBe(ProjectileConfig.PoolSize)

		local taken = {}
		for _ = 1, ProjectileConfig.PoolSize do
			local part = pool:Acquire(Vector3.zero)
			expect(part).toBeTruthy()
			table.insert(taken, part)
		end
		expect(pool:GetFreeCount()).toBe(0)
		expect(pool:Acquire(Vector3.zero)).toBeNil()
		expect(#parent:FindFirstChild("ProjectilePool"):GetChildren()).toBe(ProjectileConfig.PoolSize)

		for _, part in taken do
			pool:Release(part)
		end
		expect(pool:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
	end)

	it("parks released parts anchored, invisible and out of play", function()
		local pool = ProjectilePool.new(Instance.new("Folder"))
		local part = pool:Acquire(Vector3.new(10, 3, 10))
		expect(part.Anchored).toBe(false)
		expect(part.Transparency).toBe(0)
		pool:Release(part)
		expect(part.Anchored).toBe(true)
		expect(part.Transparency).toBe(1)
		expect(part.Position).toEqual(ProjectileConfig.StoragePosition)
		expect(part.AssemblyLinearVelocity).toEqual(Vector3.zero)
	end)
end)

describe("ProjectileService", function()
	it("despawns after the configured bounce budget", function()
		local service, parent = newService()
		Harness.setClock(0)
		service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(0, 0, 1), 1)
		expect(service:GetActiveCount()).toBe(1)

		advance(service, poolFolderOf(parent), 240)
		expect(service:GetActiveCount()).toBe(0)
		expect(service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
	end)

	it("despawns on lifetime expiry even without any contact", function()
		local service, parent = newService()
		Harness.setClock(0)
		-- A single slow projectile aimed down the long axis will not spend its budget in 4s.
		service:Fire(nil, Vector3.new(0, PLANE_Y, -55), Vector3.new(0, 0, 1), 0)
		local frames = math.ceil(ProjectileConfig.Lifetime / DT) + 2
		advance(service, poolFolderOf(parent), frames)
		expect(service:GetActiveCount()).toBe(0)
		expect(service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
	end)

	it("keeps every projectile inside the room across randomised headings", function()
		local service, parent = newService()
		local folder = poolFolderOf(parent)
		Harness.setClock(0)

		local escapes, maxOvershoot = 0, 0
		local random = Random and Random.new(20260922) or nil
		local seed = 7
		local function nextRandom()
			if random then
				return random:NextNumber()
			end
			-- Deterministic LCG fallback so results are reproducible without Random.
			seed = (1103515245 * seed + 12345) % 2147483648
			return seed / 2147483648
		end

		for _ = 1, 120 do
			local angle = nextRandom() * math.pi * 2
			local startX = (nextRandom() * 2 - 1) * 50
			local startZ = (nextRandom() * 2 - 1) * 50
			service:Fire(
				nil,
				Vector3.new(startX, PLANE_Y, startZ),
				Vector3.new(math.cos(angle), 0, math.sin(angle)),
				nextRandom()
			)
		end
		expect(service:GetActiveCount()).toBe(120)

		for _ = 1, 300 do
			advance(service, folder, 1)
			for _, part in folder:GetChildren() do
				if part.Anchored == false then
					local overshootX = math.abs(part.Position.X) - HALF
					local overshootZ = math.abs(part.Position.Z) - HALF
					maxOvershoot = math.max(maxOvershoot, overshootX, overshootZ)
					if overshootX > 1 or overshootZ > 1 then
						escapes += 1
					end
				end
			end
		end

		expect(escapes).toBe(0)
		expect(maxOvershoot).toBeLessThan(ProjectileConfig.Radius + ProjectileConfig.SurfaceSkin + 0.01)
		expect(service:GetActiveCount()).toBe(0)
		expect(service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
	end)

	it("holds projectiles on their travel plane", function()
		local service, parent = newService()
		local folder = poolFolderOf(parent)
		Harness.setClock(0)
		service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(1, 0, 0.3), 0.8)
		advance(service, folder, 100)
		for _, part in folder:GetChildren() do
			if part.Anchored == false then
				expect(part.Position.Y).toBeCloseTo(PLANE_Y, 0.01)
			end
		end
	end)

	it("drops shots instead of allocating when the pool is dry", function()
		local service, parent = newService()
		Harness.setClock(0)
		local accepted = 0
		for _ = 1, ProjectileConfig.PoolSize + 25 do
			if service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(0, 0, 1), 1) then
				accepted += 1
			end
		end
		expect(accepted).toBe(ProjectileConfig.PoolSize)
		expect(#poolFolderOf(parent):GetChildren()).toBe(ProjectileConfig.PoolSize)
	end)

	it("hands confirmed impacts to OnImpact and consumes the projectile when asked", function()
		local service, parent = newService()
		Harness.setClock(0)
		local impacts = 0
		service.OnImpact = function(result, entry)
			impacts += 1
			expect(result.Instance).toBe(wallPart)
			expect(result.Normal.Magnitude).toBeCloseTo(1, 1e-6)
			expect(entry.contacts).toBe(1)
			expect(entry.damage).toBe(1)
			return true -- consume on first contact
		end
		service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(0, 0, 1), 1)
		advance(service, poolFolderOf(parent), 200)
		expect(impacts).toBe(1)
		expect(service:GetActiveCount()).toBe(0)
		expect(service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
	end)
end)

describe("FireValidator", function()
	local player = Harness.addPlayer("Shooter")
	Harness.giveCharacter(player, Vector3.new(0, 3, 0))

	it("accepts a sane request and returns clamped values", function()
		Harness.setClock(100)
		local root, direction, power = FireValidator.Validate(player, Vector3.new(0, 5, 2), 99)
		expect(root).toBeTruthy()
		expect(direction.Y).toBe(0)
		expect(direction.Magnitude).toBeCloseTo(1, 1e-6)
		expect(power).toBe(ProjectileConfig.MaxPower)
	end)

	it("rate limits repeat requests", function()
		Harness.setClock(200)
		FireValidator.Clear(player)
		expect((FireValidator.Validate(player, Vector3.new(0, 0, 1), 1))).toBeTruthy()
		expect((FireValidator.Validate(player, Vector3.new(0, 0, 1), 1))).toBeNil()
		Harness.setClock(200 + ProjectileConfig.FireCooldown + 1e-4)
		expect((FireValidator.Validate(player, Vector3.new(0, 0, 1), 1))).toBeTruthy()
	end)

	it("rejects malformed directions and powers", function()
		local cases = {
			{ direction = "north", power = 1 },
			{ direction = Vector3.new(0 / 0, 0, 1), power = 1 },
			{ direction = Vector3.new(math.huge, 0, 1), power = 1 },
			{ direction = Vector3.new(0, 1, 0), power = 1 },
			{ direction = Vector3.new(0, 0, 0), power = 1 },
			{ direction = Vector3.new(0, 0, 1), power = "max" },
			{ direction = Vector3.new(0, 0, 1), power = 0 / 0 },
			{ direction = nil, power = nil },
		}
		for index, case in cases do
			Harness.setClock(1000 + index * 10)
			FireValidator.Clear(player)
			local root, reason = FireValidator.Validate(player, case.direction, case.power)
			expect(root).toBeNil()
			expect(type(reason)).toBe("string")
		end
	end)

	it("rejects requests from a player with no live character", function()
		local ghost = Harness.addPlayer("Ghost")
		Harness.setClock(2000)
		expect((FireValidator.Validate(ghost, Vector3.new(0, 0, 1), 1))).toBeNil()

		Harness.giveCharacter(ghost, Vector3.new(0, 3, 0))
		ghost.Character:FindFirstChildOfClass("Humanoid").Health = 0
		Harness.setClock(2100)
		expect((FireValidator.Validate(ghost, Vector3.new(0, 0, 1), 1))).toBeNil()
	end)
end)

describe("muzzle clearance", function()
	it("never spawns a projectile past a wall the shooter is pressed against", function()
		local parent = Instance.new("Folder")
		local service = ProjectileService.new(parent, parent, PLANE_Y)
		Harness.setClock(0)

		-- Standing 1 stud from the +Z wall, firing straight into it.
		service:Fire(nil, Vector3.new(0, PLANE_Y, HALF - 1), Vector3.new(0, 0, 1), 1)
		local folder = poolFolderOf(parent)
		for _, part in folder:GetChildren() do
			if part.Anchored == false then
				expect(part.Position.Z).toBeLessThanOrEqual(HALF)
			end
		end

		advance(service, folder, 260)
		expect(service:GetActiveCount()).toBe(0)
		expect(service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
	end)

	it("still uses the full muzzle offset in open space", function()
		local parent = Instance.new("Folder")
		local service = ProjectileService.new(parent, parent, PLANE_Y)
		Harness.setClock(0)
		service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(0, 0, 1), 1)
		for _, part in poolFolderOf(parent):GetChildren() do
			if part.Anchored == false then
				expect(part.Position.Z).toBeCloseTo(ProjectileConfig.MuzzleOffset, 1e-6)
			end
		end
	end)
end)
