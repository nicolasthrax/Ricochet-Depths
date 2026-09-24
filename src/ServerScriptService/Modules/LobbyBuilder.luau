-- The Descent Hall, where players gather between runs. North: the solo portal (a pedestal) in
-- front of the zone banners. West: two multiplayer gates of 2-8 players. East: the Armory and
-- Cosmetics kiosks. South: the (invisible) spawn. An invisible barrier and ceiling keep everyone inside.
-- Built at runtime; nothing here is a binary model.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local Signage = require(script.Parent.Signage)

local LobbyBuilder = {}

local SIZE = Vector3.new(120, 1, 100)
local HALF_X, HALF_Z = SIZE.X / 2, SIZE.Z / 2
local SPAWN_OFFSET = Vector3.new(0, 0, 34)
local PEDESTAL_SIZE = Vector3.new(6, 5, 6)
local PEDESTAL_OFFSET = Vector3.new(0, 0, -28)

local GATE_SIZE = 16 -- booth footprint, square
local GATE_X = -44
local GATE_ZS = { -16, 16 }
local GATE_WALL_HEIGHT = 8
local GATE_NAMES = { "GATE I", "GATE II" }

local KIOSK_SIZE = Vector3.new(4, 7, 6) -- thin side faces west, towards the hall
local KIOSK_X = 46
local KIOSKS = {
	{ Name = "ArmoryKiosk", Z = -14, Title = "ARMORY", Prompt = "OpenArmoryPrompt", Object = "Armory", Color = Color3.fromRGB(226, 196, 120) },
	{ Name = "CosmeticsKiosk", Z = 14, Title = "COSMETICS", Prompt = "OpenCosmeticsPrompt", Object = "Cosmetics", Color = Color3.fromRGB(200, 150, 255) },
}

local HALL_HEIGHT = 16
local HALL_THICKNESS = 2
local BARRIER_HEIGHT = 100
local CEILING_Y = 60

local STONE = Color3.fromRGB(66, 72, 92)
local TRIM = Color3.fromRGB(150, 190, 255)
local LAMP_GLOW = Color3.fromRGB(255, 226, 170)
local SIGN_BACK = Color3.fromRGB(24, 26, 36)
local SIGN_TEXT = Color3.fromRGB(240, 242, 250)
local GATE_IDLE = Color3.fromRGB(62, 90, 130)
local GATE_GLOW = Color3.fromRGB(120, 235, 255)

local WEST = Vector3.new(-1, 0, 0)
local EAST = Vector3.new(1, 0, 0)
local SOUTH = Vector3.new(0, 0, 1)

local function block(parent, name, size, position, color, material, solid)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = solid == true
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function LobbyBuilder.Build(parent)
	local origin = RunConfig.LobbyPosition
	local floorY = RoomConfig.FloorY

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = parent

	local floor = block(lobby, "LobbyFloor", SIZE, origin + Vector3.new(0, floorY - SIZE.Y / 2, 0),
		Color3.fromRGB(46, 50, 66), Enum.Material.Slate, true)
	floor.CanQuery = true

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "LobbySpawn"
	spawnPad.Size = RoomConfig.SpawnPadSize
	spawnPad.Position = origin + SPAWN_OFFSET + Vector3.new(0, floorY + RoomConfig.SpawnPadSize.Y / 2, 0)
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	-- Invisible and intangible: players still spawn here, but they stand on the hall floor and
	-- never see or trip over a pad.
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	spawnPad.CanQuery = false
	spawnPad.CanTouch = false
	spawnPad.CastShadow = false
	spawnPad.Parent = lobby

	local signs = Instance.new("Folder")
	signs.Name = "Signs"
	signs.Parent = lobby

	local soloPrompt = LobbyBuilder._buildSoloPortal(lobby, signs, origin)
	local gates = LobbyBuilder._buildGates(lobby, signs, origin)
	local prompts = LobbyBuilder._buildKiosks(lobby, signs, origin)
	LobbyBuilder._buildHall(lobby, signs, origin)
	LobbyBuilder._buildBarrier(lobby, origin)

	return lobby, soloPrompt, {
		gates = gates,
		armoryPrompt = prompts.ArmoryKiosk,
		cosmeticsPrompt = prompts.CosmeticsKiosk,
	}
end

