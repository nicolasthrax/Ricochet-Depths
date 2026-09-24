-- Long-running load: repeated runs, sustained projectile traffic and enemy churn must leave
-- every pool at its configured size and the instance count flat.
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local ProjectileConfig = __require("ProjectileConfig")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3
local DT = 1 / 30
local HALF = 60

local wallPart = Instance.new("Part")
wallPart.Name = "SoakWall"

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

local function silentRemote()
	local remote = {}
	function remote:FireClient() end
	function remote:FireAllClients() end
	return remote
end

describe("sustained projectile load", function()
	it("returns the pool to full size after thousands of shots", function()
		__raycastHandler = boxRoomRaycast
		local parent = Instance.new("Folder")
		local service = ProjectileService.new(parent, parent, PLANE_Y)
		local folder = parent:FindFirstChild("ProjectilePool")
		Harness.setClock(0)

		local random = Random.new(99)
		local fired = 0
		-- Roughly two simulated minutes of continuous fire at the pool's limit.
		for frame = 1, 3600 do
			for _ = 1, 4 do
				local angle = random:NextNumber() * math.pi * 2
				if service:Fire(
					nil,
					Vector3.new(random:NextNumber(-40, 40), PLANE_Y, random:NextNumber(-40, 40)),
					Vector3.new(math.cos(angle), 0, math.sin(angle)),
					random:NextNumber()
				) then
					fired += 1
				end
			end

			for _, part in folder:GetChildren() do
				if part.Anchored == false then
					part.Position = part.Position + part.AssemblyLinearVelocity * DT
				end
			end
			Harness.setClock(Harness.now() + DT)
			service:Step(DT)

			expect(service:GetActiveCount() + service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
			expect(#folder:GetChildren()).toBe(ProjectileConfig.PoolSize)
			expect(frame).toBe(frame)
		end

		expect(fired).toBeGreaterThan(1000)
		service:Clear()
		expect(service:GetActiveCount()).toBe(0)
		expect(service:GetFreeCount()).toBe(ProjectileConfig.PoolSize)
		expect(#folder:GetChildren()).toBe(ProjectileConfig.PoolSize)
	end)

	it("never exceeds the pool however hard it is pushed", function()
		__raycastHandler = boxRoomRaycast
		local parent = Instance.new("Folder")
		local service = ProjectileService.new(parent, parent, PLANE_Y)
		Harness.setClock(0)
		for _ = 1, 5000 do
			service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(0, 0, 1), 1)
		end
		expect(service:GetActiveCount()).toBe(ProjectileConfig.PoolSize)
		expect(#parent:FindFirstChild("ProjectilePool"):GetChildren()).toBe(ProjectileConfig.PoolSize)
	end)
end)

describe("enemy churn", function()
	it("holds the pool size across 200 spawn and clear cycles", function()
		local parent = Instance.new("Folder")
		local enemies = EnemyService.new(parent, PLANE_Y, 5150)
		enemies:SetBounds(Vector3.new(0, PLANE_Y, 0), Vector2.new(HALF, HALF))
		enemies:SetTargetProvider(function()
			return { { player = "soak", position = Vector3.new(0, PLANE_Y, 0) } }
		end)
		local folder = parent:FindFirstChild("EnemyPool")
		local archetypes = { "Drifter", "Chaser", "Bulwark" }

		for cycle = 1, 200 do
			for index = 1, 12 do
				enemies:Spawn(archetypes[(index % #archetypes) + 1], Vector3.new(index * 3 - 20, PLANE_Y, cycle % 40))
			end
			for frame = 1, 8 do
				enemies:Step(DT, cycle * 10 + frame * DT)
			end
			enemies:Clear()
			expect(enemies:GetActiveCount()).toBe(0)
			expect(#folder:GetChildren()).toBe(EnemyConfig.PoolSize)
		end
	end)
end)

describe("repeated runs", function()
	it("completes 25 runs back to back with a flat instance count", function()
		__raycastHandler = boxRoomRaycast

		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 808)
		local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
		local net = {}
		for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
			net[name] = silentRemote()
		end
		local upgrades = UpgradeService.new(808)
		local match = MatchService.new({
			rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(808)),
			enemies = enemies,
			upgrades = upgrades,
			projectiles = projectiles,
			rewards = RewardService.new(),
			net = net,
			world = {
				GetPosition = function()
					return Vector3.new(0, PLANE_Y, 0)
				end,
				Teleport = function() end,
			},
		})

		local subject = { Name = "Soaker", UserId = 999 }
		match:RegisterPlayer(subject)

		local clock = 0
		local function step(seconds)
			for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
				clock += DT
				match:Step(DT, clock)
			end
		end

		local baseline
		for run = 1, 25 do
			match:RequestStart(subject, clock)
			step(RunConfig.StartCountdown + DT)

			for roomIndex = 1, RunConfig.RoomCount() do
				__clearRoom(match._rooms, function()
					local guard = 0
					while enemies:GetActiveCount() > 0 and guard < 600 do
						guard += 1
						local enemy = enemies:GetEnemies()[1]
						match:HandleImpact(
							{ Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part },
							{ direction = Vector3.new(0, 0, 1), damage = 99, damagePerBounce = 0, contacts = 1, wallBounces = 1, shooter = subject },
							clock
						)
					end
				end, step)
				step(DT)
				if roomIndex < RunConfig.RoomCount() then
					local offer = upgrades:GetOffer(subject)
					if offer then
						match:ChooseUpgrade(subject, offer.id, offer.cards[1].Id, clock)
					end
					step(RunConfig.TransitionDuration + DT * 2)
				end
			end

			step(RunConfig.ResultsDuration + DT * 3)
			expect(match:GetState()).toBe(RunConfig.States.Lobby)
			expect(enemies:GetActiveCount()).toBe(0)
			expect(projectiles:GetActiveCount()).toBe(0)
			expect(projectiles:GetFreeCount()).toBe(ProjectileConfig.PoolSize)

			-- Rooms are rebuilt each run; the count must settle, not creep.
			if run == 3 then
				baseline = Harness.instanceCount()
			elseif run > 3 then
				expect(Harness.instanceCount()).toBe(baseline)
			end
		end

		local state = match:GetPlayerState(subject)
		expect(state.kills).toBe(0)
		expect(#state.upgradeOrder).toBe(0)
	end)
end)
