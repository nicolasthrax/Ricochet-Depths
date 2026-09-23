-- Room layouts, built at runtime by RoomBuilder. Nothing here is a committed binary model.
local RoomConfig = {}

RoomConfig.FloorY = 0
RoomConfig.WallHeight = 14
RoomConfig.WallThickness = 2
RoomConfig.FloorThickness = 2

-- Dark floor, lighter walls: bounce planes must read against the ground at a glance. Floor
-- colours and materials come from each zone's style (RoomConfig.Zones, below).
RoomConfig.WallColor = Color3.fromRGB(88, 96, 118)
RoomConfig.ObstacleColor = Color3.fromRGB(70, 78, 98)
-- Bevels and reflectors: brighter and metallic, so they never read as ordinary cover.
RoomConfig.BumperColor = Color3.fromRGB(150, 160, 184)
RoomConfig.BumperMaterial = Enum.Material.DiamondPlate

-- Decor is cosmetic only: non-colliding, non-queryable, and kept off the projectile plane.
RoomConfig.Decor = {
	GridSpacing = 8,
	GridLineWidth = 0.25,
	-- Two-tone checker under the grid, so distance and angle read at a glance. Its colours and
	-- the grid's come from the zone style.
	TileSize = 16,
	-- Neon hazard trim on every bevel and reflector: "this surface is for banking".
	HazardColor = Color3.fromRGB(255, 184, 64),
	-- A glowing floor line just inside each wall marks the playable edge.
	BorderInset = 1.5,
	BorderWidth = 0.35,
	-- Neon strips capping every wall and pillar, and a glow line where walls meet the floor.
	TrimColor = Color3.fromRGB(190, 210, 255),
	TopTrimHeight = 0.5,
	BaseTrimHeight = 0.35,
	-- How far trims stand proud of the surface they outline, so they are not z-fighting.
	TrimInset = 0.05,
	-- Bank-shot trims are this much taller than wall trims where the two overlap.
	HazardTrimLift = 0.12,
	-- Height between floor layers (tiles, grid, border). Must stay >= 0.05 or they shimmer.
	LayerStep = 0.08,
	-- The glowing square inset on top of the spawn pad.
	SpawnRingWidth = 0.4,
	SpawnRingHeight = 0.08,
	SpawnRingInset = 0.6,
}

RoomConfig.SpawnPadSize = Vector3.new(8, 0.4, 8)

-- Angled bank-shot geometry (see RoomGeometry). Bevels cut the four inner corners at 45
-- degrees; reflectors are free-standing 45 degree slabs placed to open flank angles.
RoomConfig.BevelDepth = 2
RoomConfig.ReflectorThickness = 2
-- Enemies are held this far (in |x| + |z| terms) in front of a bevel face, so the widest body
-- cannot be pushed into the sealed triangle behind it where no shot can reach.
RoomConfig.BevelEnemyClearance = 8

