-- Room layouts, built at runtime by RoomBuilder. Nothing here is a committed binary model.
local RoomConfig = {}

RoomConfig.FloorY = 0
RoomConfig.WallHeight = 14
RoomConfig.WallThickness = 2
RoomConfig.FloorThickness = 2

-- Dark floor, lighter walls: bounce planes must read against the ground at a glance.
RoomConfig.FloorColor = Color3.fromRGB(26, 28, 36)
RoomConfig.FloorMaterial = Enum.Material.Slate
RoomConfig.WallColor = Color3.fromRGB(88, 96, 118)
RoomConfig.WallMaterial = Enum.Material.Concrete
RoomConfig.ObstacleColor = Color3.fromRGB(70, 78, 98)
-- Bevels and reflectors: brighter and metallic, so they never read as ordinary cover.
RoomConfig.BumperColor = Color3.fromRGB(150, 160, 184)
RoomConfig.BumperMaterial = Enum.Material.DiamondPlate

-- Decor is cosmetic only: non-colliding, non-queryable, and kept off the projectile plane.
RoomConfig.Decor = {
	GridSpacing = 8,
	GridLineWidth = 0.25,
	GridColor = Color3.fromRGB(44, 50, 66),
	-- Two-tone checker under the grid, so distance and angle read at a glance.
	TileSize = 16,
	TileColors = { Color3.fromRGB(24, 26, 34), Color3.fromRGB(32, 35, 46) },
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
		DisplayName = "Shattered Gallery",
		TrimColor = Color3.fromRGB(222, 196, 255),
		InteriorSize = Vector2.new(104, 132),
		AccentColor = Color3.fromRGB(110, 92, 128),
		Obstacles = {
			-- Shifted off the origin: as a centred spine it covered the player spawn point.
			{ Offset = Vector2.new(0, 26), Size = Vector2.new(8, 32) },
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
}

RoomConfig.DefaultLayout = "Atrium"

function RoomConfig.GetLayout(layoutId)
	return RoomConfig.Layouts[layoutId]
end

return RoomConfig
