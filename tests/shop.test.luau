-- The Cosmetics shop and the purchase path it shares with the home base: catalogue integrity,
-- authoritative purchases through PlayerDataService's grant-style reconciliation (including
-- across servers, exercised on multi-level buildings since the Armory was retired), building
-- bonuses reaching a run, trails, and the remote boundary.
local BaseConfig = __require("BaseConfig")
local BaseService = __require("BaseService")
local EnemyService = __require("EnemyService")
local FeatureFlags = __require("FeatureFlags")
local MatchService = __require("MatchService")
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")
local ProjectileService = __require("ProjectileService")
local RemoteRouter = __require("RemoteRouter")
local Remotes = __require("Remotes")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local ShopConfig = __require("ShopConfig")
local ShopService = __require("ShopService")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3

local function subject(userId)
	return { Name = "S" .. userId, UserId = userId }
end

-- A loaded profile holding `salvage`, paid in as a run grant and saved, the way real salvage
-- arrives.
local function funded(persistence, player, salvage)
	persistence:Load(player)
	if salvage > 0 then
		persistence:GrantReward(player, "seed-" .. player.UserId, salvage)
		persistence:Save(player, 0)
	end
	return player
end

local function newShop(persistence, overrides)
	local options = { canShop = function()
		return true
	end }
	for key, value in overrides or {} do
		options[key] = value
	end
	return ShopService.new(persistence, options)
end

local function stored(store, player)
	return store:Peek(PlayerDataConfig.KeyPrefix .. tostring(player.UserId))
end

local function newBase(persistence)
	return BaseService.new(persistence)
end

local function buildingCost(id, level)
	local building = BaseConfig.Get(id)
	return BaseConfig.CostFor(building, level)
end

local function trailIds()
	local ids = {}
	for _, item in ShopConfig.Items do
		if item.Kind == "Trail" and not item.RequiresPass then
			table.insert(ids, item.Id)
		end
	end
	return ids
end