-- The pedestal at the north end. Its prompt starts a one-player run.
function LobbyBuilder._buildSoloPortal(lobby, signs, origin)
	local floorY = RoomConfig.FloorY
	local pedestal = block(lobby, "DescentPedestal", PEDESTAL_SIZE,
		origin + PEDESTAL_OFFSET + Vector3.new(0, floorY + PEDESTAL_SIZE.Y / 2, 0), GATE_GLOW, Enum.Material.Neon, true)

	-- A ProximityPrompt works with mouse, gamepad and touch without any custom input code.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StartRunPrompt"
	prompt.ActionText = "Descend Solo"
	prompt.ObjectText = "Solo Portal"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal

	Signage.Board(signs, "SoloSign", Vector3.new(12, 2.4, 0.2), origin + PEDESTAL_OFFSET + Vector3.new(0, floorY + 6, -8),
		SOUTH, "SOLO DESCENT", GATE_GLOW, SIGN_BACK)
	return prompt
end

-- Two open-fronted booths on the west side. Standing on a booth's glowing floor puts you in its
-- party; the board on its back wall shows the count and countdown.
function LobbyBuilder._buildGates(lobby, signs, origin)
	local floorY = RoomConfig.FloorY
	local folder = Instance.new("Folder")
	folder.Name = "Gates"
	folder.Parent = lobby

	local gates = {}
	local half = GATE_SIZE / 2
	for index, z in GATE_ZS do
		local centre = origin + Vector3.new(GATE_X, floorY, z)
		local name = GATE_NAMES[index]
		local id = "Gate" .. index

		local zone = block(folder, id .. "Zone", Vector3.new(GATE_SIZE - 2, 0.3, GATE_SIZE - 2),
			centre + Vector3.new(0, 0.15, 0), GATE_IDLE, Enum.Material.Neon)
		local back = block(folder, id .. "Back", Vector3.new(1, GATE_WALL_HEIGHT, GATE_SIZE),
			centre + Vector3.new(-half, GATE_WALL_HEIGHT / 2, 0), STONE, Enum.Material.Concrete, true)
		for side, sign in { North = -1, South = 1 } do
			block(folder, id .. side, Vector3.new(GATE_SIZE, GATE_WALL_HEIGHT, 1),
				centre + Vector3.new(0, GATE_WALL_HEIGHT / 2, sign * half), STONE, Enum.Material.Concrete, true)
		end
		block(folder, id .. "Lintel", Vector3.new(1, 0.6, GATE_SIZE + 1),
			centre + Vector3.new(half, GATE_WALL_HEIGHT - 0.3, 0), GATE_GLOW, Enum.Material.Neon)
		local _ = back

		local board = Signage.Board(signs, id .. "Board", Vector3.new(12, 2.6, 0.2),
			centre + Vector3.new(-half + 0.7, 5.5, 0), EAST, name .. "  0/" .. RunConfig.Lobby.GateCapacity, SIGN_TEXT, SIGN_BACK)
		Signage.Floating(zone, "Header", name, GATE_GLOW, Vector2.new(10, 2.2), Vector3.new(0, GATE_WALL_HEIGHT + 3, 0))

		local gate = {
			Id = id,
			name = name,
			zone = zone,
			board = board,
			capacity = RunConfig.Lobby.GateCapacity,
			minPlayers = RunConfig.Lobby.GateMinPlayers,
			-- Where overflow is sent: just outside the booth's open side.
			mouth = centre + Vector3.new(half + 5, 3, 0),
		}
		LobbyBuilder.SetGateStatus(gate, 0, nil)
		table.insert(gates, gate)
	end
	return gates
end

-- Shows a gate's party size and countdown on its board, and lights its floor when anyone is in.
function LobbyBuilder.SetGateStatus(gate, count, countdown)
	local detail
	if countdown then
		detail = string.format("%ds", math.ceil(countdown))
	else
		detail = "need " .. gate.minPlayers
	end
	Signage.SetText(gate.board, string.format("%s  %d/%d  ·  %s", gate.name, count, gate.capacity, detail))
	local lit = count > 0
	if gate.lit ~= lit then
		gate.lit = lit
		gate.zone.Color = lit and GATE_GLOW or GATE_IDLE
	end
end

