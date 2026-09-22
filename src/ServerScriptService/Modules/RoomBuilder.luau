-- Builds the prototype room from RoomConfig at runtime: floor, four walls, pillars, spawn pad.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))

local RoomBuilder = {}

local function makePart(name, size, position, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function RoomBuilder.Build(parent)
	local interior = RoomConfig.InteriorSize
	local thickness = RoomConfig.WallThickness
	local height = RoomConfig.WallHeight
	local floorY = RoomConfig.FloorY

	local room = Instance.new("Folder")
	room.Name = "Room"
	room.Parent = parent

	local outerX = interior.X + thickness * 2
	local outerZ = interior.Y + thickness * 2

	makePart(
		"Floor",
		Vector3.new(outerX, RoomConfig.FloorThickness, outerZ),
		Vector3.new(0, floorY - RoomConfig.FloorThickness / 2, 0),
		RoomConfig.FloorColor,
		room
	)

	local wallY = floorY + height / 2
	local halfX = interior.X / 2 + thickness / 2
	local halfZ = interior.Y / 2 + thickness / 2

	makePart("WallNorth", Vector3.new(outerX, height, thickness), Vector3.new(0, wallY, halfZ), RoomConfig.WallColor, room)
	makePart("WallSouth", Vector3.new(outerX, height, thickness), Vector3.new(0, wallY, -halfZ), RoomConfig.WallColor, room)
	makePart("WallEast", Vector3.new(thickness, height, outerZ), Vector3.new(halfX, wallY, 0), RoomConfig.WallColor, room)
	makePart("WallWest", Vector3.new(thickness, height, outerZ), Vector3.new(-halfX, wallY, 0), RoomConfig.WallColor, room)

	for index, obstacle in RoomConfig.Obstacles do
		makePart(
			"Obstacle" .. index,
			Vector3.new(obstacle.Size.X, height, obstacle.Size.Y),
			Vector3.new(obstacle.Offset.X, wallY, obstacle.Offset.Y),
			RoomConfig.ObstacleColor,
			room
		)
	end

	local padSize = RoomConfig.SpawnPadSize
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "PlayerSpawn"
	spawnPad.Size = padSize
	spawnPad.Position = Vector3.new(0, floorY + padSize.Y / 2, 0)
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.TopSurface = Enum.SurfaceType.Smooth
	spawnPad.Parent = room

	return room
end

return RoomBuilder
