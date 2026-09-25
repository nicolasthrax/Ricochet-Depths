-- Robux purchases, the concept's launch economy: two passes (Explorer, Supporter) that grant
-- convenience and cosmetics, and two products (a Revive, a Reroll bundle) granted as consumable
-- tokens. Receipts are granted exactly once, only once saved; nothing with id 0 is offered; and
-- nothing sold changes a run's power.
local MonetizationConfig = __require("MonetizationConfig")
local MonetizationService = __require("MonetizationService")
local PlayerDataService = __require("PlayerDataService")

local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet

-- A MarketplaceService stand-in: which user owns which pass.
local function fakeMarketplace(owned)
	local market = { owned = owned or {}, calls = 0 }
	function market:UserOwnsGamePassAsync(userId, passId)
		self.calls += 1
		if self.fail then
			error("marketplace unavailable")
		end
		return self.owned[userId .. ":" .. passId] == true
	end
	return market
end

-- A config with real-looking ids, so the tests do not depend on what ships.
local function testConfig()
	return {
		Passes = {
			ExplorerPass = { Id = 111, Title = "Explorer Pass", PresetSlots = 1 },
			SupporterPack = { Id = 222, Title = "Supporter Pack", PresetSlots = 2, ExtraCapHours = 2, ChatTag = "Supporter" },
			Unset = { Id = 0, Title = "Not configured", PresetSlots = 9 },
		},
		Products = {
			{ Key = "Revive", Id = 301, Kind = "Revive", Title = "Revive", Extras = { ReviveTokens = 1 } },
			{ Key = "RerollBundle", Id = 501, Kind = "Grant", Title = "5 Rerolls", Extras = { Rerolls = 5 } },
			{ Key = "Unset", Id = 0, Kind = "Grant", Title = "Not configured", Extras = { Rerolls = 999 } },
		},
		Ads = { RewardProductId = 901, MaxPerDay = 3, Coins = 40, Rerolls = 0 },
	}
end

local function setup(owned)
	local store = __FakeDataStore.new()
	local persistence = PlayerDataService.new(store)
	local player = { Name = "Buyer", UserId = 8801 }
	persistence:Load(player)
	local players = { [player.UserId] = player }
	local changed = 0
	local service = MonetizationService.new({
		marketplace = fakeMarketplace(owned),
		persistence = persistence,
		config = testConfig(),
		getPlayer = function(userId)
			return players[userId]
		end,
		onChanged = function()
			changed += 1
		end,
	})
	return service, persistence, player, store, function()
		return changed
	end
end

local function receipt(purchaseId, productId, userId)
	return { PurchaseId = purchaseId, ProductId = productId, PlayerId = userId or 8801 }
end

