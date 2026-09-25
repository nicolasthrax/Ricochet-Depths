--!strict
-- Run progression: XP and levels, the 3-card modifier offers, each player's modifier loadout,
-- and fusion. Owns the SelectUpgrade and RerollUpgrade remotes.
--
-- Flow: XP fills a level -> an offer of 3 distinct base cards opens (one is recommended) ->
-- the player picks one -> if the pick has a FusionRecipes entry with a card already held, the two
-- fuse into the fused variant on the spot; otherwise the pick joins the loadout (or stacks) ->
-- shot stats are recomputed. Levels gained while an offer is open queue up and open one by one.
--
-- Other services never call into the offer flow; they listen to the signals below and read shot
-- stats with getShotStats().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local ModifierDefinitions = require(ReplicatedStorage.Source.ModifierDefinitions)
local FusionRecipes = require(ReplicatedStorage.Source.FusionRecipes)
local ShotStats = require(ReplicatedStorage.Source.Sim.ShotStats)
local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Modules.Signal)

type ModifierId = Types.ModifierId
type BaseModifierId = Types.BaseModifierId
type Stats = ShotStats.ShotStats

type Offer = {
	id: number,
	level: number,
	choices: { Network.UpgradeChoice },
}

type Entry = {
	id: ModifierId,
	stacks: number,
}

type State = {
	active: boolean,
	loadout: { Entry },
	stats: Stats,
	xp: number,
	xpGained: number,
	level: number,
	xpToNext: number,
	pendingLevels: number,
	offer: Offer?,
	rerolls: number,
	fusions: number,
	seen: { [ModifierId]: boolean }, -- every card this player has held this session
	discoveries: { ModifierId }, -- first-time cards this run
	rng: Random,
}

-- Keyed by string: the old type solver mis-handles singleton-union indexers.
local RARITY_RANK: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Fused = 4 }

local states: { [Player]: State } = {}
local connections: { RBXScriptConnection } = {}
local nextOfferId = 0
local baseStats = ShotStats.compute({})

local UpgradeService = {
	-- An offer is on screen for this player (the run should hold still).
	OfferOpened = Signal.new() :: Signal.Signal<Player>,
	-- The last queued offer was resolved.
	OfferClosed = Signal.new() :: Signal.Signal<Player>,
	-- The player's shot stats changed (a pick, a fusion, a new run).
	StatsChanged = Signal.new() :: Signal.Signal<Player, Stats>,
	Fused = Signal.new() :: Signal.Signal<Player, Network.FusionEvent>,
}

---------------------------------------------------------------------------------------------
-- XP
---------------------------------------------------------------------------------------------

local function xpForLevel(level: number): number
	return math.ceil(GameConfig.Xp.firstLevel * GameConfig.Xp.growth ^ (level - 1))
end

local function xpPayload(state: State): Network.XpChangedPayload
	return { fraction = math.clamp(state.xp / state.xpToNext, 0, 1), level = state.level }
end

---------------------------------------------------------------------------------------------
-- Loadout
---------------------------------------------------------------------------------------------

local function findEntry(state: State, id: ModifierId): Entry?
	for _, entry in state.loadout do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- The first held base card that `id` fuses with, and the recipe.
local function fusionPartner(state: State, id: BaseModifierId): (Entry?, Types.FusionRecipe?)
	for _, entry in state.loadout do
		if ModifierDefinitions.get(entry.id).kind == "Base" then
			local recipe = FusionRecipes.find(id, entry.id)
			if recipe then
				return entry, recipe
			end
		end
	end
	return nil, nil
end

local function discover(state: State, id: ModifierId)
	if not state.seen[id] then
		state.seen[id] = true
		table.insert(state.discoveries, id)
	end
end

local function addToLoadout(state: State, id: ModifierId)
	local entry = findEntry(state, id)
	if entry then
		entry.stacks += 1
	else
		table.insert(state.loadout, { id = id, stacks = 1 })
	end
end

local function removeStack(state: State, entry: Entry)
	entry.stacks -= 1
	if entry.stacks <= 0 then
		local index = table.find(state.loadout, entry)
		if index then
			table.remove(state.loadout, index)
		end
	end
end

-- Applies a pick. Returns the fusion it caused, if any.
local function applyPick(state: State, id: BaseModifierId): Network.FusionEvent?
	discover(state, id)
	local partner, recipe = fusionPartner(state, id)
	if partner and recipe then
		local partnerId = partner.id
		removeStack(state, partner)
		addToLoadout(state, recipe.result)
		discover(state, recipe.result)
		state.fusions += 1
		return { first = partnerId :: any, second = id, result = recipe.result }
	end
	addToLoadout(state, id)
	return nil
end

