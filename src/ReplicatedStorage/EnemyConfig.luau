-- Enemy archetypes. IDs are persisted in telemetry and run summaries, so they are stable.
local EnemyConfig = {}

-- Hard ceilings. The spawner refuses past these rather than degrading the frame rate.
-- Raised for 2.0's swarms: a pack of Mites is eight bodies on its own.
EnemyConfig.MaxActive = 40
EnemyConfig.PoolSize = 48

-- Enemies are sized so their body spans the projectile travel plane.
EnemyConfig.BodyHeight = 6

-- Contact damage is only applied this often per enemy, so brushing past is survivable.
EnemyConfig.DefaultContactCooldown = 1

-- Idle pool parts are parked here, invisible, so they cost nothing.
EnemyConfig.StoragePosition = Vector3.new(0, -500, 0)

-- Enemy orbs (Sentinel shots, the boss's rings): slow, glowing and dodgeable. They fly on the
-- travel plane, burn the first player they reach, and die on cover and walls. Player shots
-- pass straight through them.
EnemyConfig.OrbPoolSize = 48
EnemyConfig.OrbSize = 1.4
EnemyConfig.OrbHitRadius = 2.2 -- orb radius plus a character's
EnemyConfig.OrbLifetime = 6
EnemyConfig.OrbColor = Color3.fromRGB(255, 96, 120)

EnemyConfig.Archetypes = {
	Drifter = {
		Id = "Drifter",
		DisplayName = "Drifter",
		Coins = 1, -- dropped as pickups when it dies
		Behaviour = "Sentry",
		-- 2.0: a straight shot needs two hits; one bounce and a straight shot, or two bounces,
		-- do it in one. Bank shots multiply damage now (ArsenalConfig.Bounce).
		Health = 2,
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
		Coins = 2, -- dropped as pickups when it dies
		Behaviour = "Chaser",
		-- 2.0 dry run: at 3 they did ~70% of the damage in the Ruins' second room. 2.5 is two
		-- hits if either one banks.
		Health = 2.5,
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
		Coins = 6, -- dropped as pickups when it dies
		Behaviour = "Lunger",
		Health = 6,
		Size = Vector3.new(4.4, EnemyConfig.BodyHeight, 4.4),
		Color = Color3.fromRGB(118, 196, 214),
		Material = Enum.Material.SmoothPlastic,
		MoveSpeed = 5,
		StandoffDistance = 6,
		-- Playtest: too punishing. Was 16.
		ContactDamage = 12,
		ContactRange = 6.5,
		ContactCooldown = 1.3,
		-- Shielded across one side: direct shots into it bounce off. Playtest: a shield that
		-- always faced the player was too hard, so it now turns steadily on its own and its
		-- back comes round every few seconds; banking round it still works any time.
		Shield = {
			-- Blocked when the incoming heading is within this half-angle of the shield's heading.
			HalfAngleDegrees = 62,
			-- Degrees per second the shield turns, independent of where the Bulwark walks.
			SpinSpeed = 70,
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
		Coins = 30, -- dropped as pickups when it dies
		Behaviour = "Lunger",
		IsElite = true,
		Health = 22,
		Size = Vector3.new(7, EnemyConfig.BodyHeight, 7),
		Color = Color3.fromRGB(176, 130, 246),
		Material = Enum.Material.Neon,
		MoveSpeed = 6,
		StandoffDistance = 9,
		-- Dry run: once the Bulwark eased off, this was where runs ended (~100 damage each).
		ContactDamage = 16,
		ContactRange = 9,
		ContactCooldown = 1.2,
		Shield = {
			HalfAngleDegrees = 80,
			SpinSpeed = 50,
			DamageMultiplier = 0,
			Color = Color3.fromRGB(236, 220, 255),
			Thickness = 0.8,
			Offset = 4.2,
		},
		Lunge = {
			Interval = 3.4,
			TelegraphTime = 0.85,
			TelegraphColor = Color3.fromRGB(255, 226, 140),
			Duration = 0.7,
			SpeedMultiplier = 5,
		},
	},
}

-- Foundry: splits into two fast Shards when it dies.
EnemyConfig.Archetypes.Splitter = {
	Id = "Splitter",
	DisplayName = "Splitter",
		Coins = 3, -- dropped as pickups when it dies
	Behaviour = "Chaser",
	Health = 3,
	Size = Vector3.new(3.2, EnemyConfig.BodyHeight, 3.2),
	Color = Color3.fromRGB(116, 214, 150),
	Material = Enum.Material.SmoothPlastic,
	MoveSpeed = 8,
	StandoffDistance = 3.5,
	ContactDamage = 10,
	ContactRange = 5,
	ContactCooldown = 1,
	SplitInto = { Archetype = "Shard", Count = 2, Spread = 2.5 },
}

EnemyConfig.Archetypes.Shard = {
	Id = "Shard",
	DisplayName = "Shard",
		Coins = 1, -- dropped as pickups when it dies
	Behaviour = "Chaser",
	Health = 1,
	Size = Vector3.new(1.8, EnemyConfig.BodyHeight, 1.8),
	Color = Color3.fromRGB(170, 255, 196),
	Material = Enum.Material.SmoothPlastic,
	MoveSpeed = 15,
	StandoffDistance = 3,
	ContactDamage = 6,
	ContactRange = 4,
	ContactCooldown = 0.8,
}

-- Foundry and Abyss: a stationary turret. It turns to face the nearest player, flashes, then
-- fires a slow orb at where they stand.
EnemyConfig.Archetypes.Sentinel = {
	Id = "Sentinel",
	DisplayName = "Sentinel",
		Coins = 4, -- dropped as pickups when it dies
	Behaviour = "Turret",
	Health = 4,
	Size = Vector3.new(3.4, EnemyConfig.BodyHeight, 3.4),
	Color = Color3.fromRGB(232, 84, 96),
	Material = Enum.Material.SmoothPlastic,
	MoveSpeed = 0,
	ContactDamage = 0,
	ReplicateFacing = true,
	Fire = {
		Interval = 2.6,
		TelegraphTime = 0.6,
		TelegraphColor = Color3.fromRGB(255, 220, 150),
		Speed = 22,
		Damage = 10,
	},
}

-- Abyss: closes like a Chaser, but every few seconds flickers out and reappears beside a
-- player. Untouchable while blinking, so the answer is to shoot it before it goes.
EnemyConfig.Archetypes.Phaser = {
	Id = "Phaser",
	DisplayName = "Phaser",
		Coins = 4, -- dropped as pickups when it dies
	Behaviour = "Phaser",
	Health = 3,
	Size = Vector3.new(2.6, EnemyConfig.BodyHeight, 2.6),
	Color = Color3.fromRGB(120, 200, 255),
	Material = Enum.Material.SmoothPlastic,
	MoveSpeed = 9,
	StandoffDistance = 4,
	ContactDamage = 12,
	ContactRange = 5,
	ContactCooldown = 1.1,
	Blink = {
		Interval = 3.5,
		TelegraphTime = 0.5,
		TelegraphColor = Color3.fromRGB(230, 240, 255),
		Duration = 0.4,
		MinRadius = 10,
		MaxRadius = 18,
	},
}

-- The final boss. Three phases by remaining health:
--   1. its shield spins on its own, so the player times shots through the gap or banks them
--   2. the shield tracks the player; it summons Shards and fires rings of orbs
--   3. the shield breaks; it moves faster and fires denser, spiralling rings
EnemyConfig.Archetypes.WardenPrime = {
	Id = "WardenPrime",
	DisplayName = "Warden Prime",
		Coins = 80, -- dropped as pickups when it dies
	Behaviour = "Boss",
	IsBoss = true,
	-- Dry run history: 36 fell in ~6s; at 80 no bot out-lasted its contact hits. 60 is a first
	-- guess for humans, who kite far better than the bots (it moves at 4, a player at 16).
	-- 2.0: bank shots now multiply damage, so the Warden needs more to chew through.
	Health = 95,
	Size = Vector3.new(9, EnemyConfig.BodyHeight, 9),
	Color = Color3.fromRGB(200, 120, 255),
	Material = Enum.Material.Neon,
	MoveSpeed = 4,
	StandoffDistance = 9,
	ContactDamage = 16,
	ContactRange = 10,
	ContactCooldown = 1.6,
	Shield = {
		HalfAngleDegrees = 80,
		DamageMultiplier = 0,
		Color = Color3.fromRGB(240, 226, 255),
		Thickness = 1,
		Offset = 5.6,
	},
	-- Dry run: bots (which never dodge) took ~120 damage here. Humans dodge; still eased.
	Orb = { Speed = 18, Damage = 6 },
	Phases = {
		{ Below = 1.01, Shield = "Spin", SpinSpeed = 90, MoveSpeedMultiplier = 1 },
		{
			Below = 0.6,
			Shield = "Track",
			MoveSpeedMultiplier = 1,
			Summon = "Shard",
			SummonCount = 2,
			SummonInterval = 6,
			SummonMax = 4,
			RingInterval = 4,
			RingCount = 8,
		},
		{ Below = 0.25, Shield = "None", MoveSpeedMultiplier = 1.6, RingInterval = 3.2, RingCount = 12, RingTwist = 15 },
	},
}

--// 2.0: swarms, ricochet-aware enemies, a treasure runner and two mini-bosses ------------

-- Swarm fodder: one hit, arrives in packs. Worth little alone; a pile as a combo chain.
EnemyConfig.Archetypes.Mite = {
	Id = "Mite",
	DisplayName = "Mite",
	Coins = 1,
	Behaviour = "Chaser",
	Health = 1,
	Size = Vector3.new(1.8, EnemyConfig.BodyHeight, 1.8),
	Color = Color3.fromRGB(255, 120, 150),
	Material = Enum.Material.SmoothPlastic,
	MoveSpeed = 10,
	StandoffDistance = 2.5,
	ContactDamage = 4,
	ContactRange = 3.5,
	ContactCooldown = 0.9,
}

-- Polished all over: a shot that has not bounced first glances off. Bank it.
EnemyConfig.Archetypes.Mirror = {
	Id = "Mirror",
	DisplayName = "Mirror",
	Coins = 3,
	Behaviour = "Chaser",
	Health = 3,
	RequiresBank = true,
	Size = Vector3.new(2.8, EnemyConfig.BodyHeight, 2.8),
	Color = Color3.fromRGB(214, 230, 245),
	Material = Enum.Material.Glass,
	-- Slow and soft-hitting: it is a lesson in banking, not a wall.
	MoveSpeed = 5.5,
	StandoffDistance = 4,
	ContactDamage = 7,
	ContactRange = 5,
	ContactCooldown = 1.2,
}

-- Soaks up a shot's remaining bounces: whatever hits it stops dead there.
EnemyConfig.Archetypes.Sponge = {
	Id = "Sponge",
	DisplayName = "Sponge",
	Coins = 3,
	Behaviour = "Chaser",
	Health = 5,
	AbsorbsBounces = true,
	Size = Vector3.new(3.6, EnemyConfig.BodyHeight, 3.6),
	Color = Color3.fromRGB(196, 170, 96),
	Material = Enum.Material.Sand,
	MoveSpeed = 5,
	StandoffDistance = 4,
	ContactDamage = 12,
	ContactRange = 5.5,
	ContactCooldown = 1.2,
}

-- Bends every shot that passes near it toward itself. A nuisance, or a free aim-assist.
EnemyConfig.Archetypes.Magnet = {
	Id = "Magnet",
	DisplayName = "Magnet",
	Coins = 4,
	Behaviour = "Sentry",
	Health = 4,
	Size = Vector3.new(3, EnemyConfig.BodyHeight, 3),
	Color = Color3.fromRGB(230, 70, 90),
	Material = Enum.Material.Metal,
	MoveSpeed = 3,
	WanderRadius = 8,
	WanderInterval = 2.5,
	ContactDamage = 0,
	-- Shots within Radius turn toward it at Strength (radians of heading per second).
	Magnet = { Radius = 20, Strength = 3.2 },
}

-- A big, slow Splitter that bursts into three Splitters (which burst into Shards).
EnemyConfig.Archetypes.SplitterKing = {
	Id = "SplitterKing",
	DisplayName = "Splitter King",
	Coins = 8,
	Behaviour = "Chaser",
	Health = 10,
	IsElite = true,
	Size = Vector3.new(5, EnemyConfig.BodyHeight, 5),
	Color = Color3.fromRGB(90, 220, 140),
	Material = Enum.Material.SmoothPlastic,
	MoveSpeed = 4,
	StandoffDistance = 5,
	ContactDamage = 14,
	ContactRange = 7,
	ContactCooldown = 1.3,
	SplitInto = { Archetype = "Splitter", Count = 3, Spread = 4 },
}

-- A thief with a full sack. Runs from you, and escapes with it if not caught in time. It never
-- holds a room open: Optional enemies do not count toward clearing it.
EnemyConfig.Archetypes.TreasureRunner = {
	Id = "TreasureRunner",
	DisplayName = "Treasure Runner",
	Coins = 45,
	Behaviour = "Runner",
	Optional = true,
	EscapeAfter = 16,
	Health = 7,
	Size = Vector3.new(2.4, EnemyConfig.BodyHeight, 2.4),
	Color = Color3.fromRGB(255, 214, 90),
	Material = Enum.Material.Neon,
	MoveSpeed = 12,
	ContactDamage = 0,
}

-- Ruins mini-boss: a lumbering statue with a turning shield. It stomps out rings of orbs and,
-- once hurt, shakes Mites loose.
EnemyConfig.Archetypes.Colossus = {
	Id = "Colossus",
	DisplayName = "The Colossus",
	Coins = 40,
	Behaviour = "Colossus",
	IsMiniBoss = true,
	Health = 40,
	Size = Vector3.new(8, EnemyConfig.BodyHeight, 8),
	Color = Color3.fromRGB(170, 160, 140),
	Material = Enum.Material.Slate,
	MoveSpeed = 3.5,
	StandoffDistance = 8,
	ContactDamage = 18,
	ContactRange = 9,
	ContactCooldown = 1.5,
	Shield = {
		HalfAngleDegrees = 70,
		SpinSpeed = 55,
		DamageMultiplier = 0,
		Color = Color3.fromRGB(236, 226, 200),
		Thickness = 1,
		Offset = 5,
	},
	Stomp = {
		Interval = 4.5,
		TelegraphTime = 1,
		TelegraphColor = Color3.fromRGB(255, 200, 120),
		RingCount = 10,
		Speed = 17,
		Damage = 8,
		-- Below this fraction of health it also summons Mites with each stomp.
		SummonBelow = 0.6,
		Summon = "Mite",
		SummonCount = 3,
		SummonMax = 8,
	},
}

-- Foundry mini-boss: a hovering press. It glides over a player, flashes, and slams the floor
-- beneath it, throwing out a ring of sparks. Keep moving.
EnemyConfig.Archetypes.ForgePress = {
	Id = "ForgePress",
	DisplayName = "The Forge Press",
	Coins = 45,
	Behaviour = "Press",
	IsMiniBoss = true,
	Health = 45,
	Size = Vector3.new(7, EnemyConfig.BodyHeight, 7),
	Color = Color3.fromRGB(255, 140, 60),
	Material = Enum.Material.CorrodedMetal,
	MoveSpeed = 10,
	ContactDamage = 0,
	Slam = {
		Interval = 3.2,
		TelegraphTime = 1.1,
		TelegraphColor = Color3.fromRGB(255, 70, 50),
		Radius = 10,
		Damage = 22,
		RingCount = 8,
		Speed = 20,
		OrbDamage = 7,
	},
}

function EnemyConfig.Get(archetypeId)
	return EnemyConfig.Archetypes[archetypeId]
end

return EnemyConfig