-- The Armory and Cosmetics kiosks on the east side, facing the hall, each under a canopy with
-- its name on a board above.
function LobbyBuilder._buildKiosks(lobby, signs, origin)
	local floorY = RoomConfig.FloorY
	local prompts = {}
	for _, spec in KIOSKS do
		local base = origin + Vector3.new(KIOSK_X, floorY, spec.Z)
		local kiosk = block(lobby, spec.Name, KIOSK_SIZE, base + Vector3.new(0, KIOSK_SIZE.Y / 2, 0),
			Color3.fromRGB(46, 50, 64), Enum.Material.Metal, true)
		block(lobby, spec.Name .. "Screen", Vector3.new(0.2, 2.4, KIOSK_SIZE.Z - 1),
			base + Vector3.new(-KIOSK_SIZE.X / 2 - 0.1, KIOSK_SIZE.Y / 2 + 1.2, 0), spec.Color, Enum.Material.Neon)

		local canopyY = KIOSK_SIZE.Y + 1.2
		block(lobby, spec.Name .. "Canopy", Vector3.new(KIOSK_SIZE.X + 4, 0.4, KIOSK_SIZE.Z + 3),
			base + Vector3.new(-1, canopyY, 0), Color3.fromRGB(90, 70, 48), Enum.Material.WoodPlanks)
		block(lobby, spec.Name .. "CanopyTrim", Vector3.new(KIOSK_SIZE.X + 4.2, 0.2, KIOSK_SIZE.Z + 3.2),
			base + Vector3.new(-1, canopyY - 0.3, 0), spec.Color, Enum.Material.Neon)
		-- The name sits on its own board above the canopy, clear of everything.
		Signage.Board(signs, spec.Name .. "Sign", Vector3.new(8, 2, 0.2), base + Vector3.new(-1, canopyY + 1.6, 0),
			WEST, spec.Title, spec.Color, SIGN_BACK)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = spec.Prompt
		prompt.ActionText = "Browse"
		prompt.ObjectText = spec.Object
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = kiosk
		prompts[spec.Name] = prompt
	end
	return prompts
end