local function loadoutPayload(state: State): { Network.LoadoutEntry }
	local list: { Network.LoadoutEntry } = {}
	local offer = state.offer
	for _, entry in state.loadout do
		-- Gold pulse: a card in the open offer would fuse with this one.
		local ready = false
		if offer and ModifierDefinitions.get(entry.id).kind == "Base" then
			for _, choice in offer.choices do
				if FusionRecipes.find(choice.modifierId, entry.id) then
					ready = true
					break
				end
			end
		end
		table.insert(list, { id = entry.id, stacks = entry.stacks, fusionReady = ready })
	end
	return list
end

local function sendLoadout(player: Player, state: State, fusion: Network.FusionEvent?)
	Network.LoadoutChanged:fireTo(player, {
		userId = player.UserId,
		modifiers = loadoutPayload(state),
		fusion = fusion,
	})
end

local function refreshStats(player: Player, state: State)
	state.stats = ShotStats.compute(state.loadout)
	UpgradeService.StatsChanged:Fire(player, state.stats)
end

---------------------------------------------------------------------------------------------
-- Offers
---------------------------------------------------------------------------------------------

-- Distinct base cards, drawn by offer weight.
local function draw(state: State, count: number): { BaseModifierId }
	-- Copied by hand: table.clone would widen the id type under the old solver.
	local pool: { BaseModifierId } = {}
	for _, id: BaseModifierId in ModifierDefinitions.baseIds do
		table.insert(pool, id)
	end
	local picked: { BaseModifierId } = {}
	while #picked < count and #pool > 0 do
		local total = 0
		for _, id: BaseModifierId in pool do
			total += ModifierDefinitions.get(id).offerWeight
		end
		local roll = state.rng:NextNumber() * total
		local chosen = #pool
		for index, id: BaseModifierId in pool do
			roll -= ModifierDefinitions.get(id).offerWeight
			if roll <= 0 then
				chosen = index
				break
			end
		end
		table.insert(picked, table.remove(pool, chosen) :: BaseModifierId)
	end
	return picked
end

-- One star per draw: a card that completes a fusion, else a card not held yet (rarest first),
-- else the rarest card.
local function recommendedIndex(state: State, ids: { BaseModifierId }): number
	local best, bestScore = 1, -math.huge
	for index, id: BaseModifierId in ids do
		local rarity = RARITY_RANK[ModifierDefinitions.get(id).rarity]
		local partner = fusionPartner(state, id)
		local score = if partner then 1000 elseif findEntry(state, id) == nil then 100 + rarity else rarity
		if score > bestScore then
			best, bestScore = index, score
		end
	end
	return best
end

local function buildChoices(state: State, ids: { BaseModifierId }): { Network.UpgradeChoice }
	local recommended = recommendedIndex(state, ids)
	local choices: { Network.UpgradeChoice } = {}
	for index, id: BaseModifierId in ids do
		local _, recipe = fusionPartner(state, id)
		table.insert(choices, {
			modifierId = id,
			recommended = index == recommended,
			isNew = not state.seen[id],
			fusesInto = if recipe then recipe.result else nil,
		})
	end
	return choices
end

local function sendOffer(player: Player, state: State, offer: Offer)
	Network.UpgradeOffered:fireTo(player, {
		offerId = offer.id,
		level = offer.level,
		choices = offer.choices,
		rerollsLeft = state.rerolls,
		rerollVisible = state.rerolls > 0,
		timeoutSeconds = GameConfig.Upgrades.soloTimeoutSeconds,
		inputLockSeconds = GameConfig.Upgrades.inputLockSeconds,
	})
end

local function openOffer(player: Player, state: State)
	state.pendingLevels -= 1
	nextOfferId += 1
	local offer: Offer = {
		id = nextOfferId,
		level = state.level - state.pendingLevels,
		choices = buildChoices(state, draw(state, GameConfig.Upgrades.choices)),
	}
	local wasOpen = state.offer ~= nil
	state.offer = offer
	sendOffer(player, state, offer)
	sendLoadout(player, state, nil)
	if not wasOpen then
		UpgradeService.OfferOpened:Fire(player)
	end
end

local function closeOffer(player: Player, state: State)
	if state.offer == nil then
		return
	end
	state.offer = nil
	UpgradeService.OfferClosed:Fire(player)
end

local function onSelect(player: Player, payload: Network.SelectUpgradePayload)
	local state = states[player]
	local offer = if state then state.offer else nil
	if state == nil or offer == nil or not state.active or offer.id ~= payload.offerId then
		return
	end
	local offered = false
	for _, choice in offer.choices do
		if choice.modifierId == payload.modifierId then
			offered = true
			break
		end
	end
	if not offered then
		return
	end

	local fusion = applyPick(state, payload.modifierId)
	Network.UpgradeResolved:fireTo(player, {
		offerId = offer.id,
		modifierId = payload.modifierId,
		autoPicked = false,
	})
	refreshStats(player, state)
	if fusion then
		UpgradeService.Fused:Fire(player, fusion)
	end

	if state.pendingLevels > 0 then
		-- The next queued offer replaces this one: the pick session carries on, so listeners see
		-- neither OfferClosed nor a second OfferOpened.
		sendLoadout(player, state, fusion)
		openOffer(player, state)
	else
		closeOffer(player, state)
		sendLoadout(player, state, fusion)
	end