describe("ShopConfig catalogue", function()
	it("gives every item a unique id, ascending positive whole-number costs and a max level", function()
		local seen = {}
		for _, item in ShopConfig.Items do
			expect(seen[item.Id]).toBeNil()
			seen[item.Id] = true
			expect(#item.Costs).toBeGreaterThan(0)
			expect(ShopConfig.MaxLevel(item)).toBe(#item.Costs)
			local previous = 0
			for _, price in item.Costs do
				expect(price).toBeGreaterThan(previous)
				expect(price).toBe(math.floor(price))
				previous = price
			end
			expect(type(item.Title)).toBe("string")
			expect(type(item.Description)).toBe("string")
		end
	end)

	it("sells nothing that changes a run: every item is cosmetic, and every trail has a colour", function()
		local trails = 0
		for _, item in ShopConfig.Items do
			expect(item.Effect).toBeNil()
			expect(item.Kind).never().toBe("Stat")
			if item.Kind == "Trail" then
				trails += 1
				expect(typeof(item.Trail.Color)).toBe("Color3")
				expect(ShopConfig.MaxLevel(item)).toBe(1)
			end
		end
		expect(trails).toBeGreaterThanOrEqual(1)
	end)

	it("never shares an id with a building or a retired Armory item, since all live in MetaUpgrades", function()
		for _, item in ShopConfig.Items do
			expect(BaseConfig.Get(item.Id)).toBeNil()
			expect(PlayerDataConfig.LegacyArmoryCosts[item.Id]).toBeNil()
		end
	end)
end)

describe("ShopService purchases", function()
	it("deducts the cost, records ownership and persists both on save", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(1), 300)
		local shop = newShop(persistence)
		local cost = ShopConfig.CostFor(ShopConfig.Get("TrailEmber"), 1)

		local ok, result = shop:Purchase(player, "TrailEmber", 0)
		expect(ok).toBe(true)
		expect(result.Level).toBe(1)
		expect(result.Balance).toBe(300 - cost)
		expect(persistence:GetBalance(player)).toBe(300 - cost)
		expect(persistence:GetMetaLevels(player).TrailEmber).toBe(1)

		persistence:Save(player, 1)
		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(300 - cost)
		expect(saved.MetaUpgrades.TrailEmber).toBe(1)
	end)

	it("refuses when the player cannot afford it, changing nothing", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(2), 10)
		local ok, reason = newShop(persistence):Purchase(player, "TrailEmber", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("insufficient salvage")
		expect(persistence:GetBalance(player)).toBe(10)
		expect(persistence:GetMetaLevels(player).TrailEmber).toBeNil()
	end)

	it("refuses to sell a cosmetic twice", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(3), 100000)
		local shop = newShop(persistence)
		expect((shop:Purchase(player, "TrailAurora", 0))).toBe(true)
		local ok, reason = shop:Purchase(player, "TrailAurora", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("max level")
	end)

	it("refuses unknown and malformed item ids, and buildings, which only the base sells", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(4), 1000)
		local shop = newShop(persistence)
		expect((shop:Purchase(player, "FreeMoney", 0))).toBe(false)
		expect((shop:Purchase(player, 42, 0))).toBe(false)
		expect((shop:Purchase(player, nil, 0))).toBe(false)
		expect((shop:Purchase(player, "Forge", 0))).toBe(false)
		expect((shop:Purchase(player, "Vitality", 0))).toBe(false)
		expect(persistence:GetBalance(player)).toBe(1000)
	end)

	it("refuses outside the lobby", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(5), 1000)
		local shop = newShop(persistence, { canShop = function()
			return false
		end })
		local ok, reason = shop:Purchase(player, "TrailEmber", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("shop closed")
	end)

	it("refuses in a read-only session, where nothing could be saved", function()
		local store = __FakeDataStore.new()
		store.alwaysFail = true
		local persistence = PlayerDataService.new(store)
		local player = subject(6)
		persistence:Load(player)
		local ok = newShop(persistence):Purchase(player, "TrailEmber", 0)
		expect(ok).toBe(false)
	end)

	it("is inert when the feature flag is off", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(7), 1000)
		local previous = FeatureFlags.SalvageShop
		FeatureFlags.SalvageShop = false
		local ok, reason = newShop(persistence):Purchase(player, "TrailEmber", 0)
		FeatureFlags.SalvageShop = previous
		expect(ok).toBe(false)
		expect(reason).toBe("shop disabled")
		expect(persistence:GetBalance(player)).toBe(1000)
	end)

	it("lets a purchase spend coins from a run grant that has not been written yet", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(8), 0)
		persistence:GrantReward(player, "run-1", 200)
		expect((newShop(persistence):Purchase(player, "TrailEmber", 0))).toBe(true)
		persistence:Save(player, 1)
		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(200 - ShopConfig.CostFor(ShopConfig.Get("TrailEmber"), 1))
		expect(saved.MetaUpgrades.TrailEmber).toBe(1)
	end)
end)

describe("multi-level purchases (buildings)", function()
	it("survives a reload on another server", function()
		local store = __FakeDataStore.new()
		local first = PlayerDataService.new(store)
		local player = funded(first, subject(9), 1000)
		local base = newBase(first)
		expect((base:Upgrade(player, "Infirmary"))).toBe(true)
		expect((base:Upgrade(player, "Infirmary"))).toBe(true)
		first:Release(player, 1)

		local second = PlayerDataService.new(store)
		second:Load(player)
		expect(second:GetMetaLevels(player).Infirmary).toBe(2)
		local spent = buildingCost("Infirmary", 1) + buildingCost("Infirmary", 2)
		expect(second:GetBalance(player)).toBe(1000 - spent)
	end)

	it("commits two levels bought before a save in the order they were bought", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(10), 5000)
		local base = newBase(persistence)
		base:Upgrade(player, "Hearth")
		base:Upgrade(player, "Hearth")
		base:Upgrade(player, "Hearth")
		persistence:Save(player, 1)
		expect(stored(store, player).MetaUpgrades.Hearth).toBe(3)
		expect(BaseConfig.LevelOf(stored(store, player).MetaUpgrades, "Hearth")).toBe(4)
	end)
