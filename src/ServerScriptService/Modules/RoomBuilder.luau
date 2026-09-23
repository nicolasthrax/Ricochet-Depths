-- Builds a named room layout at runtime: floor, walls, pillars, a spawn pad, and cosmetic
-- decor (floor grid, neon trims) that outlines every bounce plane.
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

-- Decor must never change play: projectiles raycast everything under the arena, so these
-- parts opt out of queries, collisions and touches, and stay off the projectile plane.
local function makeDecor(name, size, position, color, material, parent)
	local part = makePart(name, size, position, color, parent)
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function buildFloorGrid(decor, interior, floorY)
	local config = RoomConfig.Decor
	local width = config.GridLineWidth
	local thickness = 0.04
	local y = floorY + thickness / 2 + 0.01
	local columns = math.floor(interior.X / 2 / config.GridSpacing)
	local rows = math.floor(interior.Y / 2 / config.GridSpacing)
	for index = -columns, columns do
		local x = index * config.GridSpacing
		local size = Vector3.new(width, thickness, interior.Y)
		makeDecor("GridX" .. index, size, Vector3.new(x, y, 0), config.GridColor, Enum.Material.SmoothPlastic, decor)
	end
	for index = -rows, rows do
		local z = index * config.GridSpacing
		local size = Vector3.new(interior.X, thickness, width)
		makeDecor("GridZ" .. index, size, Vector3.new(0, y, z), config.GridColor, Enum.Material.SmoothPlastic, decor)
	end
end

-- Outlines a block standing on the floor: a neon cap on top and a glow strip around its foot.
-- footprint is the block's XZ size, centre its XZ position.
local function outlineBlock(decor, name, footprint, centre, floorY, height, color)
	local config = RoomConfig.Decor
	local inset = config.TrimInset
	local capHeight = config.TopTrimHeight
	makeDecor(
		name .. "Cap",
		Vector3.new(footprint.X + inset * 2, capHeight, footprint.Y + inset * 2),
		Vector3.new(centre.X, floorY + height + capHeight / 2, centre.Y),
		color,
		Enum.Material.Neon,
		decor
	)
	local baseHeight = config.BaseTrimHeight
	makeDecor(
		name .. "Base",
		Vector3.new(footprint.X + inset * 4, baseHeight, footprint.Y + inset * 4),
		Vector3.new(centre.X, floorY + baseHeight / 2, centre.Y),
		color,
		Enum.Material.Neon,
		decor
	)
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

	local floor = makePart(
		"Floor",
		Vector3.new(outerX, RoomConfig.FloorThickness, outerZ),
		Vector3.new(0, floorY - RoomConfig.FloorThickness / 2, 0),
		RoomConfig.FloorColor,
		room
	)
	floor.Material = RoomConfig.FloorMaterial

	local wallY = floorY + height / 2
	local halfX = interior.X / 2 + thickness / 2
	local halfZ = interior.Y / 2 + thickness / 2
	local wallColor = layout.AccentColor or RoomConfig.WallColor

	local walls = {
		{ "WallNorth", Vector2.new(outerX, thickness), Vector2.new(0, halfZ) },
		{ "WallSouth", Vector2.new(outerX, thickness), Vector2.new(0, -halfZ) },
		{ "WallEast", Vector2.new(thickness, outerZ), Vector2.new(halfX, 0) },
		{ "WallWest", Vector2.new(thickness, outerZ), Vector2.new(-halfX, 0) },
	}

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = room
	local trimColor = layout.TrimColor or RoomConfig.Decor.TrimColor
	buildFloorGrid(decor, interior, floorY)

	for _, wall in walls do
		local name, footprint, centre = wall[1], wall[2], wall[3]
		local size = Vector3.new(footprint.X, height, footprint.Y)
		local part = makePart(name, size, Vector3.new(centre.X, wallY, centre.Y), wallColor, room)
		part.Material = RoomConfig.WallMaterial
		outlineBlock(decor, name, footprint, centre, floorY, height, trimColor)
	end

	for index, obstacle in layout.Obstacles do
		local part = makePart(
			"Obstacle" .. index,
			Vector3.new(obstacle.Size.X, height, obstacle.Size.Y),
			Vector3.new(obstacle.Offset.X, wallY, obstacle.Offset.Y),
			RoomConfig.ObstacleColor,
			room
		)
		part.Material = RoomConfig.WallMaterial
		outlineBlock(decor, "Obstacle" .. index, obstacle.Size, obstacle.Offset, floorY, height, trimColor)
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
