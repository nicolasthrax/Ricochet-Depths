-- The Descent Hall, where players gather between runs. North: the solo portal (a pedestal) in
-- front of the zone banners. West: two multiplayer gates of 2-4 players. East: the Outpost portal
-- (to your home base) and the Cosmetics kiosk. South: the (invisible) spawn. An invisible barrier and ceiling keep everyone inside.
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
	{ Name = "OutpostKiosk", Z = -14, Title = "YOUR OUTPOST", Prompt = "OpenOutpostPrompt", Object = "Outpost",
		Action = "Go to your base", Color = Color3.fromRGB(255, 196, 120) },
	{ Name = "CosmeticsKiosk", Z = 14, Title = "COSMETICS", Prompt = "OpenCosmeticsPrompt", Object = "Cosmetics",
		Action = "Browse", Color = Color3.fromRGB(200, 150, 255) },
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
	-- Characters spawn facing the pad's front: north, straight at the descent well.
	local spawnAt = origin + SPAWN_OFFSET + Vector3.new(0, floorY + RoomConfig.SpawnPadSize.Y / 2, 0)
	spawnPad.CFrame = CFrame.lookAt(spawnAt, spawnAt + Vector3.new(0, 0, -1))
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
	LobbyBuilder._buildLandmarks(lobby, signs, origin)
	LobbyBuilder._buildAmbience(lobby, origin)
	local leaderboards = LobbyBuilder._buildLeaderboards(lobby, origin)
	LobbyBuilder._buildBarrier(lobby, origin)

	return lobby, soloPrompt, {
		gates = gates,
		outpostPrompt = prompts.OutpostKiosk,
		cosmeticsPrompt = prompts.CosmeticsKiosk,
		leaderboards = leaderboards,
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

-- The Outpost and Cosmetics kiosks on the east side, facing the hall, each under a canopy with
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
		prompt.ActionText = spec.Action
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

local GOLD = Color3.fromRGB(255, 214, 120)
local EMBER = Color3.fromRGB(255, 140, 60)
local NORTH = Vector3.new(0, 0, -1)

-- The name over the north wall, a walkway from the spawn to the solo portal, and fire braziers
-- by the portal, the gates and the shops.
function LobbyBuilder._buildLandmarks(lobby, signs, origin)
	local dressing = lobby:FindFirstChild("Dressing")
	local floorY = RoomConfig.FloorY

	Signage.Board(signs, "TitleSign", Vector3.new(44, 5, 0.3), origin + Vector3.new(0, floorY + 19, -HALF_Z + 0.2),
		SOUTH, "RICOCHET DEPTHS", GOLD, SIGN_BACK)
	Signage.Board(signs, "TaglineSign", Vector3.new(26, 1.4, 0.2), origin + Vector3.new(0, floorY + 15, -HALF_Z + 0.4),
		SOUTH, "BANK YOUR SHOTS  ·  CHAIN YOUR KILLS  ·  ESCAPE THE DEPTHS", SIGN_TEXT, SIGN_BACK)

	-- The walkway: a dark runner edged in light, from the spawn to the well.
	local runnerStart, runnerEnd = -20, 30
	local runnerZ, runnerLength = (runnerStart + runnerEnd) / 2, runnerEnd - runnerStart
	block(dressing, "Runner", Vector3.new(8, 0.06, runnerLength), origin + Vector3.new(0, floorY + 0.03, runnerZ),
		Color3.fromRGB(32, 34, 48), Enum.Material.Fabric)
	for side, x in { West = -4.2, East = 4.2 } do
		block(dressing, "RunnerEdge" .. side, Vector3.new(0.3, 0.08, runnerLength), origin + Vector3.new(x, floorY + 0.04, runnerZ),
			GATE_GLOW, Enum.Material.Neon)
	end

	local braziers = {
		Vector3.new(-12, 0, -30), Vector3.new(12, 0, -30), -- the solo portal
		Vector3.new(-33, 0, 0), -- between the gates
		Vector3.new(40, 0, 0), -- between the shops
	}
	for index, spot in braziers do
		local base = origin + spot + Vector3.new(0, floorY, 0)
		block(dressing, "Brazier" .. index .. "Stand", Vector3.new(1.4, 3, 1.4), base + Vector3.new(0, 1.5, 0),
			Color3.fromRGB(40, 42, 52), Enum.Material.Metal, true)
		block(dressing, "Brazier" .. index .. "Bowl", Vector3.new(2.6, 0.6, 2.6), base + Vector3.new(0, 3.3, 0),
			Color3.fromRGB(70, 60, 50), Enum.Material.Metal, true)
		local ember = block(dressing, "Brazier" .. index .. "Embers", Vector3.new(2, 0.2, 2), base + Vector3.new(0, 3.65, 0),
			EMBER, Enum.Material.Neon)
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 8
		fire.Color = EMBER
		fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
		fire.Parent = ember
		local light = Instance.new("PointLight")
		light.Color = EMBER
		light.Range = 18
		light.Brightness = 1.8
		light.Parent = ember
	end
	return dressing
end

-- Things that move: crystals turning over the well (animated on each client by LobbyAmbience,
-- from their Spin and Bob attributes), motes rising from the well and dust drifting in the hall.
-- All non-solid, and kept apart from Dressing so nothing here counts as a prop.
function LobbyBuilder._buildAmbience(lobby, origin)
	local folder = Instance.new("Folder")
	folder.Name = "Ambience"
	folder.Parent = lobby
	local floorY = RoomConfig.FloorY
	local well = origin + PEDESTAL_OFFSET

	local crystals = {
		{ Size = Vector3.new(2, 4, 2), Offset = Vector3.new(0, 11, 0), Color = GATE_GLOW, Spin = 45 },
		{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(4, 9, 0), Color = Color3.fromRGB(200, 150, 255), Spin = -70 },
		{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(-4, 9, 0), Color = Color3.fromRGB(200, 150, 255), Spin = 70 },
		{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(0, 9, 4), Color = GOLD, Spin = 60 },
		{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(0, 9, -4), Color = GOLD, Spin = -60 },
	}
	for index, spec in crystals do
		local crystal = block(folder, "Crystal" .. index, spec.Size, well + spec.Offset + Vector3.new(0, floorY, 0),
			spec.Color, Enum.Material.Neon)
		crystal.CastShadow = false
		crystal:SetAttribute("Spin", spec.Spin)
		crystal:SetAttribute("Bob", index == 1 and 0.8 or 0.5)
		if index == 1 then
			local light = Instance.new("PointLight")
			light.Color = spec.Color
			light.Range = 24
			light.Brightness = 2
			light.Parent = crystal
		end
	end

	local function emitterPart(name, size, position)
		local part = block(folder, name, size, position, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
		part.Transparency = 1
		part.CastShadow = false
		return part
	end

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Color = ColorSequence.new(GATE_GLOW, Color3.fromRGB(200, 150, 255))
	motes.LightEmission = 1
	motes.Rate = 14
	motes.Lifetime = NumberRange.new(2.5, 4.5)
	motes.Speed = NumberRange.new(3, 6)
	motes.Size = NumberSequence.new(0.35, 0)
	motes.Transparency = NumberSequence.new(0.1, 1)
	motes.Parent = emitterPart("WellMotes", Vector3.new(10, 0.2, 10), well + Vector3.new(0, floorY + 0.2, 0))

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 236, 200))
	dust.LightEmission = 0.4
	dust.Rate = 18
	dust.Lifetime = NumberRange.new(8, 12)
	dust.Speed = NumberRange.new(0.3, 0.8)
	dust.EmissionDirection = Enum.NormalId.Bottom
	dust.Size = NumberSequence.new(0.12, 0.05)
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.Parent = emitterPart("HallDust", Vector3.new(SIZE.X - 8, 0.2, SIZE.Z - 8), origin + Vector3.new(0, floorY + 14, 0))
	return folder
