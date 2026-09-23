-- ArenaDirector: several groups descend at once, each in its own arena slot on this server.
local ArenaDirector = __require("ArenaDirector")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")

local States = RunConfig.States
local PLANE_Y = 3
local DT = 1 / 30

local function fakeRemote()
	local remote = { calls = {} }
	function remote:FireClient(player, payload)
		table.insert(self.calls, { player = player, payload = payload })
	end
	function remote:FireAllClients(...)
		table.insert(self.calls, { player = "all", payload = table.pack(...) })
	end
	return remote
end

local function build(maxSlots)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
		net[name] = fakeRemote()
	end
	local positions = {}
	local world = {
		GetPosition = function(player)
			return positions[player]
		end,
		Teleport = function(player, position)
			positions[player] = position
		end,
	}
	local released = {}
	local director = ArenaDirector.new({
		parent = Instance.new("Folder"),
		planeY = PLANE_Y,
		seed = 3,
		maxSlots = maxSlots or 3,
		shared = {
			net = net,
			world = world,
			runKeyPrefix = "test",
			planRun = function()
				return RunPlanner.Fixed({ "Atrium", "Cistern" })
			end,
		},
		onReleased = function(players)
			for _, player in players do
				table.insert(released, player)
			end
		end,
	})
	return { director = director, net = net, positions = positions, released = released }
end

local function group(prefix, count)
	local players = {}
	for index = 1, count do
		table.insert(players, { Name = prefix .. index, UserId = #prefix * 100 + index })
	end
	return players
end

local function step(ctx, seconds, from)
	local now = from or 0
	for _ = 1, math.ceil(seconds / DT) do
		now += DT
		ctx.director:Step(DT, now)
	end
	return now
end

describe("ArenaDirector", function()
	it("runs two groups at once, each in its own arena", function()
		local ctx = build()
		local a, b = group("A", 2), group("B", 3)
		expect((ctx.director:StartGroup(a, 0))).toBeTruthy()
		expect((ctx.director:StartGroup(b, 0))).toBeTruthy()

		local matchA, matchB = ctx.director:MatchFor(a[1]), ctx.director:MatchFor(b[1])
		expect(matchA).toBeTruthy()
		expect(matchA).never().toBe(matchB)
		expect(ctx.director:MatchFor(a[2])).toBe(matchA)
		expect(#matchA:GetParticipants()).toBe(2)
		expect(#matchB:GetParticipants()).toBe(3)

		step(ctx, RunConfig.StartCountdown + 0.2)
		expect(matchA:GetState()).toBe(States.Combat)
		expect(matchB:GetState()).toBe(States.Combat)

		-- Each group stands in its own room, far apart.
		local spawnA, spawnB = ctx.positions[a[1]], ctx.positions[b[1]]
		expect((Vector3.new(spawnA.X, 0, spawnA.Z) - Vector3.new(spawnB.X, 0, spawnB.Z)).Magnitude)
			.toBeGreaterThan(RunConfig.Arenas.Spacing * 0.9)
		local slotA = ctx.director:SlotFor(a[1])
		for _, enemy in slotA.enemies:GetEnemies() do
			expect(math.abs(enemy.position.X - slotA.origin.X)).toBeLessThan(80)
		end

		-- Everyone lands on their own room's floor, not beside it in empty space.
		for _, player in { a[1], a[2], b[1], b[2], b[3] } do
			local floor = ctx.director:SlotFor(player).arena:FindFirstChild("Room"):FindFirstChild("Floor")
			local at = ctx.positions[player]
			expect(math.abs(at.X - floor.Position.X)).toBeLessThan(floor.Size.X / 2)
			expect(math.abs(at.Z - floor.Position.Z)).toBeLessThan(floor.Size.Z / 2)
			expect(at.Y).toBeGreaterThan(floor.Position.Y)
		end
	end)

	it("tells each group only about its own run", function()
		local ctx = build()
		local a, b = group("A", 2), group("B", 2)
		ctx.director:StartGroup(a, 0)
		ctx.director:StartGroup(b, 0)
		step(ctx, RunConfig.StartCountdown + 0.2)
		local runOf = {}
		for _, player in a do
			runOf[player] = ctx.director:MatchFor(player)
		end
		for _, player in b do
			runOf[player] = ctx.director:MatchFor(player)
		end
		for _, call in ctx.net.RunStateChanged.calls do
			expect(call.player).never().toBe("all")
			expect(call.payload.Players).toBe(#runOf[call.player]:GetParticipants())
		end
	end)

	it("never puts one player in two runs", function()
		local ctx = build()
		local a = group("A", 2)
		ctx.director:StartGroup(a, 0)
		local ok, reason = ctx.director:StartGroup({ a[1], { Name = "Other", UserId = 999 } }, 0)
		expect(ok).toBeFalsy()
		expect(reason).toBe("already in a run")
	end)

	it("refuses a group when every arena is busy", function()
		local ctx = build(2)
		ctx.director:StartGroup(group("A", 2), 0)
		ctx.director:StartGroup(group("B", 2), 0)
		local ok, reason = ctx.director:StartGroup(group("C", 2), 0)
		expect(ok).toBeFalsy()
		expect(reason).toBe("all arenas busy")
	end)

	it("frees and reuses an arena once its run is over, and sends the group home", function()
		local ctx = build(1)
		local a = group("A", 1)
		ctx.director:StartGroup(a, 0)
		local slot = ctx.director:SlotFor(a[1])
		local now = step(ctx, RunConfig.StartCountdown + 0.2)
		-- Everyone leaves: the run is abandoned, shows results, then cleans up.
		ctx.director:RemovePlayer(a[1], now)
		step(ctx, RunConfig.ResultsDuration + 1, now)
		expect(ctx.director:MatchFor(a[1])).toBeNil()
		expect(slot.busy).toBe(false)

		local b = group("B", 2)
		now = step(ctx, 0.1, now)
		expect((ctx.director:StartGroup(b, now))).toBeTruthy()
		expect(ctx.director:SlotFor(b[1])).toBe(slot)
	end)

	it("returns a finished group to the lobby and reports it", function()
		local ctx = build()
		local a = group("A", 2)
		ctx.director:StartGroup(a, 0)
		local match = ctx.director:MatchFor(a[1])
		local now = step(ctx, RunConfig.StartCountdown + 0.2)
		match:_finish("Defeated", now)
		step(ctx, RunConfig.ResultsDuration + 1, now)
		expect(ctx.director:MatchFor(a[1])).toBeNil()
		expect(#ctx.released).toBe(2)
		local home = ctx.positions[a[1]]
		expect((home - RunConfig.LobbyReturnPosition).Magnitude).toBeLessThan(1)
	end)

	it("keys each arena's rewards apart, so runs in different arenas never collide", function()
		local ctx = build()
		ctx.director:StartGroup(group("A", 1), 0)
		ctx.director:StartGroup(group("B", 1), 0)
		local keys = {}
		for _, slot in ctx.director:GetSlots() do
			keys[slot.match._runKeyPrefix] = true
		end
		local count = 0
		for _ in keys do
			count += 1
		end
		expect(count).toBe(2)
	end)
end)