-- Each layout is interior size, pillar footprints, and enemy spawn markers, all as XZ offsets
-- from the room centre. Layouts are chosen by RunConfig.Rooms.
RoomConfig.Layouts = {
	-- Open and forgiving: long sightlines so a first ricochet is easy to land.
	Atrium = {
		Zone = "Ruins",
		DisplayName = "Collapsed Atrium",
		TrimColor = Color3.fromRGB(190, 210, 255),
		InteriorSize = Vector2.new(120, 120),
		AccentColor = Color3.fromRGB(96, 104, 128),
		Obstacles = {
			{ Offset = Vector2.new(-30, 24), Size = Vector2.new(10, 10) },
			{ Offset = Vector2.new(30, 24), Size = Vector2.new(10, 10) },
			{ Offset = Vector2.new(0, -28), Size = Vector2.new(20, 8) },
		},
		CornerBevel = 12,
		-- Flank bumpers either side of the low wall: a shot fired across the room turns 90
		-- degrees into the lanes behind it.
		Reflectors = {
			{ Offset = Vector2.new(-38, -24), Length = 14, Yaw = 45 },
			{ Offset = Vector2.new(38, -24), Length = 14, Yaw = -45 },
		},
		EnemySpawns = {
			Vector2.new(-42, 42), Vector2.new(0, 48), Vector2.new(42, 42),
			Vector2.new(-46, -6), Vector2.new(46, -6), Vector2.new(0, 20),
			Vector2.new(-24, -44), Vector2.new(24, -44),
		},
	},

	-- Tighter, with a central spine that rewards banking shots around cover.
	Gallery = {
		Zone = "Ruins",
		DisplayName = "Shattered Gallery",
		TrimColor = Color3.fromRGB(222, 196, 255),
		InteriorSize = Vector2.new(104, 132),
		AccentColor = Color3.fromRGB(110, 92, 128),
		Obstacles = {
			-- Shifted off the origin: as a centred spine it covered the player spawn point, and
			-- nearer than 20 studs it closed the spawn's northward line.
			{ Offset = Vector2.new(0, 34), Size = Vector2.new(8, 24) },
			{ Offset = Vector2.new(-32, -26), Size = Vector2.new(16, 8) },
			{ Offset = Vector2.new(32, -26), Size = Vector2.new(16, 8) },
			{ Offset = Vector2.new(-34, 40), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(34, 40), Size = Vector2.new(8, 8) },
		},
		CornerBevel = 10,
		-- At the top of each side lane: a shot sent up a lane turns in behind the spine. Kept
		-- off every line from the spawn to a marker, where they only blocked direct fire.
		Reflectors = {
			{ Offset = Vector2.new(-18, 50), Length = 12, Yaw = -45 },
			{ Offset = Vector2.new(18, 50), Length = 12, Yaw = 45 },
		},
		EnemySpawns = {
			Vector2.new(-38, 52), Vector2.new(38, 52), Vector2.new(-38, 8),
			Vector2.new(38, 8), Vector2.new(-16, -50), Vector2.new(16, -50),
			Vector2.new(-44, -12), Vector2.new(44, -12),
		},
	},

	-- Diagonal cover: almost every safe angle here is a bank shot.
	Crossing = {
		Zone = "Ruins",
		DisplayName = "Fractured Crossing",
		TrimColor = Color3.fromRGB(255, 214, 176),
		InteriorSize = Vector2.new(132, 112),
		AccentColor = Color3.fromRGB(128, 100, 84),
		-- Room 3 difficulty pass: the long bars moved outward and the centre pair (which sat
		-- either side of the spawn, closing east and west) moved onto the north-south axis, so
		-- the player starts with all eight directions open.
		Obstacles = {
			{ Offset = Vector2.new(-32, 20), Size = Vector2.new(26, 8) },
			{ Offset = Vector2.new(32, -20), Size = Vector2.new(26, 8) },
			{ Offset = Vector2.new(-30, -28), Size = Vector2.new(8, 24) },
			{ Offset = Vector2.new(30, 28), Size = Vector2.new(8, 24) },
			{ Offset = Vector2.new(0, 30), Size = Vector2.new(12, 8) },
			{ Offset = Vector2.new(0, -30), Size = Vector2.new(12, 8) },
		},
		CornerBevel = 12,
		-- Room 3 difficulty pass: reflectors that bank shots into the open ground around each
		-- Bulwark, so a shielded enemy's back is always one bounce away.
		Reflectors = {
			{ Offset = Vector2.new(-24, 40), Length = 14, Yaw = 45 },
			{ Offset = Vector2.new(24, -40), Length = 14, Yaw = 45 },
		},
		EnemySpawns = {
			Vector2.new(-52, 44), Vector2.new(52, 44), Vector2.new(-52, -44),
			Vector2.new(52, -44), Vector2.new(0, 46), Vector2.new(0, -46),
			Vector2.new(-56, 0), Vector2.new(56, 0),
			-- 9: the Bulwark's post. Clear of walls and cover on every side, so the ground
			-- around it is open for a flanking ricochet.
			Vector2.new(-48, 34),
		},
	},

	-- Boss arena: wide, few pillars, so the fight is about angles rather than cover.
	WardenVault = {
		Zone = "Abyss",
		DisplayName = "Warden Vault",
		TrimColor = Color3.fromRGB(206, 186, 255),
		InteriorSize = Vector2.new(140, 140),
		AccentColor = Color3.fromRGB(122, 96, 160),
		Obstacles = {
			{ Offset = Vector2.new(-44, 44), Size = Vector2.new(12, 12) },
			{ Offset = Vector2.new(44, 44), Size = Vector2.new(12, 12) },
			{ Offset = Vector2.new(-44, -44), Size = Vector2.new(12, 12) },
			{ Offset = Vector2.new(44, -44), Size = Vector2.new(12, 12) },
		},
		CornerBevel = 14,
		-- Bumpers facing the centre: the core's shield turns to face you, and these send a
		-- shot round behind it.
		Reflectors = {
			{ Offset = Vector2.new(-30, -30), Length = 14, Yaw = 45 },
			{ Offset = Vector2.new(30, 30), Length = 14, Yaw = 45 },
		},
		EnemySpawns = {
			Vector2.new(0, 40), Vector2.new(-40, 0), Vector2.new(40, 0),
			Vector2.new(0, -40), Vector2.new(-28, 28), Vector2.new(28, -28),
		},
	},

	-- Upper Ruins, tier 1: a ring of four pillars around a flooded floor. Wide lanes between
	-- them, and side bumpers that turn a shot along the room's cross axis.
	Cistern = {
		Zone = "Ruins",
		DisplayName = "Drowned Cistern",
		TrimColor = Color3.fromRGB(176, 226, 255),
		InteriorSize = Vector2.new(112, 112),
		AccentColor = Color3.fromRGB(84, 108, 126),
		Obstacles = {
			{ Offset = Vector2.new(-28, 28), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(28, 28), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(-28, -28), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(28, -28), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(0, 40), Size = Vector2.new(20, 6) },
			{ Offset = Vector2.new(0, -40), Size = Vector2.new(20, 6) },
		},
		CornerBevel = 12,
		Reflectors = {
			{ Offset = Vector2.new(-42, 0), Length = 12, Yaw = 45 },
			{ Offset = Vector2.new(42, 0), Length = 12, Yaw = -45 },
		},
		EnemySpawns = {
			Vector2.new(-40, 40), Vector2.new(40, 40), Vector2.new(-40, -40), Vector2.new(40, -40),
			Vector2.new(0, 26), Vector2.new(0, -26), Vector2.new(-24, 0), Vector2.new(24, 0),
		},
	},

	-- Foundry, tier 1: two cold furnaces either side of the spawn and a long conveyor bar to
	-- the south. Shots bank off the furnace faces into the lanes behind them.
	Smelter = {
		Zone = "Foundry",
		DisplayName = "Cold Smelter",
		TrimColor = Color3.fromRGB(255, 176, 96),
		InteriorSize = Vector2.new(124, 108),
		AccentColor = Color3.fromRGB(116, 88, 70),
		Obstacles = {
			{ Offset = Vector2.new(-34, 18), Size = Vector2.new(14, 14) },
			{ Offset = Vector2.new(34, 18), Size = Vector2.new(14, 14) },
			{ Offset = Vector2.new(0, -34), Size = Vector2.new(40, 6) },
		},
		CornerBevel = 12,
		Reflectors = {
			{ Offset = Vector2.new(-44, -28), Length = 12, Yaw = -45 },
			{ Offset = Vector2.new(44, -28), Length = 12, Yaw = 45 },
		},
		EnemySpawns = {
			Vector2.new(-44, 38), Vector2.new(44, 38), Vector2.new(0, 40), Vector2.new(-52, 0),
			Vector2.new(52, 0), Vector2.new(-22, -46), Vector2.new(22, -46), Vector2.new(0, 18),
		},
	},

	-- Foundry, tier 1: a wide hall of staggered conveyor bars. Every lane is long, and the two
	-- bumpers at the head of the hall fold shots back down it.
	Conveyor = {
		Zone = "Foundry",
		DisplayName = "Stalled Conveyor",
		TrimColor = Color3.fromRGB(255, 200, 112),
		InteriorSize = Vector2.new(136, 100),
		AccentColor = Color3.fromRGB(108, 94, 76),
		Obstacles = {
			{ Offset = Vector2.new(-40, 16), Size = Vector2.new(24, 6) },
			{ Offset = Vector2.new(0, -26), Size = Vector2.new(24, 6) },
			{ Offset = Vector2.new(40, 16), Size = Vector2.new(24, 6) },
		},
		CornerBevel = 10,
		Reflectors = {
			{ Offset = Vector2.new(-20, 36), Length = 12, Yaw = 45 },
			{ Offset = Vector2.new(20, 36), Length = 12, Yaw = -45 },
		},
		EnemySpawns = {
			Vector2.new(-54, 34), Vector2.new(54, 34), Vector2.new(-54, -30), Vector2.new(54, -30),
			Vector2.new(0, 38), Vector2.new(-28, -38), Vector2.new(28, -38), Vector2.new(0, -40),
		},
	},

	-- Foundry, tier 2: a square crucible ringed by four slag walls, with gaps on every axis.
	-- The Bulwark holds the west gap; the slag walls and the bumpers bank shots round it.
	Crucible = {
		Zone = "Foundry",
		DisplayName = "The Crucible",
		TrimColor = Color3.fromRGB(255, 150, 90),
		InteriorSize = Vector2.new(116, 116),
		AccentColor = Color3.fromRGB(122, 82, 66),
		Obstacles = {
			{ Offset = Vector2.new(-28, 28), Size = Vector2.new(16, 6) },
			{ Offset = Vector2.new(28, 28), Size = Vector2.new(16, 6) },
			{ Offset = Vector2.new(-28, -28), Size = Vector2.new(16, 6) },
			{ Offset = Vector2.new(28, -28), Size = Vector2.new(16, 6) },
		},
		CornerBevel = 14,
		Reflectors = {
			{ Offset = Vector2.new(0, 44), Length = 14, Yaw = 45 },
			{ Offset = Vector2.new(0, -44), Length = 14, Yaw = -45 },
		},
		EnemySpawns = {
			Vector2.new(-42, 42), Vector2.new(42, 42), Vector2.new(-42, -42), Vector2.new(42, -42),
			Vector2.new(0, 24), Vector2.new(0, -24), Vector2.new(-24, 0), Vector2.new(24, 0),
			-- 9: the Bulwark's post, off the west gap with open floor on every side.
			Vector2.new(-42, 0),
		},
	},

	-- Foundry, tier 2: a long works floor split by offset benches. A diagonal pair of bumpers
	-- turns shots round the benches, and the Bulwark waits at the far end.
	Forgeworks = {
		Zone = "Foundry",
		DisplayName = "Forgeworks",
		TrimColor = Color3.fromRGB(255, 186, 120),
		InteriorSize = Vector2.new(140, 112),
		AccentColor = Color3.fromRGB(112, 90, 80),
		Obstacles = {
			{ Offset = Vector2.new(-36, 24), Size = Vector2.new(8, 20) },
			{ Offset = Vector2.new(36, -24), Size = Vector2.new(8, 20) },
			{ Offset = Vector2.new(-8, 40), Size = Vector2.new(20, 6) },
			{ Offset = Vector2.new(8, -40), Size = Vector2.new(20, 6) },
		},
		CornerBevel = 12,
		Reflectors = {
			{ Offset = Vector2.new(-50, -30), Length = 14, Yaw = 45 },
			{ Offset = Vector2.new(50, 30), Length = 14, Yaw = 45 },
		},
		EnemySpawns = {
			Vector2.new(-54, 42), Vector2.new(54, -42), Vector2.new(28, 44), Vector2.new(-28, -44),
			Vector2.new(-56, 0), Vector2.new(56, 0), Vector2.new(0, 22), Vector2.new(0, -22),
		},
	},

	-- Abyss, tier 1: two broken walls either side of a rift, and bumpers on its axis that
	-- throw shots across it.
	Rift = {
		Zone = "Abyss",
		DisplayName = "The Rift",
		TrimColor = Color3.fromRGB(196, 150, 255),
		InteriorSize = Vector2.new(128, 128),
		AccentColor = Color3.fromRGB(90, 74, 126),
		Obstacles = {
			{ Offset = Vector2.new(-24, 40), Size = Vector2.new(30, 6) },
			{ Offset = Vector2.new(24, -40), Size = Vector2.new(30, 6) },
			{ Offset = Vector2.new(-44, -20), Size = Vector2.new(6, 24) },
			{ Offset = Vector2.new(44, 20), Size = Vector2.new(6, 24) },
		},
		CornerBevel = 16,
		Reflectors = {
			{ Offset = Vector2.new(0, 30), Length = 12, Yaw = 45 },
			{ Offset = Vector2.new(0, -30), Length = 12, Yaw = -45 },
		},
		EnemySpawns = {
			Vector2.new(48, 48), Vector2.new(-48, 48), Vector2.new(-48, -48), Vector2.new(48, -48),
			Vector2.new(0, 50), Vector2.new(0, -50), Vector2.new(-24, 0), Vector2.new(24, 0),
		},
	},

	-- Abyss, tier 1: a tall, narrow shaft with a spine of stones down its middle. Chasers pour
	-- down the long axis; the bumpers at the ends send shots back along the walls.
	Spire = {
		Zone = "Abyss",
		DisplayName = "Hanging Spire",
		TrimColor = Color3.fromRGB(170, 170, 255),
		InteriorSize = Vector2.new(110, 130),
		AccentColor = Color3.fromRGB(80, 80, 124),
		Obstacles = {
			{ Offset = Vector2.new(0, 34), Size = Vector2.new(10, 10) },
			{ Offset = Vector2.new(0, -34), Size = Vector2.new(10, 10) },
			{ Offset = Vector2.new(-30, 0), Size = Vector2.new(10, 10) },
			{ Offset = Vector2.new(30, 0), Size = Vector2.new(10, 10) },
		},
		CornerBevel = 12,
		Reflectors = {
			{ Offset = Vector2.new(-36, -46), Length = 12, Yaw = 45 },
			{ Offset = Vector2.new(36, 46), Length = 12, Yaw = 45 },
		},
		EnemySpawns = {
			Vector2.new(-36, 48), Vector2.new(36, -48), Vector2.new(0, 52), Vector2.new(0, -52),
			Vector2.new(-38, 20), Vector2.new(38, -20), Vector2.new(-38, -20), Vector2.new(38, 20),
		},
	},

	-- Abyss, tier 1: an open bowl ringed by six small stones. Little cover and long angles:
	-- the fight is about keeping the Bulwark turned while you find its back.
	Hollow = {
		Zone = "Abyss",
		DisplayName = "Starless Hollow",
		TrimColor = Color3.fromRGB(214, 160, 255),
		InteriorSize = Vector2.new(124, 124),
		AccentColor = Color3.fromRGB(96, 70, 124),
		Obstacles = {
			{ Offset = Vector2.new(0, 34), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(0, -34), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(-30, 17), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(30, 17), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(-30, -17), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(30, -17), Size = Vector2.new(8, 8) },
		},
		CornerBevel = 14,
		Reflectors = {
			{ Offset = Vector2.new(-46, 0), Length = 14, Yaw = 45 },
			{ Offset = Vector2.new(46, 0), Length = 14, Yaw = -45 },
		},
		EnemySpawns = {
			Vector2.new(-44, 44), Vector2.new(44, 44), Vector2.new(-44, -44), Vector2.new(44, -44),
			Vector2.new(0, 50), Vector2.new(0, -50), Vector2.new(-18, 0), Vector2.new(18, 0),
		},
	},
}