describe("products", function()
	it("grants a reroll bundle once and saves it before confirming", function()
		local service, persistence, player, store = setup()
		expect(service:ProcessReceipt(receipt("r1", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player, "Rerolls")).toBe(5)
		expect(store:Peek("profile_8801").Currency.Rerolls).toBe(5)
		-- Roblox may deliver the same receipt again: it must not pay twice.
		expect(service:ProcessReceipt(receipt("r1", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player, "Rerolls")).toBe(5)
		expect(service:ProcessReceipt(receipt("r2", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player, "Rerolls")).toBe(10)
		expect(persistence:GetBalance(player)).toBe(0) -- never coins
	end)

	it("turns a Revive into a token and tries to spend it at once", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = { Name = "Downed", UserId = 8803 }
		persistence:Load(player)
		local revived = {}
		local service = MonetizationService.new({
			marketplace = fakeMarketplace(),
			persistence = persistence,
			config = testConfig(),
			getPlayer = function()
				return player
			end,
			onRevive = function(who)
				table.insert(revived, who)
			end,
		})
		expect(service:ProcessReceipt(receipt("rv", 301, 8803), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player, "ReviveTokens")).toBe(1)
		expect(revived[1]).toBe(player)
		-- A repeat delivery neither pays nor revives again.
		expect(service:ProcessReceipt(receipt("rv", 301, 8803), 0)).toBe(GRANTED)
		expect(#revived).toBe(1)
	end)

	it("waits when the buyer is not here or their profile has not loaded", function()
		local service = setup()
		expect(service:ProcessReceipt(receipt("r3", 501, 424242), 0)).toBe(NOT_YET)
		local store = __FakeDataStore.new()
		local unloaded = MonetizationService.new({
			marketplace = fakeMarketplace(),
			persistence = PlayerDataService.new(store),
			config = testConfig(),
			getPlayer = function()
				return { Name = "Late", UserId = 8802 }
			end,
		})
		expect(unloaded:ProcessReceipt(receipt("r4", 501, 8802), 0)).toBe(NOT_YET)
	end)

	it("never grants an unknown or unconfigured product", function()
		local service, persistence, player = setup()
		expect(service:ProcessReceipt(receipt("r5", 999), 0)).toBe(NOT_YET)
		expect(service:ProcessReceipt(receipt("r6", 0), 0)).toBe(NOT_YET)
		expect(persistence:GetBalance(player, "Rerolls")).toBe(0)
	end)

	it("waits and retries when the save fails, without paying twice", function()
		local service, persistence, player, store = setup()
		store.failing = true
		expect(service:ProcessReceipt(receipt("r7", 501), 0)).toBe(NOT_YET)
		store.failing = false
		expect(service:ProcessReceipt(receipt("r7", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player, "Rerolls")).toBe(5)
	end)

	it("acknowledges the rewarded-video product without paying for it again", function()
		local service, persistence, player = setup()
		expect(service:ProcessReceipt(receipt("ad1", 901), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player)).toBe(0)
	end)

	it("keeps the paid Revive out of the Store while it is switched off", function()
		local store = __FakeDataStore.new()
		local service = MonetizationService.new({
			marketplace = fakeMarketplace(),
			persistence = PlayerDataService.new(store),
			config = testConfig(),
			getPlayer = function() end,
			productEnabled = function(product)
				return product.Kind ~= "Revive"
			end,
		})
		local keys = {}
		for _, product in service:Catalogue().Products do
			keys[product.Key] = true
		end
		expect(keys.Revive).toBeNil()
		expect(keys.RerollBundle).toBe(true)
	end)
end)

describe("game passes", function()
	it("reads ownership once per pass and turns it into entitlements, never run power", function()
		local service, _, player = setup({ ["8801:222"] = true })
		service:RefreshOwnership(player)
		expect(service:OwnsPass(player, "SupporterPack")).toBe(true)
		expect(service:OwnsPass(player, "ExplorerPass")).toBe(false)
		expect(service:GetExtraCapHours(player)).toBe(2)
		expect(service:GetPresetSlots(player)).toBe(2)
		expect(service:GetPerk(player, "ChatTag")).toBe("Supporter")
		expect(service.GetRunBonuses).toBeNil()

		service:MarkOwned(player, "ExplorerPass")
		expect(service:GetPresetSlots(player)).toBe(3)
	end)

	it("treats a marketplace outage as not owned rather than failing the join", function()
		local service, _, player = setup()
		service._marketplace.fail = true
		service:RefreshOwnership(player)
		expect(service:OwnsPass(player, "SupporterPack")).toBe(false)
		expect(service:GetPresetSlots(player)).toBe(0)
	end)

	it("never checks or offers a pass or product whose id is 0", function()
		local service, _, player = setup()
		service:RefreshOwnership(player)
		expect(service._marketplace.calls).toBe(2)
		local offered = service:Catalogue()
		for _, entry in offered.Passes do
			expect(entry.Id).never().toBe(0)
		end
		for _, entry in offered.Products do
			expect(entry.Id).never().toBe(0)
		end
	end)
end)

describe("the launch catalogue", function()
	it("ships every id as 0 until the owner fills them in, so nothing is sold by accident", function()
		for _, pass in MonetizationConfig.Passes do
			expect(pass.Id).toBe(0)
		end
		for _, product in MonetizationConfig.Products do
			expect(product.Id).toBe(0)
		end
		expect(MonetizationConfig.Ads.RewardProductId).toBe(0)
	end)

	it("sells no coins, no coin multiplier and no stats: the concept's no-paid-power rule", function()
		for _, pass in MonetizationConfig.Passes do
			expect(pass.CoinBonus).toBeNil()
			expect(pass.Coins).toBeNil()
			expect(pass.Stats).toBeNil()
		end
		for _, product in MonetizationConfig.Products do
			expect(product.Coins).toBeNil()
			for currencyId in product.Extras do
				expect(currencyId).never().toBe("Salvage")
			end
		end
	end)

	it("prices the passes and products inside the concept's ranges", function()
		local explorer, supporter = MonetizationConfig.Passes.ExplorerPass, MonetizationConfig.Passes.SupporterPack
		expect(explorer.Price >= 99 and explorer.Price <= 149).toBe(true)
		expect(supporter.Price >= 299 and supporter.Price <= 399).toBe(true)
		expect(explorer.PresetSlots).toBe(1)
		expect(supporter.PresetSlots).toBe(2)
		expect(supporter.ExtraCapHours).toBe(2)
		local byKey = {}
		for _, product in MonetizationConfig.Products do
			byKey[product.Key] = product
		end
		expect(byKey.Revive.Price).toBe(29)
		expect(byKey.RerollBundle.Extras.Rerolls).toBe(5)
		expect(byKey.RerollBundle.Price >= 49 and byKey.RerollBundle.Price <= 79).toBe(true)
		expect(byKey.Coins500).toBeNil()
	end)

	it("keeps the paid Revive and rewarded video off until they are checked in Studio", function()
		local FeatureFlags = __require("FeatureFlags")
		expect(FeatureFlags.PaidRevive).toBe(false)
		expect(FeatureFlags.RewardedVideo).toBe(false)
	end)
end)
