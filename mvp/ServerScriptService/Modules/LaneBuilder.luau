--!strict
-- Builds the physical lane a player stands in: the floor, the bumper walls, the rail strip and the
-- danger line, placed from the lane origin. Shots never touch these parts (the server simulates
-- walls as math); they are what everyone sees, and the floor is what the avatar stands on.
--
-- Colours follow the design's value hierarchy: a dark floor, bright cyan walls, magenta for harm.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Source.GameConfig)

local Lane = GameConfig.Lane
local World = GameConfig.World
local Palette = GameConfig.Palette

local FOLDER_NAME = "Lanes"
local RAIL_COLOR = Color3.fromRGB(52, 74, 84)

local LaneBuilder = {}

local function lanesFolder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

-- A box part in lane space: centred at (x, y) across and up the lane, `height` above the floor,
-- sized (width across, tall, depth along the lane).
local function box(
	model: Model,
	name: string,
	origin: CFrame,
	x: number,
	y: number,
	height: number,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	collides: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = collides
	part.CanTouch = false
	part.CanQuery = collides
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.Material = material
	-- Lane +y is the origin's LookVector, which is -Z in the origin's own space.
	part.CFrame = origin * CFrame.new(x, height, -y)
	part.Parent = model
	return part
end

-- The lane origin for a slot: slots sit side by side along +X from the first origin.
function LaneBuilder.originForSlot(slot: number): CFrame
	return World.firstLaneOrigin * CFrame.new((slot - 1) * World.laneSpacing, 0, 0)
end

function LaneBuilder.build(origin: CFrame, name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local halfWidth = Lane.halfWidth
	local wall = World.wallThickness
	local outerWidth = halfWidth * 2 + wall * 2
	local floorStart = -World.apronDepth
	local floorEnd = Lane.length + wall
	local floorDepth = floorEnd - floorStart

	local floor = box(
		model,
		"Floor",
		origin,
		0,
		(floorStart + floorEnd) / 2,
		-World.floorThickness / 2,
		Vector3.new(outerWidth, World.floorThickness, floorDepth),
		Palette.Floor,
		Enum.Material.Slate,
		true
	)
	model.PrimaryPart = floor

	local wallY = World.wallHeight / 2
	box(model, "WallLeft", origin, -halfWidth - wall / 2, Lane.length / 2, wallY,
		Vector3.new(wall, World.wallHeight, Lane.length + wall), Palette.Wall, Enum.Material.Neon, false)
	box(model, "WallRight", origin, halfWidth + wall / 2, Lane.length / 2, wallY,
		Vector3.new(wall, World.wallHeight, Lane.length + wall), Palette.Wall, Enum.Material.Neon, false)
	box(model, "WallBack", origin, 0, Lane.length + wall / 2, wallY,
		Vector3.new(outerWidth, World.wallHeight, wall), Palette.Wall, Enum.Material.Neon, false)

	box(model, "Rail", origin, 0, GameConfig.Rail.y, 0.05,
		Vector3.new(halfWidth * 2, 0.1, 0.5), RAIL_COLOR, Enum.Material.SmoothPlastic, false)
	box(model, "DangerLine", origin, 0, Lane.dangerLineY, 0.05,
		Vector3.new(halfWidth * 2, 0.1, 0.15), Palette.Harm, Enum.Material.Neon, false)

	model.Parent = lanesFolder()
	return model
end

table.freeze(LaneBuilder)
return LaneBuilder
