--!strict
-- The MVP modifier cards: 8 base cards that can be offered, and the 8 fused variants that only
-- come out of FusionRecipes. Pure data plus read-only lookups; combat code interprets `effect`.
--
-- Card text budget (design): label 12 characters at most, effect text verb-led and 3 words at
-- most, numbers only in the stat line. The stat line is generated from `effect` by statLine()
-- so the numbers a player reads can never drift from the numbers the server uses.
-- The budget is asserted when this module loads, so a bad entry fails in Studio immediately.

local Source = script.Parent
local Types = require(Source.Types)
local deepFreeze = require(Source.DeepFreeze)

type ModifierId = Types.ModifierId
type BaseModifierId = Types.BaseModifierId
type ModifierDefinition = Types.ModifierDefinition
type ModifierEffect = Types.ModifierEffect

local MAX_LABEL_LENGTH = 12
local MAX_EFFECT_WORDS = 3

-- Offer weights by rarity. Fused variants are never drawn, so they weigh 0.
local WEIGHT = {
	Common = 100,
	Rare = 45,
	Epic = 20,
	Fused = 0,
}

local DEFINITIONS: { ModifierDefinition } = {
	-----------------------------------------------------------------------------------------
	-- Base cards (offerable)
	-----------------------------------------------------------------------------------------
	{
		id = "Splitshot",
		kind = "Base",
		rarity = "Common",
		family = "Split",
		label = "Splitshot",
		badge = "SP",
		effectText = "Splits on bounce",
		tip = "The first bounce splits your shot into two shards.",
		offerWeight = WEIGHT.Common,
		effect = {
			kind = "SplitOnBounce",
			shardCount = 2,
			shardDamageScale = 0.4,
			spreadDegrees = 30,
			everyBounce = false,
		},
	},
	{
		-- Common, not Rare: the FTUE's first pick must be three commons, and Ember is on it.
		id = "Ember",
		kind = "Base",
		rarity = "Common",
		family = "Burn",
		label = "Ember",
		badge = "EM",
		effectText = "Burns on hit",
		tip = "Hits set targets burning for a moment.",
		offerWeight = WEIGHT.Common,
		effect = {
			kind = "BurnOnHit",
			damagePerSecond = 2,
			durationSeconds = 2,
			blastRadius = 0,
			blastDamageScale = 0,
			shotTint = "Ember",
		},
	},
	{
		id = "Bigshot",
		kind = "Base",
		rarity = "Common",
		family = "Size",
		label = "Bigshot",
		badge = "BG",
		effectText = "Bigger shots",
		tip = "Your shots are larger and hit harder.",
		offerWeight = WEIGHT.Common,
		effect = {
			kind = "ShotSize",
			radiusScale = 1.35,
			flatDamage = 1,
		},
	},
	{
		id = "Quickdraw",
		kind = "Base",
		rarity = "Common",
		family = "Tempo",
		label = "Quickdraw",
		badge = "QD",
		effectText = "Fires faster",
		tip = "Less waiting between shots.",
		offerWeight = WEIGHT.Common,
		effect = {
			kind = "FireRate",
			cooldownScale = 0.8,
		},
	},
	{
		id = "Frostbite",
		kind = "Base",
		rarity = "Rare",
		family = "Chill",
		label = "Frostbite",
		badge = "FR",
		effectText = "Slows on hit",
		tip = "A target you hit skips its next step forward.",
		offerWeight = WEIGHT.Rare,
		effect = {
			kind = "ChillOnHit",
			skipSteps = 1,
			wholeRow = false,
		},
	},
	{
		id = "Spark",
		kind = "Base",
		rarity = "Rare",
		family = "Arc",
		label = "Spark",
		badge = "SK",
		effectText = "Arcs on hit",
		tip = "Each hit jumps to a nearby target.",
		offerWeight = WEIGHT.Rare,
		effect = {
			kind = "ArcOnHit",
			arcCount = 1,
			arcDamageScale = 0.5,
			arcRangeCells = 2,
		},
	},
	{
		id = "Drill",
		kind = "Base",
		rarity = "Rare",
		family = "Pierce",
		label = "Drill",
		badge = "DR",
		effectText = "Pierces one block",
		tip = "Shots break through the first target they hit.",
		offerWeight = WEIGHT.Rare,
		effect = {
			kind = "Pierce",
			pierceCount = 1,
			damageScale = 0.9,
		},
	},
	{
		id = "Echo",
		kind = "Base",
		rarity = "Epic",
		family = "Bounce",
		label = "Echo",
		badge = "EC",
		effectText = "One more bounce",
		tip = "Every shot bounces one extra time.",
		offerWeight = WEIGHT.Epic,
		effect = {
			kind = "ExtraBounce",
			extraBounces = 1,
			damagePerBounce = 0,
		},
	},

	-----------------------------------------------------------------------------------------
	-- Fused variants (never offered; see FusionRecipes)
	-----------------------------------------------------------------------------------------
	{
		id = "Shatter",
		kind = "Fused",
		rarity = "Fused",
		family = "Split",
		label = "Shatter",
		badge = "SH",
		effectText = "Splits every bounce",
		tip = "Every bounce splits your shot into three shards.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "SplitOnBounce",
			shardCount = 3,
			shardDamageScale = 0.5,
			spreadDegrees = 40,
			everyBounce = true,
		},
	},
	{
		id = "Inferno",
		kind = "Fused",
		rarity = "Fused",
		family = "Burn",
		label = "Inferno",
		badge = "INF", -- (design) the FTUE fusion badge
		effectText = "Burns and blasts",
		tip = "Big fiery shots that burn and blast nearby blocks.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "BurnOnHit",
			damagePerSecond = 4,
			durationSeconds = 3,
			blastRadius = 3,
			blastDamageScale = 0.5,
			shotTint = "Inferno",
		},
	},
	{
		id = "Boulder",
		kind = "Fused",
		rarity = "Fused",
		family = "Size",
		label = "Boulder",
		badge = "BO",
		effectText = "Hits much harder",
		tip = "Huge, heavy shots.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "ShotSize",
			radiusScale = 1.8,
			flatDamage = 3,
		},
	},
	{
		id = "Gatling",
		kind = "Fused",
		rarity = "Fused",
		family = "Tempo",
		label = "Gatling",
		badge = "GT",
		effectText = "Fires much faster",
		tip = "Almost no wait between shots.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "FireRate",
			cooldownScale = 0.55,
		},
	},
	{
		id = "Glacier",
		kind = "Fused",
		rarity = "Fused",
		family = "Chill",
		label = "Glacier",
		badge = "GL",
		effectText = "Freezes whole rows",
		tip = "A hit freezes its whole row for two steps.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "ChillOnHit",
			skipSteps = 2,
			wholeRow = true,
		},
	},
	{
		id = "Tempest",
		kind = "Fused",
		rarity = "Fused",
		family = "Arc",
		label = "Tempest",
		badge = "TP",
		effectText = "Chains through crowds",
		tip = "Each hit arcs to three nearby targets.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "ArcOnHit",
			arcCount = 3,
			arcDamageScale = 0.6,
			arcRangeCells = 3,
		},
	},
	{
		id = "Auger",
		kind = "Fused",
		rarity = "Fused",
		family = "Pierce",
		label = "Auger",
		badge = "AU",
		effectText = "Drills through rows",
		tip = "Shots break through three targets at full damage.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "Pierce",
			pierceCount = 3,
			damageScale = 1,
		},
	},
	{
		id = "Resonance",
		kind = "Fused",
		rarity = "Fused",
		family = "Bounce",
		label = "Resonance",
		badge = "RS",
		effectText = "Grows every bounce",
		tip = "Two extra bounces, and each bounce hits harder.",
		offerWeight = WEIGHT.Fused,
		effect = {
			kind = "ExtraBounce",
			extraBounces = 2,
			damagePerBounce = 0.15,
		},
	},
}

