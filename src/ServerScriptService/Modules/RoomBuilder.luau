-- Builds a named room layout at runtime from RoomGeometry: walls, pillars, 45 degree corner
-- bevels and reflectors, a spawn pad, and cosmetic decor (checker floor, grid, neon trims) that
-- makes every bounce plane readable at a glance. Nothing here is a committed binary model.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RoomGeometry = require(ReplicatedStorage:WaitForChild("RoomGeometry"))

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

-- Turns a part to a yaw about +Y. Every part gets an explicit CFrame, so rotated and
-- axis-aligned pieces are built the same way.
local function orient(part, position, yaw)
	part.CFrame = CFrame.lookAt(position, position + RoomGeometry.LookVector(yaw))
	part.Position = position
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

-- Floor layers, bottom to top. Each sits a clear step above the last: at the tactical camera's
-- range, layers a few hundredths of a stud apart z-fight and shimmer as the camera moves.
local LAYER = RoomConfig.Decor.LayerStep
local function layerY(floorY, level)
	return floorY + LAYER * (level - 0.5)
end

-- Two-tone checker across the interior; edge tiles are trimmed to fit.
local function buildFloorTiles(decor, interior, floorY)
	local config = RoomConfig.Decor
	local size = config.TileSize
	local halfX, halfZ = interior.X / 2, interior.Y / 2
	local y = layerY(floorY, 1)
	for column = 0, math.ceil(interior.X / size) - 1 do
		local x0 = -halfX + column * size
		local x1 = math.min(x0 + size, halfX)
		for row = 0, math.ceil(interior.Y / size) - 1 do
			local z0 = -halfZ + row * size
			local z1 = math.min(z0 + size, halfZ)
			local color = config.TileColors[(column + row) % 2 + 1]
			makeDecor(
				("Tile_%d_%d"):format(column, row),
				Vector3.new(x1 - x0, LAYER, z1 - z0),
				Vector3.new((x0 + x1) / 2, y, (z0 + z1) / 2),
				color,
				Enum.Material.SmoothPlastic,
				decor
			)
		end
	end
end

local function buildFloorGrid(decor, interior, floorY)
	local config = RoomConfig.Decor
	local width = config.GridLineWidth
	local y = layerY(floorY, 2)
	local columns = math.floor(interior.X / 2 / config.GridSpacing)
	local rows = math.floor(interior.Y / 2 / config.GridSpacing)
	for index = -columns, columns do
		local x = index * config.GridSpacing
		local size = Vector3.new(width, LAYER, interior.Y)
		makeDecor("GridX" .. index, size, Vector3.new(x, y, 0), config.GridColor, Enum.Material.SmoothPlastic, decor)
	end
	for index = -rows, rows do
		local z = index * config.GridSpacing
		local size = Vector3.new(interior.X, LAYER, width)
		makeDecor("GridZ" .. index, size, Vector3.new(0, y, z), config.GridColor, Enum.Material.SmoothPlastic, decor)
	end
end

-- A glowing line just inside each wall: the playable edge, readable from any camera height.
local function buildBorder(decor, interior, floorY, color)
	local config = RoomConfig.Decor
	local inset, width = config.BorderInset, config.BorderWidth
	local y = layerY(floorY, 3)
	local x, z = interior.X / 2 - inset, interior.Y / 2 - inset
	local lines = {
		{ "BorderNorth", Vector3.new(x * 2, LAYER, width), Vector3.new(0, y, z) },
		{ "BorderSouth", Vector3.new(x * 2, LAYER, width), Vector3.new(0, y, -z) },
		{ "BorderEast", Vector3.new(width, LAYER, z * 2), Vector3.new(x, y, 0) },
		{ "BorderWest", Vector3.new(width, LAYER, z * 2), Vector3.new(-x, y, 0) },
	}
	for _, line in lines do
		makeDecor(line[1], line[2], line[3], color, Enum.Material.Neon, decor)
	end
end

