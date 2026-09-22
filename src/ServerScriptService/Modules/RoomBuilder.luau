-- Builds a named room layout at runtime: floor, walls, pillars and a spawn pad.
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

-- Returns the room folder plus the interior bounds the rest of the game clamps against.
function RoomBuilder.Build(parent, layoutId)
	local layout = RoomConfig.GetLayout(layoutId or RoomConfig.DefaultLayout)
	if not layout then
		return nil, "unknown layout: " .. tostring(layoutId)
	end

	local interior = layout.InteriorSize
	local thickness = RoomConfig.WallThickness
	local height = RoomConfig.WallHeight
	local floorY = RoomConfig.FloorY

	local room = Instance.new("Folder")
	room.Name = "Room"
	room:SetAttribute("LayoutId", layoutId)
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
	local wallColor = layout.AccentColor or RoomConfig.WallColor

	makePart("WallNorth", Vector3.new(outerX, height, thickness), Vector3.new(0, wallY, halfZ), wallColor, room)
	makePart("WallSouth", Vector3.new(outerX, height, thickness), Vector3.new(0, wallY, -halfZ), wallColor, room)
	makePart("WallEast", Vector3.new(thickness, height, outerZ), Vector3.new(halfX, wallY, 0), wallColor, room)
	makePart("WallWest", Vector3.new(thickness, height, outerZ), Vector3.new(-halfX, wallY, 0), wallColor, room)

	for index, obstacle in layout.Obstacles do
		makePart(
			"Obstacle" .. index,
			Vector3.new(obstacle.Size.X, height, obstacle.Size.Y),
			Vector3.new(obstacle.Offset.X, wallY, obstacle.Offset.Y),
			RoomConfig.ObstacleColor,
			room
		)
	end

	local padSize = RoomConfig.SpawnPadSize
	local spawnPad = makePart("PlayerSpawn", padSize, Vector3.new(0, floorY + padSize.Y / 2, 0), wallColor, room)
	spawnPad.CanCollide = true

	local bounds = {
		center = Vector3.new(0, floorY, 0),
		-- Kept a little inside the walls so nothing can be pushed into geometry.
		half = Vector2.new(interior.X / 2 - 4, interior.Y / 2 - 4),
	}

	return room, bounds, layout
end

return RoomBuilder
