-- The Depth Pact: optional conditions that make a descent harder in exchange for more coins and
-- experience. Each condition has ranks; every rank adds Heat. It opens after a player's first
-- extraction and is set in the lobby. IDs are saved in profiles, so they never change.
--
-- In a group, each condition runs at the lowest rank anyone in the group chose, so nobody is
-- dragged into a harder descent than they signed up for.
local PactConfig = {}

-- Extractions needed before the Pact opens.
PactConfig.UnlockExtractions = 1
-- Coins and experience from a run grow by this much per point of Heat.
PactConfig.RewardPerHeat = 0.1

PactConfig.Conditions = {
	{
		Id = "Hardened",
		Title = "Hardened Foes",
		Description = "Enemies have 30% more health per rank.",
		MaxRank = 3,
		HeatPerRank = 1,
		Effect = { EnemyHealth = 0.3 },
	},
	{
		Id = "Frenzy",
		Title = "Frenzy",
		Description = "Enemies move 15% faster per rank.",
		MaxRank = 2,
		HeatPerRank = 1,
		Effect = { EnemySpeed = 0.15 },
	},
	{
		Id = "Brutal",
		Title = "Brutal Blows",
		Description = "Enemies hit 25% harder per rank.",
		MaxRank = 3,
		HeatPerRank = 1,
		Effect = { EnemyDamage = 0.25 },
	},
	{
		Id = "Champions",
		Title = "Rising Champions",
		Description = "Champions are 12% more likely per rank, even in the Ruins.",
		MaxRank = 2,
		HeatPerRank = 1,
		Effect = { ChampionChance = 0.12 },
	},
	{
		Id = "Frailty",
		Title = "Frailty",
		Description = "20 less maximum health per rank.",
		MaxRank = 2,
		HeatPerRank = 1,
		Effect = { MaxHealth = -20 },
	},
	{
		Id = "Drought",
		Title = "Drought",
		Description = "No healing between fights.",
		MaxRank = 1,
		HeatPerRank = 2,
		Effect = { NoRegen = 1 },
	},
	{
		Id = "Narrow",
		Title = "Narrow Path",
		Description = "Upgrade choices show two cards, not three.",
		MaxRank = 1,
		HeatPerRank = 2,
		Effect = { FewerCards = 1 },
	},
}

local byId = {}
for _, condition in PactConfig.Conditions do
	assert(byId[condition.Id] == nil, "duplicate pact condition: " .. condition.Id)
	byId[condition.Id] = condition
end

function PactConfig.Get(conditionId)
	return byId[conditionId]
end

-- The highest Heat the Pact can reach.
function PactConfig.MaxHeat()
	local total = 0
	for _, condition in PactConfig.Conditions do
		total += condition.MaxRank * condition.HeatPerRank
	end
	return total
end

-- A clean pact from anything: known conditions only, whole ranks clamped to 0..MaxRank, and
-- zero ranks left out. Arrives from the client, so nothing about it is trusted.
function PactConfig.Sanitise(incoming)
	local pact = {}
	if type(incoming) ~= "table" then
		return pact
	end
	for _, condition in PactConfig.Conditions do
		local rank = incoming[condition.Id]
		if type(rank) == "number" and rank == rank then
			rank = math.clamp(math.floor(rank), 0, condition.MaxRank)
			if rank > 0 then
				pact[condition.Id] = rank
			end
		end
	end
	return pact
end

function PactConfig.Heat(pact)
	local heat = 0
	for conditionId, rank in PactConfig.Sanitise(pact) do
		heat += rank * byId[conditionId].HeatPerRank
	end
	return heat
end

-- A group's pact: each condition at the lowest rank any member chose.
function PactConfig.Merge(pacts)
	if type(pacts) ~= "table" or #pacts == 0 then
		return {}
	end
	local merged = {}
	for _, condition in PactConfig.Conditions do
		local lowest = math.huge
		for _, pact in pacts do
			lowest = math.min(lowest, PactConfig.Sanitise(pact)[condition.Id] or 0)
		end
		if lowest > 0 and lowest < math.huge then
			merged[condition.Id] = lowest
		end
	end
	return merged
end

-- What a pact does to a run, as plain numbers the run loop applies.
function PactConfig.Effects(pact)
	local effects = {
		Heat = 0,
		EnemyHealth = 1,
		EnemySpeed = 1,
		EnemyDamage = 1,
		ChampionBonus = 0,
		MaxHealthDelta = 0,
		NoRegen = false,
		OfferCount = nil,
		RewardMultiplier = 1,
	}
	for conditionId, rank in PactConfig.Sanitise(pact) do
		local effect = byId[conditionId].Effect
		effects.EnemyHealth += (effect.EnemyHealth or 0) * rank
		effects.EnemySpeed += (effect.EnemySpeed or 0) * rank
		effects.EnemyDamage += (effect.EnemyDamage or 0) * rank
		effects.ChampionBonus += (effect.ChampionChance or 0) * rank
		effects.MaxHealthDelta += (effect.MaxHealth or 0) * rank
		if effect.NoRegen then
			effects.NoRegen = true
		end
		if effect.FewerCards then
			effects.OfferCount = 2
		end
	end
	effects.Heat = PactConfig.Heat(pact)
	effects.RewardMultiplier = 1 + effects.Heat * PactConfig.RewardPerHeat
	return effects
end

function PactConfig.IsUnlocked(extractions)
	return (tonumber(extractions) or 0) >= PactConfig.UnlockExtractions
end

return PactConfig
