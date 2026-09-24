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
	-- On-hit and on-kill behaviour: burning, arcing, exploding, chilling, critting.
	Element = { Id = "Element", DisplayName = "Element", Color = Color3.fromRGB(255, 120, 200) },
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

	-- Shot effects (CombatEffects). All start at 0, which means "off".
	-- Chance (0..1) that a hit is a critical, dealing CritMultiplier times the damage.
	CritChance = 0,
	CritMultiplier = 2,
	-- A shot that has ricocheted at least this many times always crits. 0 is off.
	TrickShotContacts = 0,
	-- Damage per second a hit sets burning for CombatEffects.BurnDuration seconds.
	BurnDamage = 0,
	-- How many other enemies a damaging hit arcs to, and the share of the hit each arc deals.
	ChainArcs = 0,
	ArcDamageFraction = 0.5,
	-- Damage dealt to every enemy near a kill. 0 is off.
	ExplosionDamage = 0,
	-- 1: explosions also set what they hit burning (Wildfire).
	ExplosionIgnites = 0,
	-- Seconds a hit slows its target, and extra damage slowed targets take (0.5 = +50%).
	ChillSeconds = 0,
	ChillDamageBonus = 0,
	-- Health restored to the shooter per kill.
	HealOnKill = 0,
	-- Extra damage against elites, champions and the boss (0.5 = +50%).
	HunterBonus = 0,
	-- Times per run a fatal blow leaves you standing at half health instead.
	ExtraLives = 0,
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
		Id = "KeenEdge",
		Title = "Keen Edge",
		Description = "12% chance for a hit to crit for double damage.",
		Category = "Power",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "CritChance", Op = "Add", Value = 0.12 } },
	},
	{
		Id = "TrickShot",
		Title = "Trick Shot",
		Description = "Shots that have ricocheted twice always crit.",
		Category = "Power",
		Rarity = "Rare",
		MaxStacks = 1,
		-- Stored as contacts: the first contact is the hit itself, so two ricochets make three.
		Effects = { { Stat = "TrickShotContacts", Op = "Add", Value = 3 } },
	},
	{
		Id = "Ignite",
		Title = "Ignite",
		Description = "Hits set enemies burning: 1 damage a second for 3s.",
		Category = "Element",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "BurnDamage", Op = "Add", Value = 1 } },
	},
	{
		Id = "ChainArc",
		Title = "Chain Arc",
		Description = "Hits arc to one more nearby enemy for half damage.",
		Category = "Element",
		Rarity = "Rare",
		MaxStacks = 3,
		Effects = { { Stat = "ChainArcs", Op = "Add", Value = 1 } },
	},
	{
		Id = "Volatile",
		Title = "Volatile",
		Description = "Kills explode, dealing 2 damage to everything close by.",
		Category = "Element",
		Rarity = "Rare",
		MaxStacks = 2,
		Effects = { { Stat = "ExplosionDamage", Op = "Add", Value = 2 } },
	},
	{
		Id = "Frostbite",
		Title = "Frostbite",
		Description = "Hits slow enemies by 40% for 2s.",
		Category = "Element",
		Rarity = "Common",
		MaxStacks = 1,
		Effects = { { Stat = "ChillSeconds", Op = "Add", Value = 2 } },
	},
	{
		Id = "Siphon",
		Title = "Siphon",
		Description = "Each kill restores 3 health.",
		Category = "Survival",
		Rarity = "Common",
		MaxStacks = 3,
		Effects = { { Stat = "HealOnKill", Op = "Add", Value = 3 } },
	},
	{
		Id = "Hunter",
		Title = "Hunter",
		Description = "Deal 50% more damage to elites, champions and bosses.",
		Category = "Power",
		Rarity = "Rare",
		MaxStacks = 2,
		Effects = { { Stat = "HunterBonus", Op = "Add", Value = 0.5 } },
	},
	{
		Id = "SecondWind",
		Title = "Second Wind",
		Description = "Once this run, a fatal blow leaves you at half health.",
		Category = "Survival",
		Rarity = "Rare",
		MaxStacks = 1,
		Effects = { { Stat = "ExtraLives", Op = "Add", Value = 1 } },
	},
	{
		Id = "FleetFoot",
		Title = "Fleet Foot",
		Description = "Move 12% faster.",
		Category = "Survival",
		Rarity = "Common",
		MaxStacks = 2,
		Effects = { { Stat = "MoveSpeedBonus", Op = "Add", Value = 2 } },
	},
	-- Evolutions: each needs two different cards, so builds grow toward them.
	{
		Id = "StormConduit",
		Title = "Storm Conduit",
		Description = "Arcs jump to two more enemies and deal full damage.",
		Category = "Element",
		Rarity = "Fused",
		MaxStacks = 1,
		Requires = { Cards = { ChainArc = 2, RicochetCharge = 1 } },
		Effects = {
			{ Stat = "ChainArcs", Op = "Add", Value = 2 },
			{ Stat = "ArcDamageFraction", Op = "Add", Value = 0.5 },
		},
	},
	{
		Id = "Wildfire",
		Title = "Wildfire",
		Description = "Burns hit harder, and explosions set everything alight.",
		Category = "Element",
		Rarity = "Fused",
		MaxStacks = 1,
		Requires = { Cards = { Ignite = 2, Volatile = 1 } },
		Effects = {
			{ Stat = "BurnDamage", Op = "Add", Value = 2 },
			{ Stat = "ExplosionIgnites", Op = "Add", Value = 1 },
		},
	},
	{
		Id = "AbsoluteZero",
		Title = "Absolute Zero",
		Description = "Slowed enemies take 60% more damage, and stay slowed longer.",
		Category = "Element",
		Rarity = "Fused",
		MaxStacks = 1,
		Requires = { Cards = { Frostbite = 1, SharpEdge = 2 } },
		Effects = {
			{ Stat = "ChillDamageBonus", Op = "Add", Value = 0.6 },
			{ Stat = "ChillSeconds", Op = "Add", Value = 1.5 },
		},
	},
	{
		Id = "Deadeye",
		Title = "Deadeye",
		Description = "Crits deal triple damage, and 15% more hits crit.",
		Category = "Power",
		Rarity = "Fused",
		MaxStacks = 1,
		Requires = { Cards = { KeenEdge = 2, TrickShot = 1 } },
		Effects = {
			{ Stat = "CritMultiplier", Op = "Add", Value = 1 },
			{ Stat = "CritChance", Op = "Add", Value = 0.15 },
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
