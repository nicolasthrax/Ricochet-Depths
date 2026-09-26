--!strict
-- Explicit fusion table: which pair of modifiers fuses into which fused variant.
--
-- The MVP only fuses duplicates (Ember + Ember -> Inferno). Recipes are stored as unordered
-- pairs, so cross-pair recipes (Ember + Spark -> ...) can be added later without changing any
-- caller. Integrity is asserted when this module loads: every input is a base card, every
-- result is a fused variant, no pair is listed twice, and every fused variant has exactly one
-- recipe (so there is no fused card a player can never reach).

local Source = script.Parent
local Types = require(Source.Types)
local ModifierDefinitions = require(Source.ModifierDefinitions)
local deepFreeze = require(Source.DeepFreeze)

type ModifierId = Types.ModifierId
type BaseModifierId = Types.BaseModifierId
type FusedModifierId = Types.FusedModifierId
type FusionRecipe = Types.FusionRecipe

local RECIPES: { FusionRecipe } = {
	{ first = "Splitshot", second = "Splitshot", result = "Shatter" },
	{ first = "Ember", second = "Ember", result = "Inferno" },
	{ first = "Bigshot", second = "Bigshot", result = "Boulder" },
	{ first = "Quickdraw", second = "Quickdraw", result = "Gatling" },
	{ first = "Frostbite", second = "Frostbite", result = "Glacier" },
	{ first = "Spark", second = "Spark", result = "Tempest" },
	{ first = "Drill", second = "Drill", result = "Auger" },
	{ first = "Echo", second = "Echo", result = "Resonance" },
}

-- Unordered pair key: "Ember+Spark" and "Spark+Ember" are the same recipe.
local function pairKey(a: ModifierId, b: ModifierId): string
	return if a <= b then `{a}+{b}` else `{b}+{a}`
end

local byPair: { [string]: FusionRecipe } = {}
local byResult: { [FusedModifierId]: FusionRecipe } = {}
local byInput: { [BaseModifierId]: { FusionRecipe } } = {}

local function addInput(id: BaseModifierId, recipe: FusionRecipe)
	local list = byInput[id]
	if list == nil then
		list = {}
		byInput[id] = list
	end
	if not table.find(list, recipe) then
		table.insert(list, recipe)
	end
end

for _, recipe in RECIPES do
	local key = pairKey(recipe.first, recipe.second)
	assert(ModifierDefinitions.get(recipe.first).kind == "Base", `{key}: {recipe.first} is not a base card`)
	assert(ModifierDefinitions.get(recipe.second).kind == "Base", `{key}: {recipe.second} is not a base card`)
	assert(ModifierDefinitions.get(recipe.result).kind == "Fused", `{key}: {recipe.result} is not a fused variant`)
	assert(byPair[key] == nil, `{key} is listed twice`)
	assert(byResult[recipe.result] == nil, `{recipe.result} has more than one recipe`)

	byPair[key] = recipe
	byResult[recipe.result] = recipe
	addInput(recipe.first, recipe)
	addInput(recipe.second, recipe)
end

for _, id: ModifierId in ModifierDefinitions.order do
	local definition = ModifierDefinitions.get(id)
	if definition.kind == "Fused" then
		assert(byResult[id :: any] ~= nil, `fused variant {id} has no recipe`)
	end
end

local EMPTY: { FusionRecipe } = {}
table.freeze(EMPTY)

deepFreeze(RECIPES)

local FusionRecipes = {
	all = RECIPES,
}

-- The recipe that fuses a and b (in either order), or nil.
function FusionRecipes.find(a: ModifierId, b: ModifierId): FusionRecipe?
	return byPair[pairKey(a, b)]
end

-- What two copies of this card fuse into: the "FUSES -> INFERNO" chip on a duplicate offer.
function FusionRecipes.duplicateResult(id: ModifierId): FusedModifierId?
	local recipe = byPair[pairKey(id, id)]
	return if recipe then recipe.result else nil
end

-- Every recipe this base card is an input to (for fusion hints and "fusion ready" badges).
function FusionRecipes.recipesUsing(id: BaseModifierId): { FusionRecipe }
	return byInput[id] or EMPTY
end

-- The recipe that produces a fused variant (for the badge's "Ember + Ember" tip).
function FusionRecipes.recipeFor(result: FusedModifierId): FusionRecipe
	local recipe = byResult[result]
	assert(recipe, `no recipe produces {result}`)
	return recipe
end

-- byInput lists are frozen now that indexing is done; they are handed out directly.
deepFreeze(byInput)

table.freeze(FusionRecipes)
return FusionRecipes
