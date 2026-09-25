-- The Cosmetics shop, bought with coins earned in runs. Item ids are persisted in profiles
-- (MetaUpgrades), so they never change. Prices are whole coins. Robux purchases live in
-- MonetizationConfig. Nothing here changes how a run plays: earnable power lives in the home
-- base's buildings (BaseConfig), and the 1.x Armory's stat upgrades were retired (and refunded)
-- in schema v9.
--
-- Every item is cosmetic, and each is earned one of three ways: bought with coins (Costs), reached
-- at an account level (UnlockLevel, free), or included in a pass (RequiresPass, free with it).
--   Trail: drawn behind the player's shots (profile.EquippedTrail).
--   Theme: the home base's palette (profile.Base.Theme; BaseConfig.Themes).
--   Sign: the base's sign board style (profile.Base.Sign; BaseConfig.Signs).
--   Emote: played in the lobby as a burst over the head (PlayEmote); owned, never equipped.
--   Nameplate: a title on the level plate over the head (profile.Nameplate).
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
		RequiresPass = "SupporterPack",
		Trail = { Color = Color3.fromRGB(255, 210, 80), Lifetime = 0.35 },
	},

	-- Base themes. Their ids match BaseConfig.Themes.
	{
		Id = "Moss",
		Category = "Cosmetics",
		Title = "Mossy Ruins",
		Description = "A green, overgrown look for your base. Cosmetic.",
		Kind = "Theme",
		Costs = { 400 },
	},
	{
		Id = "Frost",
		Category = "Cosmetics",
		Title = "Frost Camp",
		Description = "Snow and ice for your base. Unlocks at level 8.",
		Kind = "Theme",
		UnlockLevel = 8,
	},
	{
		Id = "Gilded",
		Category = "Cosmetics",
		Title = "Gilded Outpost",
		Description = "Gold trim on everything. Supporter Pack.",
		Kind = "Theme",
		RequiresPass = "SupporterPack",
	},

	-- Base sign styles. Their ids match BaseConfig.Signs.
	{
		Id = "Slate",
		Category = "Cosmetics",
		Title = "Slate Sign",
		Description = "A dark slate board with bright lettering. Cosmetic.",
		Kind = "Sign",
		Costs = { 150 },
	},
	{
		Id = "Banner",
		Category = "Cosmetics",
		Title = "Explorer Banner",
		Description = "A blue and gold banner over your base. Explorer Pass.",
		Kind = "Sign",
		RequiresPass = "ExplorerPass",
	},

	-- Emotes, played in the lobby.
	{
		Id = "Wave",
		Category = "Cosmetics",
		Title = "Wave",
		Description = "Say hello. Everyone has it.",
		Kind = "Emote",
		UnlockLevel = 1,
		Emote = { Text = "👋", Color = Color3.fromRGB(255, 236, 200) },
	},
	{
		Id = "Flex",
		Category = "Cosmetics",
		Title = "Flex",
		Description = "Show off a good run. Unlocks at level 5.",
		Kind = "Emote",
		UnlockLevel = 5,
		Emote = { Text = "💪", Color = Color3.fromRGB(255, 176, 102) },
	},
	{
		Id = "Ricochet",
		Category = "Cosmetics",
		Title = "Ricochet",
		Description = "A burst of bouncing sparks. Cosmetic.",
		Kind = "Emote",
		Costs = { 200 },
		Emote = { Text = "✨", Color = Color3.fromRGB(120, 235, 255) },
	},
	{
		Id = "Cheer",
		Category = "Cosmetics",
		Title = "Cheer",
		Description = "A golden cheer. Supporter Pack.",
		Kind = "Emote",
		RequiresPass = "SupporterPack",
		Emote = { Text = "🎉", Color = Color3.fromRGB(255, 214, 90) },
	},

	-- Nameplate titles.
	{
		Id = "Delver",
		Category = "Cosmetics",
		Title = "Delver",
		Description = "A title for your nameplate. Unlocks at level 3.",
		Kind = "Nameplate",
		UnlockLevel = 3,
	},
	{
		Id = "DeepDiver",
		Category = "Cosmetics",
		Title = "Deep Diver",
		Description = "A title for your nameplate. Unlocks at level 10.",
		Kind = "Nameplate",
		UnlockLevel = 10,
	},
	{
		Id = "Explorer",
		Category = "Cosmetics",
		Title = "Explorer",
		Description = "A title for your nameplate. Explorer Pass.",
		Kind = "Nameplate",
		RequiresPass = "ExplorerPass",
	},
}

-- The tabs the Cosmetics shop shows, in order, and the kinds that can be equipped (an emote is
-- played, not worn).
ShopConfig.Kinds = { "Trail", "Theme", "Sign", "Emote", "Nameplate" }
ShopConfig.Equippable = { Trail = true, Theme = true, Sign = true, Nameplate = true }

local byId = {}
for _, item in ShopConfig.Items do
	byId[item.Id] = item
end

function ShopConfig.Get(itemId)
	return byId[itemId]
end

-- How many levels can be bought: 1 for a coin cosmetic, 0 for one earned by level or a pass.
function ShopConfig.MaxLevel(item)
	return item.Costs and #item.Costs or 0
end

-- Price of buying `level` (the level the player will own afterwards). nil past the max, and for
-- items that are not sold.
function ShopConfig.CostFor(item, level)
	return item.Costs and item.Costs[level] or nil
end

-- Whether an item is owned: bought (levels), reached (level), or included in an owned pass.
-- ownsPass(passKey) -> bool.
function ShopConfig.Owns(item, levels, level, ownsPass)
	if not item then
		return false
	end
	if item.RequiresPass then
		return ownsPass ~= nil and ownsPass(item.RequiresPass) == true
	end
	if item.UnlockLevel and (tonumber(level) or 0) >= item.UnlockLevel then
		return true
	end
	return type(levels) == "table" and (levels[item.Id] or 0) >= 1
end

return ShopConfig
