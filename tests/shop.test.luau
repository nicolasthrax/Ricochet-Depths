-- Salvage shop: catalogue integrity, authoritative purchases through PlayerDataService's
-- grant-style reconciliation (including across servers), meta bonuses reaching a run, trails,
-- and the remote boundary.
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

describe("ShopConfig catalogue", function()
	it("gives every item a unique id, ascending positive whole-number costs and a max level", function()
		local seen = {}
		for _, item in ShopConfig.Items do
			expect(seen[item.Id]).toBeNil()
			seen[item.Id] = true
			expect(#item.Costs).toBeGreaterThan(0)
			expect(ShopConfig.MaxLevel(item)).toBe(#item.Costs)
			local previous = 0
			for _, cost in item.Costs do
				expect(cost).toBeGreaterThan(previous)
				expect(cost).toBe(math.floor(cost))
				previous = cost
			end
			expect(type(item.Title)).toBe("string")
			expect(type(item.Description)).toBe("string")
		end
	end)

	it("only moves stats that exist, and gives every trail a colour", function()
		local stats, trails = 0, 0
		for _, item in ShopConfig.Items do
			if item.Kind == "Stat" then
				stats += 1
				expect(UpgradeConfig.BaseStats[item.Effect.Stat]).never().toBeNil()
				expect(item.Effect.PerLevel).toBeGreaterThan(0)
			elseif item.Kind == "Trail" then
				trails += 1
				expect(typeof(item.Trail.Color)).toBe("Color3")
				expect(ShopConfig.MaxLevel(item)).toBe(1)
			else
				error("unknown item kind " .. tostring(item.Kind))
			end
		end
		expect(stats).toBeGreaterThanOrEqual(3)
		expect(trails).toBeGreaterThanOrEqual(1)
	end)

	it("offers max health, starting speed and a 1% projectile speed step", function()
		expect(ShopConfig.Get("Vitality").Effect.Stat).toBe("MaxHealthBonus")
		expect(ShopConfig.Get("Stride").Effect.Stat).toBe("MoveSpeedBonus")
		expect(ShopConfig.Get("Velocity").Effect.Stat).toBe("SpeedMultiplier")
		expect(ShopConfig.Get("Velocity").Effect.PerLevel).toBeCloseTo(0.01)
	end)

	it("folds owned levels into stat bonuses, ignoring unknown ids and clamping to max level", function()
		local vitality = ShopConfig.Get("Vitality")
		local bonuses = ShopConfig.ComputeBonuses({ Vitality = 2, Velocity = 3, Nonsense = 9 })
		expect(bonuses.MaxHealthBonus).toBeCloseTo(vitality.Effect.PerLevel * 2)
		expect(bonuses.SpeedMultiplier).toBeCloseTo(0.03)
		expect(bonuses.MoveSpeedBonus or 0).toBe(0)
		local capped = ShopConfig.ComputeBonuses({ Vitality = 99 })
		expect(capped.MaxHealthBonus).toBeCloseTo(vitality.Effect.PerLevel * ShopConfig.MaxLevel(vitality))
	end)
end)

describe("ShopService purchases", function()
	it("deducts the cost, raises the level and persists both on save", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(1), 300)
		local shop = newShop(persistence)
		local cost = ShopConfig.CostFor(ShopConfig.Get("Vitality"), 1)

		local ok, result = shop:Purchase(player, "Vitality", 0)
		expect(ok).toBe(true)
		expect(result.Level).toBe(1)
		expect(result.Balance).toBe(300 - cost)
		expect(persistence:GetBalance(player)).toBe(300 - cost)
		expect(persistence:GetMetaLevels(player).Vitality).toBe(1)

		persistence:Save(player, 1)
		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(300 - cost)
		expect(saved.MetaUpgrades.Vitality).toBe(1)
	end)

	it("refuses when the player cannot afford it, changing nothing", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(2), 10)
		local ok, reason = newShop(persistence):Purchase(player, "Vitality", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("insufficient salvage")
		expect(persistence:GetBalance(player)).toBe(10)
		expect(persistence:GetMetaLevels(player).Vitality).toBeNil()
	end)

	it("refuses past the item's max level", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(3), 100000)
		local shop = newShop(persistence)
		local item = ShopConfig.Get("Stride")
		for _ = 1, ShopConfig.MaxLevel(item) do
			expect((shop:Purchase(player, "Stride", 0))).toBe(true)
		end
		local ok, reason = shop:Purchase(player, "Stride", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("max level")
	end)

	it("refuses unknown and malformed item ids", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(4), 1000)
		local shop = newShop(persistence)
		expect((shop:Purchase(player, "FreeMoney", 0))).toBe(false)
		expect((shop:Purchase(player, 42, 0))).toBe(false)
		expect((shop:Purchase(player, nil, 0))).toBe(false)
		expect(persistence:GetBalance(player)).toBe(1000)
	end)

	it("refuses outside the lobby", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(5), 1000)
		local shop = newShop(persistence, { canShop = function()
			return false
		end })
		local ok, reason = shop:Purchase(player, "Vitality", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("shop closed")
	end)

	it("refuses in a read-only session, where nothing could be saved", function()
		local store = __FakeDataStore.new()
		store.alwaysFail = true
		local persistence = PlayerDataService.new(store)
		local player = subject(6)
		persistence:Load(player)
		local ok = newShop(persistence):Purchase(player, "Vitality", 0)
		expect(ok).toBe(false)
	end)

	it("is inert when the feature flag is off", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(7), 1000)
		local previous = FeatureFlags.SalvageShop
		FeatureFlags.SalvageShop = false
		local ok, reason = newShop(persistence):Purchase(player, "Vitality", 0)
		FeatureFlags.SalvageShop = previous
		expect(ok).toBe(false)
		expect(reason).toBe("shop disabled")
		expect(persistence:GetBalance(player)).toBe(1000)
	end)

	it("lets a purchase spend salvage from a run grant that has not been written yet", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(8), 0)
		persistence:GrantReward(player, "run-1", 150)
		expect((newShop(persistence):Purchase(player, "Vitality", 0))).toBe(true)
		persistence:Save(player, 1)
		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(150 - ShopConfig.CostFor(ShopConfig.Get("Vitality"), 1))
		expect(saved.MetaUpgrades.Vitality).toBe(1)
	end)

	it("survives a reload on another server", function()
		local store = __FakeDataStore.new()
		local first = PlayerDataService.new(store)
		local player = funded(first, subject(9), 500)
		newShop(first):Purchase(player, "Velocity", 0)
		newShop(first):Purchase(player, "Velocity", 0)
		first:Release(player, 1)

		local second = PlayerDataService.new(store)
		second:Load(player)
		expect(second:GetMetaLevels(player).Velocity).toBe(2)
		local spent = ShopConfig.CostFor(ShopConfig.Get("Velocity"), 1) + ShopConfig.CostFor(ShopConfig.Get("Velocity"), 2)
		expect(second:GetBalance(player)).toBe(500 - spent)
	end)
