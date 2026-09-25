-- Lane-game foundation (mvp/): config invariants, modifier data, fusion table, and the network
-- layer's validation, rate limiting, ownership and delivery.
__freshMvp()
local GameConfig = __require("GameConfig")
local ModifierDefinitions = __require("ModifierDefinitions")
local FusionRecipes = __require("FusionRecipes")
local Network = __require("Network")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

describe("GameConfig", function()
	it("is frozen all the way down", function()
		expect(table.isfrozen(GameConfig)).toBe(true)
		expect(table.isfrozen(GameConfig.Lane.grid)).toBe(true)
		expect(table.isfrozen(GameConfig.Palette.Rarity)).toBe(true)
		expect(function()
			(GameConfig.Shot :: any).baseSpeed = 999
		end).toThrow()
	end)

	it("keeps the rail, grid and danger line inside the lane", function()
		local lane = GameConfig.Lane
		expect(GameConfig.Rail.minX).toBeGreaterThan(-lane.halfWidth)
		expect(GameConfig.Rail.maxX).toBeLessThan(lane.halfWidth)
		expect(lane.grid.columns * lane.grid.cellSize).toBeCloseTo(lane.halfWidth * 2, 1e-9)
		expect(lane.dangerLineY).toBeGreaterThan(GameConfig.Rail.y)
		expect(lane.dangerLineY + lane.grid.rows * lane.grid.cellSize).toBeLessThanOrEqual(lane.length)
		expect(lane.grid.rows).toBe(12)
	end)

	it("keeps bounce angles true (friction is speed loss only)", function()
		expect(GameConfig.Ricochet.tangentialFriction).toBe(0)
		expect(GameConfig.Ricochet.minSpeed).toBeLessThan(GameConfig.Shot.baseSpeed)
		expect(GameConfig.Shot.minCooldownSeconds).toBeLessThanOrEqual(GameConfig.Shot.cooldownSeconds)
	end)

	it("scripts an FTUE first pick of three commons whose recommended card fuses", function()
		local ftue = GameConfig.Ftue
		expect(#ftue.firstOffer).toBe(GameConfig.Upgrades.choices)
		expect(table.find(ftue.firstOffer, ftue.recommended)).toBeTruthy()
		for _, id in ftue.firstOffer do
			local definition = ModifierDefinitions.get(id)
			expect(definition.kind).toBe("Base")
			expect(definition.rarity).toBe("Common")
		end
		expect(FusionRecipes.duplicateResult(ftue.recommended)).toBe("Inferno")
	end)
end)

describe("ModifierDefinitions", function()
	it("has eight offerable cards and eight fused variants", function()
		expect(#ModifierDefinitions.baseIds).toBe(8)
		expect(#ModifierDefinitions.order).toBe(16)
		for _, id in ModifierDefinitions.baseIds do
			expect(ModifierDefinitions.get(id).offerWeight).toBeGreaterThan(0)
		end
	end)

	it("writes stat lines from the effect data", function()
		local function line(id)
			return ModifierDefinitions.statLine(ModifierDefinitions.get(id).effect)
		end
		expect(line("Splitshot")).toBe("2 shards · 40% dmg")
		expect(line("Ember")).toBe("2 dmg/s · 2s")
		expect(line("Bigshot")).toBe("+35% size · +1 dmg")
		expect(line("Quickdraw")).toBe("-20% cooldown")
		expect(line("Frostbite")).toBe("skip 1 step")
		expect(line("Spark")).toBe("1 arc · 50% dmg")
		expect(line("Drill")).toBe("pierce 1 · 90% dmg")
		expect(line("Echo")).toBe("+1 bounce · all shots")
		expect(line("Inferno")).toBe("4 dmg/s · 3s · blast 3")
		expect(line("Glacier")).toBe("whole row · skip 2 steps")
		expect(line("Resonance")).toBe("+2 bounces · +15%/bounce")
	end)

	it("parses untrusted ids", function()
		expect(ModifierDefinitions.parseId("Inferno")).toBe("Inferno")
		expect(ModifierDefinitions.parseId("inferno")).toBeNil()
		expect(ModifierDefinitions.parseId(42)).toBeNil()
		expect(ModifierDefinitions.parseId(nil)).toBeNil()
		expect(ModifierDefinitions.parseBaseId("Ember")).toBe("Ember")
		expect(ModifierDefinitions.parseBaseId("Inferno")).toBeNil()
	end)

	it("cannot be mutated", function()
		expect(function()
			(ModifierDefinitions.get("Ember").effect :: any).damagePerSecond = 100
		end).toThrow()
		expect(function()
			(ModifierDefinitions.byId :: any).Cheat = {}
		end).toThrow()
	end)
end)

describe("FusionRecipes", function()
	it("fuses every base card with its duplicate into a fused variant of the same family", function()
		for _, id in ModifierDefinitions.baseIds do
			local result = FusionRecipes.duplicateResult(id)
			expect(result).toBeTruthy()
			local base = ModifierDefinitions.get(id)
			local fused = ModifierDefinitions.get(result)
			expect(fused.kind).toBe("Fused")
			expect(fused.family).toBe(base.family)
			expect(fused.effect.kind).toBe(base.effect.kind)
			expect(FusionRecipes.recipeFor(result).first).toBe(id)
		end
	end)

	it("looks pairs up in either order and rejects non-recipes", function()
		expect(FusionRecipes.find("Ember", "Ember").result).toBe("Inferno")
		expect(FusionRecipes.find("Ember", "Spark")).toBeNil()
		expect(FusionRecipes.duplicateResult("Inferno")).toBeNil()
		expect(#FusionRecipes.recipesUsing("Ember")).toBe(1)
	end)
end)

describe("Network", function()
	local rejections = {}
	local received = {}
	Network.setRejectionHandler(function(player, remoteName, reason)
		table.insert(rejections, { remote = remoteName, reason = reason })
	end)
	Network.mountServer()

	for _, name in { "FireProjectile", "RailInput", "SelectUpgrade", "ContextAction", "ExtractDecision" } do
		(Network :: any)[name]:connect(function(player, payload)
			table.insert(received, { remote = name, player = player, payload = payload })
		end)
	end

	local folder = ReplicatedStorage:FindFirstChild("NetworkRemotes")
	local player = Harness.addPlayer("NetTester")

	local function send(name, raw)
		table.clear(rejections)
		table.clear(received)
		folder:FindFirstChild(name).OnServerEvent:Fire(player, raw)
		return received[1], rejections[1]
	end

	it("creates every declared remote with the right class", function()
		local seen = {}
		for _, entry in Network.listRemotes() do
			expect(seen[entry.name]).toBeNil()
			seen[entry.name] = true
			local remote = folder:FindFirstChild(entry.name)
			expect(remote).toBeTruthy()
			expect(remote.ClassName).toBe(entry.class)
		end
		expect(folder:FindFirstChild("RailInput").ClassName).toBe("UnreliableRemoteEvent")
		expect(folder:FindFirstChild("FetchRunSnapshot").ClassName).toBe("RemoteFunction")
		expect(folder:FindFirstChild("DamageReport").ClassName).toBe("RemoteEvent")
	end)

	it("rebuilds a valid shot payload with a unit direction and no extra keys", function()
		Harness.advance(5)
		local got = send("FireProjectile", { originX = 2, direction = Vector2.new(3, 4), sequence = 7, damage = 9999 })
		expect(got).toBeTruthy()
		expect(got.player).toBe(player)
		expect(got.payload.direction.X).toBeCloseTo(0.6, 1e-9)
		expect(got.payload.direction.Y).toBeCloseTo(0.8, 1e-9)
		expect(got.payload.sequence).toBe(7)
		expect(got.payload.originX).toBe(2)
		expect(got.payload.damage).toBeNil()
	end)

	it("drops malformed shots before the handler sees them", function()
		local bad = {
			"not a table",
			{ originX = 0, direction = Vector2.new(0, 0), sequence = 1 },
			{ originX = 0, direction = Vector2.new(0 / 0, 1), sequence = 1 },
			{ originX = 0, direction = Vector2.new(math.huge, 1), sequence = 1 },
			{ originX = 0, direction = { X = 0, Y = 1 }, sequence = 1 },
			{ originX = 0, direction = Vector2.new(0, 1), sequence = -1 },
			{ originX = 0, direction = Vector2.new(0, 1), sequence = 1.5 },
			{ originX = 0, direction = Vector2.new(0, 1) },
			{ direction = Vector2.new(0, 1), sequence = 1 },
			{ originX = GameConfig.Rail.maxX + 1, direction = Vector2.new(0, 1), sequence = 1 },
			{ originX = 0 / 0, direction = Vector2.new(0, 1), sequence = 1 },
		}
		for _, raw in bad do
			Harness.advance(5)
			local got, rejected = send("FireProjectile", raw)
			expect(got).toBeNil()
			expect(rejected.reason).toBe("InvalidPayload")
		end
	end)

	it("rate limits a flood, then refills over time", function()
		Harness.advance(5)
		local accepted = 0
		for _ = 1, 20 do
			if send("FireProjectile", { originX = 0, direction = Vector2.new(0, 1), sequence = 1 }) then
				accepted += 1
			end
		end
		expect(accepted).toBe(4) -- the burst
		local _, rejected = send("FireProjectile", { originX = 0, direction = Vector2.new(0, 1), sequence = 1 })
		expect(rejected.reason).toBe("RateLimited")
		Harness.advance(1)
		expect(send("FireProjectile", { originX = 0, direction = Vector2.new(0, 1), sequence = 2 })).toBeTruthy()
	end)

	it("validates the other inputs", function()
		Harness.advance(5)
		expect(send("RailInput", { x = 0, sequence = 1 })).toBeTruthy()
		expect(send("RailInput", { x = GameConfig.Rail.maxX + 1, sequence = 2 })).toBeNil()
		expect(send("SelectUpgrade", { offerId = 1, modifierId = "Ember" })).toBeTruthy()
		expect(send("SelectUpgrade", { offerId = 1, modifierId = "Inferno" })).toBeNil()
		expect(send("SelectUpgrade", { offerId = 0, modifierId = "Ember" })).toBeNil()
		expect(send("ContextAction", { verb = "Fuse" })).toBeTruthy()
		expect(send("ContextAction", { verb = "Explode" })).toBeNil()
		expect(send("ExtractDecision", { choice = "BankLoot" })).toBeTruthy()
		expect(send("ExtractDecision", { choice = true })).toBeNil()
	end)

	it("gives each client input exactly one server owner and blocks wrong-direction calls", function()
		expect(function()
			Network.FireProjectile:connect(function() end)
		end).toThrow()
		expect(function()
			Network.FireProjectile:fire({ originX = 0, direction = Vector2.new(0, 1), sequence = 1 })
		end).toThrow()
		expect(function()
			Network.DamageReport:connect(function() end)
		end).toThrow()
	end)

	it("delivers server events to one player or a party", function()
		local remote = folder:FindFirstChild("HaulChanged")
		table.clear(remote._fired)
		local teammate = Harness.addPlayer("Teammate")
		Network.HaulChanged:fireTo(player, { haul = 12, delta = 12 })
		Network.HaulChanged:fireToList({ player, teammate }, { haul = 20, delta = 8 })
		expect(#remote._fired).toBe(3)
		expect(remote._fired[1].player).toBe(player)
		expect(remote._fired[1].args[1].haul).toBe(12)
		expect(remote._fired[3].player).toBe(teammate)
	end)

	it("answers the snapshot request through the validator and rate limit", function()
		local remote = folder:FindFirstChild("FetchRunSnapshot")
		Network.FetchRunSnapshot:setHandler(function(requester, _request)
			return if requester == player then ({ runId = 3 } :: any) else nil
		end)
		Harness.advance(5)
		expect(remote.OnServerInvoke(player, nil).runId).toBe(3)
		expect(remote.OnServerInvoke(player, "junk")).toBeNil()
		for _ = 1, 5 do
			remote.OnServerInvoke(player, nil)
		end
		expect(remote.OnServerInvoke(player, nil)).toBeNil()
	end)
end)
