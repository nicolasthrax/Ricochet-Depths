-- Robux purchases: game passes (2x Coins, VIP) and coin packs. Receipts are granted exactly once,
-- only once the coins are saved, and nothing configured with id 0 is ever offered.
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
			DoubleCoins = { Id = 111, Title = "2x Coins", CoinBonus = 1 },
			VIP = { Id = 222, Title = "VIP", CoinBonus = 0.1 },
			Unset = { Id = 0, Title = "Not configured", CoinBonus = 5 },
		},
		Products = {
			{ Key = "Coins500", Id = 501, Coins = 500, Title = "500 Coins" },
			{ Key = "Unset", Id = 0, Coins = 99999, Title = "Not configured" },
		},
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

describe("coin packs", function()
	it("grants the coins once and saves them before confirming", function()
		local service, persistence, player, store = setup()
		expect(service:ProcessReceipt(receipt("r1", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player)).toBe(500)
		expect(store:Peek("profile_8801").Currency.Salvage).toBe(500)
		-- Roblox may deliver the same receipt again: it must not pay twice.
		expect(service:ProcessReceipt(receipt("r1", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player)).toBe(500)
		expect(service:ProcessReceipt(receipt("r2", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player)).toBe(1000)
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
		expect(persistence:GetBalance(player)).toBe(0)
	end)

	it("waits and retries when the save fails, without paying twice", function()
		local service, persistence, player, store = setup()
		store.failing = true
		expect(service:ProcessReceipt(receipt("r7", 501), 0)).toBe(NOT_YET)
		store.failing = false
		expect(service:ProcessReceipt(receipt("r7", 501), 0)).toBe(GRANTED)
		expect(persistence:GetBalance(player)).toBe(500)
	end)
end)

describe("game passes", function()
	it("reads ownership once per pass and turns it into run bonuses", function()
		local service, _, player = setup({ ["8801:111"] = true })
		service:RefreshOwnership(player)
		expect(service:OwnsPass(player, "DoubleCoins")).toBe(true)
		expect(service:OwnsPass(player, "VIP")).toBe(false)
		expect(service:GetRunBonuses(player).CoinMultiplier).toBe(1)

		service:MarkOwned(player, "VIP")
		expect(service:GetRunBonuses(player).CoinMultiplier).toBeCloseTo(1.1)
	end)

	it("treats a marketplace outage as not owned rather than failing the join", function()
		local service, _, player = setup()
		service._marketplace.fail = true
		service:RefreshOwnership(player)
		expect(service:OwnsPass(player, "DoubleCoins")).toBe(false)
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

	it("ships every id as 0 until the owner fills them in, so nothing is sold by accident", function()
		for _, pass in MonetizationConfig.Passes do
			expect(type(pass.Id)).toBe("number")
		end
		for _, product in MonetizationConfig.Products do
			expect(product.Coins).toBeGreaterThan(0)
		end
	end)
end)