end

-- Three global leaderboards on the south wall, printed by LeaderboardService. Returns
-- board id -> the part whose sign shows the rows.
local LEADERBOARDS = {
	{ Id = "Level", Title = "TOP LEVELS", X = -30, Color = GOLD },
	{ Id = "Kills", Title = "MOST DEFEATED", X = 0, Color = Color3.fromRGB(240, 118, 118) },
	{ Id = "Extractions", Title = "MOST EXTRACTIONS", X = 30, Color = Color3.fromRGB(122, 224, 146) },
}

function LobbyBuilder._buildLeaderboards(lobby, origin)
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = lobby
	local floorY = RoomConfig.FloorY
	local z = HALF_Z - 0.3
	local boards = {}
	for _, spec in LEADERBOARDS do
		local centre = origin + Vector3.new(spec.X, floorY, z)
		Signage.Board(folder, spec.Id .. "Header", Vector3.new(16, 2.2, 0.2), centre + Vector3.new(0, 15, 0),
			NORTH, spec.Title, spec.Color, SIGN_BACK)
		boards[spec.Id] = Signage.Board(folder, "Leaderboard" .. spec.Id, Vector3.new(16, 11, 0.2), centre + Vector3.new(0, 8, 0),
			NORTH, "Loading...", SIGN_TEXT, SIGN_BACK)
		-- A lit frame round the board.
		for side, x in { Left = -8.3, Right = 8.3 } do
			block(folder, spec.Id .. "Frame" .. side, Vector3.new(0.4, 13.6, 0.4), centre + Vector3.new(x, 9.2, -0.1),
				spec.Color, Enum.Material.Neon)
		end
		block(folder, spec.Id .. "FrameBase", Vector3.new(17, 0.4, 0.4), centre + Vector3.new(0, 2.3, -0.1),
			spec.Color, Enum.Material.Neon)
	end
	return boards
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
