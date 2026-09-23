-- The salvage shop: permanent upgrades bought between runs with salvage earned in them.
-- Item ids are persisted in profiles (MetaUpgrades), so they never change. Prices are whole
-- salvage and rise with each level. There is no premium currency and nothing here costs money.
--
-- Kind "Stat" adds Effect.PerLevel per level owned to one of UpgradeConfig.BaseStats before any
-- run card is applied, so cards stack on top. Kind "Trail" is cosmetic: owning it lets it be
-- equipped, and the equipped one is drawn behind the player's shots.
local ShopConfig = {}

ShopConfig.Items = {
	{
		Id = "Vitality",
		Title = "Reinforced Frame",
		Description = "+10 maximum health at the start of every run.",
		Kind = "Stat",
		Effect = { Stat = "MaxHealthBonus", PerLevel = 10 },
		Costs = { 80, 160, 260, 380, 520 },
	},
	{
		Id = "Stride",
		Title = "Servo Stride",
		Description = "+1 walk speed at the start of every run.",
		Kind = "Stat",
		Effect = { Stat = "MoveSpeedBonus", PerLevel = 1 },
		Costs = { 60, 140, 240 },
	},
	{
		Id = "Velocity",
		Title = "Rail Tuning",
		Description = "+1% projectile speed.",
		Kind = "Stat",
		Effect = { Stat = "SpeedMultiplier", PerLevel = 0.01 },
		Costs = { 40, 55, 70, 90, 110, 135, 160, 190, 220, 250 },
	},
	{
		Id = "TrailEmber",
		Title = "Ember Trail",
		Description = "Your shots leave a trail of embers. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(255, 140, 64), Lifetime = 0.2 },
		Costs = { 150 },
	},
	{
		Id = "TrailAurora",
		Title = "Aurora Trail",
		Description = "Your shots leave a ribbon of green light. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(110, 255, 170), Lifetime = 0.25 },
		Costs = { 250 },
	},
	{
		Id = "TrailVoid",
		Title = "Void Trail",
		Description = "Your shots leave a deep violet wake. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(170, 110, 255), Lifetime = 0.3 },
		Costs = { 400 },
	},
}

local byId = {}
for _, item in ShopConfig.Items do
	byId[item.Id] = item
end

function ShopConfig.Get(itemId)
	return byId[itemId]
end

function ShopConfig.MaxLevel(item)
	return #item.Costs
end

-- Price of buying `level` (the level the player will own afterwards). nil past the max.
function ShopConfig.CostFor(item, level)
	return item.Costs[level]
end

-- Stat deltas from owned levels, as { [stat] = amount }. Unknown ids are ignored and levels are
-- clamped to the item's max, so a stale or tampered profile can never grant more than the shop
-- sells.
function ShopConfig.ComputeBonuses(levels)
	local bonuses = {}
	for itemId, level in levels or {} do
		local item = byId[itemId]
		if item and item.Kind == "Stat" and type(level) == "number" and level > 0 then
			local owned = math.min(math.floor(level), ShopConfig.MaxLevel(item))
			local stat = item.Effect.Stat
			bonuses[stat] = (bonuses[stat] or 0) + item.Effect.PerLevel * owned
		end
	end
	return bonuses
end

return ShopConfig