end)

describe("purchases across servers", function()
	it("charges once when two servers sell the same level", function()
		local store = __FakeDataStore.new()
		local serverA, serverB = PlayerDataService.new(store), PlayerDataService.new(store)
		local player = subject(20)
		funded(serverA, player, 200)
		serverB:Load(player)

		expect((newBase(serverA):Upgrade(player, "Infirmary"))).toBe(true)
		expect((newBase(serverB):Upgrade(player, "Infirmary"))).toBe(true)
		serverA:Save(player, 1)
		serverB:Save(player, 2)

		local cost = buildingCost("Infirmary", 1)
		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(200 - cost)
		expect(saved.MetaUpgrades.Infirmary).toBe(1)
		expect(serverB:GetBalance(player)).toBe(200 - cost)
	end)

	it("rejects a purchase the stored balance can no longer cover, and rolls it back", function()
		local store = __FakeDataStore.new()
		local serverA, serverB = PlayerDataService.new(store), PlayerDataService.new(store)
		local player = subject(21)
		local forge = buildingCost("Forge", 1)
		local boots = buildingCost("Bootworks", 1)
		-- Enough for either purchase, not both.
		local balance = forge + boots - 1
		funded(serverA, player, balance)
		serverB:Load(player)

		expect((newBase(serverA):Upgrade(player, "Forge"))).toBe(true)
		expect((newBase(serverB):Upgrade(player, "Bootworks"))).toBe(true)
		serverA:Save(player, 1)
		serverB:Save(player, 2)

		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(balance - forge)
		expect(saved.MetaUpgrades.Forge).toBe(1)
		expect(saved.MetaUpgrades.Bootworks).toBeNil()

		-- Server B learns the truth: its optimistic purchase is undone and reported.
		expect(serverB:GetBalance(player)).toBe(balance - forge)
		expect(serverB:GetMetaLevels(player).Bootworks).toBeNil()
		local rejections = serverB:TakePurchaseRejections(player)
		expect(#rejections).toBe(1)
		expect(rejections[1].ItemId).toBe("Bootworks")
		expect(#serverB:TakePurchaseRejections(player)).toBe(0)
	end)

	it("rejects a cosmetic the other server already spent the coins on", function()
		local store = __FakeDataStore.new()
		local serverA, serverB = PlayerDataService.new(store), PlayerDataService.new(store)
		local player = subject(23)
		local ember = ShopConfig.CostFor(ShopConfig.Get("TrailEmber"), 1)
		funded(serverA, player, ember)
		serverB:Load(player)
		expect((newShop(serverA):Purchase(player, "TrailEmber", 0))).toBe(true)
		expect((newBase(serverB):Upgrade(player, "Forge"))).toBe(true)
		serverA:Save(player, 1)
		serverB:Save(player, 2)
		expect(stored(store, player).MetaUpgrades.Forge).toBeNil()
		expect(stored(store, player).MetaUpgrades.TrailEmber).toBe(1)
	end)

	it("never lets Update edit meta upgrades directly", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(22), 0)
		local ok = pcall(function()
			persistence:Update(player, function(profile)
				profile.MetaUpgrades.TrailVoid = 1
			end)
		end)
		expect(ok).toBe(false)
		expect(persistence:GetMetaLevels(player).TrailVoid).toBeNil()
	end)
end)
describe("profile schema v5", function()
	it("migrates a v4 profile, keeping its salvage and ledger", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 4,
			Currency = { Salvage = 77 },
			GrantedRuns = { ["run-a"] = { Amount = 77, At = 5 } },
		})
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(PlayerDataConfig.SchemaVersion).toBe(9)
		expect(profile.Currency.Salvage).toBe(77)
		expect(profile.GrantedRuns["run-a"].Amount).toBe(77)
		expect(type(profile.MetaUpgrades)).toBe("table")
		expect(profile.EquippedTrail).toBe("")
	end)