---------------------------------------------------------------------------------------------
-- Stat line
---------------------------------------------------------------------------------------------

local function percent(fraction: number): string
	return string.format("%d%%", math.round(fraction * 100))
end

local function plural(count: number, word: string): string
	return string.format("%d %s%s", count, word, if count == 1 then "" else "s")
end

-- The small mono line under the card text. Every branch covers one ModifierEffect kind.
local function statLine(effect: ModifierEffect): string
	if effect.kind == "SplitOnBounce" then
		local line = `{plural(effect.shardCount, "shard")} · {percent(effect.shardDamageScale)} dmg`
		return if effect.everyBounce then `{line} · every bounce` else line
	elseif effect.kind == "BurnOnHit" then
		local line = `{effect.damagePerSecond} dmg/s · {effect.durationSeconds}s`
		return if effect.blastRadius > 0 then `{line} · blast {effect.blastRadius}` else line
	elseif effect.kind == "ShotSize" then
		return `+{percent(effect.radiusScale - 1)} size · +{effect.flatDamage} dmg`
	elseif effect.kind == "FireRate" then
		return `-{percent(1 - effect.cooldownScale)} cooldown`
	elseif effect.kind == "ChillOnHit" then
		local line = `skip {plural(effect.skipSteps, "step")}`
		return if effect.wholeRow then `whole row · {line}` else line
	elseif effect.kind == "ArcOnHit" then
		return `{plural(effect.arcCount, "arc")} · {percent(effect.arcDamageScale)} dmg`
	elseif effect.kind == "Pierce" then
		return `pierce {effect.pierceCount} · {percent(effect.damageScale)} dmg`
	elseif effect.kind == "ExtraBounce" then
		local line = `+{plural(effect.extraBounces, "bounce")}`
		return if effect.damagePerBounce > 0
			then `{line} · +{percent(effect.damagePerBounce)}/bounce`
			else `{line} · all shots`
	end
	error("unhandled modifier effect kind")
