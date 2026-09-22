-- Dimensions and layout of the prototype room. RoomBuilder reads this at runtime;
-- nothing is committed as a binary model file.
return {
	FloorY = 0,
	InteriorSize = Vector2.new(120, 120),
	WallHeight = 14,
	WallThickness = 2,
	FloorThickness = 2,

	FloorColor = Color3.fromRGB(46, 50, 62),
	WallColor = Color3.fromRGB(88, 96, 118),
	ObstacleColor = Color3.fromRGB(70, 78, 98),

	SpawnPadSize = Vector3.new(8, 1, 8),

	-- Interior pillars, as {X, Z} offsets from room centre plus footprint size.
	Obstacles = {
		{ Offset = Vector2.new(-28, 22), Size = Vector2.new(10, 10) },
		{ Offset = Vector2.new(30, 18), Size = Vector2.new(10, 10) },
		{ Offset = Vector2.new(-22, -26), Size = Vector2.new(14, 6) },
		{ Offset = Vector2.new(26, -24), Size = Vector2.new(6, 14) },
		{ Offset = Vector2.new(0, 34), Size = Vector2.new(18, 6) },
	},

	-- Markers consumed by the enemy spawner in Task 3.
	EnemySpawns = {
		Vector2.new(-45, 45), Vector2.new(0, 50), Vector2.new(45, 45),
		Vector2.new(-50, 0), Vector2.new(50, 0),
		Vector2.new(-45, -45), Vector2.new(0, -50), Vector2.new(45, -45),
	},
}