-- Outlines a solid standing on the floor: a neon cap on top and a glow strip around its foot,
-- both turned to the solid's own heading.
local function outlineSolid(decor, solid, floorY, height, color)
	local config = RoomConfig.Decor
	local inset = config.TrimInset
	-- Bank-shot trims stand a step taller than wall trims: where a bevel meets a wall their
	-- trims overlap, and at equal heights the two colours would z-fight.
	local lift = if solid.Kind == "Bevel" or solid.Kind == "Reflector" then config.HazardTrimLift else 0
	local capHeight = config.TopTrimHeight + lift
	local cap = makeDecor(
		solid.Name .. "Cap",
		Vector3.new(solid.Size.X + inset * 2, capHeight, solid.Size.Y + inset * 2),
		Vector3.zero,
		color,
		Enum.Material.Neon,
		decor
	)
	orient(cap, Vector3.new(solid.Center.X, floorY + height + capHeight / 2, solid.Center.Y), solid.Yaw)

	local baseHeight = config.BaseTrimHeight + lift
	local base = makeDecor(
		solid.Name .. "Base",
		Vector3.new(solid.Size.X + inset * 4, baseHeight, solid.Size.Y + inset * 4),
		Vector3.zero,
		color,
		Enum.Material.Neon,
		decor
	)
	orient(base, Vector3.new(solid.Center.X, floorY + baseHeight / 2, solid.Center.Y), solid.Yaw)
end

-- A low plinth with a glowing ring inset on top. It casts no shadow: the character standing on
-- it would otherwise throw a shadow that shimmers across its face as the camera follows.
local function buildSpawnPad(room, decor, floorY, color, ringColor)
	local size = RoomConfig.SpawnPadSize
	local pad = makePart("PlayerSpawn", size, Vector3.new(0, floorY + size.Y / 2, 0), color, room)
	pad.Material = Enum.Material.SmoothPlastic
	pad.CastShadow = false

	local config = RoomConfig.Decor
	local width, height = config.SpawnRingWidth, config.SpawnRingHeight
	local reach = size.X / 2 - config.SpawnRingInset
	local y = floorY + size.Y + height / 2
	local strips = {
		{ "SpawnRingNorth", Vector3.new(reach * 2, height, width), Vector3.new(0, y, reach - width / 2) },
		{ "SpawnRingSouth", Vector3.new(reach * 2, height, width), Vector3.new(0, y, -reach + width / 2) },
		{ "SpawnRingEast", Vector3.new(width, height, reach * 2 - width * 2), Vector3.new(reach - width / 2, y, 0) },
		{ "SpawnRingWest", Vector3.new(width, height, reach * 2 - width * 2), Vector3.new(-reach + width / 2, y, 0) },
	}
	for _, strip in strips do
		makeDecor(strip[1], strip[2], strip[3], ringColor, Enum.Material.Neon, decor)
	end
	return pad
end

-- Colour and trim for each kind of solid. Bank-shot pieces wear hazard trim so they read as
-- surfaces to play off rather than as cover.
local function styleFor(kind, layout)
	local trim = layout.TrimColor or RoomConfig.Decor.TrimColor
	if kind == "Wall" then
		return layout.AccentColor or RoomConfig.WallColor, trim
	elseif kind == "Obstacle" then
		return RoomConfig.ObstacleColor, trim
	end
	return RoomConfig.BumperColor, RoomConfig.Decor.HazardColor
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

	local floor = makePart(
		"Floor",
		Vector3.new(interior.X + thickness * 2, RoomConfig.FloorThickness, interior.Y + thickness * 2),
		Vector3.new(0, floorY - RoomConfig.FloorThickness / 2, 0),
		RoomConfig.FloorColor,
		room
	)
	floor.Material = RoomConfig.FloorMaterial

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = room
	local trimColor = layout.TrimColor or RoomConfig.Decor.TrimColor
	buildFloorTiles(decor, interior, floorY)
	buildFloorGrid(decor, interior, floorY)
	buildBorder(decor, interior, floorY, trimColor)

	local wallY = floorY + height / 2
	for _, solid in RoomGeometry.Solids(layout, RoomConfig) do
		local color, trim = styleFor(solid.Kind, layout)
		local part = makePart(solid.Name, Vector3.new(solid.Size.X, height, solid.Size.Y), Vector3.zero, color, room)
		local isCover = solid.Kind == "Wall" or solid.Kind == "Obstacle"
		part.Material = if isCover then RoomConfig.WallMaterial else RoomConfig.BumperMaterial
		orient(part, Vector3.new(solid.Center.X, wallY, solid.Center.Y), solid.Yaw)
		outlineSolid(decor, solid, floorY, height, trim)
	end

	buildSpawnPad(room, decor, floorY, layout.AccentColor or RoomConfig.WallColor, trimColor)

	local bounds = {
		center = Vector3.new(0, floorY, 0),
		-- Kept a little inside the walls so nothing can be pushed into geometry.
		half = Vector2.new(interior.X / 2 - 4, interior.Y / 2 - 4),
		-- And out of the sealed corners behind any bevels.
		diagonal = RoomGeometry.DiagonalLimit(layout, RoomConfig),
	}

	return room, bounds, layout
end

return RoomBuilder