end)

describe("trails", function()
	local function firstTrail()
		for _, item in ShopConfig.Items do
			if item.Kind == "Trail" then
				return item
			end
		end
		return nil
	end

	it("equips a trail on purchase and refuses one the player does not own", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(30), 5000)
		local shop = newShop(persistence)
		local trail = firstTrail()

		local ok, reason = shop:Equip(player, trail.Id)
		expect(ok).toBe(false)
		expect(reason).toBe("not owned")

		expect((shop:Purchase(player, trail.Id, 0))).toBe(true)
		expect(persistence:GetPublicProfile(player).EquippedTrail).toBe(trail.Id)
		expect(shop:GetTrail(player).Color).toBe(trail.Trail.Color)

		expect((shop:Equip(player, ""))).toBe(true)
		expect(shop:GetTrail(player)).toBeNil()
		expect((shop:Equip(player, "Forge"))).toBe(false)
	end)

	it("lights the trail on the shooter's pooled projectiles and clears it on release", function()
		local arena = Instance.new("Folder")
		local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
		local trail = firstTrail()
		projectiles:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(1, 0, 0), 1, { trail = trail.Trail })
		local lit = 0
		for _, part in arena:FindFirstChild("ProjectilePool"):GetChildren() do
			local effect = part:FindFirstChild("Trail")
			expect(effect).toBeTruthy()
			if effect.Enabled then
				lit += 1
				expect(effect.Color.Keypoints[1].Value).toBe(trail.Trail.Color)
			end
		end
		expect(lit).toBe(1)
		projectiles:Clear()
		for _, part in arena:FindFirstChild("ProjectilePool"):GetChildren() do
			expect(part:FindFirstChild("Trail").Enabled).toBe(false)
		end
	end)
end)

describe("building bonuses in a run", function()
	it("starts the run with built max health and projectile speed", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = Harness.addPlayer("Meta")
		funded(persistence, player, 100000)
		local base = newBase(persistence)
		base:Upgrade(player, "Infirmary")
		base:Upgrade(player, "Infirmary")
		base:Upgrade(player, "RailLab")

		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 1)
		local match = MatchService.new({
			rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(1)),
			enemies = enemies,
			upgrades = UpgradeService.new(1),
			projectiles = ProjectileService.new(arena, arena, PLANE_Y),
			rewards = RewardService.new(),
			net = {},
			metaProvider = function(target)
				return { stats = base:GetRunBonuses(target) }
			end,
		})
		match:RequestStart(player, 0)
		local state = match:GetPlayerState(player)
		local perLevel = BaseConfig.Get("Infirmary").Effect.PerLevel
		expect(state.maxHealth).toBe(RunConfig.BaseHealth + perLevel * 2)
		expect(state.health).toBe(state.maxHealth)
		expect(state.stats.SpeedMultiplier).toBeCloseTo(1 + BaseConfig.Get("RailLab").Effect.PerLevel)

		-- Cards stack on top of building bonuses rather than replacing them.
		state:AddUpgrade(UpgradeConfig.Get("Plating"))
		expect(state.stats.MaxHealthBonus).toBeGreaterThan(perLevel * 2)
		Harness.removePlayer(player)
	end)

	it("only moves stats a run has", function()
		for _, building in BaseConfig.Buildings do
			if building.Effect then
				expect(UpgradeConfig.BaseStats[building.Effect.Stat]).never().toBeNil()
				expect(building.Effect.PerLevel).toBeGreaterThan(0)
			end
		end
	end)
end)

