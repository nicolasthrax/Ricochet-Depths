-- Direct coverage for the server modules that previously only ran incidentally: the remote
-- boundary, telemetry, room construction, the world adapter, the datastore wrapper and the
-- behaviour functions.
local DataStoreProvider = __require("DataStoreProvider")
local EnemyBehaviour = __require("EnemyBehaviour")
local EnemyService = __require("EnemyService")
local LobbyBuilder = __require("LobbyBuilder")
local PartPool = __require("PartPool")
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerState = __require("PlayerState")
local RemoteGuard = __require("RemoteGuard")
local RemoteRouter = __require("RemoteRouter")
local Remotes = __require("Remotes")
local RoomBuilder = __require("RoomBuilder")
local RoomConfig = __require("RoomConfig")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunSummary = __require("RunSummary")
local TelemetryService = __require("TelemetryService")
local UpgradeConfig = __require("UpgradeConfig")

local PLANE_Y = 3

describe("RemoteGuard", function()
	it("allows a burst then refuses until tokens refill", function()
		local guard = RemoteGuard.new({ Fire = { Cooldown = 0.1, Burst = 3 } })
		local player = { Name = "A" }

		for _ = 1, 3 do
			expect((guard:Check(player, "Fire", 0))).toBe(true)
		end
		local ok, reason = guard:Check(player, "Fire", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("rate limited")

		-- One cooldown later, exactly one more token is available.
		expect((guard:Check(player, "Fire", 0.1))).toBe(true)
		expect((guard:Check(player, "Fire", 0.1))).toBe(false)
	end)

	it("never refills past the burst allowance", function()
		local guard = RemoteGuard.new({ Fire = { Cooldown = 0.1, Burst = 2 } })
		local player = { Name = "A" }
		-- Idle for a long time, then spam: only the burst gets through.
		local allowed = 0
		for _ = 1, 10 do
			if guard:Check(player, "Fire", 1000) then
				allowed += 1
			end
		end
		expect(allowed).toBe(2)
	end)

	it("keeps separate buckets per player and per action", function()
		local guard = RemoteGuard.new({
			Fire = { Cooldown = 1, Burst = 1 },
			Chat = { Cooldown = 1, Burst = 1 },
		})
		local first, second = { Name = "A" }, { Name = "B" }

		expect((guard:Check(first, "Fire", 0))).toBe(true)
		expect((guard:Check(first, "Fire", 0))).toBe(false)
		expect((guard:Check(second, "Fire", 0))).toBe(true) -- other player unaffected
		expect((guard:Check(first, "Chat", 0))).toBe(true) -- other action unaffected
	end)

	it("allows any action it has no rule for", function()
		local guard = RemoteGuard.new({})
		for _ = 1, 50 do
			expect((guard:Check({ Name = "A" }, "Unruled", 0))).toBe(true)
		end
	end)

	it("forgets a player on clear", function()
		local guard = RemoteGuard.new({ Fire = { Cooldown = 10, Burst = 1 } })
		local player = { Name = "A" }
		expect((guard:Check(player, "Fire", 0))).toBe(true)
		expect((guard:Check(player, "Fire", 0))).toBe(false)
		guard:Clear(player)
		expect((guard:Check(player, "Fire", 0))).toBe(true)
	end)
end)

describe("RemoteRouter", function()
	local function buildRouter()
		local calls = { fire = {}, choose = {}, start = 0, lobby = 0, settings = {} }
		local match = {}
		function match:HandleFire(player, direction, power)
			table.insert(calls.fire, { player = player, direction = direction, power = power })
		end
		function match:ChooseUpgrade(player, offerId, cardId)
			table.insert(calls.choose, { player = player, offerId = offerId, cardId = cardId })
		end
		function match:RequestStart()
			calls.start += 1
		end
		function match:RequestReturnToLobby()
			calls.lobby += 1
		end

		local persistence = {}
		function persistence:ApplySettings(player, settings)
			table.insert(calls.settings, { player = player, settings = settings })
			return settings
		end

		local router = RemoteRouter.new(match, persistence, function() end)
		router:Bind()
		return router, calls
	end

	it("passes a well-formed fire request through to the match", function()
		local router, calls = buildRouter()
		local player = { Name = "Shooter", UserId = 1 }
		Harness.setClock(500)

		Remotes.Get("FireProjectile").OnServerEvent:Fire(player, Vector3.new(0, 0, 1), 0.5)
		expect(#calls.fire).toBe(1)
		expect(calls.fire[1].player).toBe(player)
		expect(calls.fire[1].power).toBe(0.5)
		router:Destroy()
	end)

	it("rate limits a spamming client at the boundary", function()
		local router, calls = buildRouter()
		local player = { Name = "Spammer", UserId = 2 }
		Harness.setClock(1000)

		for _ = 1, 40 do
			Remotes.Get("FireProjectile").OnServerEvent:Fire(player, Vector3.new(0, 0, 1), 1)
		end
		-- The burst allowance gets through; the rest never reaches the match at all.
		expect(#calls.fire).toBe(RunConfig.RemoteRules.Fire.Burst)
		expect(#calls.fire).toBeLessThan(40)
		router:Destroy()
	end)

	it("ignores a settings payload that is not a table", function()
		local router, calls = buildRouter()
		local player = { Name = "Fiddler", UserId = 3 }
		Harness.setClock(2000)

		Remotes.Get("UpdateSettings").OnServerEvent:Fire(player, "not a table")
		Remotes.Get("UpdateSettings").OnServerEvent:Fire(player, 42)
		expect(#calls.settings).toBe(0)

		Remotes.Get("UpdateSettings").OnServerEvent:Fire(player, { ReducedFlash = true })
		expect(#calls.settings).toBe(1)
		router:Destroy()
	end)

	it("forwards run control requests", function()
		local router, calls = buildRouter()
		local player = { Name = "Starter", UserId = 4 }
		Harness.setClock(3000)
		Remotes.Get("RequestStartRun").OnServerEvent:Fire(player)
		Remotes.Get("RequestReturnToLobby").OnServerEvent:Fire(player)
		expect(calls.start).toBe(1)
		expect(calls.lobby).toBe(1)
		router:Destroy()
	end)

	it("disconnects everything on destroy", function()
		local router, calls = buildRouter()
		local player = { Name = "Gone", UserId = 5 }
		Harness.setClock(4000)
		router:Destroy()

		Remotes.Get("FireProjectile").OnServerEvent:Fire(player, Vector3.new(0, 0, 1), 1)
		Remotes.Get("RequestStartRun").OnServerEvent:Fire(player)
		expect(#calls.fire).toBe(0)
		expect(calls.start).toBe(0)
	end)

	it("leaves no listeners behind after repeated bind and destroy cycles", function()
		local signal = rawget(Remotes.Get("FireProjectile"), "OnServerEvent")
		local baseline = signal:CountHandlers()
		for _ = 1, 10 do
			local router = buildRouter()
			router:Destroy()
		end
		expect(signal:CountHandlers()).toBe(baseline)
	end)
end)

describe("TelemetryService", function()
	local function collector()
		local events = {}
		local service = TelemetryService.new(function(name, payload, now)
			table.insert(events, { name = name, payload = payload, now = now })
		end)
		return service, events
	end

	it("emits within budget and drops beyond it", function()
		local service, events = collector()
		local budget = 120 -- DefaultBudget
		for index = 1, budget + 50 do
			service:Log("SomeEvent", { Index = index }, 0)
		end
		expect(#events).toBe(budget)
		expect(service:GetStats().dropped).toBe(50)
		expect(service:GetStats().emitted).toBe(budget)
	end)

	it("opens a fresh window once the interval passes", function()
		local service, events = collector()
		for _ = 1, 200 do
			service:Log("SomeEvent", {}, 0)
		end
		local firstWindow = #events
		for _ = 1, 10 do
			service:Log("SomeEvent", {}, 61)
		end
		expect(#events).toBe(firstWindow + 10)
	end)

	it("applies a tighter budget to noisy events", function()
		local service, events = collector()
		for _ = 1, 100 do
			service:Log("ShotFired", {}, 0)
		end
		expect(#events).toBe(30) -- the ShotFired budget
	end)


	it("truncates error detail and keeps the category", function()
		local service, events = collector()
		service:LogError("ProfileLoadFailed", string.rep("x", 500), 0)
		expect(events[1].name).toBe("Error")
		expect(events[1].payload.Category).toBe("ProfileLoadFailed")
		expect(#events[1].payload.Detail).toBeLessThanOrEqual(120)
	end)

	it("emits nothing at all when disabled", function()
		local service, events = collector()
		service:SetEnabled(false)
		for _ = 1, 20 do
			service:Log("SomeEvent", {}, 0)
			service:LogError("Category", "detail", 0)
		end
		expect(#events).toBe(0)
	end)

	it("survives a missing sink and a nil payload", function()
		local service = TelemetryService.new(nil)
		expect(service:Log("SomeEvent", nil, 0)).toBe(true)
	end)
end)

describe("RoomBuilder", function()
	it("builds four walls, a floor, a pad and every obstacle", function()
		local parent = Instance.new("Folder")
		local room, bounds, layout = RoomBuilder.Build(parent, "Atrium")
		expect(room).toBeTruthy()

		local names = {}
		for _, child in room:GetChildren() do
			names[child.Name] = true
		end
		for _, required in { "Floor", "WallNorth", "WallSouth", "WallEast", "WallWest", "PlayerSpawn" } do
			expect(names[required]).toBe(true)
		end
		for index = 1, #layout.Obstacles do
			expect(names["Obstacle" .. index]).toBe(true)
		end

		-- Bounds sit inside the walls so nothing can be clamped into geometry.
		expect(bounds.half.X).toBeLessThan(layout.InteriorSize.X / 2)
		expect(bounds.half.Y).toBeLessThan(layout.InteriorSize.Y / 2)
		expect(room:GetAttribute("LayoutId")).toBe("Atrium")
	end)

	it("keeps decor out of play: no collisions, queries or touches, and off the projectile plane", function()
		local room = RoomBuilder.Build(Instance.new("Folder"), "Atrium")
		local decor = room:FindFirstChild("Decor")
		expect(decor).toBeTruthy()
		local planeY = RoomConfig.FloorY + __require("ProjectileConfig").PlaneHeight
		local count = 0
		for _, part in decor:GetChildren() do
			count += 1
			expect(part.CanCollide).toBe(false)
			expect(part.CanQuery).toBe(false)
			expect(part.CanTouch).toBe(false)
			local bottom = part.Position.Y - part.Size.Y / 2
			local top = part.Position.Y + part.Size.Y / 2
			expect(top < planeY - 1 or bottom > planeY + 1).toBe(true)
		end
		expect(count).toBeGreaterThan(0)
	end)

	it("refuses an unknown layout with a reason instead of erroring", function()
		local room, reason = RoomBuilder.Build(Instance.new("Folder"), "NoSuchLayout")
		expect(room).toBeNil()
		expect(type(reason)).toBe("string")
	end)

	it("builds every shipped layout", function()
		for layoutId in RoomConfig.Layouts do
			local room = RoomBuilder.Build(Instance.new("Folder"), layoutId)
			expect(room).toBeTruthy()
		end
	end)
end)

describe("RoomService", function()
	local function build()
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 5)
		enemies:SetTargetProvider(function()
			return { { player = "x", position = Vector3.new(0, PLANE_Y, 0) } }
		end)
		return RoomService.new(arena, enemies, PLANE_Y, Random.new(5)), enemies, arena
	end

	it("spawns exactly what the room definition asks for", function()
		local rooms, enemies = build()
		local definition = RunConfig.Rooms[2]
		local current = rooms:Load(definition, 0)

		local expected = 0
		for _, group in definition.Spawns do
			expected += group.Count
		end
		expect(current.spawned).toBe(expected)
		expect(current.failed).toBe(0)
		expect(enemies:GetActiveCount()).toBe(expected)
		expect(rooms:GetRemaining()).toBe(expected)
	end)

	it("destroys the previous room when loading the next", function()
		local rooms, _, arena = build()
		rooms:Load(RunConfig.Rooms[1], 0)
		local firstRoom = arena:FindFirstChild("Room")
		rooms:Load(RunConfig.Rooms[2], 10)
		expect(rawget(firstRoom, "_destroyed")).toBe(true)
		-- Exactly one Room folder at a time.
		local roomCount = 0
		for _, child in arena:GetChildren() do
			if child.Name == "Room" then
				roomCount += 1
			end
		end
		expect(roomCount).toBe(1)
	end)

	it("reports cleared once everything is dead", function()
		local rooms, enemies = build()
		rooms:Load(RunConfig.Rooms[1], 0)
		expect(rooms:IsCleared(1)).toBe(false)
		enemies:Clear()
		expect(rooms:IsCleared(1)).toBe(true)
	end)

	it("force-clears past the room time limit", function()
		local rooms = build()
		rooms:Load(RunConfig.Rooms[1], 0)
		expect(rooms:IsCleared(RunConfig.RoomTimeLimit - 1)).toBe(false)
		expect(rooms:IsCleared(RunConfig.RoomTimeLimit)).toBe(true)
		expect(rooms:GetCurrent().timedOut).toBe(true)
	end)

	it("treats a room that spawned nothing as already clear", function()
		local rooms = build()
		rooms:Load({ Id = "Empty", DisplayName = "Empty", Layout = "Atrium", Kind = "Normal", Spawns = {} }, 0)
		expect(rooms:GetCurrent().spawned).toBe(0)
		expect(rooms:IsCleared(0)).toBe(true)
	end)

	it("replaces elite escorts while the core lives, and stops when it dies", function()
		local rooms, enemies = build()
		local vault = RunConfig.GetRoomById("WardenVault")
		expect(vault.EscortRespawn).toBeTruthy()
		local current = rooms:Load(vault, 0)
		expect(current.elite).toBeTruthy()

		-- Kill the escorts; the core should call in replacements.
		for _, enemy in enemies:GetEnemies() do
			if enemy.archetypeId == vault.EscortRespawn.Archetype then
				enemies:Despawn(enemy, "test")
			end
		end
		local afterWipe = enemies:GetActiveCount()
		rooms:Step(1, vault.EscortRespawn.Delay + 1)
		expect(enemies:GetActiveCount()).toBe(afterWipe + 1)

		-- Once the core is gone, no more escorts arrive.
		enemies:Despawn(current.elite, "killed")
		local afterCore = enemies:GetActiveCount()
		rooms:Step(1, vault.EscortRespawn.Delay * 10)
		expect(enemies:GetActiveCount()).toBe(afterCore)
	end)

	it("never caps escorts above the configured maximum", function()
		local rooms, enemies = build()
		local vault = RunConfig.GetRoomById("WardenVault")
		rooms:Load(vault, 0)
		for step = 1, 40 do
			rooms:Step(1, step * vault.EscortRespawn.Delay)
			local escorts = 0
			for _, enemy in enemies:GetEnemies() do
				if enemy.archetypeId == vault.EscortRespawn.Archetype then
					escorts += 1
				end
			end
			expect(escorts).toBeLessThanOrEqual(vault.EscortRespawn.MaxAlive)
		end
	end)

	it("picks a spawn point clear of cover in every layout", function()
		local rooms = build()
		for _, room in RunConfig.Rooms do
			rooms:Load(room, 0)
			local point = rooms:GetSpawnPoint()
			local layout = RoomConfig.GetLayout(room.Layout)
			local clearance = RoomConfig.SpawnPadSize.X / 2 + 1
			for _, obstacle in layout.Obstacles do
				local insideX = math.abs(point.X - obstacle.Offset.X) < obstacle.Size.X / 2 + clearance
				local insideZ = math.abs(point.Z - obstacle.Offset.Y) < obstacle.Size.Y / 2 + clearance
				expect(insideX and insideZ).toBe(false)
			end
			expect(math.abs(point.X)).toBeLessThanOrEqual(layout.InteriorSize.X / 2)
			expect(math.abs(point.Z)).toBeLessThanOrEqual(layout.InteriorSize.Y / 2)
		end
	end)

	it("leaves nothing behind on unload", function()
		local rooms, enemies, arena = build()
		rooms:Load(RunConfig.Rooms[3], 0)
		expect(enemies:GetActiveCount()).toBeGreaterThan(0)
		rooms:Unload()
		expect(enemies:GetActiveCount()).toBe(0)
		expect(arena:FindFirstChild("Room")).toBeNil()
		expect(rooms:GetCurrent()).toBeNil()
	end)
end)

describe("LobbyBuilder", function()
	it("builds a spawn, a pedestal and a start prompt", function()
		local parent = Instance.new("Folder")
		local lobby, prompt = LobbyBuilder.Build(parent)
		expect(lobby).toBeTruthy()
		expect(prompt).toBeTruthy()
		expect(lobby:FindFirstChild("LobbySpawn")).toBeTruthy()

		local pedestal = lobby:FindFirstChild("DescentPedestal")
		expect(pedestal).toBeTruthy()
		expect(pedestal:FindFirstChild("StartRunPrompt")).toBe(prompt)
		-- A prompt works on mouse, touch and gamepad without custom input code.
		expect(prompt.ClassName).toBe("ProximityPrompt")
		expect(prompt.MaxActivationDistance).toBeGreaterThan(0)
	end)

	it("places the lobby far from the arena so geometry cannot overlap", function()
		local parent = Instance.new("Folder")
		local lobby = LobbyBuilder.Build(parent)
		local floor = lobby:FindFirstChild("LobbyFloor")
		local distance = (Vector3.new(floor.Position.X, 0, floor.Position.Z) - Vector3.zero).Magnitude
		local widestLayout = 0
		for _, layout in RoomConfig.Layouts do
			widestLayout = math.max(widestLayout, layout.InteriorSize.X, layout.InteriorSize.Y)
		end
		expect(distance).toBeGreaterThan(widestLayout)
	end)
end)

describe("DataStoreProvider", function()
	it("returns an unavailable store rather than throwing when the API is inaccessible", function()
		local store, scope = DataStoreProvider.Get(true)
		expect(store).toBeTruthy()
		expect(scope).toBe(PlayerDataConfig.DevelopmentScope)
		-- Every call fails, which is what puts a session into read-only mode.
		expect(function()
			store:UpdateAsync("key", function(value)
				return value
			end)
		end).toThrow()
	end)

	it("selects the production scope when not in development", function()
		local _, scope = DataStoreProvider.Get(false)
		expect(scope).toBe(PlayerDataConfig.ProductionScope)
	end)
end)

describe("PartPool", function()
	it("builds once, hands out, refuses when dry and takes parts back", function()
		local parent = Instance.new("Folder")
		local created = 0
		local pool = PartPool.new("TestPool", parent, 5, function()
			created += 1
			return Instance.new("Part")
		end)

		expect(created).toBe(5)
		expect(pool:GetSize()).toBe(5)
		expect(pool:GetFreeCount()).toBe(5)
		expect(pool:GetActiveCount()).toBe(0)

		local taken = {}
		for _ = 1, 5 do
			table.insert(taken, pool:Acquire())
		end
		expect(pool:Acquire()).toBeNil()
		expect(created).toBe(5) -- never allocates on demand
		expect(pool:GetActiveCount()).toBe(5)

		for _, part in taken do
			pool:Release(part)
		end
		expect(pool:GetFreeCount()).toBe(5)

		pool:Destroy()
		expect(pool:GetFreeCount()).toBe(0)
		expect(parent:FindFirstChild("TestPool")).toBeNil()
	end)
end)

describe("RunSummary", function()
	it("reports server-tracked counters and the chosen upgrades in order", function()
		local state = PlayerState.new({ Name = "Summary", UserId = 1 })
		state.roomsCleared = 3
		state.kills = 17
		state.bestChain = 5
		state.shotsFired = 40
		state.damageTaken = 62.7
		state:AddUpgrade(UpgradeConfig.Get("SharpEdge"))
		state:AddUpgrade(UpgradeConfig.Get("LongBounce"))

		local summary = RunSummary.ForPlayer(state, {
			runId = 9,
			outcome = "Extracted",
			duration = 372.45,
			roomCount = 4,
			eliteCleared = true,
		})

		expect(summary.Outcome).toBe("Extracted")
		expect(summary.RoomsCleared).toBe(3)
		expect(summary.EnemiesDefeated).toBe(17)
		expect(summary.BestChain).toBe(5)
		expect(summary.DamageTaken).toBe(62)
		expect(summary.DurationSeconds).toBeCloseTo(372.4, 0.05)
		expect(summary.Survived).toBe(true)
		expect(#summary.Upgrades).toBe(2)
		expect(summary.Upgrades[1].Id).toBe("SharpEdge")
		expect(summary.Reward).toBeGreaterThan(0)
	end)
end)

describe("EnemyBehaviour", function()
	local function fakeEnemy(position)
		return {
			position = position,
			anchor = position,
			facing = Vector3.new(0, 0, 1),
			phase = "Approach",
		}
	end

	it("leaves an enemy alone when there is no target", function()
		local archetype = __require("EnemyConfig").Archetypes.Chaser
		local enemy = fakeEnemy(Vector3.new(5, PLANE_Y, 5))
		local result = EnemyBehaviour.Chaser(enemy, archetype, 1 / 60, nil, 0, function()
			return 0.5
		end)
		expect(result).toEqual(Vector3.new(5, PLANE_Y, 5))
	end)

	it("faces a chaser at its target as it closes", function()
		local archetype = __require("EnemyConfig").Archetypes.Chaser
		local enemy = fakeEnemy(Vector3.new(0, PLANE_Y, -20))
		EnemyBehaviour.Chaser(enemy, archetype, 1 / 60, { position = Vector3.new(0, PLANE_Y, 20) }, 0, function()
			return 0.5
		end)
		expect(enemy.facing.Z).toBeGreaterThan(0)
		expect(enemy.position.Z).toBeGreaterThan(-20)
	end)

	it("keeps a sentry inside its leash however long it wanders", function()
		local archetype = __require("EnemyConfig").Archetypes.Drifter
		local anchor = Vector3.new(10, PLANE_Y, -10)
		local enemy = fakeEnemy(anchor)
		local random = Random.new(3)
		for frame = 1, 3000 do
			EnemyBehaviour.Sentry(enemy, archetype, 1 / 60, nil, frame / 60, function()
				return random:NextNumber()
			end)
			expect((enemy.position - anchor).Magnitude).toBeLessThanOrEqual(archetype.WanderRadius + 0.5)
		end
	end)

	it("moves a lunger through approach, telegraph and lunge in order", function()
		local archetype = __require("EnemyConfig").Archetypes.Bulwark
		local enemy = fakeEnemy(Vector3.new(0, PLANE_Y, -40))
		local target = { position = Vector3.new(0, PLANE_Y, 40) }
		local order = {}
		local lastPhase = nil

		for frame = 1, 1200 do
			EnemyBehaviour.Lunger(enemy, archetype, 1 / 60, target, frame / 60, function()
				return 0.5
			end)
			if enemy.phase ~= lastPhase then
				table.insert(order, enemy.phase)
				lastPhase = enemy.phase
			end
		end

		expect(order[1]).toBe("Approach")
		expect(order[2]).toBe("Telegraph")
		expect(order[3]).toBe("Lunging")
	end)

	it("roots a lunger while it telegraphs", function()
		local archetype = __require("EnemyConfig").Archetypes.Bulwark
		local enemy = fakeEnemy(Vector3.new(0, PLANE_Y, -40))
		local target = { position = Vector3.new(0, PLANE_Y, 40) }

		for frame = 1, 1200 do
			local before = enemy.position
			EnemyBehaviour.Lunger(enemy, archetype, 1 / 60, target, frame / 60, function()
				return 0.5
			end)
			if enemy.phase == "Telegraph" then
				expect((enemy.position - before).Magnitude).toBeCloseTo(0, 1e-9)
			end
		end
	end)
end)
