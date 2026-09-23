-- Upgrade cards. IDs are persisted in run summaries and telemetry, so they never change.
-- Effects are pure data folded over BaseStats by UpgradeService; no logic lives here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))

local UpgradeConfig = {}

UpgradeConfig.OffersPerEvent = 3
UpgradeConfig.ChoiceTimeout = 10
-- Cards with unlimited stacks keep the candidate pool from ever emptying.
UpgradeConfig.UnlimitedStacks = math.huge

UpgradeConfig.Categories = {
	Projectile = { Id = "Projectile", DisplayName = "Projectile", Color = Color3.fromRGB(120, 235, 255) },
	Power = { Id = "Power", DisplayName = "Power", Color = Color3.fromRGB(255, 176, 102) },
	Survival = { Id = "Survival", DisplayName = "Survival", Color = Color3.fromRGB(140, 236, 168) },
	Economy = { Id = "Economy", DisplayName = "Coins", Color = Color3.fromRGB(226, 196, 120) },
}

UpgradeConfig.Rarities = {
	Common = { Id = "Common", Weight = 100, Color = Color3.fromRGB(196, 202, 216) },
	Rare = { Id = "Rare", Weight = 45, Color = Color3.fromRGB(120, 200, 255) },
	Fused = { Id = "Fused", Weight = 30, Color = Color3.fromRGB(226, 160, 255) },
}

-- Every stat a card can move, with its starting value.
UpgradeConfig.BaseStats = {
	ProjectilesPerShot = 1,
	SpreadDegrees = 7,
	BounceBudget = ProjectileConfig.MaxBounces,
	SpeedMultiplier = 1,
	LifetimeBonus = 0,
	Damage = 1,
	DamagePerBounce = 0,
	FireCooldownMultiplier = 1,
	MaxHealthBonus = 0,
	RoomClearHeal = 0,
	RewardMultiplier = 1,
	-- Studs per second added to walk speed. Only the Armory moves this today.
	MoveSpeedBonus = 0,
	-- Health per second added to the out-of-combat regen (Armory: Mending).
	RegenBonus = 0,
	-- Studs added to the coin magnet's reach (Armory: Coin Magnet).
	MagnetBonus = 0,
	-- Multiplies the whole payout; the 2x Coins pass sets it to 2.
	CoinMultiplier = 1,
}

