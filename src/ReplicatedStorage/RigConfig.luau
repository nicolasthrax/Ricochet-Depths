-- Rigs: the loadout a player descends with. Each one bends the starting stats toward a
-- playstyle, so an unlock changes how you play rather than only how big the numbers are. Rigs
-- unlock by level and are chosen in the lobby. IDs are saved in profiles, so they never change.
--
-- Stats are deltas added to UpgradeConfig.BaseStats before any card is applied, the same way
-- Armory bonuses are, so cards scale from a rig's start exactly as they do from the base.
local RigConfig = {}

RigConfig.DefaultId = "Striker"

RigConfig.Rigs = {
	{
		Id = "Striker",
		Title = "Striker",
		Tagline = "Balanced. Every shot counts.",
		Level = 1,
		Color = Color3.fromRGB(120, 235, 255),
		Stats = {},
	},
	{
		Id = "Scatter",
		Title = "Scatter",
		Tagline = "Two shots at once, a little slower to reload.",
		Level = 3,
		Color = Color3.fromRGB(255, 176, 102),
		Stats = { ProjectilesPerShot = 1, SpreadDegrees = 7, FireCooldownMultiplier = 0.2 },
	},
	{
		Id = "Carom",
		Title = "Carom",
		Tagline = "Lives for the bank shot: more bounces, and each one hurts. Fragile.",
		Level = 5,
		Color = Color3.fromRGB(226, 160, 255),
		Stats = { BounceBudget = 2, DamagePerBounce = 0.5, MaxHealthBonus = -20 },
	},
	{
		Id = "Juggernaut",
		Title = "Juggernaut",
		Tagline = "Soaks punishment and patches up between rooms. Slow.",
		Level = 8,
		Color = Color3.fromRGB(140, 236, 168),
		Stats = { MaxHealthBonus = 60, RoomClearHeal = 20, FireCooldownMultiplier = 0.15, MoveSpeedBonus = -2 },
	},
	{
		Id = "Arcanist",
		Title = "Arcanist",
		Tagline = "Shots burn and arc from the first room. Frail.",
		Level = 12,
		Color = Color3.fromRGB(255, 120, 200),
		Stats = { ChainArcs = 1, BurnDamage = 1, MaxHealthBonus = -20 },
	},
	{
		Id = "Gambler",
		Title = "Gambler",
		Tagline = "Crits often and earns more coins. A glass cannon.",
		Level = 16,
		Color = Color3.fromRGB(255, 214, 120),
		Stats = { CritChance = 0.25, RewardMultiplier = 0.15, MaxHealthBonus = -30 },
	},
}

local byId = {}
for _, rig in RigConfig.Rigs do
	assert(byId[rig.Id] == nil, "duplicate rig id: " .. rig.Id)
	byId[rig.Id] = rig
end

function RigConfig.Get(rigId)
	return type(rigId) == "string" and byId[rigId] or nil
end

function RigConfig.IsUnlocked(rig, level)
	return rig ~= nil and (tonumber(level) or 1) >= rig.Level
end

-- How each stat reads on a rig card, in display order. A rig shows only what it changes.
local STAT_TEXT = {
	{ Stat = "ProjectilesPerShot", Format = function(v) return string.format("%+d projectile", v) end },
	{ Stat = "BounceBudget", Format = function(v) return string.format("%+d bounces", v) end },
	{ Stat = "DamagePerBounce", Format = function(v) return string.format("+%g damage per bounce", v) end },
	{ Stat = "ChainArcs", Format = function(v) return string.format("chain arc x%d", v) end },
	{ Stat = "BurnDamage", Format = function(v) return string.format("ignite %d/s", v) end },
	{ Stat = "CritChance", Format = function(v) return string.format("+%d%% crit", math.floor(v * 100 + 0.5)) end },
	{ Stat = "FireCooldownMultiplier", Format = function(v) return string.format("%d%% slower fire", math.floor(v * 100 + 0.5)) end },
	{ Stat = "MaxHealthBonus", Format = function(v) return string.format("%+d max health", v) end },
	{ Stat = "RoomClearHeal", Format = function(v) return string.format("heal %d per room", v) end },
	{ Stat = "MoveSpeedBonus", Format = function(v) return string.format("%+d speed", v) end },
	{ Stat = "RewardMultiplier", Format = function(v) return string.format("+%d%% coins", math.floor(v * 100 + 0.5)) end },
}

-- "+1 projectile, 20% slower fire" and so on; "No changes" for the default rig.
function RigConfig.Summary(rig)
	local parts = {}
	for _, entry in STAT_TEXT do
		local value = rig and rig.Stats[entry.Stat]
		if type(value) == "number" and value ~= 0 then
			table.insert(parts, entry.Format(value))
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "No changes: the baseline every rig is measured against"
end

-- The rig a profile descends with: its saved choice if that is still unlocked, else the default.
function RigConfig.Resolve(rigId, level)
	local rig = RigConfig.Get(rigId)
	if rig and RigConfig.IsUnlocked(rig, level) then
		return rig
	end
	return byId[RigConfig.DefaultId]
end

return RigConfig
