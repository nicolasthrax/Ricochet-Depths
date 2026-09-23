-- Regressions found during the post-split review pass. Each of these failed before its fix.
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomConfig = __require("RoomConfig")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")
local PlayerState = __require("PlayerState")

local PLANE_Y = 3
local DT = 1 / 30

local function silentRemote()
	local remote = { calls = {} }
	function remote:FireClient(player, payload)
		table.insert(self.calls, { player = player, payload = payload })
	end
	function remote:FireAllClients() end
	function remote:Last()
		return self.calls[#self.calls]
	end
	return remote
end

local function buildMatch(seed)
	local arena = Instance.new("Folder")
	local enemies = EnemyService.new(arena, PLANE_Y, seed)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
		net[name] = silentRemote()
	end
	local match = MatchService.new({
		rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(seed)),
		enemies = enemies,
		upgrades = UpgradeService.new(seed),
		projectiles = ProjectileService.new(arena, arena, PLANE_Y),
		rewards = RewardService.new(),
		net = net,
		world = {
			GetPosition = function()
				return Vector3.new(0, PLANE_Y, 0)
			end,
			Teleport = function() end,
		},
	})
	return match, net, enemies
end

describe("a room that fails to build must not hang the run", function()
	it("ends the run instead of sitting in combat until the hard time limit", function()
		-- A layout id that does not exist makes RoomBuilder refuse, which used to leave the
		-- match in Combat with no current room. IsCleared returns false with no room, so the
		-- run sat there until the 900s hard limit.
		local room = RunConfig.Rooms[1]
		local savedLayout = room.Layout
		room.Layout = "ThisLayoutDoesNotExist"

		local ok, err = pcall(function()
			local match, net = buildMatch(1)
			local player = { Name = "Stuck", UserId = 1 }
			match:RegisterPlayer(player)
			match:RequestStart(player, 0)

			local clock = 0
			for _ = 1, math.ceil((RunConfig.StartCountdown + 10) / DT) do
				clock += DT
				match:Step(DT, clock)
			end

			-- Well inside the hard run limit, the run must already be over.
			expect(clock).toBeLessThan(RunConfig.HardRunTimeLimit)
			expect(match:GetState()).never().toBe(RunConfig.States.Combat)
			expect(net.RunResults:Last()).toBeTruthy()
		end)

		room.Layout = savedLayout
		if not ok then
			error(err, 0)
		end
	end)

	it("still runs normally when the layout is valid", function()
		local match = buildMatch(2)
		local player = { Name = "Fine", UserId = 2 }
		match:RegisterPlayer(player)
		match:RequestStart(player, 0)
		local clock = 0
		for _ = 1, math.ceil((RunConfig.StartCountdown + 1) / DT) do
			clock += DT
			match:Step(DT, clock)
		end
		expect(match:GetState()).toBe(RunConfig.States.Combat)
	end)
end)

