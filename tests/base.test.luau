-- The home base: building and upgrading through the purchase path, Hearth gates, tile rules and
-- moves, layouts cleaned against what is built, offline claims (math, cap and idempotency across
-- servers), friend cheers and the run bonuses buildings grant.
local BaseConfig = __require("BaseConfig")
local BaseService = __require("BaseService")
local FeatureFlags = __require("FeatureFlags")
local MetaConfig = __require("MetaConfig")
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")

local HOUR = 3600
-- A wall-clock time well inside a UTC day, so a few hours on never cross midnight by accident.
local T0 = 20000 * MetaConfig.SecondsPerDay + 2 * HOUR

local function subject(userId)
	return { Name = "B" .. userId, UserId = userId }
end

local function stored(store, player)
	return store:Peek(PlayerDataConfig.KeyPrefix .. tostring(player.UserId))
end

-- A clock tests can move; shared by the persistence (grant stamps) and the base.
local function newClock(start)
	local clock = { now = start or T0 }
	function clock.read()
		return clock.now
	end
	return clock
end

-- A persistence + base pair on one store. canManage defaults to always.
local function newWorld(store, clock, options)
	options = options or {}
	local persistence = PlayerDataService.new(store, { wallClock = clock.read })
	local base = BaseService.new(persistence, {
		wallClock = clock.read,
		canManage = options.canManage,
		extraCapHours = options.extraCapHours,
		onChanged = options.onChanged,
		onFirstBuild = options.onFirstBuild,
	})
	return persistence, base
end

local function funded(persistence, player, coins)
	persistence:Load(player)
	if coins > 0 then
		persistence:GrantReward(player, "seed-" .. player.UserId, coins)
		persistence:Save(player, 0)
	end
	return player
end

local function cost(id, level)
	local building = BaseConfig.Get(id)
	return BaseConfig.CostFor(building, level)
end

