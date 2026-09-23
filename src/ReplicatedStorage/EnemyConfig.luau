-- Enemy archetypes. IDs are persisted in telemetry and run summaries, so they are stable.
local EnemyConfig = {}

-- Hard ceilings. The spawner refuses past these rather than degrading the frame rate.
EnemyConfig.MaxActive = 28
EnemyConfig.PoolSize = 36

-- Enemies are sized so their body spans the projectile travel plane.
EnemyConfig.BodyHeight = 6

-- Contact damage is only applied this often per enemy, so brushing past is survivable.
EnemyConfig.DefaultContactCooldown = 1

-- Idle pool parts are parked here, invisible, so they cost nothing.
EnemyConfig.StoragePosition = Vector3.new(0, -500, 0)

EnemyConfig.Archetypes = {
	Drifter = {
		Id = "Drifter",
		DisplayName = "Drifter",
		Behaviour = "Sentry",
		Health = 1,
		Size = Vector3.new(3, EnemyConfig.BodyHeight, 3),
		Color = Color3.fromRGB(226, 108, 132),
		Material = Enum.Material.SmoothPlastic,
		MoveSpeed = 2.5,
		-- Sentries wander inside this radius of their spawn so they read as alive without threatening.
		WanderRadius = 7,
		WanderInterval = 2.2,
		ContactDamage = 0,
	},

	Chaser = {
		Id = "Chaser",
		DisplayName = "Chaser",
		Behaviour = "Chaser",
		Health = 2,
		Size = Vector3.new(2.6, EnemyConfig.BodyHeight, 2.6),
		Color = Color3.fromRGB(245, 168, 76),
		Material = Enum.Material.SmoothPlastic,
		MoveSpeed = 13,
		-- Stops short of the player so it threatens without shoving the character around.
		StandoffDistance = 3.5,
		ContactDamage = 10,
		ContactRange = 5,
		ContactCooldown = 1,
	},

	Bulwark = {
		Id = "Bulwark",
		DisplayName = "Bulwark",
		Behaviour = "Lunger",
		Health = 4,
		Size = Vector3.new(4.4, EnemyConfig.BodyHeight, 4.4),
		Color = Color3.fromRGB(118, 196, 214),
		Material = Enum.Material.SmoothPlastic,
		MoveSpeed = 5,
		StandoffDistance = 6,
		ContactDamage = 16,
		ContactRange = 6.5,
		ContactCooldown = 1.3,
		-- Shielded across the front: direct shots bounce off, so the answer is a ricochet
		-- that arrives from the flank or behind.
		Shield = {
			-- Blocked when the incoming heading is within this half-angle of dead-on.
			HalfAngleDegrees = 72,
			DamageMultiplier = 0,
			Color = Color3.fromRGB(226, 246, 252),
			Thickness = 0.6,
			Offset = 2.6,
		},
		-- Telegraphed lunge: it stops, flashes, then commits to a short fast charge.
		Lunge = {
			Interval = 3.4,
			TelegraphTime = 0.7,
			TelegraphColor = Color3.fromRGB(255, 244, 168),
			Duration = 0.55,
			SpeedMultiplier = 4.2,
		},
	},

	WardenCore = {
		Id = "WardenCore",
		DisplayName = "Warden Core",
		Behaviour = "Lunger",
		IsElite = true,
		Health = 14,
		Size = Vector3.new(7, EnemyConfig.BodyHeight, 7),
		Color = Color3.fromRGB(176, 130, 246),
		Material = Enum.Material.Neon,
		MoveSpeed = 6,
		StandoffDistance = 9,
		ContactDamage = 22,
		ContactRange = 9,
		ContactCooldown = 1.2,
		Shield = {
			HalfAngleDegrees = 88,
			DamageMultiplier = 0,
			Color = Color3.fromRGB(236, 220, 255),
			Thickness = 0.8,
			Offset = 4.2,
		},
		Lunge = {
			Interval = 2.6,
			TelegraphTime = 0.85,
			TelegraphColor = Color3.fromRGB(255, 226, 140),
			Duration = 0.7,
			SpeedMultiplier = 5,
		},
	},
}

function EnemyConfig.Get(archetypeId)
	return EnemyConfig.Archetypes[archetypeId]
end

return EnemyConfig