describe("upgrade countdown must not compare clocks across machines", function()
	it("sends a duration rather than a server timestamp", function()
		local service = UpgradeService.new(3)
		local state = PlayerState.new({ Name = "Timer", UserId = 3 })

		-- os.clock() is per-process. A server timestamp is meaningless on a client, so the
		-- payload must carry how long is left, not when it ends.
		local serverNow = 91234.5
		local offer = service:BuildOffer("p1", state, serverNow)
		local payload = UpgradeService.ToClientPayload(offer, serverNow)

		expect(payload.SecondsRemaining).toBeCloseTo(UpgradeConfig.ChoiceTimeout, 1e-6)
		expect(payload.ExpiresAt).toBeNil()
		expect(payload.OfferId).toBe(offer.id)
		expect(#payload.Cards).toBe(#offer.cards)
	end)

	it("reports the time actually left when the payload is built late", function()
		local service = UpgradeService.new(4)
		local state = PlayerState.new({ Name = "Late", UserId = 4 })
		local offer = service:BuildOffer("p1", state, 1000)
		local payload = UpgradeService.ToClientPayload(offer, 1000 + 4)
		expect(payload.SecondsRemaining).toBeCloseTo(UpgradeConfig.ChoiceTimeout - 4, 1e-6)
	end)

	it("never reports a negative duration", function()
		local service = UpgradeService.new(5)
		local state = PlayerState.new({ Name = "Expired", UserId = 5 })
		local offer = service:BuildOffer("p1", state, 0)
		expect(UpgradeService.ToClientPayload(offer, 9999).SecondsRemaining).toBe(0)
	end)
end)

describe("contact damage must use the current frame's time", function()
	it("passes the enemy step's clock through to the damage handler", function()
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 6)
		enemies:SetBounds(Vector3.new(0, PLANE_Y, 0), Vector2.new(60, 60))
		enemies:SetTargetProvider(function()
			return { { player = "victim", position = Vector3.new(0, PLANE_Y, 0) } }
		end)

		local seen = {}
		enemies.OnPlayerContact = function(_player, _damage, _enemy, now)
			table.insert(seen, now)
		end
		enemies:Spawn("Chaser", Vector3.new(0, PLANE_Y, 1))

		local stepTimes = {}
		for frame = 1, 300 do
			local now = 5000 + frame * DT
			table.insert(stepTimes, now)
			enemies:Step(DT, now)
		end

		expect(#seen).toBeGreaterThan(0)
		-- Every reported time must be one the caller actually passed in, not a stale value.
		for _, reported in seen do
			local matched = false
			for _, stepTime in stepTimes do
				if math.abs(stepTime - reported) < 1e-9 then
					matched = true
					break
				end
			end
			expect(matched).toBe(true)
		end
	end)

	it("applies damage against the correct invulnerability window", function()
		local match, _net, enemies = buildMatch(7)
		local player = { Name = "Guarded", UserId = 7 }
		match:RegisterPlayer(player)
		match:RequestStart(player, 0)

		local clock = 0
		for _ = 1, math.ceil((RunConfig.StartCountdown + 0.2) / DT) do
			clock += DT
			match:Step(DT, clock)
		end

		local state = match:GetPlayerState(player)
		expect(state:IsInvulnerable(clock)).toBe(true)
		-- Spawn invulnerability must actually hold against a contact on this frame.
		match:HandlePlayerContact(player, 50, nil, clock)
		expect(state.health).toBe(state.maxHealth)
		expect(enemies).toBeTruthy()

		-- And must expire on schedule.
		local later = clock + RunConfig.SpawnInvulnerability + 0.1
		match:HandlePlayerContact(player, 50, nil, later)
		expect(state.health).toBe(state.maxHealth - 50)
	end)
end)

describe("spawn point fallback must not return a blocked point", function()
	it("picks the clearest available spot when the whole room is covered", function()
		-- A pathological layout with cover everywhere. The old fallback returned the room
		-- centre, which is the one point already known to be blocked.
		local layoutId = "RegressionFullyBlocked"
		RoomConfig.Layouts[layoutId] = {
			DisplayName = "Fully Blocked",
			InteriorSize = Vector2.new(60, 60),
			AccentColor = Color3.fromRGB(0, 0, 0),
			Obstacles = {
				{ Offset = Vector2.new(0, 0), Size = Vector2.new(50, 50) },
			},
			EnemySpawns = { Vector2.new(0, 0) },
		}

		local ok, err = pcall(function()
			local arena = Instance.new("Folder")
			local enemies = EnemyService.new(arena, PLANE_Y, 8)
			local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(8))
			rooms:Load({ Id = "Blocked", DisplayName = "Blocked", Layout = layoutId, Kind = "Normal", Spawns = {} }, 0)

			local point = rooms:GetSpawnPoint()
			local obstacle = RoomConfig.Layouts[layoutId].Obstacles[1]

			-- With cover this large no point inside the bounds escapes it, so the contract is
			-- not "finds clear ground" but "never hands back the centre it already rejected".
			local function depthInside(x, z)
				return math.min(
					obstacle.Size.X / 2 - math.abs(x - obstacle.Offset.X),
					obstacle.Size.Y / 2 - math.abs(z - obstacle.Offset.Y)
				)
			end
			expect(depthInside(point.X, point.Z)).toBeLessThan(depthInside(0, 0))
		end)

		RoomConfig.Layouts[layoutId] = nil
		if not ok then
			error(err, 0)
		end
	end)

	it("still prefers the exact centre when the centre is clear", function()
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 9)
		local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(9))
		rooms:Load(RunConfig.Rooms[1], 0)
		local point = rooms:GetSpawnPoint()
		expect(point.X).toBe(0)
		expect(point.Z).toBe(0)
	end)
