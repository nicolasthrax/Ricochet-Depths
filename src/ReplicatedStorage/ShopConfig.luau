-- The Cosmetics shop, bought with coins earned in runs. Item ids are persisted in profiles
-- (MetaUpgrades), so they never change. Prices are whole coins. Robux purchases live in
-- MonetizationConfig. Nothing here changes how a run plays: earnable power lives in the home
-- base's buildings (BaseConfig), and the 1.x Armory's stat upgrades were retired (and refunded)
-- in schema v9.
--
-- Kind "Trail" is cosmetic: owning it lets it be equipped, and the equipped one is drawn behind
-- the player's shots.
local ShopConfig = {}

ShopConfig.Items = {
	{
		Id = "TrailEmber",
		Category = "Cosmetics",
		Title = "Ember Trail",
		Description = "Your shots leave a trail of embers. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(255, 140, 64), Lifetime = 0.2 },
		Costs = { 150 },
	},
	{
		Id = "TrailAurora",
		Category = "Cosmetics",
		Title = "Aurora Trail",
		Description = "Your shots leave a ribbon of green light. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(110, 255, 170), Lifetime = 0.25 },
		Costs = { 250 },
	},
	{
		Id = "TrailVoid",
		Category = "Cosmetics",
		Title = "Void Trail",
		Description = "Your shots leave a deep violet wake. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(170, 110, 255), Lifetime = 0.3 },
		Costs = { 400 },
	},
	{
		Id = "TrailFrost",
		Category = "Cosmetics",
		Title = "Frost Trail",
		Description = "Your shots leave a trail of ice crystals. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(170, 230, 255), Lifetime = 0.28 },
		Costs = { 300 },
	},
	{
		Id = "TrailToxic",
		Category = "Cosmetics",
		Title = "Toxic Trail",
		Description = "Your shots drip a sickly green wake. Cosmetic.",
		Kind = "Trail",
		Trail = { Color = Color3.fromRGB(160, 255, 60), Lifetime = 0.25 },
		Costs = { 350 },
	},
	{
		Id = "TrailGold",
		Category = "Cosmetics",
		Title = "Gold Trail",
		Description = "A blazing gold wake. VIP only. Cosmetic.",
		Kind = "Trail",
		RequiresPass = "VIP",
		Trail = { Color = Color3.fromRGB(255, 210, 80), Lifetime = 0.35 },
		Costs = { 1 },
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

return ShopConfig
