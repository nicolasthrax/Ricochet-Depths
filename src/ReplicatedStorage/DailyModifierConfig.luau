-- The daily biome modifier: one twist a day for every descent, the same on every server, drawn
-- by the UTC day (MetaConfig.DayOf) so the hub sign, the HUD and the run all agree. The first
-- run of the day to clear a room pays a small bonus, once a day.
--
-- Stats are deltas added to a run's starting stats, exactly like building bonuses. Enemy values
-- multiply the Pact's enemy modifiers; ChampionBonus adds to the champion chance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))

local DailyModifierConfig = {}

DailyModifierConfig.Modifiers = {
	{
		Id = "BouncyWalls",
		Title = "Bouncy Walls",
		Text = "Every shot bounces twice more.",
		Stats = { BounceBudget = 2 },
		Color = Color3.fromRGB(120, 235, 255),
	},
	{
		Id = "GlassDepths",
		Title = "Glass Depths",
		Text = "Enemies have 25% less health. So do you.",
		Stats = { MaxHealthBonus = -25 },
		Enemy = { Health = 0.75 },
		Color = Color3.fromRGB(196, 230, 255),
	},
	{
		Id = "GoldRush",
		Title = "Gold Rush",
		Text = "+25% coins from every run.",
		Stats = { CoinMultiplier = 0.25 },
		Color = Color3.fromRGB(255, 214, 120),
	},
	{
		Id = "ChampionHunt",
		Title = "Champion Hunt",
		Text = "Champions turn up far more often.",
		ChampionBonus = 0.25,
		Color = Color3.fromRGB(226, 160, 255),
	},
	{
		Id = "HeavyOrbs",
		Title = "Heavy Orbs",
		Text = "Shots hit 25% harder but fly 10% slower.",
		Stats = { Damage = 0.25, SpeedMultiplier = -0.1 },
		Color = Color3.fromRGB(255, 150, 70),
	},
	{
		Id = "QuickFeet",
		Title = "Quick Feet",
		Text = "Move faster and dash more often.",
		Stats = { MoveSpeedBonus = 3, DashCooldownMultiplier = -0.25 },
		Color = Color3.fromRGB(140, 236, 168),
	},
	{
		Id = "SurgeDay",
		Title = "Surge Day",
		Text = "Surge fills 50% faster.",
		Stats = { SurgeGain = 0.5 },
		Color = Color3.fromRGB(255, 120, 200),
	},
}

-- Paid once a day, to the first run that clears at least one room.
DailyModifierConfig.Bonus = { Coins = 60, Xp = 40 }

local byId = {}
for _, modifier in DailyModifierConfig.Modifiers do
	byId[modifier.Id] = modifier
end

function DailyModifierConfig.Get(modifierId)
	return byId[modifierId]
end

-- The modifier for a UTC day number.
function DailyModifierConfig.ForDay(day)
	local count = #DailyModifierConfig.Modifiers
	return DailyModifierConfig.Modifiers[(math.floor(tonumber(day) or 0) % count) + 1]
end

-- The modifier in force at a wall-clock time.
function DailyModifierConfig.Today(unixTime)
	return DailyModifierConfig.ForDay(MetaConfig.DayOf(unixTime))
end

-- What clients are shown: the hub sign, the HUD chip and the lobby panel.
function DailyModifierConfig.Describe(modifier, secondsLeft)
	if not modifier then
		return nil
	end
	return {
		Id = modifier.Id,
		Title = modifier.Title,
		Text = modifier.Text,
		Bonus = DailyModifierConfig.Bonus.Coins,
		ResetsIn = secondsLeft,
	}
end

return DailyModifierConfig