end)

describe("late joiners are credited only for rooms they were present for", function()
	local RewardServiceModule = __require("RewardService")

	local function wipeRoom(match, enemies, shooter, clock)
		local guard = 0
		while enemies:GetActiveCount() > 0 and guard < 500 do
			guard += 1
			local enemy = enemies:GetEnemies()[1]
			match:HandleImpact(
				{ Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part },
				{ direction = Vector3.new(0, 0, 1), damage = 100, damagePerBounce = 0, contacts = 1, shooter = shooter },
				clock
			)
		end
	end

	local function stepFor(match, clock, seconds)
		for _ = 1, math.max(1, math.ceil(seconds / DT)) do
			clock += DT
			match:Step(DT, clock)
		end
		return clock
	end

	it("does not pay a player held out until the elite room for the rooms before it", function()
		local match, net, enemies = buildMatch(40)
		local upgrades = match._upgrades
		local founder = { Name = "Founder", UserId = 401 }
		local latecomer = { Name = "Latecomer", UserId = 402 }

		match:RegisterPlayer(founder)
		match:RequestStart(founder, 0)
		local clock = stepFor(match, 0, RunConfig.StartCountdown + DT)

		local eliteIndex = RunConfig.RoomCount()
		for roomIndex = 1, eliteIndex - 1 do
			expect(match:GetRunSnapshot().RoomIndex).toBe(roomIndex)

			-- The latecomer arrives during the last normal room, so the earliest boundary that
			-- can admit them is the start of the elite room.
			if roomIndex == eliteIndex - 1 then
				match:RegisterPlayer(latecomer)
				expect(match:IsPendingJoin(latecomer)).toBe(true)
			end

			wipeRoom(match, enemies, founder, clock)
			clock = stepFor(match, clock, DT)
			local offer = upgrades:GetOffer(founder)
			match:ChooseUpgrade(founder, offer.id, offer.cards[1].Id, clock)
			clock = stepFor(match, clock, RunConfig.TransitionDuration + DT * 2)
		end

		-- Admitted at the elite room, and not a moment before.
		expect(match:GetRunSnapshot().RoomIndex).toBe(eliteIndex)
		expect(match:IsParticipant(latecomer)).toBe(true)
		local lateState = match:GetPlayerState(latecomer)
		expect(lateState.roomsCleared).toBe(0)
		expect(lateState.joinedAtRoom).toBe(eliteIndex)

		wipeRoom(match, enemies, founder, clock)
		clock = stepFor(match, clock, DT)
		expect(match:GetState()).toBe(RunConfig.States.Results)

		local founderState = match:GetPlayerState(founder)
		expect(founderState.roomsCleared).toBe(eliteIndex)
		-- One room: the only one the latecomer was actually in.
		expect(lateState.roomsCleared).toBe(1)

		-- The payout follows. Before the fix the latecomer was paid as if present for all four.
		local founderSummary, lateSummary
		for _, call in net.RunResults.calls do
			if call.player == founder then
				founderSummary = call.payload
			elseif call.player == latecomer then
				lateSummary = call.payload
			end
		end
		expect(lateSummary.RoomsCleared).toBe(1)
		expect(founderSummary.RoomsCleared).toBe(eliteIndex)
		expect(lateSummary.Reward).toBe(RewardServiceModule.Compute(lateState, "Extracted", true))
		expect(lateSummary.Reward).toBeLessThan(founderSummary.Reward)
	end)

	it("credits a player who starts the run from room one as before", function()
		local match, _net, enemies = buildMatch(41)
		local founder = { Name = "Solo", UserId = 403 }
		match:RegisterPlayer(founder)
		match:RequestStart(founder, 0)
		local clock = stepFor(match, 0, RunConfig.StartCountdown + DT)

		local state = match:GetPlayerState(founder)
		expect(state.joinedAtRoom).toBe(1)
		wipeRoom(match, enemies, founder, clock)
		stepFor(match, clock, DT)
		expect(state.roomsCleared).toBe(1)
	end)
end)
