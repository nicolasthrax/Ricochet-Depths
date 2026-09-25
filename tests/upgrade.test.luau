-- Offer generation, selection validation, stacking rules, fusion gating and run reset.
local PlayerState = __require("PlayerState")
local RunConfig = __require("RunConfig")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local function newState()
	return PlayerState.new({ Name = "Tester", UserId = 1 })
end

local function cardIds(offer)
	local ids = {}
	for _, card in offer.cards do
		table.insert(ids, card.Id)
	end
	return ids
end

local function contains(list, value)
	for _, entry in list do
		if entry == value then
			return true
		end
	end
	return false
end

describe("UpgradeConfig", function()
	it("has at least nine cards spread across categories", function()
		expect(#UpgradeConfig.Cards).toBeGreaterThanOrEqual(9)
		local categories = {}
		for _, card in UpgradeConfig.Cards do
			expect(type(card.Id)).toBe("string")
			expect(type(card.Title)).toBe("string")
			expect(type(card.Description)).toBe("string")
			expect(UpgradeConfig.Categories[card.Category]).toBeTruthy()
			expect(UpgradeConfig.Rarities[card.Rarity]).toBeTruthy()
			expect(card.MaxStacks).toBeGreaterThan(0)
			expect(#card.Effects).toBeGreaterThan(0)
			categories[card.Category] = true
		end
		local count = 0
		for _ in categories do
			count += 1
		end
		expect(count).toBeGreaterThanOrEqual(4)
	end)

	it("only moves stats that exist in BaseStats", function()
		for _, card in UpgradeConfig.Cards do
			for _, effect in card.Effects do
				expect(UpgradeConfig.BaseStats[effect.Stat]).never().toBeNil()
				expect(contains({ "Add", "Multiply" }, effect.Op)).toBe(true)
			end
		end
	end)

	it("exposes exactly one unlimited-stack fallback card per pool", function()
		local fallbacks = {}
		for _, card in UpgradeConfig.Cards do
			if card.IsFallback then
				local pool = card.Pool or "Main"
				fallbacks[pool] = (fallbacks[pool] or 0) + 1
				expect(card.MaxStacks).toBe(UpgradeConfig.UnlimitedStacks)
				expect(card.Requires).toBeNil()
			end
		end
		expect(fallbacks.Main).toBe(1)
		expect(fallbacks.Minor).toBe(1)
	end)
end)

describe("offer generation", function()
	it("offers exactly three distinct cards to a fresh player", function()
		local service = UpgradeService.new(1234)
		local offer = service:BuildOffer("p1", newState(), 0)
		expect(#offer.cards).toBe(UpgradeConfig.OffersPerEvent)
		local seen = {}
		for _, card in offer.cards do
			expect(seen[card.Id]).toBeNil()
			seen[card.Id] = true
		end
	end)

	it("never offers a card the player has maxed out", function()
		local service = UpgradeService.new(99)
		local state = newState()
		local card = UpgradeConfig.Get("SplitShot")
		for _ = 1, card.MaxStacks do
			state:AddUpgrade(card)
		end
		for _ = 1, 60 do
			expect(contains(cardIds(service:BuildOffer("p1", state, 0)), "SplitShot")).toBe(false)
		end
	end)

	it("gates fusion cards behind their prerequisite stacks", function()
		local state = newState()
		expect(UpgradeService.IsEligible(UpgradeConfig.Get("Fusillade"), state)).toBe(false)

		state:AddUpgrade(UpgradeConfig.Get("SplitShot"))
		expect(UpgradeService.IsEligible(UpgradeConfig.Get("Fusillade"), state)).toBe(false)

		state:AddUpgrade(UpgradeConfig.Get("SplitShot"))
		expect(UpgradeService.IsEligible(UpgradeConfig.Get("Fusillade"), state)).toBe(true)
	end)

	it("gates stat-conditional cards until the stat qualifies", function()
		local state = newState()
		expect(UpgradeService.IsEligible(UpgradeConfig.Get("TightGroup"), state)).toBe(false)
		state:AddUpgrade(UpgradeConfig.Get("SplitShot"))
		expect(UpgradeService.IsEligible(UpgradeConfig.Get("TightGroup"), state)).toBe(true)
	end)

	it("still produces an offer when almost everything is exhausted", function()
		local service = UpgradeService.new(5)
		local state = newState()
		for _, card in UpgradeConfig.Cards do
			if not card.IsFallback then
				for _ = 1, card.MaxStacks do
					state:AddUpgrade(card)
				end
			end
		end
		local offer = service:BuildOffer("p1", state, 0)
		expect(#offer.cards).toBeGreaterThanOrEqual(1)
		for _, card in offer.cards do
			expect(UpgradeService.IsEligible(card, state)).toBe(true)
		end
	end)

	it("is reproducible for a given seed", function()
		local first = table.concat(cardIds(UpgradeService.new(4242):BuildOffer("p1", newState(), 0)), ",")
		local second = table.concat(cardIds(UpgradeService.new(4242):BuildOffer("p1", newState(), 0)), ",")
		expect(first).toBe(second)
	end)
end)

describe("selection validation", function()
	local function setup()
		local service = UpgradeService.new(11)
		local state = newState()
		local offer = service:BuildOffer("p1", state, 0)
		return service, state, offer
	end

	it("applies a valid choice exactly once", function()
		local service, state, offer = setup()
		local chosen = service:Choose("p1", state, offer.id, offer.cards[1].Id)
		expect(chosen.Id).toBe(offer.cards[1].Id)
		expect(state:GetStacks(chosen.Id)).toBe(1)

		local repeated, reason = service:Choose("p1", state, offer.id, offer.cards[1].Id)
		expect(repeated).toBeNil()
		expect(reason).toBe("no pending offer")
		expect(state:GetStacks(chosen.Id)).toBe(1)
	end)

	it("rejects a card that was not in the offer", function()
		local service, state, offer = setup()
		local absent
		for _, card in UpgradeConfig.Cards do
			if not contains(cardIds(offer), card.Id) then
				absent = card.Id
				break
			end
		end
		local chosen, reason = service:Choose("p1", state, offer.id, absent)
		expect(chosen).toBeNil()
		expect(reason).toBe("card was not offered")
		expect(state:GetStacks(absent)).toBe(0)
	end)

	it("rejects stale offer ids and malformed payloads", function()
		local service, state, offer = setup()
		local cases = {
			{ offerId = offer.id + 1, cardId = offer.cards[1].Id, reason = "stale offer" },
			{ offerId = "1", cardId = offer.cards[1].Id, reason = "stale offer" },
			{ offerId = offer.id, cardId = 12345, reason = "invalid card id" },
			{ offerId = offer.id, cardId = "NotARealCard", reason = "card was not offered" },
		}
		for _, case in cases do
			local chosen, reason = service:Choose("p1", state, case.offerId, case.cardId)
			expect(chosen).toBeNil()
			expect(reason).toBe(case.reason)
		end
		expect(#state.upgradeOrder).toBe(0)
	end)

	it("rejects a choice from a player with no pending offer", function()
		local service = UpgradeService.new(3)
		local chosen, reason = service:Choose("ghost", newState(), 1, "SharpEdge")
		expect(chosen).toBeNil()
		expect(reason).toBe("no pending offer")
	end)

	it("auto-picks the recommended card when the timer runs out", function()
		local service = UpgradeService.new(21)
		local state = newState()
		local offer = service:BuildOffer("p1", state, 100)
		local expected = offer.recommended
		expect(expected).toBeTruthy()

		expect(#service:ResolveExpired(100 + UpgradeConfig.ChoiceTimeout - 0.1, function()
			return state
		end)).toBe(0)

		local resolved = service:ResolveExpired(100 + UpgradeConfig.ChoiceTimeout, function()
			return state
		end)
		expect(#resolved).toBe(1)
		expect(resolved[1].auto).toBe(true)
		expect(state:GetStacks(expected)).toBe(1)
		expect(service:HasPendingOffers()).toBe(false)
	end)

	it("drops offers for a player who leaves", function()
		local service, state, offer = setup()
		service:Clear("p1")
		local chosen, reason = service:Choose("p1", state, offer.id, offer.cards[1].Id)
		expect(chosen).toBeNil()
		expect(reason).toBe("no pending offer")
	end)
end)

describe("stat stacking", function()
	it("adds linearly and multiplies compounding", function()
		local state = newState()
		state:AddUpgrade(UpgradeConfig.Get("SharpEdge"))
		state:AddUpgrade(UpgradeConfig.Get("SharpEdge"))
		expect(state.stats.Damage).toBe(UpgradeConfig.BaseStats.Damage + 2)

		state:AddUpgrade(UpgradeConfig.Get("RapidCycle"))
		state:AddUpgrade(UpgradeConfig.Get("RapidCycle"))
		expect(state.stats.FireCooldownMultiplier).toBeCloseTo(0.8 * 0.8, 1e-9)
	end)

	it("refuses to exceed a card's stack cap", function()
		local state = newState()
		local card = UpgradeConfig.Get("SplitShot")
		for _ = 1, card.MaxStacks do
			expect((state:AddUpgrade(card))).toBe(true)
		end
		local ok, reason = state:AddUpgrade(card)
		expect(ok).toBe(false)
		expect(reason).toBe("stack cap reached")
		expect(state:GetStacks(card.Id)).toBe(card.MaxStacks)
	end)

	it("raises maximum health and heals the difference", function()
		local state = newState()
		state.health = state.maxHealth - 10
		local before = state.maxHealth
		state:AddUpgrade(UpgradeConfig.Get("Plating"))
		expect(state.maxHealth).toBe(before + 25)
		expect(state.health).toBe(before - 10 + 25)
	end)

	it("rejects malformed cards", function()
		local state = newState()
		expect((state:AddUpgrade(nil))).toBe(false)
		expect((state:AddUpgrade("SharpEdge"))).toBe(false)
		expect((state:AddUpgrade({}))).toBe(false)
	end)
end)

describe("run reset", function()
	it("clears every upgrade and restores base stats", function()
		local state = newState()
		state:AddUpgrade(UpgradeConfig.Get("SplitShot"))
		state:AddUpgrade(UpgradeConfig.Get("Plating"))
		state.kills = 9
		state:ApplyDamage(30, 100)
		expect(state.health).toBeLessThan(state.maxHealth)

		state:ResetRun()
		expect(state:GetStacks("SplitShot")).toBe(0)
		expect(#state.upgradeOrder).toBe(0)
		expect(state.kills).toBe(0)
		expect(state.maxHealth).toBe(RunConfig.BaseHealth)
		expect(state.health).toBe(RunConfig.BaseHealth)
		expect(state.stats).toEqual(UpgradeConfig.BaseStats)
	end)
end)

describe("player health", function()
	it("ignores damage while invulnerable", function()
		local state = newState()
		state:GrantInvulnerability(0, 2)
		expect((state:ApplyDamage(50, 1))).toBe(0)
		expect(state.health).toBe(state.maxHealth)
		local applied = state:ApplyDamage(50, 3)
		expect(applied).toBe(50)
	end)

	it("reports the fatal blow and stops taking damage afterwards", function()
		local state = newState()
		local _, fatal = state:ApplyDamage(RunConfig.BaseHealth, 10)
		expect(fatal).toBe(true)
		expect(state.alive).toBe(false)
		expect(state.health).toBe(0)
		expect((state:ApplyDamage(10, 11))).toBe(0)
		expect((state:Heal(10))).toBe(0)
	end)

	it("never heals past the maximum", function()
		local state = newState()
		state:ApplyDamage(10, 5)
		expect((state:Heal(999))).toBe(10)
		expect(state.health).toBe(state.maxHealth)
	end)
end)
