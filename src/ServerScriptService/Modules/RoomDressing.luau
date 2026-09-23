-- Cosmetic set-dressing in each zone's style: broken columns and rubble in the Ruins, pipes,
-- vents and hazard stripes in the Foundry, floating crystals and glow lines in the Abyss.
--
-- Dressing must never read as something a shot can hit, so every prop sits outside the play
-- space: above the walls, beyond them, or in the sealed triangles behind the corner bevels.
-- Placement() is the rule, and the tests hold every prop to it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))

local RoomDressing = {}

-- Shared colours: parts that share a colour and material never visibly z-fight.
local STONE = Color3.fromRGB(120, 126, 140)
local RUBBLE = Color3.fromRGB(96, 100, 112)
local PIPE = Color3.fromRGB(110, 84, 64)
local VENT = Color3.fromRGB(70, 60, 54)
local VENT_GLOW = Color3.fromRGB(255, 140, 60)
local STRIPE_YELLOW = Color3.fromRGB(250, 196, 60)
local STRIPE_BLACK = Color3.fromRGB(30, 30, 34)

-- Why a prop at `position` with `size` is allowed ("above", "outside" or "corner"), or nil if
-- it would stand in the play space. Yaw is allowed for, by treating the footprint as the
-- circle it can turn through.
function RoomDressing.Placement(layout, position, size)
	local halfX, halfZ = layout.InteriorSize.X / 2, layout.InteriorSize.Y / 2
	if position.Y - size.Y / 2 >= RoomConfig.WallHeight then
		return "above"
	end
	local reach = math.sqrt(size.X * size.X + size.Z * size.Z) / 2
	if position.X - reach >= halfX or position.X + reach <= -halfX or position.Z - reach >= halfZ or position.Z + reach <= -halfZ then
		return "outside"
	end
	local leg = layout.CornerBevel
	if leg and leg > 0 then
		local sx, sz = math.sign(position.X), math.sign(position.Z)
		-- Behind the bevel slab: past the face line by the slab's depth, for every point of the
		-- footprint.
		local line = halfX + halfZ - leg + RoomConfig.BevelDepth * math.sqrt(2)
		local nearest = sx * position.X + sz * position.Z - reach * math.sqrt(2)
		if sx ~= 0 and sz ~= 0 and nearest >= line then
			return "corner"
		end
	end
	return nil
end

