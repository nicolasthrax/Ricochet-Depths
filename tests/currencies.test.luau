-- Schema v9: consumable balances (Rerolls, ReviveTokens) travel through the same grant and spend
-- paths as coins, and the v8 -> v9 migration refunds the retired Armory in coins exactly once.
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")
local Payout = __require("Payout")

local function player(userId)
	return { Name = "C" .. userId, UserId = userId }
end

local function stored(store, subject)
	return store:Peek(PlayerDataConfig.KeyPrefix .. tostring(subject.UserId))
end

describe("consumable grants", function()
	it("adds rerolls and revive tokens with the grant, and persists them on save", function()
		local store = __FakeDataStore.new()
		local service = PlayerDataService.new(store)
		local subject = player(1)
		service:Load(subject)

		local coins, reason = service:GrantReward(subject, "receipt:1", 0, 0, { Rerolls = 5 })
		expect(reason).toBeNil()
		expect(coins).toBe(0)
		expect(service:GetBalance(subject, "Rerolls")).toBe(5)
		expect((service:Save(subject, 1))).toBe(true)
		expect(stored(store, subject).Currency.Rerolls).toBe(5)
		expect(stored(store, subject).Currency.Salvage).toBe(0)
	end)

	it("pays a consumable grant once however often its key is replayed", function()
		local store = __FakeDataStore.new()
		local service = PlayerDataService.new(store)
		local subject = player(2)
		service:Load(subject)
		service:GrantReward(subject, "k", 10, 0, { ReviveTokens = 1 })
		local _, reason = service:GrantReward(subject, "k", 10, 0, { ReviveTokens = 1 })
		expect(reason).toBe("already granted")
		service:Save(subject, 1)
		expect(stored(store, subject).Currency.ReviveTokens).toBe(1)
		expect(stored(store, subject).Currency.Salvage).toBe(10)
	end)

	it("refuses unknown currencies, coins passed as an extra, and negative amounts", function()
		local service = PlayerDataService.new(__FakeDataStore.new())
		local subject = player(3)
		service:Load(subject)
		expect(select(2, service:GrantReward(subject, "a", 0, 0, { Gems = 3 }))).toBe("invalid amount")
		expect(select(2, service:GrantReward(subject, "b", 0, 0, { Salvage = 3 }))).toBe("invalid amount")
		expect(select(2, service:GrantReward(subject, "c", 0, 0, { Rerolls = -1 }))).toBe("invalid amount")
		expect(select(2, service:GrantReward(subject, "d", 0, 0, {}))).toBe("invalid amount")
		expect(service:GetBalance(subject, "Rerolls")).toBe(0)
	end)

	it("carries extras through Payout.Grant", function()
		local service = PlayerDataService.new(__FakeDataStore.new())
		local subject = player(4)
		service:Load(subject)
		local _, _, _, _, _, reason = Payout.Grant(service, subject, "quest:x", 0, 0, { Rerolls = 2 })
		expect(reason).toBeNil()
		expect(service:GetBalance(subject, "Rerolls")).toBe(2)
	end)
end)