RoomConfig.DefaultLayout = "Atrium"

-- Each zone's look. RoomBuilder reads the floor and wall materials and colours from here; a
-- layout's own AccentColor and TrimColor still tint its walls and trims.
RoomConfig.Zones = {
	Ruins = {
		FloorColor = Color3.fromRGB(26, 28, 36),
		FloorMaterial = Enum.Material.Slate,
		TileColors = { Color3.fromRGB(24, 26, 34), Color3.fromRGB(32, 35, 46) },
		GridColor = Color3.fromRGB(44, 50, 66),
		WallMaterial = Enum.Material.Concrete,
	},
	Foundry = {
		FloorColor = Color3.fromRGB(34, 28, 24),
		FloorMaterial = Enum.Material.DiamondPlate,
		TileColors = { Color3.fromRGB(38, 30, 26), Color3.fromRGB(48, 38, 30) },
		GridColor = Color3.fromRGB(90, 62, 36),
		WallMaterial = Enum.Material.CorrodedMetal,
	},
	Abyss = {
		FloorColor = Color3.fromRGB(18, 14, 28),
		FloorMaterial = Enum.Material.Basalt,
		TileColors = { Color3.fromRGB(20, 16, 32), Color3.fromRGB(30, 22, 46) },
		GridColor = Color3.fromRGB(70, 48, 110),
		WallMaterial = Enum.Material.Basalt,
	},
}

function RoomConfig.ZoneStyle(layout)
	return RoomConfig.Zones[layout and layout.Zone or ""] or RoomConfig.Zones.Ruins
end

function RoomConfig.GetLayout(layoutId)
	return RoomConfig.Layouts[layoutId]
end

return RoomConfig
