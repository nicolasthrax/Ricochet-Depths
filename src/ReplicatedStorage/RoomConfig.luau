-- Room layouts, built at runtime by RoomBuilder. Nothing here is a committed binary model.
local RoomConfig = {}

RoomConfig.FloorY = 0
RoomConfig.WallHeight = 14
RoomConfig.WallThickness = 2
RoomConfig.FloorThickness = 2

RoomConfig.FloorColor = Color3.fromRGB(46, 50, 62)
RoomConfig.WallColor = Color3.fromRGB(88, 96, 118)
RoomConfig.ObstacleColor = Color3.fromRGB(70, 78, 98)

RoomConfig.SpawnPadSize = Vector3.new(8, 1, 8)

-- Each layout is interior size, pillar footprints, and enemy spawn markers, all as XZ offsets
-- from the room centre. Layouts are chosen by RunConfig.Rooms.
RoomConfig.Layouts = {
	-- Open and forgiving: long sightlines so a first ricochet is easy to land.
	Atrium = {
		DisplayName = "Collapsed Atrium",
		InteriorSize = Vector2.new(120, 120),
		AccentColor = Color3.fromRGB(96, 104, 128),
		Obstacles = {
			{ Offset = Vector2.new(-30, 24), Size = Vector2.new(10, 10) },
			{ Offset = Vector2.new(30, 24), Size = Vector2.new(10, 10) },
			{ Offset = Vector2.new(0, -28), Size = Vector2.new(20, 8) },
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
		InteriorSize = Vector2.new(104, 132),
		AccentColor = Color3.fromRGB(110, 92, 128),
		Obstacles = {
			{ Offset = Vector2.new(0, 20), Size = Vector2.new(8, 44) },
			{ Offset = Vector2.new(-32, -26), Size = Vector2.new(16, 8) },
			{ Offset = Vector2.new(32, -26), Size = Vector2.new(16, 8) },
			{ Offset = Vector2.new(-34, 40), Size = Vector2.new(8, 8) },
			{ Offset = Vector2.new(34, 40), Size = Vector2.new(8, 8) },
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
		InteriorSize = Vector2.new(132, 112),
		AccentColor = Color3.fromRGB(128, 100, 84),
		Obstacles = {
			{ Offset = Vector2.new(-26, 18), Size = Vector2.new(26, 8) },
			{ Offset = Vector2.new(26, -18), Size = Vector2.new(26, 8) },
			{ Offset = Vector2.new(-30, -28), Size = Vector2.new(8, 24) },
			{ Offset = Vector2.new(30, 28), Size = Vector2.new(8, 24) },
			{ Offset = Vector2.new(0, 0), Size = Vector2.new(12, 12) },
		},
		EnemySpawns = {
			Vector2.new(-52, 44), Vector2.new(52, 44), Vector2.new(-52, -44),
			Vector2.new(52, -44), Vector2.new(0, 46), Vector2.new(0, -46),
			Vector2.new(-56, 0), Vector2.new(56, 0),
		},
	},

	-- Boss arena: wide, few pillars, so the fight is about angles rather than cover.
	WardenVault = {
		DisplayName = "Warden Vault",
		InteriorSize = Vector2.new(140, 140),
		AccentColor = Color3.fromRGB(122, 96, 160),
		Obstacles = {
			{ Offset = Vector2.new(-44, 44), Size = Vector2.new(12, 12) },
			{ Offset = Vector2.new(44, 44), Size = Vector2.new(12, 12) },
			{ Offset = Vector2.new(-44, -44), Size = Vector2.new(12, 12) },
			{ Offset = Vector2.new(44, -44), Size = Vector2.new(12, 12) },
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
