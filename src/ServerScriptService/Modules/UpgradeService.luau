-- Card offers and selection. Offers are generated, tracked and applied entirely server-side;
-- the client only ever sends back an offer id and a card id, both of which are re-validated.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))

local UpgradeService = {}
UpgradeService.__index = UpgradeService

function UpgradeService.new(seed)
	return setmetatable({
		_random = Random.new(seed or 1),
		_offers = {},
		_nextOfferId = 0,
	}, UpgradeService)
end

local function meetsRequirements(card, playerState)
	local requires = card.Requires
	if not requires then
		return true
	end
	if requires.Cards then
		for requiredId, needed in requires.Cards do
			if playerState:GetStacks(requiredId) < needed then
				return false
			end
		end
	end
	if requires.Stats then
		for stat, needed in requires.Stats do
			if (playerState.stats[stat] or 0) < needed then
				return false
			end
		end
	end
	return true
end

function UpgradeService.IsEligible(card, playerState)
	if playerState:GetStacks(card.Id) >= card.MaxStacks then
		return false
	end
	return meetsRequirements(card, playerState)
end

function UpgradeService:GetEligibleCards(playerState)
	local eligible = {}
	for _, card in UpgradeConfig.Cards do
		if UpgradeService.IsEligible(card, playerState) then
			table.insert(eligible, card)
		end
	end
	return eligible
end

function UpgradeService:_pickWeighted(candidates)
	local total = 0
	for _, card in candidates do
		total += UpgradeConfig.WeightOf(card)
	end
	if total <= 0 then
		return 1
	end

	local roll = self._random:NextNumber() * total
	for index, card in candidates do
		roll -= UpgradeConfig.WeightOf(card)
		if roll <= 0 then
			return index
		end
	end
	return #candidates
end

-- Builds an offer of up to OffersPerEvent distinct cards, weighted by rarity and drawn without
-- replacement. The unlimited-stack fallback card guarantees the pool is never empty.
function UpgradeService:BuildOffer(playerKey, playerState, now)
	local candidates = self:GetEligibleCards(playerState)
	local cards = {}
	for _ = 1, UpgradeConfig.OffersPerEvent do
		if #candidates == 0 then
			break
		end
		table.insert(cards, table.remove(candidates, self:_pickWeighted(candidates)))
	end

	if #cards == 0 then
		-- Deterministic last resort: the fallback card is always takeable.
		for _, card in UpgradeConfig.Cards do
			if card.IsFallback then
				table.insert(cards, card)
				break
			end
		end
	end

	self._nextOfferId += 1
	local offer = {
		id = self._nextOfferId,
		cards = cards,
		expiresAt = now + UpgradeConfig.ChoiceTimeout,
		resolved = false,
		playerKey = playerKey,
	}
	self._offers[playerKey] = offer
	return offer
end

function UpgradeService:GetOffer(playerKey)
	return self._offers[playerKey]
end

-- Card payload for the client. Only display data crosses the wire.
function UpgradeService.ToClientPayload(offer, now)
	local cards = {}
	for _, card in offer.cards do
		table.insert(cards, {
			Id = card.Id,
			Title = card.Title,
			Description = card.Description,
			Category = card.Category,
			Rarity = card.Rarity,
		})
	end
	-- A duration, never a timestamp. os.clock() is per-process, so a server clock value is
	-- meaningless on a client; the client counts down from this against its own clock.
	local secondsRemaining = now and math.max(offer.expiresAt - now, 0) or UpgradeConfig.ChoiceTimeout
	return { OfferId = offer.id, Cards = cards, SecondsRemaining = secondsRemaining }
end

-- Validates and applies a selection. Every rejection path returns a reason and changes nothing.
function UpgradeService:Choose(playerKey, playerState, offerId, cardId)
	local offer = self._offers[playerKey]
	if not offer then
		return nil, "no pending offer"
	end
	if offer.resolved then
		return nil, "offer already resolved"
	end
	if type(offerId) ~= "number" or offerId ~= offer.id then
		return nil, "stale offer"
	end
	if type(cardId) ~= "string" then
		return nil, "invalid card id"
	end

	local chosen
	for _, card in offer.cards do
		if card.Id == cardId then
			chosen = card
			break
		end
	end
	if not chosen then
		return nil, "card was not offered"
	end

	local applied, reason = playerState:AddUpgrade(chosen)
	if not applied then
		return nil, reason
	end

	offer.resolved = true
	self._offers[playerKey] = nil
	return chosen
end

-- Auto-picks the first card of any offer whose timer ran out, so a run never stalls.
function UpgradeService:ResolveExpired(now, stateResolver)
	local resolved = {}
	for playerKey, offer in self._offers do
		if now >= offer.expiresAt and not offer.resolved then
			local playerState = stateResolver and stateResolver(playerKey)
			local card = offer.cards[1]
			if playerState and card then
				local applied = playerState:AddUpgrade(card)
				if applied then
					table.insert(resolved, { playerKey = playerKey, card = card, auto = true })
				end
			end
			offer.resolved = true
			self._offers[playerKey] = nil
		end
	end
	return resolved
end

function UpgradeService:HasPendingOffers()
	return next(self._offers) ~= nil
end

function UpgradeService:Clear(playerKey)
	self._offers[playerKey] = nil
end

function UpgradeService:ClearAll()
	table.clear(self._offers)
end

return UpgradeService