UpgradeConfig.Cards = {
	{
		Id = "SplitShot",
		Title = "Split Shot",
		Description = "Every shot fires one extra projectile.",
		Category = "Projectile",
		Rarity = "Rare",
		MaxStacks = 2,
		Effects = { { Stat = "ProjectilesPerShot", Op = "Add", Value = 1 } },
	},
	{
		Id = "LongBounce",
		Title = "Long Bounce",
		Description = "Shots survive two more ricochets.",
		Category = "Projectile",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "BounceBudget", Op = "Add", Value = 2 } },
	},
	{
		Id = "HeavyRound",
		Title = "Heavy Round",
		Description = "Shots travel 35% faster.",
		Category = "Projectile",
		Rarity = "Common",
		MaxStacks = 2,
		Effects = { { Stat = "SpeedMultiplier", Op = "Multiply", Value = 1.35 } },
	},
	{
		Id = "Persistence",
		Title = "Persistence",
		Description = "Shots stay alive 1.5s longer.",
		Category = "Projectile",
		Rarity = "Common",
		MaxStacks = 2,
		Effects = { { Stat = "LifetimeBonus", Op = "Add", Value = 1.5 } },
	},
	{
		Id = "TightGroup",
		Title = "Tight Group",
		Description = "Multi-shot spread is much tighter.",
		Category = "Projectile",
		Rarity = "Common",
		MaxStacks = 2,
		Effects = { { Stat = "SpreadDegrees", Op = "Multiply", Value = 0.55 } },
		-- Pointless with a single projectile, so it is only offered once you fire more than one.
		Requires = { Stats = { ProjectilesPerShot = 2 } },
	},
	{
		Id = "SharpEdge",
		Title = "Sharp Edge",
		Description = "Shots deal 1 more damage.",
		Category = "Power",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "Damage", Op = "Add", Value = 1 } },
	},
	{
		Id = "RapidCycle",
		Title = "Rapid Cycle",
		Description = "Fire 20% more often.",
		Category = "Power",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "FireCooldownMultiplier", Op = "Multiply", Value = 0.8 } },
	},
	{
		Id = "RicochetCharge",
		Title = "Ricochet Charge",
		Description = "Each ricochet adds 1 damage to that shot.",
		Category = "Power",
		Rarity = "Rare",
		MaxStacks = 2,
		Effects = { { Stat = "DamagePerBounce", Op = "Add", Value = 1 } },
	},
	{
		Id = "Plating",
		Title = "Plating",
		Description = "Gain 25 maximum health, healed immediately.",
		Category = "Survival",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "MaxHealthBonus", Op = "Add", Value = 25 } },
	},
	{
		Id = "FieldMend",
		Title = "Field Mend",
		Description = "Recover 30 health each time a room is cleared.",
		Category = "Survival",
		Rarity = "Rare",
		MaxStacks = 2,
		Effects = { { Stat = "RoomClearHeal", Op = "Add", Value = 30 } },
	},
	{
		Id = "Scavenger",
		Title = "Scavenger",
		Description = "Earn 25% more coins from this run.",
		Category = "Economy",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "RewardMultiplier", Op = "Multiply", Value = 1.25 } },
	},
	{
		Id = "Reclaim",
		Title = "Reclaim",
		Description = "A steady trickle of extra coins. Always available.",
		Category = "Economy",
		Rarity = "Common",
		MaxStacks = UpgradeConfig.UnlimitedStacks,
		-- The guaranteed floor of the candidate pool: an offer can always be filled.
		IsFallback = true,
		Effects = { { Stat = "RewardMultiplier", Op = "Multiply", Value = 1.08 } },
	},
	{
		Id = "Fusillade",
		Title = "Fusillade",
		Description = "Two more projectiles per shot, in a tighter fan.",
		Category = "Projectile",
		Rarity = "Fused",
		MaxStacks = 1,
		-- Fusion: only reachable once Split Shot is fully stacked.
		Requires = { Cards = { SplitShot = 2 } },
		Effects = {
			{ Stat = "ProjectilesPerShot", Op = "Add", Value = 2 },
			{ Stat = "SpreadDegrees", Op = "Multiply", Value = 0.7 },
		},
	},
	{
		Id = "Caroms",
		Title = "Caroms",
		Description = "Three more ricochets, and each one hits harder.",
		Category = "Power",
		Rarity = "Fused",
		MaxStacks = 1,
		Requires = { Cards = { LongBounce = 2 } },
		Effects = {
			{ Stat = "BounceBudget", Op = "Add", Value = 3 },
			{ Stat = "DamagePerBounce", Op = "Add", Value = 1 },
		},
	},
	{
		Id = "Bulwarker",
		Title = "Counterweight",
		Description = "Gain 40 maximum health and fire slightly slower.",
		Category = "Survival",
		Rarity = "Rare",
		MaxStacks = 2,
		Effects = {
			{ Stat = "MaxHealthBonus", Op = "Add", Value = 40 },
			{ Stat = "FireCooldownMultiplier", Op = "Multiply", Value = 1.1 },
		},
	},
}

local byId = {}
for _, card in UpgradeConfig.Cards do
	assert(byId[card.Id] == nil, "duplicate upgrade card id: " .. card.Id)
	byId[card.Id] = card
end

function UpgradeConfig.Get(cardId)
	return byId[cardId]
end

function UpgradeConfig.WeightOf(card)
	local rarity = UpgradeConfig.Rarities[card.Rarity]
	return card.Weight or (rarity and rarity.Weight) or 1
end

return UpgradeConfig