describe("BaseConfig catalogue", function()
	it("has twelve buildings on a 4x4 grid, each with ascending costs and matching Hearth gates", function()
		expect(#BaseConfig.Buildings).toBe(12)
		expect(BaseConfig.Tiles).toBe(16)
		for _, building in BaseConfig.Buildings do
			expect(#building.HearthLevels).toBe(#building.Costs)
			local previous = 0
			for index, price in building.Costs do
				expect(price).toBeGreaterThan(previous)
				expect(price).toBe(math.floor(price))
				previous = price
				-- A level can never need a Hearth above the Hearth's own max.
				expect(building.HearthLevels[index]).toBeLessThanOrEqual(BaseConfig.MaxLevel(BaseConfig.Get("Hearth")))
			end
			expect(type(building.Title)).toBe("string")
			expect(#string.split(building.Label, " ")).toBeLessThanOrEqual(3)
		end
	end)

	it("starts the Hearth at level 1 for free and every other building unbuilt", function()
		expect(BaseConfig.LevelOf({}, "Hearth")).toBe(1)
		expect(BaseConfig.LevelOf({}, "Forge")).toBe(0)
		expect(BaseConfig.LevelOf({ Hearth = 2 }, "Hearth")).toBe(3)
		expect(BaseConfig.LevelOf({}, "Nonsense")).toBe(0)
		expect(BaseConfig.CostFor(BaseConfig.Get("Hearth"), 1)).toBeNil()
		expect(BaseConfig.CostFor(BaseConfig.Get("Hearth"), 2)).toBe(200)
	end)
end)

describe("ComputeBonuses", function()
	it("adds each building's effect per level", function()
		local bonuses = BaseConfig.ComputeBonuses({ Forge = 2, Infirmary = 3, TrophyHall = 1 })
		expect(bonuses.Damage).toBeCloseTo(0.1)
		expect(bonuses.MaxHealthBonus).toBeCloseTo(30)
		expect(bonuses.RewardMultiplier).toBeCloseTo(0.05)
		expect(bonuses.MoveSpeedBonus).toBeNil()
	end)

	it("clamps tampered levels to what is sold and ignores unknown ids", function()
		local forge = BaseConfig.Get("Forge")
		local bonuses = BaseConfig.ComputeBonuses({ Forge = 99, Infirmary = -4, Nonsense = 5, Bootworks = "x" })
		expect(bonuses.Damage).toBeCloseTo(forge.Effect.PerLevel * BaseConfig.MaxLevel(forge))
		expect(bonuses.MaxHealthBonus).toBeNil()
		expect(bonuses.MoveSpeedBonus).toBeNil()
		local fractional = BaseConfig.ComputeBonuses({ Forge = 1.9 })
		expect(fractional.Damage).toBeCloseTo(forge.Effect.PerLevel)
	end)
end)

describe("BaseService building", function()
	it("builds on a chosen tile, charges the cost and persists level and layout on save", function()
		local store, clock = __FakeDataStore.new(), newClock()
		local persistence, base = newWorld(store, clock)
		local player = funded(persistence, subject(1), 500)

		local ok, result = base:Upgrade(player, "Forge", 1)
		expect(ok).toBe(true)
		expect(result.Level).toBe(1)
		expect(result.Tile).toBe(1)
		expect(result.Cost).toBe(cost("Forge", 1))
		expect(persistence:GetBalance(player)).toBe(500 - cost("Forge", 1))

		persistence:Save(player, 1)
		local saved = stored(store, player)
		expect(saved.MetaUpgrades.Forge).toBe(1)
		expect(saved.Base.Layout.Forge).toBe(1)
		expect(saved.Base.Layout.Hearth).toBe(BaseConfig.Get("Hearth").DefaultTile)
		expect(saved.Currency.Salvage).toBe(500 - cost("Forge", 1))
	end)

	it("takes the first free tile when none is named, and upgrades in place", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local persistence = base._persistence
		local player = funded(persistence, subject(2), 5000)
		local _, first = base:Upgrade(player, "Infirmary")
		expect(first.Tile).toBe(1)
		local _, second = base:Upgrade(player, "Infirmary", 9)
		expect(second.Level).toBe(2)
		expect(second.Tile).toBe(1) -- already built: the tile is ignored
	end)

	it("gates levels behind the Hearth, and opens them once the Hearth is raised", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local persistence = base._persistence
		local player = funded(persistence, subject(3), 5000)
		expect((base:Upgrade(player, "Forge"))).toBe(true)
		local ok, reason = base:Upgrade(player, "Forge")
		expect(ok).toBe(false)
		expect(reason).toBe("hearth too low")
		local _, hearth = base:Upgrade(player, "Hearth")
		expect(hearth.Level).toBe(2)
		expect((base:Upgrade(player, "Forge"))).toBe(true)
		expect(base:GetLevels(player).Forge).toBe(2)
		-- Springhouse's first level already needs Hearth 2; Storehouse's second needs 3.
		expect((base:Upgrade(player, "Springhouse"))).toBe(true)
		expect((base:Upgrade(player, "Storehouse"))).toBe(true)
		expect(select(2, base:Upgrade(player, "Storehouse"))).toBe("hearth too low")
	end)

	it("refuses past the max level", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local player = funded(base._persistence, subject(4), 100000)
		local hearth = BaseConfig.Get("Hearth")
		for _ = 1, #hearth.Costs do
			expect((base:Upgrade(player, "Hearth"))).toBe(true)
		end
		expect(base:GetLevels(player).Hearth).toBe(BaseConfig.MaxLevel(hearth))
		local ok, reason = base:Upgrade(player, "Hearth")
		expect(ok).toBe(false)
		expect(reason).toBe("max level")
	end)

	it("refuses when the coins do not cover it, changing nothing", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local persistence = base._persistence
		local player = funded(persistence, subject(5), 10)
		local ok, reason = base:Upgrade(player, "Forge", 1)
		expect(ok).toBe(false)
		expect(reason).toBe("insufficient salvage")
		expect(persistence:GetBalance(player)).toBe(10)
		expect(persistence:GetMetaLevels(player).Forge).toBeNil()
	end)

	it("refuses unknown and malformed buildings", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local player = funded(base._persistence, subject(6), 1000)
		expect(select(2, base:Upgrade(player, "Castle"))).toBe("unknown building")
		expect(select(2, base:Upgrade(player, 7))).toBe("unknown building")
		expect(select(2, base:Upgrade(player, nil))).toBe("unknown building")
		expect(base._persistence:GetBalance(player)).toBe(1000)
	end)

	it("refuses in a read-only session, where nothing could be saved", function()
		local store = __FakeDataStore.new()
		store.alwaysFail = true
		local persistence, base = newWorld(store, newClock())
		local player = subject(7)
		persistence:Load(player)
		local ok, reason = base:Upgrade(player, "Forge")
		expect(ok).toBe(false)
		expect(reason).toBe("profile not loaded")
		expect((base:Move(player, "Hearth", 1))).toBe(false)
		expect((base:Claim(player))).toBe(false)
	end)

	it("refuses during a run", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock(), {
			canManage = function()
				return false
			end,
		})
		local player = funded(base._persistence, subject(8), 1000)
		expect(select(2, base:Upgrade(player, "Forge"))).toBe("in a run")
		expect(select(2, base:Move(player, "Hearth", 1))).toBe("in a run")
		expect(select(2, base:Claim(player))).toBe("in a run")
	end)

	it("is inert when the feature flag is off", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local player = funded(base._persistence, subject(9), 1000)
		local previous = FeatureFlags.BaseBuilding
		FeatureFlags.BaseBuilding = false
		local ok, reason = base:Upgrade(player, "Forge")
		FeatureFlags.BaseBuilding = previous
		expect(ok).toBe(false)
		expect(reason).toBe("base disabled")
		expect(base._persistence:GetBalance(player)).toBe(1000)
	end)

	it("reports the first building ever bought once, and pushes every change", function()
		local firsts, changes = 0, 0
		local _, base = newWorld(__FakeDataStore.new(), newClock(), {
			onFirstBuild = function()
				firsts += 1
			end,
			onChanged = function()
				changes += 1
			end,
		})
		local player = funded(base._persistence, subject(10), 5000)
		base:Upgrade(player, "Forge")
		base:Upgrade(player, "Infirmary")
		base:Upgrade(player, "Hearth")
		expect(firsts).toBe(1)
		expect(changes).toBe(3)
	end)

	it("never lets Update raise a building level directly", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(11), 0)
		local ok = pcall(function()
			persistence:Update(player, function(profile)
				profile.MetaUpgrades.Forge = 5
			end)
		end)
		expect(ok).toBe(false)
		expect(BaseConfig.LevelOf(persistence:GetMetaLevels(player), "Forge")).toBe(0)
	end)
end)

describe("tiles and moves", function()
	it("refuses invalid and occupied tiles for a new building", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local player = funded(base._persistence, subject(20), 5000)
		for _, tile in { 0, 17, 1.5, -3, "a" } do
			expect(select(2, base:Upgrade(player, "Forge", tile))).toBe("invalid tile")
		end
		local hearthTile = BaseConfig.Get("Hearth").DefaultTile
		expect(select(2, base:Upgrade(player, "Forge", hearthTile))).toBe("tile taken")
		expect(base._persistence:GetBalance(player)).toBe(5000)
	end)

	it("fits every building on the grid at once, each on its own tile", function()
		local levels = {}
		for _, building in BaseConfig.Buildings do
			levels[building.Id] = 1
		end
		local layout = BaseConfig.NormaliseLayout({}, levels)
		local used = 0
		for _ in layout do
			used += 1
		end
		-- Twelve buildings fit on sixteen tiles with room to spare.
		expect(used).toBe(12)
	end)

	it("moves a building to a free tile, and swaps with an occupied one", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local player = funded(base._persistence, subject(21), 5000)
		base:Upgrade(player, "Forge", 1)
		base:Upgrade(player, "Infirmary", 2)

		local ok, moved = base:Move(player, "Forge", 16)
		expect(ok).toBe(true)
		expect(moved.Swapped).toBeNil()
		expect(base:EnsureLayout(player).Forge).toBe(16)

		local _, swapped = base:Move(player, "Forge", 2)
		expect(swapped.Swapped).toBe("Infirmary")
		local layout = base:EnsureLayout(player)
		expect(layout.Forge).toBe(2)
		expect(layout.Infirmary).toBe(16)
	end)

	it("refuses to move what is not built, or onto a tile that does not exist", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local player = funded(base._persistence, subject(22), 5000)
		expect(select(2, base:Move(player, "Forge", 3))).toBe("not built")
		expect(select(2, base:Move(player, "Hearth", 0))).toBe("invalid tile")
		expect(select(2, base:Move(player, "Keep", 3))).toBe("unknown building")
		-- Moving onto its own tile is a no-op, not an error.
		expect((base:Move(player, "Hearth", BaseConfig.Get("Hearth").DefaultTile))).toBe(true)
	end)
end)

describe("NormaliseLayout", function()
	it("cleans a tampered layout: duplicates, bad tiles and unbuilt buildings", function()
		local levels = { Forge = 1, Infirmary = 1 }
		local layout = BaseConfig.NormaliseLayout({
			Hearth = 3,
			Forge = 3, -- same tile as the Hearth
			Infirmary = 99, -- off the grid
			Bootworks = 4, -- not built
			Nonsense = 5,
		}, levels)
		expect(layout.Hearth).toBe(3)
		expect(layout.Bootworks).toBeNil()
		expect(layout.Nonsense).toBeNil()
		expect(layout.Forge).never().toBe(3)
		expect(BaseConfig.ValidTile(layout.Forge)).toBe(true)
		expect(BaseConfig.ValidTile(layout.Infirmary)).toBe(true)
		expect(layout.Forge).never().toBe(layout.Infirmary)
	end)

	it("survives a layout that is not a table at all", function()
		local layout = BaseConfig.NormaliseLayout("garbage", {})
		expect(layout.Hearth).toBe(BaseConfig.Get("Hearth").DefaultTile)
	end)

	it("gives a building bought on another server a tile here", function()
		local store, clock = __FakeDataStore.new(), newClock()
		local serverA, baseA = newWorld(store, clock)
		local serverB, baseB = newWorld(store, clock)
		local player = subject(30)
		funded(serverA, player, 1000)
		serverB:Load(player)

		expect((baseA:Upgrade(player, "Forge", 12))).toBe(true)
		serverA:Save(player, 1)
		-- Server B learns of the purchase on its next save, but its own layout never had the Forge.
		serverB:Update(player, function(profile)
			profile.Nameplate = ""
		end)
		serverB:Save(player, 2)
		expect(BaseConfig.LevelOf(serverB:GetMetaLevels(player), "Forge")).toBe(1)
		local layout = baseB:EnsureLayout(player)
		expect(BaseConfig.ValidTile(layout.Forge)).toBe(true)
		expect(layout.Forge).never().toBe(layout.Hearth)
	end)
end)

describe("offline claims", function()
	it("fills at the yard's rate, up to the cap, and pays the claim", function()
		local store, clock = __FakeDataStore.new(), newClock()
		local persistence, base = newWorld(store, clock)
		local player = funded(persistence, subject(40), 100)
		expect((base:Upgrade(player, "SalvageYard"))).toBe(true)
		local afterBuild = persistence:GetBalance(player)
		local rate = BaseConfig.Get("SalvageYard").Production[1]

		clock.now = T0 + 3 * HOUR
		local state = base:GetState(player, clock.now)
		expect(state.Offline.Coins).toBe(3 * rate)
		expect(state.Offline.PerHour).toBe(rate)
		expect(state.Offline.Fill).toBeCloseTo(3 / BaseConfig.Offline.BaseCapHours)

		local ok, claimed = base:Claim(player)
		expect(ok).toBe(true)
		expect(claimed.Coins).toBe(3 * rate)
		expect(persistence:GetBalance(player)).toBe(afterBuild + 3 * rate)
		expect(select(2, base:Claim(player))).toBe("nothing to claim")

		-- Away far longer than the cap: only the cap's worth is waiting.
		clock.now += 100 * HOUR
		expect(base:GetState(player, clock.now).Offline.Coins).toBe(BaseConfig.Offline.BaseCapHours * rate)
		expect(base:GetState(player, clock.now).Offline.Fill).toBeCloseTo(1)
	end)

	it("pays nothing without a yard", function()
		local clock = newClock()
		local _, base = newWorld(__FakeDataStore.new(), clock)
		local player = funded(base._persistence, subject(41), 0)
		clock.now += 10 * HOUR
		expect(select(2, base:Claim(player))).toBe("nothing to claim")
	end)

	it("raises the cap with the Storehouse and pass hours, never past the maximum", function()
		expect(BaseConfig.CapHours({}, 0)).toBe(8)
		expect(BaseConfig.CapHours({ Storehouse = 2 }, 0)).toBe(10)
		expect(BaseConfig.CapHours({ Storehouse = 2 }, 2)).toBe(BaseConfig.Offline.MaxCapHours)
		expect(BaseConfig.CapHours({}, 50)).toBe(BaseConfig.Offline.MaxCapHours)
		expect(BaseConfig.CapHours({}, -5)).toBe(8)
	end)

	it("pays a stretch of time once when two servers claim it", function()
		local store, clock = __FakeDataStore.new(), newClock()
		local serverA, baseA = newWorld(store, clock)
		local player = subject(42)
		funded(serverA, player, 100)
		baseA:Upgrade(player, "SalvageYard")
		serverA:Save(player, 1)
		local afterBuild = stored(store, player).Currency.Salvage

		-- A second server loads the same profile: same yard, same LastClaimAt.
		local serverB, baseB = newWorld(store, clock)
		local other = subject(42)
		serverB:Load(other)
		clock.now = T0 + 4 * HOUR
		local rate = BaseConfig.Get("SalvageYard").Production[1]
		expect(select(2, baseA:Claim(player)).Coins).toBe(4 * rate)
		expect(select(2, baseB:Claim(other)).Coins).toBe(4 * rate)
		serverA:Save(player, 2)
		serverB:Save(other, 3)
		expect(stored(store, player).Currency.Salvage).toBe(afterBuild + 4 * rate)
		expect(serverB:GetBalance(other)).toBe(afterBuild + 4 * rate)
	end)

	it("empties the yard before an upgrade, so the new rate is never paid backwards", function()
		local clock = newClock()
		local persistence, base = newWorld(__FakeDataStore.new(), clock)
		local player = funded(persistence, subject(43), 1000)
		base:Upgrade(player, "SalvageYard")
		local afterBuild = persistence:GetBalance(player)
		local yard = BaseConfig.Get("SalvageYard")

		clock.now = T0 + 2 * HOUR
		expect((base:Upgrade(player, "SalvageYard"))).toBe(true)
		expect(persistence:GetBalance(player)).toBe(afterBuild + 2 * yard.Production[1] - cost("SalvageYard", 2))
		expect(base:GetState(player, clock.now).Offline.Coins).toBe(0)

		clock.now += HOUR
		expect(base:GetState(player, clock.now).Offline.Coins).toBe(yard.Production[2])
	end)

	it("empties the yard before a Storehouse upgrade too", function()
		local clock = newClock()
		local persistence, base = newWorld(__FakeDataStore.new(), clock)
		local player = funded(persistence, subject(44), 5000)
		base:Upgrade(player, "Hearth")
		base:Upgrade(player, "SalvageYard")
		clock.now = T0 + 20 * HOUR
		local before = persistence:GetBalance(player)
		expect((base:Upgrade(player, "Storehouse"))).toBe(true)
		local capped = BaseConfig.Offline.BaseCapHours * BaseConfig.Get("SalvageYard").Production[1]
		expect(persistence:GetBalance(player)).toBe(before + capped - cost("Storehouse", 1))
	end)

	it("uses the pass hours a caller supplies", function()
		local clock = newClock()
		local _, base = newWorld(__FakeDataStore.new(), clock, {
			extraCapHours = function()
				return 2
			end,
		})
		local player = funded(base._persistence, subject(45), 100)
		base:Upgrade(player, "SalvageYard")
		clock.now += 50 * HOUR
		local state = base:GetState(player, clock.now)
		expect(state.Offline.CapHours).toBe(10)
		expect(state.Offline.Coins).toBe(10 * BaseConfig.Get("SalvageYard").Production[1])
	end)
end)

describe("friend cheers", function()
	local function pair(clock)
		local store = __FakeDataStore.new()
		local persistence, base = newWorld(store, clock)
		local visitor, owner = subject(50), subject(51)
		persistence:Load(visitor)
		persistence:Load(owner)
		return persistence, base, visitor, owner
	end

	it("pays both players once a day per pair", function()
		local clock = newClock()
		local persistence, base, visitor, owner = pair(clock)
		local ok, result = base:Cheer(visitor, owner)
		expect(ok).toBe(true)
		expect(result.OwnerCoins).toBe(BaseConfig.Visits.CheerCoins)
		expect(result.VisitorCoins).toBe(BaseConfig.Visits.VisitCoins)
		expect(persistence:GetBalance(owner)).toBe(BaseConfig.Visits.CheerCoins)
		expect(persistence:GetBalance(visitor)).toBe(BaseConfig.Visits.VisitCoins)
		expect(select(2, base:Cheer(visitor, owner))).toBe("already cheered")
		expect(base:GetState(owner, clock.now).CheersReceived).toBe(1)
	end)

	it("refuses to cheer your own base", function()
		local clock = newClock()
		local _, base, visitor = pair(clock)
		expect(select(2, base:Cheer(visitor, visitor))).toBe("own base")
		expect(select(2, base:Cheer(visitor, nil))).toBe("own base")
	end)

	it("cheers again the next day", function()
		local clock = newClock()
		local persistence, base, visitor, owner = pair(clock)
		base:Cheer(visitor, owner)
		clock.now += MetaConfig.SecondsPerDay
		local ok, result = base:Cheer(visitor, owner)
		expect(ok).toBe(true)
		expect(result.OwnerCoins).toBe(BaseConfig.Visits.CheerCoins)
		expect(persistence:GetBalance(owner)).toBe(2 * BaseConfig.Visits.CheerCoins)
		-- Yesterday's count does not carry into today.
		expect(base:GetState(owner, clock.now).CheersReceived).toBe(1)
	end)

	it("caps what an owner and a visitor are paid in a day", function()
		local clock = newClock()
		local store = __FakeDataStore.new()
		local persistence, base = newWorld(store, clock)
		local visits = BaseConfig.Visits

		local owner = subject(60)
		persistence:Load(owner)
		local paid = 0
		for index = 1, visits.MaxPaidCheers + 3 do
			local fan = subject(600 + index)
			persistence:Load(fan)
			local ok, result = base:Cheer(fan, owner)
			expect(ok).toBe(true)
			paid += result.OwnerCoins
		end
		expect(paid).toBe(visits.MaxPaidCheers * visits.CheerCoins)

		local traveller = subject(70)
		persistence:Load(traveller)
		local earned = 0
		for index = 1, visits.MaxPaidVisits + 2 do
			local host = subject(700 + index)
			persistence:Load(host)
			local _, result = base:Cheer(traveller, host)
			earned += result.VisitorCoins
		end
		expect(earned).toBe(visits.MaxPaidVisits * visits.VisitCoins)
	end)

	it("refuses while either profile is unavailable", function()
		local clock = newClock()
		local persistence, base = newWorld(__FakeDataStore.new(), clock)
		local visitor = subject(80)
		persistence:Load(visitor)
		expect(select(2, base:Cheer(visitor, subject(81)))).toBe("profile not loaded")
	end)
end)

describe("run bonuses and state", function()
	it("reports the buildings' stat deltas for a run", function()
		local _, base = newWorld(__FakeDataStore.new(), newClock())
		local player = funded(base._persistence, subject(90), 5000)
		base:Upgrade(player, "Infirmary")
		base:Upgrade(player, "Bootworks")
		local bonuses = base:GetRunBonuses(player)
		expect(bonuses.MaxHealthBonus).toBe(10)
		expect(bonuses.MoveSpeedBonus).toBe(1)
	end)

	it("describes the base for the panel, including the next build to save for", function()
		local clock = newClock()
		local _, base = newWorld(__FakeDataStore.new(), clock)
		local player = funded(base._persistence, subject(91), 0)
		local state = base:GetState(player, clock.now)
		expect(state.Hearth).toBe(1)
		expect(state.Levels.Forge).toBe(0)
		expect(state.Layout.Hearth).toBe(BaseConfig.Get("Hearth").DefaultTile)
		expect(state.Balance).toBe(0)
		expect(state.NextBuild.Id).toBe("SalvageYard") -- the cheapest Hearth-1 build
		expect(state.NextBuild.Cost).toBe(cost("SalvageYard", 1))
		expect(base:GetState(subject(92))).toBeNil()
	end)
end)

describe("BaseBuilder plots", function()
	local BaseBuilder = __require("BaseBuilder")
	local RunConfig = __require("RunConfig")

	local function build(options)
		local root = Instance.new("Folder")
		return BaseBuilder.new(root, RunConfig.LobbyPosition, options), root
	end

	it("builds the Outpost with every plot: ground, 16 tiles, fence, sign, entry pad and prompts", function()
		local builder, root = build()
		local outpost = root:FindFirstChild("Outpost")
		expect(outpost).toBeTruthy()
		expect(outpost:FindFirstChild("OutpostGround")).toBeTruthy()
		for index = 1, BaseConfig.Plots.Count do
			local plot = outpost:FindFirstChild("Plot" .. index)
			expect(plot).toBeTruthy()
			expect(#plot:FindFirstChild("Tiles"):GetChildren()).toBe(BaseConfig.Tiles)
			expect(#plot:FindFirstChild("Fence"):GetChildren()).toBeGreaterThan(0)
			expect(plot:FindFirstChild("Sign"):FindFirstChildOfClass("SurfaceGui")).toBeTruthy()
			expect(plot:FindFirstChild("EntryPad"):FindFirstChild("ReturnPrompt")).toBeTruthy()
			expect(builder:EntryPosition(index)).toBeTruthy()
		end
		expect(builder:EntryPosition(BaseConfig.Plots.Count + 1)).toBeNil()
	end)

	it("keeps every plot apart and clear of the hall", function()
		local builder = build()
		local size = BaseConfig.PlotSize()
		for a = 1, BaseConfig.Plots.Count do
			local centre = BaseConfig.PlotCentre(a, RunConfig.LobbyPosition)
			-- The hall is 100 studs deep: the Outpost must start well beyond its north wall.
			expect(RunConfig.LobbyPosition.Z - centre.Z).toBeGreaterThan(50 + size)
			for b = a + 1, BaseConfig.Plots.Count do
				local other = BaseConfig.PlotCentre(b, RunConfig.LobbyPosition)
				local apart = math.max(math.abs(centre.X - other.X), math.abs(centre.Z - other.Z))
				expect(apart).toBeGreaterThan(size)
			end
		end
		local _ = builder
	end)

	it("assigns the first free plot, marks the player, and frees it on release", function()
		local builder, root = build()
		local first, second = Harness.addPlayer("PlotA"), Harness.addPlayer("PlotB")
		expect(builder:Assign(first)).toBe(1)
		expect(builder:Assign(second)).toBe(2)
		expect(builder:Assign(first)).toBe(1) -- idempotent
		expect(first:GetAttribute("PlotIndex")).toBe(1)
		expect(builder:OwnerOf(2)).toBe(second)
		local sign = root:FindFirstChild("Outpost"):FindFirstChild("Plot1"):FindFirstChild("Sign")
		expect(sign:FindFirstChildOfClass("SurfaceGui"):FindFirstChild("Text").Text).toBe("PLOTA'S OUTPOST")

		builder:Release(first)
		expect(first:GetAttribute("PlotIndex")).toBeNil()
		expect(builder:OwnerOf(1)).toBeNil()
		expect(sign:FindFirstChildOfClass("SurfaceGui"):FindFirstChild("Text").Text).toBe("OPEN PLOT")
		local third = Harness.addPlayer("PlotC")
		expect(builder:Assign(third)).toBe(1)
		for _, player in { first, second, third } do
			Harness.removePlayer(player)
		end
	end)

	it("has no plot for a player past the plot count", function()
		local builder = build()
		local players = {}
		for index = 1, BaseConfig.Plots.Count do
			players[index] = { Name = "P" .. index, UserId = index, SetAttribute = function() end }
			expect(builder:Assign(players[index])).toBe(index)
		end
		local late = { Name = "Late", UserId = 99, SetAttribute = function() end }
		expect(builder:Assign(late)).toBeNil()
		expect(builder:Refresh(late, { Levels = {}, Layout = {} })).toBe(false)
	end)

	it("raises a storey per level with a label, moves the Hearth prompts, and shows trophies", function()
		local builder = build()
		local owner = Harness.addPlayer("Builder")
		builder:Assign(owner)
		local refreshed = builder:Refresh(owner, {
			Levels = { Hearth = 2, Forge = 3, TrophyHall = 1, Bootworks = 0 },
			Layout = { Hearth = 6, Forge = 1, TrophyHall = 16, Bootworks = 2 },
			Theme = "Frost",
			Sign = "Banner",
			Trophies = 20,
		})
		expect(refreshed).toBe(true)
		local plot = builder:PlotFor(owner)
		local forge = plot.buildings:FindFirstChild("Forge")
		expect(forge:GetAttribute("Level")).toBe(3)
		expect(forge:FindFirstChild("Storey3")).toBeTruthy()
		expect(forge:FindFirstChild("Storey4")).toBeNil()
		local label = forge:FindFirstChild("Roof"):FindFirstChild("Label")
		expect(label:FindFirstChild("Text").Text).toBe("Forge Lv3")
		expect(plot.buildings:FindFirstChild("Bootworks")).toBeNil() -- level 0 is not built

		local hearthRoof = plot.buildings:FindFirstChild("Hearth"):FindFirstChild("Roof")
		expect(hearthRoof:FindFirstChild("ManagePrompt")).toBeTruthy()
		expect(hearthRoof:FindFirstChild("CheerPrompt")).toBeTruthy()

		local hall = plot.buildings:FindFirstChild("TrophyHall")
		expect(hall:FindFirstChild("Trophy" .. BaseConfig.MaxTrophies)).toBeTruthy()
		expect(hall:FindFirstChild("Trophy" .. (BaseConfig.MaxTrophies + 1))).toBeNil()

		expect(plot.ground.Color).toBe(BaseConfig.ThemeOf("Frost").Ground)
		expect(plot.sign.Color).toBe(BaseConfig.SignOf("Banner").Back)

		-- A rebuild replaces the models rather than piling new ones on top.
		builder:Refresh(owner, { Levels = { Hearth = 1 }, Layout = { Hearth = 6 } })
		expect(#plot.buildings:GetChildren()).toBe(1)
		expect(plot.ground.Color).toBe(BaseConfig.ThemeOf("").Ground)
		Harness.removePlayer(owner)
	end)

	it("routes the prompts to their handlers with the plot's owner", function()
		local managed, cheered, returned = {}, {}, {}
		local builder = build({
			onManage = function(player, owner)
				table.insert(managed, { player, owner })
			end,
			onCheer = function(player, owner)
				table.insert(cheered, { player, owner })
			end,
			onReturn = function(player)
				table.insert(returned, player)
			end,
		})
		local owner, visitor = Harness.addPlayer("Owner"), Harness.addPlayer("Visitor")
		builder:Assign(owner)
		builder:Refresh(owner, { Levels = { Hearth = 1 }, Layout = { Hearth = 6 } })
		local plot = builder:PlotFor(owner)
		plot.cheer.Triggered:Fire(visitor)
		plot.manage.Triggered:Fire(owner)
		plot.entry:FindFirstChild("ReturnPrompt").Triggered:Fire(visitor)
		expect(cheered[1][1]).toBe(visitor)
		expect(cheered[1][2]).toBe(owner)
		expect(managed[1][2]).toBe(owner)
		expect(returned[1]).toBe(visitor)
		Harness.removePlayer(owner)
		Harness.removePlayer(visitor)
	end)
end)

describe("base remotes", function()
	local RemoteRouter = __require("RemoteRouter")
	local Remotes = __require("Remotes")

	it("routes build, move, claim and sync requests and sanitises what the client sends", function()
		local clock = newClock()
		local persistence, base = newWorld(__FakeDataStore.new(), clock)
		local player = Harness.addPlayer("BaseRemote")
		funded(persistence, player, 5000)
		local results, visits, cheers = {}, {}, {}
		local router = RemoteRouter.new(function()
			return nil
		end, persistence, nil, nil, {
			base = base,
			onBaseResult = function(_, kind, ok, result)
				table.insert(results, { kind = kind, ok = ok, result = result })
			end,
			onVisitBase = function(_, userId)
				table.insert(visits, userId or "own")
			end,
			onCheerBase = function(_, userId)
				table.insert(cheers, userId)
			end,
		})
		router:Bind()

		Remotes.Get("UpgradeBuilding").OnServerEvent:Fire(player, "Forge", 2)
		expect(results[1].kind).toBe("Upgrade")
		expect(results[1].ok).toBe(true)
		expect(base:EnsureLayout(player).Forge).toBe(2)

		Harness.advance(1)
		Remotes.Get("UpgradeBuilding").OnServerEvent:Fire(player, "Bootworks", 2.5)
		expect(results[2].result).toBe("invalid tile")
		Harness.advance(1)
		Remotes.Get("UpgradeBuilding").OnServerEvent:Fire(player, { "Forge" })
		expect(results[3].result).toBe("unknown building")

		Remotes.Get("MoveBuilding").OnServerEvent:Fire(player, "Forge", 9)
		expect(base:EnsureLayout(player).Forge).toBe(9)
		Harness.advance(1)
		Remotes.Get("MoveBuilding").OnServerEvent:Fire(player, "Forge", "9")
		expect(results[#results].result).toBe("invalid tile")

		Remotes.Get("ClaimBase").OnServerEvent:Fire(player)
		expect(results[#results].kind).toBe("Claim")
		Remotes.Get("RequestBase").OnServerEvent:Fire(player)
		expect(results[#results].kind).toBe("Sync")

		Remotes.Get("VisitBase").OnServerEvent:Fire(player, nil)
		Harness.advance(2)
		Remotes.Get("VisitBase").OnServerEvent:Fire(player, 0 / 0)
		expect(visits[1]).toBe("own")
		expect(visits[2]).toBe("own") -- a malformed id falls back to your own plot
		Remotes.Get("CheerBase").OnServerEvent:Fire(player, "nobody")
		Remotes.Get("CheerBase").OnServerEvent:Fire(player, 77)
		expect(#cheers).toBe(1)
		expect(cheers[1]).toBe(77)

		router:Destroy()
		Harness.removePlayer(player)
	end)
end)
