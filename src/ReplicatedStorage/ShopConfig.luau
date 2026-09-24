-- The lobby shops: permanent upgrades in the Armory and trails in Cosmetics, all bought with
-- coins earned in runs. Item ids are persisted in profiles (MetaUpgrades), so they never change.
-- Prices are whole coins and rise with each level. Robux purchases live in MonetizationConfig.
--
-- Kind "Stat" adds Effect.PerLevel per level owned to one of UpgradeConfig.BaseStats before any
-- run card is applied, so cards stack on top. Kind "Trail" is cosmetic: owning it lets it be
-- equipped, and the equipped one is drawn behind the player's shots.
local ShopConfig = {}

ShopConfig.Items = {
	{
		Id = "Vitality",
		Category = "Armory",
		Title = "Reinforced Frame",
		Description = "+10 maximum health at the start of every run.",
		Kind = "Stat",
		Effect = { Stat = "MaxHealthBonus", PerLevel = 10 },
		Costs = { 80, 160, 260, 380, 520 },
	},
	{
		Id = "Stride",
		Category = "Armory",
		Title = "Servo Stride",
		Description = "+1 walk speed at the start of every run.",
		Kind = "Stat",
		Effect = { Stat = "MoveSpeedBonus", PerLevel = 1 },
		Costs = { 60, 140, 240 },
	},
	{
		Id = "Velocity",
		Category = "Armory",
		Title = "Rail Tuning",
		Description = "+1% projectile speed.",
		Kind = "Stat",
		Effect = { Stat = "SpeedMultiplier", PerLevel = 0.01 },
		Costs = { 40, 55, 70, 90, 110, 135, 160, 190, 220, 250 },
	},
	{
		Id = "Mending",
		Category = "Armory",
		Title = "Mending Core",
		Description = "+0.5 health per second of regeneration between fights.",
		Kind = "Stat",
		Effect = { Stat = "RegenBonus", PerLevel = 0.5 },
		Costs = { 120, 240, 400, 600 },
	},
	{
		Id = "CoinMagnet",
		Category = "Armory",
		Title = "Coin Magnet",
		Description = "+3 studs of reach when pulling in coins.",
		Kind = "Stat",
		Effect = { Stat = "MagnetBonus", PerLevel = 3 },
		Costs = { 100, 220, 380 },
	},
	{
		Id = "Fortune",
		Category = "Armory",
		Title = "Fortune",
		Description = "+10% coins from every run.",
		Kind = "Stat",
		Effect = { Stat = "RewardMultiplier", PerLevel = 0.1 },
		Costs = { 250, 500, 900 },
	},
	{
		Id = "Quiver",
		Category = "Armory",
		Title = "Deep Quiver",
		Description = "+1 orb carried into every run.",
		Kind = "Stat",
		-- Only worth selling while orbs are a limited resource.
		RequiresFlag = "Orbs",
		Effect = { Stat = "OrbCount", PerLevel = 1 },
		Costs = { 1500, 4000 },
	},
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

-- Deepen: once every Armory upgrade is maxed, the player can reset them all for the next Depth
-- Rank, which adds RewardPerRank to their coin multiplier for good. Trails are never reset.
-- The rank is saved in profiles (DepthRank).
ShopConfig.Deepen = {
	MaxRank = 10,
	RewardPerRank = 0.1,
	Stat = "RewardMultiplier",
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

-- Whether an item is on sale in this build. `flags` is FeatureFlags; an item naming a flag
-- that is off is neither sold nor shown.
function ShopConfig.IsAvailable(item, flags)
	return item.RequiresFlag == nil or (flags ~= nil and flags[item.RequiresFlag] == true)
end

-- The Armory items a Deepen resets, as item id -> the level each must reach first.
function ShopConfig.DeepenRequirements(flags)
	local required = {}
	for _, item in ShopConfig.Items do
		if item.Kind == "Stat" and ShopConfig.IsAvailable(item, flags) then
			required[item.Id] = ShopConfig.MaxLevel(item)
		end
	end
	return required
end

-- Whether `levels` has every Armory upgrade maxed, so the next Deepen is open.
function ShopConfig.CanDeepen(levels, rank, flags)
	if (tonumber(rank) or 0) >= ShopConfig.Deepen.MaxRank then
		return false
	end
	for itemId, level in ShopConfig.DeepenRequirements(flags) do
		if (tonumber((levels or {})[itemId]) or 0) < level then
			return false
		end
	end
	return true
end

-- A whole Depth Rank in 0..MaxRank; anything malformed counts as none.
function ShopConfig.SanitiseRank(rank)
	local value = tonumber(rank)
	if not value or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, ShopConfig.Deepen.MaxRank)
end

-- Stat deltas from owned levels, as { [stat] = amount }, plus the Depth Rank's bonus when a
-- rank is given. Unknown ids are ignored and levels are clamped to the item's max, so a stale
-- or tampered profile can never grant more than the shop sells.
function ShopConfig.ComputeBonuses(levels, depthRank)
	local bonuses = {}
	local rank = ShopConfig.SanitiseRank(depthRank)
	if rank > 0 then
		bonuses[ShopConfig.Deepen.Stat] = ShopConfig.Deepen.RewardPerRank * rank
	end
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