end

local function onReroll(player: Player, payload: Network.RerollUpgradePayload)
	local state = states[player]
	local offer = if state then state.offer else nil
	if state == nil or offer == nil or offer.id ~= payload.offerId or state.rerolls <= 0 then
		return
	end
	state.rerolls -= 1
	nextOfferId += 1
	local rerolled: Offer = {
		id = nextOfferId,
		level = offer.level,
		choices = buildChoices(state, draw(state, GameConfig.Upgrades.choices)),
	}
	state.offer = rerolled
	sendOffer(player, state, rerolled)
	sendLoadout(player, state, nil)
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

local function newState(): State
	return {
		active = false,
		loadout = {},
		stats = baseStats,
		xp = 0,
		xpGained = 0,
		level = 1,
		xpToNext = xpForLevel(1),
		pendingLevels = 0,
		offer = nil,
		rerolls = GameConfig.Upgrades.startingRerolls,
		fusions = 0,
		seen = {},
		discoveries = {},
		rng = Random.new(0),
	}
end

local function stateFor(player: Player): State
	local state = states[player]
	if state == nil then
		state = newState()
		states[player] = state
	end
	return state
end

function UpgradeService.init()
	table.insert(connections, Network.SelectUpgrade:connect(onSelect))
	table.insert(connections, Network.RerollUpgrade:connect(onReroll))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end))
end

-- Disconnects everything init() connected.
function UpgradeService.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(states)
end

-- Starts a run: empty loadout, level 1, no offer. What the player has seen before is kept.
function UpgradeService.beginRun(player: Player, seed: number)
	local state = stateFor(player)
	local hadOffer = state.offer ~= nil
	state.active = true
	state.loadout = {}
	state.xp = 0
	state.xpGained = 0
	state.level = 1
	state.xpToNext = xpForLevel(1)
	state.pendingLevels = 0
	state.offer = nil
	state.rerolls = GameConfig.Upgrades.startingRerolls
	state.fusions = 0
	state.discoveries = {}
	state.rng = Random.new(seed)
	if hadOffer then
		UpgradeService.OfferClosed:Fire(player)
	end
	refreshStats(player, state)
	Network.XpChanged:fireTo(player, xpPayload(state))
	sendLoadout(player, state, nil)
end

-- Ends the run: any open offer is dropped and no more XP is taken.
function UpgradeService.endRun(player: Player)
	local state = states[player]
	if state then
		state.active = false
		state.pendingLevels = 0
		closeOffer(player, state)
	end
end

function UpgradeService.addXp(player: Player, amount: number)
	local state = states[player]
	if state == nil or not state.active or amount <= 0 then
		return
	end
	state.xp += amount
	state.xpGained += amount
	while state.xp >= state.xpToNext do
		state.xp -= state.xpToNext
		state.level += 1
		state.xpToNext = xpForLevel(state.level)
		state.pendingLevels += 1
	end
	Network.XpChanged:fireTo(player, xpPayload(state))
	if state.offer == nil and state.pendingLevels > 0 then
		openOffer(player, state)
	end
end

-- Applies a card outside an offer, exactly as if it had been picked (the scripted first descent's
-- guaranteed cards, rewards, tests). Returns the fusion it caused, if any.
function UpgradeService.grant(player: Player, id: BaseModifierId): Network.FusionEvent?
	local state = stateFor(player)
	local fusion = applyPick(state, id)
	refreshStats(player, state)
	if fusion then
		UpgradeService.Fused:Fire(player, fusion)
	end
	sendLoadout(player, state, fusion)
	return fusion
end

function UpgradeService.grantRerolls(player: Player, count: number)
	local state = stateFor(player)
	state.rerolls += count
end

function UpgradeService.getShotStats(player: Player): Stats
	local state = states[player]
	return if state then state.stats else baseStats
end

function UpgradeService.hasOpenOffer(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.offer ~= nil
end

function UpgradeService.getLoadout(player: Player): { Network.LoadoutEntry }
	return loadoutPayload(stateFor(player))
end

function UpgradeService.getXp(player: Player): Network.XpChangedPayload
	return xpPayload(stateFor(player))
end

export type RunSummary = {
	fusions: number,
	discoveries: { ModifierId },
	xpGained: number,
}

function UpgradeService.runSummary(player: Player): RunSummary
	local state = stateFor(player)
	return {
		fusions = state.fusions,
		discoveries = table.clone(state.discoveries),
		xpGained = math.floor(state.xpGained),
	}
end

-- Re-sends the open offer (a client that reloaded its UI).
function UpgradeService.resendOffer(player: Player)
	local state = states[player]
	local offer = if state then state.offer else nil
	if state and offer then
		sendOffer(player, state, offer)
	end
end

return UpgradeService