describe("shop remotes", function()
	it("routes a purchase request through the rate limiter and reports the result", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = Harness.addPlayer("Buyer")
		funded(persistence, player, 100000)
		local shop = newShop(persistence)
		local match = { HandleFire = function() end }
		local router = RemoteRouter.new(match, persistence, nil, shop)
		router:Bind()

		local purchase = Remotes.Get("PurchaseShopItem")
		local results = Remotes.Get("ShopResult")
		local before = #rawget(results, "_fired")
		purchase.OnServerEvent:Fire(player, "TrailEmber")
		expect(persistence:GetMetaLevels(player).TrailEmber).toBe(1)
		local reply = rawget(results, "_fired")[before + 1]
		expect(reply.player).toBe(player)
		expect(reply.args[1].Ok).toBe(true)

		-- A flood is cut off by the per-player bucket, whatever the balance allows.
		local ids = trailIds()
		local bought = 0
		for index = 1, 20 do
			purchase.OnServerEvent:Fire(player, ids[(index % #ids) + 1])
		end
		for _, id in ids do
			bought += persistence:GetMetaLevels(player)[id] or 0
		end
		expect(bought).toBeLessThan(#ids)

		router:Destroy()
		Harness.removePlayer(player)
	end)
end)

describe("ShopView", function()
	local ShopView = __require("ShopView")

	local function rowButton(view, itemId)
		return view.panel:FindFirstChild("Items"):FindFirstChild(itemId):FindFirstChild("Action")
	end

	it("prices an unowned cosmetic and offers equip for an owned trail", function()
		local view = ShopView.new(Instance.new("Folder"), function() end, function() end)
		view:SetProfile({
			Salvage = 500,
			MetaUpgrades = { TrailEmber = 1 },
			EquippedTrail = "",
		})
		expect(rowButton(view, "TrailAurora").Text).toBe("Buy  " .. ShopConfig.CostFor(ShopConfig.Get("TrailAurora"), 1))
		expect(rowButton(view, "TrailEmber").Text).toBe("Equip")
		expect(view.balanceLabel.Text).toBe("500 coins")
	end)

	it("asks the server to buy or equip, and never changes its own numbers", function()
		local bought, equipped = {}, {}
		local view = ShopView.new(Instance.new("Folder"), function(itemId)
			table.insert(bought, itemId)
		end, function(itemId)
			table.insert(equipped, itemId)
		end)
		view:SetProfile({ Salvage = 1000, MetaUpgrades = { TrailEmber = 1 }, EquippedTrail = "TrailEmber" })
		rowButton(view, "TrailVoid").Activated:Fire()
		rowButton(view, "TrailEmber").Activated:Fire()
		expect(bought[1]).toBe("TrailVoid")
		expect(equipped[1]).toBe("") -- tapping the equipped trail takes it off
		expect(view.balanceLabel.Text).toBe("1000 coins")
	end)
end)

describe("Cosmetics catalogue", function()
	it("sorts every coin item into Cosmetics", function()
		for _, item in ShopConfig.Items do
			expect(item.Category).toBe("Cosmetics")
		end
	end)

	it("sells Frost, Toxic and a pass-only Gold trail", function()
		for _, id in { "TrailFrost", "TrailToxic", "TrailGold" } do
			expect(ShopConfig.Get(id).Kind).toBe("Trail")
		end
		expect(ShopConfig.Get("TrailGold").RequiresPass).toBeTruthy()
	end)

	it("refuses the Gold trail without its pass, and sells it with one", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(7701), 5000)
		local pass = ShopConfig.Get("TrailGold").RequiresPass
		local owns = false
		local shop = newShop(persistence, {
			ownsPass = function(_, key)
				return key == pass and owns
			end,
		})
		local ok, reason = shop:Purchase(player, "TrailGold", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("requires " .. pass)
		owns = true
		ok = shop:Purchase(player, "TrailGold", 0)
		expect(ok).toBe(true)
	end)
end)

describe("ShopView tabs", function()
	local ShopView = __require("ShopView")

	it("shows only the open tab's items", function()
		local view = ShopView.new(Instance.new("Folder"), function() end, function() end)
		view:SetTab("Cosmetics")
		local items = view.panel:FindFirstChild("Items")
		expect(items:FindFirstChild("TrailEmber").Visible).toBe(true)
		view:SetTab("Store")
		expect(items:FindFirstChild("TrailEmber").Visible).toBe(false)
	end)
end)