end)

describe("purchases across servers", function()
	it("charges once when two servers sell the same level", function()
		local store = __FakeDataStore.new()
		local serverA, serverB = PlayerDataService.new(store), PlayerDataService.new(store)
		local player = subject(20)
		funded(serverA, player, 200)
		serverB:Load(player)

		expect((newShop(serverA):Purchase(player, "Vitality", 0))).toBe(true)
		expect((newShop(serverB):Purchase(player, "Vitality", 0))).toBe(true)
		serverA:Save(player, 1)
		serverB:Save(player, 2)

		local cost = ShopConfig.CostFor(ShopConfig.Get("Vitality"), 1)
		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(200 - cost)
		expect(saved.MetaUpgrades.Vitality).toBe(1)
		expect(serverB:GetBalance(player)).toBe(200 - cost)
	end)

	it("rejects a purchase the stored balance can no longer cover, and rolls it back", function()
		local store = __FakeDataStore.new()
		local serverA, serverB = PlayerDataService.new(store), PlayerDataService.new(store)
		local player = subject(21)
		local vitality = ShopConfig.CostFor(ShopConfig.Get("Vitality"), 1)
		local stride = ShopConfig.CostFor(ShopConfig.Get("Stride"), 1)
		-- Enough for either purchase, not both.
		local balance = math.max(vitality, stride) + math.min(vitality, stride) - 1
		funded(serverA, player, balance)
		serverB:Load(player)

		expect((newShop(serverA):Purchase(player, "Vitality", 0))).toBe(true)
		expect((newShop(serverB):Purchase(player, "Stride", 0))).toBe(true)
		serverA:Save(player, 1)
		serverB:Save(player, 2)

		local saved = stored(store, player)
		expect(saved.Currency.Salvage).toBe(balance - vitality)
		expect(saved.MetaUpgrades.Vitality).toBe(1)
		expect(saved.MetaUpgrades.Stride).toBeNil()

		-- Server B learns the truth: its optimistic purchase is undone and reported.
		expect(serverB:GetBalance(player)).toBe(balance - vitality)
		expect(serverB:GetMetaLevels(player).Stride).toBeNil()
		local rejections = serverB:TakePurchaseRejections(player)
		expect(#rejections).toBe(1)
		expect(rejections[1].ItemId).toBe("Stride")
		expect(#serverB:TakePurchaseRejections(player)).toBe(0)
	end)

	it("never lets Update edit meta upgrades directly", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = funded(persistence, subject(22), 0)
		local ok = pcall(function()
			persistence:Update(player, function(profile)
				profile.MetaUpgrades.Vitality = 5
			end)
		end)
		expect(ok).toBe(false)
		expect(persistence:GetMetaLevels(player).Vitality).toBeNil()
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
		expect(PlayerDataConfig.SchemaVersion).toBe(5)
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
		expect(shop:GetRunBonuses(player).trail.Color).toBe(trail.Trail.Color)

		expect((shop:Equip(player, ""))).toBe(true)
		expect(shop:GetRunBonuses(player).trail).toBeNil()
		expect((shop:Equip(player, "Vitality"))).toBe(false)
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

describe("meta bonuses in a run", function()
	it("starts the run with bought max health and projectile speed", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = Harness.addPlayer("Meta")
		funded(persistence, player, 100000)
		local shop = newShop(persistence)
		shop:Purchase(player, "Vitality", 0)
		shop:Purchase(player, "Vitality", 0)
		shop:Purchase(player, "Velocity", 0)

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
				return shop:GetRunBonuses(target)
			end,
		})
		match:RequestStart(player, 0)
		local state = match:GetPlayerState(player)
		local perLevel = ShopConfig.Get("Vitality").Effect.PerLevel
		expect(state.maxHealth).toBe(RunConfig.BaseHealth + perLevel * 2)
		expect(state.health).toBe(state.maxHealth)
		expect(state.stats.SpeedMultiplier).toBeCloseTo(1.01)

		-- Cards stack on top of meta bonuses rather than replacing them.
		state:AddUpgrade(UpgradeConfig.Get("Plating"))
		expect(state.stats.MaxHealthBonus).toBeGreaterThan(perLevel * 2)
		Harness.removePlayer(player)
	end)
end)

describe("shop remotes", function()
	it("routes a purchase request through the rate limiter and reports the result", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = Harness.addPlayer("Buyer")
		funded(persistence, player, 1000)
		local shop = newShop(persistence)
		local match = { HandleFire = function() end }
		local router = RemoteRouter.new(match, persistence, nil, shop)
		router:Bind()

		local purchase = Remotes.Get("PurchaseShopItem")
		local results = Remotes.Get("ShopResult")
		local before = #rawget(results, "_fired")
		purchase.OnServerEvent:Fire(player, "Vitality")
		expect(persistence:GetMetaLevels(player).Vitality).toBe(1)
		local reply = rawget(results, "_fired")[before + 1]
		expect(reply.player).toBe(player)
		expect(reply.args[1].Ok).toBe(true)

		-- A flood is cut off by the per-player bucket, whatever the balance allows.
		for _ = 1, 20 do
			purchase.OnServerEvent:Fire(player, "Velocity")
		end
		expect(persistence:GetMetaLevels(player).Velocity).toBeLessThan(10)

		router:Destroy()
		Harness.removePlayer(player)
	end)
end)

describe("ShopView", function()
	local ShopView = __require("ShopView")

	local function rowButton(view, itemId)
		return view.panel:FindFirstChild("Items"):FindFirstChild(itemId):FindFirstChild("Action")
	end

	it("prices the next level, marks a maxed item and offers equip for an owned trail", function()
		local view = ShopView.new(Instance.new("Folder"), function() end, function() end)
		local stride = ShopConfig.Get("Stride")
		view:SetProfile({
			Salvage = 500,
			MetaUpgrades = { Vitality = 1, Stride = ShopConfig.MaxLevel(stride), TrailEmber = 1 },
			EquippedTrail = "",
		})
		expect(rowButton(view, "Vitality").Text).toBe("Buy  " .. ShopConfig.CostFor(ShopConfig.Get("Vitality"), 2))
		expect(rowButton(view, "Stride").Text).toBe("Maxed")
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
		rowButton(view, "Velocity").Activated:Fire()
		rowButton(view, "TrailEmber").Activated:Fire()
		expect(bought[1]).toBe("Velocity")
		expect(equipped[1]).toBe("") -- tapping the equipped trail takes it off
		expect(view.balanceLabel.Text).toBe("1000 coins")
	end)
end)

describe("Armory and Cosmetics catalogue", function()
	it("sorts every item into the Armory or Cosmetics", function()
		for _, item in ShopConfig.Items do
			local expected = item.Kind == "Trail" and "Cosmetics" or "Armory"
			expect(item.Category).toBe(expected)
		end
	end)

	it("sells Mending, Coin Magnet and Fortune in the Armory", function()
		expect(ShopConfig.Get("Mending").Effect.Stat).toBe("RegenBonus")
		expect(ShopConfig.Get("CoinMagnet").Effect.Stat).toBe("MagnetBonus")
		expect(ShopConfig.Get("Fortune").Effect.Stat).toBe("RewardMultiplier")
		local bonuses = ShopConfig.ComputeBonuses({ Mending = 2, CoinMagnet = 1, Fortune = 3 })
		expect(bonuses.RegenBonus).toBeCloseTo(2 * ShopConfig.Get("Mending").Effect.PerLevel)
		expect(bonuses.MagnetBonus).toBeCloseTo(ShopConfig.Get("CoinMagnet").Effect.PerLevel)
		expect(bonuses.RewardMultiplier).toBeCloseTo(3 * ShopConfig.Get("Fortune").Effect.PerLevel)
	end)

	it("adds Frost, Toxic and a VIP-only Gold trail to the Cosmetics", function()
		for _, id in { "TrailFrost", "TrailToxic", "TrailGold" } do
			expect(ShopConfig.Get(id).Kind).toBe("Trail")
		end
		expect(ShopConfig.Get("TrailGold").RequiresPass).toBe("VIP")
	end)

	it("refuses the Gold trail without VIP, and sells it with VIP", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = funded(persistence, subject(7701), 5000)
		local vip = false
		local shop = newShop(persistence, {
			ownsPass = function(_, pass)
				return pass == "VIP" and vip
			end,
		})
		local ok, reason = shop:Purchase(player, "TrailGold", 0)
		expect(ok).toBe(false)
		expect(reason).toBe("requires VIP")
		vip = true
		ok = shop:Purchase(player, "TrailGold", 0)
		expect(ok).toBe(true)
	end)
end)

describe("ShopView tabs", function()
	local ShopView = __require("ShopView")

	it("shows only the open tab's items", function()
		local view = ShopView.new(Instance.new("Folder"), function() end, function() end)
		view:SetTab("Armory")
		local items = view.panel:FindFirstChild("Items")
		expect(items:FindFirstChild("Vitality").Visible).toBe(true)
		expect(items:FindFirstChild("TrailEmber").Visible).toBe(false)
		view:SetTab("Cosmetics")
		expect(items:FindFirstChild("Vitality").Visible).toBe(false)
		expect(items:FindFirstChild("TrailEmber").Visible).toBe(true)
	end)
end)
