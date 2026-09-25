-- Card offers and selection. Offers are generated, tracked and applied entirely server-side;
-- the client only ever sends back an offer id and a card id, both of which are re-validated.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))

local UpgradeService = {}
UpgradeService.__index = UpgradeService

-- pool is nil for the between-room cards, or "Minor" for Surge perks; each service only ever
-- offers cards from its own pool.
function UpgradeService.new(seed, pool)
	return setmetatable({
		_pool = pool,
		_random = Random.new(seed or 1),
		_offers = {},
		-- The last offer each player settled this round, and the card it gave: what a respec
		-- undoes and reopens.
		_settled = {},
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
	-- Gradual unlocks: a card waits for the account level it unlocks at. A state with no known
	-- level (tests, tools) is never gated.
	if card.UnlockLevel and playerState.level and playerState.level < card.UnlockLevel then
		return false
	end
	return meetsRequirements(card, playerState)
end

-- How strongly a card is worth taking now, for the RECOMMENDED tag: a fused card first, then a
-- piece of a fusion (more so one already started), then the rarer card.
local function recommendScore(card, playerState)
	if card.Rarity == "Fused" then
		return 100
	end
	if UpgradeConfig.IsFusionPart(card.Id) then
		return playerState:GetStacks(card.Id) > 0 and 60 or 50
	end
	return card.Rarity == "Rare" and 20 or 10
end

-- The fusion a card builds toward, for the card face: { Fusion, Have, Need } counted in this
-- card's own stacks, or nil for a fused card or a card no unowned fusion needs. When a card
-- feeds several fusions it points at the one the player is furthest along (ties: declared order).
function UpgradeService.FusionHint(card, playerState)
	if card.Rarity == "Fused" or not playerState then
		return nil
	end
	local best, bestProgress = nil, -1
	for _, fused in UpgradeConfig.FusionsUsing(card.Id) do
		if playerState:GetStacks(fused.Id) < fused.MaxStacks then
			local have, need = 0, 0
			for partId, count in fused.Requires.Cards do
				have += math.min(playerState:GetStacks(partId), count)
				need += count
			end
			local progress = have / need
			if progress > bestProgress then
				best, bestProgress = fused, progress
			end
		end
	end
	if not best then
		return nil
	end
	local need = best.Requires.Cards[card.Id]
	return { Fusion = best.Title, Have = math.min(playerState:GetStacks(card.Id), need), Need = need }
end

-- The card of an offer to recommend (ties go to the earlier card).
function UpgradeService.Recommend(cards, playerState)
	local best, bestScore = nil, -1
	for _, card in cards do
		local score = recommendScore(card, playerState)
		if score > bestScore then
			best, bestScore = card, score
		end
	end
	return best
end

function UpgradeService:GetEligibleCards(playerState)
	local eligible = {}
	for _, card in UpgradeConfig.Cards do
		if card.Pool == self._pool and UpgradeService.IsEligible(card, playerState) then
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

-- Builds an offer of up to `count` (default OffersPerEvent) distinct cards, weighted by rarity
-- and drawn without replacement. The unlimited-stack fallback card guarantees the pool is never
-- empty. A fused card the player qualifies for is always among them: an evolution is the payoff
-- a build was working toward, and it should never be lost to a bad roll.
--
-- options (optional): { rare = true } makes sure at least one card is Rare or better;
-- { force = { cardId, ... } } puts those cards in first when they are eligible (the first
-- descent); { exclude = { [cardId] = true } } leaves cards out, unless that would leave nothing
-- to offer (a reroll).
function UpgradeService:BuildOffer(playerKey, playerState, now, count, options)
	local candidates = self:GetEligibleCards(playerState)
	local cards = {}
	if options and options.exclude then
		local kept = {}
		for _, card in candidates do
			if not options.exclude[card.Id] then
				table.insert(kept, card)
			end
		end
		if #kept > 0 then
			candidates = kept
		end
	end
	for _, forcedId in options and options.force or {} do
		for index, card in candidates do
			if card.Id == forcedId then
				table.insert(cards, table.remove(candidates, index))
				break
			end
		end
	end
	if options and options.rare then
		local rares = {}
		for index, card in candidates do
			if card.Rarity ~= "Common" then
				table.insert(rares, index)
			end
		end
		if #rares > 0 then
			table.insert(cards, table.remove(candidates, rares[self._random:NextInteger(1, #rares)]))
		end
	end
	-- One qualifying evolution, if there is any and none is in the offer yet.
	local hasFused = false
	for _, card in cards do
		hasFused = hasFused or card.Rarity == "Fused"
	end
	for index = #candidates, 1, -1 do
		if not hasFused and candidates[index].Rarity == "Fused" and candidates[index].Requires then
			table.insert(cards, table.remove(candidates, index))
			hasFused = true
		end
	end
	for _ = #cards + 1, count or UpgradeConfig.OffersPerEvent do
		if #candidates == 0 then
			break
		end
		table.insert(cards, table.remove(candidates, self:_pickWeighted(candidates)))
	end

	if #cards == 0 then
		-- Deterministic last resort: the fallback card is always takeable.
		for _, card in UpgradeConfig.Cards do
			if card.IsFallback and card.Pool == self._pool then
				table.insert(cards, card)
				break
			end
		end
	end

	return self:_open(playerKey, playerState, cards, now, options and options.timeout)
end

function UpgradeService:_open(playerKey, playerState, cards, now, timeout)
	self._nextOfferId += 1
	local recommended = UpgradeService.Recommend(cards, playerState)
	local hints = {}
	for _, card in cards do
		hints[card.Id] = UpgradeService.FusionHint(card, playerState)
	end
	local offer = {
		id = self._nextOfferId,
		cards = cards,
		recommended = recommended and recommended.Id or nil,
		fusionHints = hints,
		expiresAt = now + (timeout or UpgradeConfig.ChoiceTimeout),
		resolved = false,
		playerKey = playerKey,
	}
	self._offers[playerKey] = offer
	return offer
end

-- A fresh offer in place of the pending one, avoiding the cards just shown where the pool
-- allows. Returns the new offer, or nil and a reason.
function UpgradeService:Reroll(playerKey, playerState, now)
	local offer = self._offers[playerKey]
	if not offer or offer.resolved then
		return nil, "no pending offer"
	end
	local shown = {}
	for _, card in offer.cards do
		shown[card.Id] = true
	end
	return self:BuildOffer(playerKey, playerState, now, #offer.cards, { exclude = shown })
end

-- Respec: undoes the card this player settled on this round and reopens the same offer, so they
-- can pick again. Returns the reopened offer, or nil and a reason.
function UpgradeService:Reopen(playerKey, playerState, now)
	if self._offers[playerKey] then
		return nil, "still choosing"
	end
	local settled = self._settled[playerKey]
	if not settled then
		return nil, "nothing to respec"
	end
	if not playerState:RemoveUpgrade(settled.card.Id) then
		return nil, "nothing to respec"
	end
	self._settled[playerKey] = nil
	return self:_open(playerKey, playerState, settled.cards, now)
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
			Label = card.Label,
			Icon = card.Icon,
			Description = card.Description,
			Category = card.Category,
			Rarity = card.Rarity,
			Recommended = card.Id == offer.recommended or nil,
			FusionHint = offer.fusionHints and offer.fusionHints[card.Id] or nil,
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
	self._settled[playerKey] = { card = chosen, cards = offer.cards }
	return chosen
end

-- Auto-picks the recommended card (else the first) of any offer whose timer ran out, so a run
-- never stalls and an idle player still gets the card most worth having.
function UpgradeService:ResolveExpired(now, stateResolver)
	local resolved = {}
	for playerKey, offer in self._offers do
		if now >= offer.expiresAt and not offer.resolved then
			local playerState = stateResolver and stateResolver(playerKey)
			local card = offer.cards[1]
			for _, candidate in offer.cards do
				if candidate.Id == offer.recommended then
					card = candidate
				end
			end
			if playerState and card then
				local applied = playerState:AddUpgrade(card)
				if applied then
					table.insert(resolved, { playerKey = playerKey, card = card, auto = true })
					self._settled[playerKey] = { card = card, cards = offer.cards }
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
	self._settled[playerKey] = nil
end

function UpgradeService:ClearAll()
	table.clear(self._offers)
	table.clear(self._settled)
end

-- A new round: last round's choices can no longer be respecced.
function UpgradeService:ClearSettled()
	table.clear(self._settled)
end

return UpgradeService