end

---------------------------------------------------------------------------------------------
-- Index and load-time checks
---------------------------------------------------------------------------------------------

-- Keyed by string: the old type solver mis-handles singleton-union indexers.
local byId: { [string]: ModifierDefinition } = {}
local order: { ModifierId } = {}
local baseIds: { BaseModifierId } = {}

for _, definition in DEFINITIONS do
	local id: ModifierId = definition.id
	assert(byId[id] == nil, `duplicate modifier id {id}`)
	assert(
		(utf8.len(definition.label) or math.huge) <= MAX_LABEL_LENGTH,
		`{id}: label is over {MAX_LABEL_LENGTH} characters`
	)
	local _, words = string.gsub(definition.effectText, "%S+", "")
	assert(words <= MAX_EFFECT_WORDS, `{id}: effect text is over {MAX_EFFECT_WORDS} words`)
	assert(#definition.badge >= 2 and #definition.badge <= 3, `{id}: badge must be 2-3 letters`)
	assert((definition.kind == "Fused") == (definition.rarity == "Fused"), `{id}: only fused variants use the Fused rarity`)
	assert((definition.kind == "Fused") == (definition.offerWeight == 0), `{id}: only fused variants have no offer weight`)

	byId[id] = definition
	table.insert(order, id)
	if definition.kind == "Base" then
		table.insert(baseIds, id :: any)
	end
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

-- Frozen in place (not through deepFreeze's return) so the declared element types survive.
deepFreeze(byId)
deepFreeze(order)
deepFreeze(baseIds)

local ModifierDefinitions = {
	-- Every definition by id (base and fused).
	byId = byId,
	-- Display order: base cards first, then fused variants, in declaration order.
	order = order,
	-- The offerable cards.
	baseIds = baseIds,
	statLine = statLine,
}

function ModifierDefinitions.get(id: ModifierId): ModifierDefinition
	local definition = byId[id]
	assert(definition, `unknown modifier id {id}`)
	return definition
end

-- Narrows an untrusted value (a remote payload field) to a known modifier id, or nil.
function ModifierDefinitions.parseId(value: unknown): ModifierId?
	if type(value) == "string" and byId[value :: string] ~= nil then
		return value :: any
	end
	return nil
end

-- Narrows an untrusted value to an offerable (base) modifier id, or nil.
function ModifierDefinitions.parseBaseId(value: unknown): BaseModifierId?
	local id = ModifierDefinitions.parseId(value)
	if id ~= nil and byId[id].kind == "Base" then
		return id :: any
	end
	return nil
end

table.freeze(ModifierDefinitions)
return ModifierDefinitions