-- Walls, pillars, lamps, the well ring round the solo portal, and the zone banners.
function LobbyBuilder._buildHall(lobby, signs, origin)
	local dressing = Instance.new("Folder")
	dressing.Name = "Dressing"
	dressing.Parent = lobby

	local floorY = RoomConfig.FloorY
	local wallY = floorY + HALL_HEIGHT / 2
	local offsetX, offsetZ = HALF_X + HALL_THICKNESS / 2, HALF_Z + HALL_THICKNESS / 2
	local spanX, spanZ = SIZE.X + HALL_THICKNESS * 2, SIZE.Z + HALL_THICKNESS * 2
	local walls = {
		{ "HallWallNorth", Vector3.new(spanX, HALL_HEIGHT, HALL_THICKNESS), Vector3.new(0, wallY, -offsetZ) },
		{ "HallWallSouth", Vector3.new(spanX, HALL_HEIGHT, HALL_THICKNESS), Vector3.new(0, wallY, offsetZ) },
		{ "HallWallEast", Vector3.new(HALL_THICKNESS, HALL_HEIGHT, spanZ), Vector3.new(offsetX, wallY, 0) },
		{ "HallWallWest", Vector3.new(HALL_THICKNESS, HALL_HEIGHT, spanZ), Vector3.new(-offsetX, wallY, 0) },
	}
	for _, wall in walls do
		block(dressing, wall[1], wall[2], origin + wall[3], STONE, Enum.Material.Concrete, true)
		block(dressing, (wall[1]:gsub("HallWall", "HallTrim")), wall[2] * Vector3.new(1, 0, 1) + Vector3.new(0.1, 0.4, 0.1),
			origin + wall[3] + Vector3.new(0, HALL_HEIGHT / 2 + 0.2, 0), TRIM, Enum.Material.Neon)
	end

	-- Pillars on the walls, clear of the gates, kiosks and banners. Solid, like the lamp posts:
	-- anything a player can see standing on the floor, they should not walk through.
	local pillars = {
		Vector3.new(-HALF_X + 2, 0, -HALF_Z + 2), Vector3.new(HALF_X - 2, 0, -HALF_Z + 2),
		Vector3.new(-HALF_X + 2, 0, HALF_Z - 2), Vector3.new(HALF_X - 2, 0, HALF_Z - 2),
		Vector3.new(-40, 0, -HALF_Z + 2), Vector3.new(40, 0, -HALF_Z + 2),
		Vector3.new(-40, 0, HALF_Z - 2), Vector3.new(40, 0, HALF_Z - 2),
		Vector3.new(-HALF_X + 2, 0, 0), Vector3.new(HALF_X - 2, 0, 0),
	}
	for index, spot in pillars do
		local height = HALL_HEIGHT + 2
		local position = origin + spot + Vector3.new(0, floorY + height / 2, 0)
		block(dressing, "Pillar" .. index, Vector3.new(2.6, height, 2.6), position, STONE, Enum.Material.Slate, true)
		block(dressing, "PillarCap" .. index, Vector3.new(3.2, 0.5, 3.2), position + Vector3.new(0, height / 2 + 0.25, 0),
			TRIM, Enum.Material.Neon)
	end

	-- Lamps in the four quarters of the hall.
	for index, corner in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		local base = origin + Vector3.new(corner[1] * 22, floorY, corner[2] * 38)
		block(dressing, "LampPost" .. index, Vector3.new(0.6, 8, 0.6), base + Vector3.new(0, 4, 0),
			Color3.fromRGB(40, 42, 52), Enum.Material.Metal, true)
		local head = block(dressing, "LampHead" .. index, Vector3.new(1.6, 1.6, 1.6), base + Vector3.new(0, 8.6, 0),
			LAMP_GLOW, Enum.Material.Neon)
		head.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = LAMP_GLOW
		light.Range = 30
		light.Brightness = 1.6
		light.Parent = head
	end

	-- The descent well: a glowing ring on the floor round the solo portal.
	local wellCentre = origin + PEDESTAL_OFFSET
	local ringY = floorY + 0.06
	local reach, width = 6, 0.5
	local ring = {
		{ "WellNorth", Vector3.new(reach * 2, 0.08, width), Vector3.new(0, ringY, -reach) },
		{ "WellSouth", Vector3.new(reach * 2, 0.08, width), Vector3.new(0, ringY, reach) },
		{ "WellEast", Vector3.new(width, 0.08, reach * 2 - width * 2), Vector3.new(reach, ringY, 0) },
		{ "WellWest", Vector3.new(width, 0.08, reach * 2 - width * 2), Vector3.new(-reach, ringY, 0) },
	}
	for _, strip in ring do
		block(dressing, strip[1], strip[2], wellCentre + strip[3], GATE_GLOW, Enum.Material.Neon)
	end

	-- The zones of the descent, in order, high on the north wall.
	local zones = {}
	for _, zone in RunConfig.Zones do
		table.insert(zones, zone)
	end
	table.sort(zones, function(a, b)
		return a.Order < b.Order
	end)
	local bannerColors = {
		Ruins = Color3.fromRGB(150, 176, 220),
		Foundry = Color3.fromRGB(230, 140, 70),
		Abyss = Color3.fromRGB(170, 110, 240),
	}
	for index, zone in zones do
		local position = origin + Vector3.new((index - 2) * 26, floorY + 10.5, -HALF_Z + 0.5)
		local color = bannerColors[zone.Id] or TRIM
		block(dressing, "ZoneBanner" .. index, Vector3.new(9, 6.5, 0.4), position, color, Enum.Material.Fabric)
		Signage.Board(signs, "ZoneSign" .. index, Vector3.new(8.4, 2, 0.2), position + Vector3.new(0, 0, 0.35),
			SOUTH, zone.DisplayName:upper(), SIGN_TEXT, color:Lerp(Color3.new(0, 0, 0), 0.55))
	end

	return dressing
end

-- Invisible walls well above anything climbable, and a ceiling, so nobody leaves the hall.
function LobbyBuilder._buildBarrier(lobby, origin)
	local folder = Instance.new("Folder")
	folder.Name = "Barrier"
	folder.Parent = lobby

	local floorY = RoomConfig.FloorY
	local outX, outZ = HALF_X + HALL_THICKNESS + 1, HALF_Z + HALL_THICKNESS + 1
	local spanX, spanZ = (outX + 1) * 2, (outZ + 1) * 2
	local y = floorY + BARRIER_HEIGHT / 2
	local parts = {
		{ "BarrierWallNorth", Vector3.new(spanX, BARRIER_HEIGHT, 2), Vector3.new(0, y, -outZ) },
		{ "BarrierWallSouth", Vector3.new(spanX, BARRIER_HEIGHT, 2), Vector3.new(0, y, outZ) },
		{ "BarrierWallEast", Vector3.new(2, BARRIER_HEIGHT, spanZ), Vector3.new(outX, y, 0) },
		{ "BarrierWallWest", Vector3.new(2, BARRIER_HEIGHT, spanZ), Vector3.new(-outX, y, 0) },
		{ "BarrierCeiling", Vector3.new(spanX, 2, spanZ), Vector3.new(0, floorY + CEILING_Y, 0) },
	}
	for _, spec in parts do
		local part = block(folder, spec[1], spec[2], origin + spec[3], Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, true)
		part.Transparency = 1
		part.CastShadow = false
	end
	return folder
end

return LobbyBuilder
