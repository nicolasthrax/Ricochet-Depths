-- The player's kit: orbs (a limited number of shots that must be recovered), bounce power (every
-- ricochet makes a shot stronger), the dash, the combo meter and the Surge meter. These are the
-- moment-to-moment systems; the numbers live here and nowhere else.
local ArsenalConfig = {}

-- Orbs. A player carries OrbCount (a stat, UpgradeConfig.BaseStats) orbs. A throw spends one;
-- the orb flies its bounces, drops where it stops, and is picked up by walking over it. Left
-- alone, it rolls home by itself, so an orb is never lost. A kill off TrickShotBounces or more
-- wall bounces sends the orb straight back to hand.
ArsenalConfig.Orbs = {
	PoolSize = 48,
	PickupRadius = 5,
	-- Seconds an orb lies where it fell before rolling back on its own. Dry run: at 1.6s and 38
	-- studs/s, a player who never fetched an orb threw about once a second and was overrun in
	-- the Ruins; picking orbs up should be the faster choice, not the only one.
	ReturnDelay = 1,
	-- Studs per second an orb rolls home, and how fast a recalled orb flies.
	ReturnSpeed = 52,
	RecallSpeed = 110,
	TrickShotBounces = 2,
	Size = 1.6,
	-- Floor orbs float just above the ground so they read as pickups, not cover.
	Height = 1.2,
	Color = Color3.fromRGB(120, 235, 255),
	StoragePosition = Vector3.new(0, -500, 0),
}

-- Bounce power: every wall, cover or reflector bounce adds DamagePerBounce (a fraction of the
-- shot's damage, the BouncePower stat) and SpeedPerBounce, and the shot grows and changes colour
-- so its power reads at a glance.
ArsenalConfig.Bounce = {
	SpeedPerBounce = 0.08,
	MaxSpeedMultiplier = 1.5,
	GrowPerBounce = 0.22,
	MaxGrowth = 2.2,
	-- The shot's colour after 0, 1, 2, 3, 4+ bounces: cool to hot.
	Colors = {
		Color3.fromRGB(120, 235, 255),
		Color3.fromRGB(140, 255, 170),
		Color3.fromRGB(255, 226, 110),
		Color3.fromRGB(255, 150, 70),
		Color3.fromRGB(255, 90, 200),
	},
}

function ArsenalConfig.BounceColor(bounces)
	local colors = ArsenalConfig.Bounce.Colors
	return colors[math.clamp(math.floor(bounces) + 1, 1, #colors)]
end

-- The dash: a short burst of movement with a moment of invulnerability. The client moves its
-- own character (it owns its physics); the server keeps the cooldown and grants the i-frames.
ArsenalConfig.Dash = {
	Cooldown = 2.2,
	Distance = 15,
	Duration = 0.17,
	Invulnerability = 0.35,
	-- Width of the path a Blink Strike dash hits.
	StrikeRadius = 4,
	-- Slack for the client's clock running a little ahead of the server's.
	ClockSlack = 0.15,
}

-- Combo: kills in quick succession build a count; the tier it reaches multiplies the coins its
-- kills drop and the experience they earn. Ricochet kills count double. Taking damage halves it,
-- and it runs out after Window seconds without a kill.
ArsenalConfig.Combo = {
	Window = 3.5,
	RicochetBonus = 1,
	HitKeeps = 0.5,
	Tiers = {
		{ At = 0, Multiplier = 1, Name = "" },
		{ At = 6, Multiplier = 1.5, Name = "HOT" },
		{ At = 14, Multiplier = 2, Name = "BLAZING" },
		{ At = 26, Multiplier = 3, Name = "UNSTOPPABLE" },
		{ At = 45, Multiplier = 4, Name = "GODLIKE" },
	},
}

-- The tier table entry and its index for a combo count.
function ArsenalConfig.ComboTier(count)
	local tiers = ArsenalConfig.Combo.Tiers
	for index = #tiers, 1, -1 do
		if (count or 0) >= tiers[index].At then
			return tiers[index], index
		end
	end
	return tiers[1], 1
end

-- Surge: kills fill a meter; a full meter offers three small perks mid-fight, picked with a tap
-- or 1/2/3 while you keep playing. Each level needs a little more than the last.
ArsenalConfig.Surge = {
	Base = 9,
	Growth = 4,
	-- Points per kill, plus a bonus for a ricochet kill. Scaled by the SurgeGain stat.
	PerKill = 1,
	RicochetBonus = 1,
	-- Big enemies are worth more.
	EliteKill = 4,
	ChoiceTimeout = 9,
	Offers = 3,
}

function ArsenalConfig.SurgeNeeded(level)
	return ArsenalConfig.Surge.Base + ArsenalConfig.Surge.Growth * math.max((level or 1) - 1, 0)
end

return ArsenalConfig