local function makeProp(parent, name, size, cframe, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Position = cframe.Position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A stable seed per layout, so a room dresses the same way every time.
local function seedFor(layoutId)
	local seed = 17
	for index = 1, #layoutId do
		seed = (seed * 31 + string.byte(layoutId, index)) % 2147483647
	end
	return seed
end

-- Points along the top of each wall, `spacing` apart, as { position, alongX }.
local function wallTopPoints(layout, spacing)
	local halfX, halfZ = layout.InteriorSize.X / 2, layout.InteriorSize.Y / 2
	local wallOffset = RoomConfig.WallThickness / 2
	local points = {}
	for x = -halfX + spacing, halfX - spacing, spacing do
		table.insert(points, { Vector3.new(x, 0, halfZ + wallOffset), true })
		table.insert(points, { Vector3.new(x, 0, -halfZ - wallOffset), true })
	end
	for z = -halfZ + spacing, halfZ - spacing, spacing do
		table.insert(points, { Vector3.new(halfX + wallOffset, 0, z), false })
		table.insert(points, { Vector3.new(-halfX - wallOffset, 0, z), false })
	end
	return points
end

-- Points in the sealed triangle behind each corner bevel.
local function cornerPoints(layout)
	local halfX, halfZ = layout.InteriorSize.X / 2, layout.InteriorSize.Y / 2
	local leg = layout.CornerBevel or 0
	local points = {}
	if leg < 8 then
		return points
	end
	local inset = leg * 0.18
	for _, signs in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		table.insert(points, Vector3.new(signs[1] * (halfX - inset), 0, signs[2] * (halfZ - inset)))
	end
	return points
end

-- The top of a wall's neon cap, where wall-top props stand.
local WALL_TOP = RoomConfig.WallHeight + RoomConfig.Decor.TopTrimHeight

local function dressRuins(folder, layout, random, trim)
	for index, point in wallTopPoints(layout, 22) do
		local height = 1.5 + random:NextNumber() * 3
		local position = point[1] + Vector3.new(0, WALL_TOP + height / 2, 0)
		makeProp(folder, "BrokenColumn" .. index, Vector3.new(2.2, height, 2.2), CFrame.new(position),
			STONE, Enum.Material.Concrete)
		if index % 2 == 0 then
			makeProp(folder, "ColumnCap" .. index, Vector3.new(2.8, 0.4, 2.8),
				CFrame.new(position + Vector3.new(0, height / 2 + 0.2, 0)), trim, Enum.Material.Neon)
		end
	end
	for index, corner in cornerPoints(layout) do
		for chunk = 1, 3 do
			local size = 0.8 + random:NextNumber() * 1.2
			local offset = Vector3.new((random:NextNumber() - 0.5) * 1.5, size / 2, (random:NextNumber() - 0.5) * 1.5)
			local position = corner + offset
			local cframe = CFrame.lookAt(position, position + Vector3.new(random:NextNumber() - 0.5, 0, random:NextNumber() - 0.5))
			makeProp(folder, ("Rubble%d_%d"):format(index, chunk), Vector3.new(size, size, size), cframe,
				RUBBLE, Enum.Material.Slate)
		end
	end
end

local function dressFoundry(folder, layout, _random, trim)
	local halfX, halfZ = layout.InteriorSize.X / 2, layout.InteriorSize.Y / 2
	local wallOffset = RoomConfig.WallThickness / 2
	-- Pipes along the tops of the long walls.
	for index, z in { halfZ + wallOffset, -halfZ - wallOffset } do
		local position = Vector3.new(0, WALL_TOP + 1.1, z)
		makeProp(folder, "Pipe" .. index, Vector3.new(layout.InteriorSize.X, 1.4, 1.4), CFrame.new(position),
			PIPE, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	end
	-- Vent stacks at the corners, with a warm glow at the mouth.
	for index, signs in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		local base = Vector3.new(signs[1] * (halfX + wallOffset), 0, signs[2] * (halfZ + wallOffset))
		makeProp(folder, "Vent" .. index, Vector3.new(3, 5, 3), CFrame.new(base + Vector3.new(0, WALL_TOP + 2.5, 0)),
			VENT, Enum.Material.Metal)
		makeProp(folder, "VentGlow" .. index, Vector3.new(2.2, 0.3, 2.2), CFrame.new(base + Vector3.new(0, WALL_TOP + 5.15, 0)),
			VENT_GLOW, Enum.Material.Neon)
	end
	-- Hazard stripes along the tops of the short walls.
	for index, point in wallTopPoints(layout, 6) do
		if not point[2] then
			local color = index % 2 == 0 and STRIPE_YELLOW or STRIPE_BLACK
			makeProp(folder, "Stripe" .. index, Vector3.new(RoomConfig.WallThickness, 0.3, 3),
				CFrame.new(point[1] + Vector3.new(0, WALL_TOP + 0.4, 0)), color, Enum.Material.SmoothPlastic)
		end
	end
	local _ = trim
end

local function dressAbyss(folder, layout, random, trim)
	local halfX, halfZ = layout.InteriorSize.X / 2, layout.InteriorSize.Y / 2
	local beyond = RoomConfig.WallThickness + 4
	-- Crystals hanging in the void beyond the walls.
	for index = 1, 14 do
		local side = index % 4
		local along = (random:NextNumber() * 2 - 1)
		local out = beyond + random:NextNumber() * 8
		local position
		if side == 0 then
			position = Vector3.new(along * halfX, 0, halfZ + out)
		elseif side == 1 then
			position = Vector3.new(along * halfX, 0, -halfZ - out)
		elseif side == 2 then
			position = Vector3.new(halfX + out, 0, along * halfZ)
		else
			position = Vector3.new(-halfX - out, 0, along * halfZ)
		end
		local height = 3 + random:NextNumber() * 6
		position += Vector3.new(0, 6 + random:NextNumber() * 14, 0)
		local cframe = CFrame.lookAt(position, position + Vector3.new(random:NextNumber() - 0.5, 0.2, random:NextNumber() - 0.5))
		makeProp(folder, "Crystal" .. index, Vector3.new(1.2, height, 1.2), cframe, trim, Enum.Material.Neon)
	end
	-- Glow lines hovering over the walls.
	for index, point in wallTopPoints(layout, 12) do
		local size = point[2] and Vector3.new(8, 0.2, 0.3) or Vector3.new(0.3, 0.2, 8)
		makeProp(folder, "GlowLine" .. index, size, CFrame.new(point[1] + Vector3.new(0, WALL_TOP + 1.2, 0)), trim, Enum.Material.Neon)
	end
end

local DRESSERS = { Ruins = dressRuins, Foundry = dressFoundry, Abyss = dressAbyss }

function RoomDressing.Build(room, layoutId, layout)
	local zone = layout.Zone or "Ruins"
	local folder = Instance.new("Folder")
	folder.Name = "Dressing"
	folder:SetAttribute("Zone", zone)
	folder.Parent = room
	local dresser = DRESSERS[zone] or dressRuins
	dresser(folder, layout, Random.new(seedFor(layoutId)), layout.TrimColor or RoomConfig.Decor.TrimColor)
	return folder
end

return RoomDressing