describe("consumable spends", function()
	it("spends a reroll as the next level of a use counter, paid in rerolls", function()
		local store = __FakeDataStore.new()
		local service = PlayerDataService.new(store)
		local subject = player(10)
		service:Load(subject)
		service:GrantReward(subject, "seed", 50, 0, { Rerolls = 2 })
		service:Save(subject, 1)

		local left = service:SpendOnUpgrade(subject, "RerollUse", 1, 1, "Rerolls")
		expect(left).toBe(1)
		expect(service:GetBalance(subject)).toBe(50) -- coins untouched
		service:Save(subject, 2)
		expect(stored(store, subject).Currency.Rerolls).toBe(1)
		expect(stored(store, subject).MetaUpgrades.RerollUse).toBe(1)
		expect(stored(store, subject).Currency.Salvage).toBe(50)
	end)

	it("refuses a spend the balance cannot cover, naming the currency", function()
		local service = PlayerDataService.new(__FakeDataStore.new())
		local subject = player(11)
		service:Load(subject)
		local left, reason = service:SpendOnUpgrade(subject, "RerollUse", 1, 1, "Rerolls")
		expect(left).toBeNil()
		expect(reason).toBe("insufficient rerolls")
		expect(select(2, service:SpendOnUpgrade(subject, "X", 1, 1, "Gems"))).toBe("invalid currency")
	end)

	it("rejects at commit time a consumable another server already spent", function()
		local store = __FakeDataStore.new()
		local subject = player(12)
		local first = PlayerDataService.new(store)
		first:Load(subject)
		first:GrantReward(subject, "seed", 0, 0, { Rerolls = 1 })
		first:Save(subject, 1)

		-- A second server, holding the same profile, spends the only reroll first.
		local second = PlayerDataService.new(store)
		local other = player(12)
		second:Load(other)
		expect(second:SpendOnUpgrade(other, "RerollUse", 1, 1, "Rerolls")).toBe(0)
		second:Save(other, 2)

		expect(first:SpendOnUpgrade(subject, "RerollUse", 1, 1, "Rerolls")).toBe(0)
		first:Save(subject, 3)
		-- The stored level already reached 1, so this server's spend is acknowledged, not charged.
		expect(stored(store, subject).Currency.Rerolls).toBe(0)
		expect(first:GetBalance(subject, "Rerolls")).toBe(0)
	end)
end)

describe("schema v9 migration", function()
	it("refunds every coin spent in the Armory and removes its levels", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 8,
			Currency = { Salvage = 100 },
			MetaUpgrades = { Vitality = 2, Fortune = 1, TrailEmber = 1 },
			Flags = { OnboardingSeen = true },
		})
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Currency.Salvage).toBe(100 + 80 + 160 + 250)
		expect(profile.MetaUpgrades.Vitality).toBeNil()
		expect(profile.MetaUpgrades.Fortune).toBeNil()
		expect(profile.MetaUpgrades.TrailEmber).toBe(1) -- cosmetics are kept
		expect(profile.Currency.Rerolls).toBe(0)
		expect(profile.Flags.FirstDescentDone).toBe(true)
		expect(type(profile.Base.Layout)).toBe("table")
	end)

	it("clamps a tampered Armory level to what was ever sold", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 8,
			Currency = { Salvage = 0 },
			MetaUpgrades = { Stride = 99 },
		})
		expect(profile.Currency.Salvage).toBe(60 + 140 + 240)
	end)

	it("cleans up a profile the 2.x haul build saved as its own v9", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 9,
			Currency = { Salvage = 10 },
			MetaUpgrades = { Quiver = 1, Stride = 1, TrailEmber = 1 },
			DepthRank = 3,
		})
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Currency.Salvage).toBe(10 + 1500 + 60)
		expect(profile.MetaUpgrades.Quiver).toBeNil()
		expect(profile.MetaUpgrades.TrailEmber).toBe(1)
		expect(profile.DepthRank).toBeNil()
		expect(profile.Currency.Rerolls).toBe(0)
	end)

	it("leaves a profile already on this build's v9 as it was", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 9,
			Currency = { Salvage = 42, Rerolls = 3 },
			MetaUpgrades = { TrailEmber = 1 },
			Flags = { FirstDescentDone = true },
		})
		expect(profile.Currency.Salvage).toBe(42)
		expect(profile.Currency.Rerolls).toBe(3)
		expect(profile.Flags.FirstDescentDone).toBe(true)
	end)

	it("refunds exactly once: the migrated profile written back does not migrate again", function()
		local store = __FakeDataStore.new()
		local subject = player(20)
		store:UpdateAsync(PlayerDataConfig.KeyPrefix .. "20", function()
			return { SchemaVersion = 8, Currency = { Salvage = 0 }, MetaUpgrades = { Vitality = 1 } }
		end)
		local service = PlayerDataService.new(store)
		service:Load(subject)
		expect(service:GetBalance(subject)).toBe(80)
		service:Release(subject, 1)

		local again = PlayerDataService.new(store)
		again:Load(subject)
		expect(again:GetBalance(subject)).toBe(80)
	end)

	it("leaves a new player's first descent ahead of them", function()
		local profile = PlayerDataService.Normalise(nil)
		expect(profile.Flags.FirstDescentDone).toBe(false)
	end)
end)
