-- Numbers for shot effects (crits, burns, arcs, explosions, chill), champion enemies and co-op
-- revives. Which effects a player has comes from their stats (UpgradeConfig.BaseStats); this
-- only says how strong each one is. No logic lives here.
local CombatConfig = {}

-- Burning: damage lands in ticks, so a burn is a handful of small hits rather than a stream.
CombatConfig.BurnDuration = 3
CombatConfig.BurnTick = 0.5

-- Chain arcs jump from the struck enemy to the nearest others within this range.
CombatConfig.ArcRange = 16

-- Kill explosions (Volatile) hit every enemy within this radius of the kill.
CombatConfig.ExplosionRadius = 9

-- Chilled enemies move at this fraction of their speed.
CombatConfig.ChillSpeedFactor = 0.6

-- Second Wind: the health fraction a spent extra life leaves you with.
CombatConfig.ExtraLifeHealth = 0.5

-- Co-op revives: stand within Radius of a downed teammate for Seconds to bring them back with
-- HealthFraction of their health. Each extra helper speeds it up by HelperBonus. Progress
-- drains at DecayPerSecond when nobody is near.
CombatConfig.Revive = {
	Radius = 9,
	Seconds = 3.5,
	HealthFraction = 0.4,
	HelperBonus = 0.5,
	DecayPerSecond = 0.5,
	-- Grace after a revive, so a teammate is not downed again the instant they stand.
	Invulnerability = 2,
}

-- Champions: tougher versions of ordinary enemies with one affix, a glow and triple coins.
-- Chance is per ordinary enemy per room, by zone; the Depth Pact can add to it. Elites,
-- bosses and anything summoned mid-fight are never champions.
CombatConfig.ChampionChance = {
	Ruins = 0,
	Foundry = 0.08,
	Abyss = 0.12,
}
CombatConfig.ChampionCoinMultiplier = 3
CombatConfig.ChampionXp = 10

CombatConfig.Champions = {
	Armored = {
		Id = "Armored",
		DisplayName = "Armored",
		HealthMultiplier = 2.5,
		Color = Color3.fromRGB(190, 200, 215),
	},
	Swift = {
		Id = "Swift",
		DisplayName = "Swift",
		HealthMultiplier = 1.5,
		SpeedMultiplier = 1.6,
		Color = Color3.fromRGB(120, 255, 200),
	},
	Volatile = {
		Id = "Volatile",
		DisplayName = "Volatile",
		HealthMultiplier = 1.5,
		-- On death it bursts into a ring of orbs: kill it from range.
		DeathRing = { Count = 6, Speed = 16, Damage = 8 },
		Color = Color3.fromRGB(255, 120, 80),
	},
	Mending = {
		Id = "Mending",
		DisplayName = "Mending",
		HealthMultiplier = 2,
		-- Heals this much every Interval seconds, up to its maximum.
		Regen = { Amount = 1, Interval = 2.5 },
		Color = Color3.fromRGB(150, 255, 120),
	},
}
-- Draw order, so a seeded roll always picks the same affix.
CombatConfig.ChampionOrder = { "Armored", "Swift", "Volatile", "Mending" }

return CombatConfig
