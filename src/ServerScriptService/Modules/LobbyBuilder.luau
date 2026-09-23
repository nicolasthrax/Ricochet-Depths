-- The hub players return to between runs: the pedestal that starts a descent, a four-pad co-op
-- ready zone, and the salvage shop kiosk. Built at runtime; nothing here is a binary model.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local LobbyBuilder = {}

local SIZE = Vector3.new(80, 1, 80)
local PEDESTAL_SIZE = Vector3.new(6, 5, 6)
local PEDESTAL_OFFSET = Vector3.new(0, 0, -14)

-- Ready zone: a row of pads behind the pedestal, away from the spawn.
local READY_ROW_Z = -26
local PAD_SIZE = Vector3.new(7, 0.4, 7)
local PAD_SPACING = 10
local PAD_IDLE_COLOR = Color3.fromRGB(62, 70, 92)
local PAD_READY_COLOR = Color3.fromRGB(140, 236, 168)

-- Shop kiosk: off to the side of the spawn, facing the room.
local KIOSK_OFFSET = Vector3.new(24, 0, 0)
local KIOSK_SIZE = Vector3.new(6, 7, 4)

function LobbyBuilder.Build(parent)
	local origin = RunConfig.LobbyPosition

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = parent

	local floor = Instance.new("Part")
	floor.Name = "LobbyFloor"
	floor.Size = SIZE
	floor.Position = origin + Vector3.new(0, RoomConfig.FloorY - SIZE.Y / 2, 0)
	floor.Color = Color3.fromRGB(58, 62, 78)
	floor.Anchored = true
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.Parent = lobby

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "LobbySpawn"
	spawnPad.Size = RoomConfig.SpawnPadSize
	spawnPad.Position = origin + Vector3.new(0, RoomConfig.FloorY + RoomConfig.SpawnPadSize.Y / 2, 8)
	spawnPad.Color = Color3.fromRGB(120, 235, 255)
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.TopSurface = Enum.SurfaceType.Smooth
	spawnPad.Parent = lobby

	local pedestal = Instance.new("Part")
	pedestal.Name = "DescentPedestal"
	pedestal.Size = PEDESTAL_SIZE
	pedestal.Position = origin + PEDESTAL_OFFSET + Vector3.new(0, RoomConfig.FloorY + PEDESTAL_SIZE.Y / 2, 0)
	pedestal.Color = Color3.fromRGB(120, 235, 255)
	pedestal.Material = Enum.Material.Neon
	pedestal.Anchored = true
	pedestal.TopSurface = Enum.SurfaceType.Smooth
	pedestal.Parent = lobby

	-- A ProximityPrompt works with mouse, gamepad and touch without any custom input code.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StartRunPrompt"
	prompt.ActionText = "Begin Descent"
	prompt.ObjectText = "Ricochet Depths"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal

	local readyPads = LobbyBuilder._buildReadyZone(lobby, origin)
	local shopPrompt = LobbyBuilder._buildShopKiosk(lobby, origin)
	LobbyBuilder._buildHall(lobby, origin)

	return lobby, prompt, { readyPads = readyPads, shopPrompt = shopPrompt }
end

-- A floating label, for signs players read from a distance.
local function sign(parent, text, color, name)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name or "Sign"
	billboard.Size = UDim2.fromOffset(220, 44)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.LightInfluence = 0
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = billboard
	return billboard
end

-- Four pads in a row behind the pedestal. Standing on one marks you ready; LobbyReady decides
-- when everyone is, and GameBootstrap lights each pad as it fills.
function LobbyBuilder._buildReadyZone(lobby, origin)
	local zone = Instance.new("Folder")
	zone.Name = "ReadyZone"
	zone.Parent = lobby

	local count = RunConfig.Lobby.ReadyPadCount
	local pads = {}
	for index = 1, count do
		local x = (index - (count + 1) / 2) * PAD_SPACING
		local pad = Instance.new("Part")
		pad.Name = "ReadyPad" .. index
		pad.Size = PAD_SIZE
		pad.Position = origin + Vector3.new(x, RoomConfig.FloorY + PAD_SIZE.Y / 2, READY_ROW_Z)
		pad.Anchored = true
		pad.CanCollide = false -- a marker on the floor, walked across freely
		pad.CanTouch = false
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.Parent = zone
		LobbyBuilder.SetPadReady(pad, false)
		local label = sign(pad, tostring(index), Color3.fromRGB(200, 214, 240), "PadLabel")
		label.Size = UDim2.fromOffset(40, 40)
		label.StudsOffset = Vector3.new(0, 2, 0)
		pads[index] = pad
	end
	sign(pads[math.ceil(count / 2)], "READY UP", Color3.fromRGB(140, 236, 168)).StudsOffset = Vector3.new(PAD_SPACING / 2, 4, 0)
	return pads
end

function LobbyBuilder.SetPadReady(pad, ready)
	pad.Color = ready and PAD_READY_COLOR or PAD_IDLE_COLOR
	pad.Material = ready and Enum.Material.Neon or Enum.Material.SmoothPlastic
end

-- The salvage shop's kiosk. Its prompt opens the shop view; purchases go through ShopService.
function LobbyBuilder._buildShopKiosk(lobby, origin)
	local kiosk = Instance.new("Part")
	kiosk.Name = "ShopKiosk"
	kiosk.Size = KIOSK_SIZE
	kiosk.Position = origin + KIOSK_OFFSET + Vector3.new(0, RoomConfig.FloorY + KIOSK_SIZE.Y / 2, 0)
	kiosk.Color = Color3.fromRGB(46, 50, 64)
	kiosk.Material = Enum.Material.Metal
	kiosk.Anchored = true
	kiosk.TopSurface = Enum.SurfaceType.Smooth
	kiosk.Parent = lobby

	local screen = Instance.new("Part")
	screen.Name = "KioskScreen"
	screen.Size = Vector3.new(KIOSK_SIZE.X - 1, 2.4, 0.2)
	screen.Position = kiosk.Position + Vector3.new(0, 1.2, -KIOSK_SIZE.Z / 2 - 0.1)
	screen.Color = Color3.fromRGB(226, 196, 120)
	screen.Material = Enum.Material.Neon
	screen.Anchored = true
	screen.CanCollide = false
	screen.Parent = lobby

	sign(kiosk, "SALVAGE SHOP", Color3.fromRGB(226, 196, 120))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenShopPrompt"
	prompt.ActionText = "Browse"
	prompt.ObjectText = "Salvage Shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = kiosk
	return prompt
end

-- The Descent Hall: walls so nobody walks off into the void, pillars and lamps, a glowing
-- well ring round the pedestal, a canopy over the kiosk, and a banner for each zone below.
-- All cosmetic except the walls, and none of it stands on the spawn, pedestal, pads or kiosk.
local HALL_HEIGHT = 12
local HALL_THICKNESS = 2
local STONE = Color3.fromRGB(66, 72, 92)
local TRIM = Color3.fromRGB(150, 190, 255)
local LAMP_GLOW = Color3.fromRGB(255, 226, 170)

local function hallPart(parent, name, size, position, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function LobbyBuilder._buildHall(lobby, origin)
	local dressing = Instance.new("Folder")
	dressing.Name = "Dressing"
	dressing.Parent = lobby

	local half = SIZE.X / 2
	local floorY = RoomConfig.FloorY
	local wallY = floorY + HALL_HEIGHT / 2
	local span = SIZE.X + HALL_THICKNESS * 2
	local offset = half + HALL_THICKNESS / 2
	local walls = {
		{ "HallWallNorth", Vector3.new(span, HALL_HEIGHT, HALL_THICKNESS), Vector3.new(0, wallY, -offset) },
		{ "HallWallSouth", Vector3.new(span, HALL_HEIGHT, HALL_THICKNESS), Vector3.new(0, wallY, offset) },
		{ "HallWallEast", Vector3.new(HALL_THICKNESS, HALL_HEIGHT, span), Vector3.new(offset, wallY, 0) },
		{ "HallWallWest", Vector3.new(HALL_THICKNESS, HALL_HEIGHT, span), Vector3.new(-offset, wallY, 0) },
	}
	for _, wall in walls do
		local part = hallPart(dressing, wall[1], wall[2], origin + wall[3], STONE, Enum.Material.Concrete)
		part.CanCollide = true -- the one solid thing here: it keeps players on the floor
		hallPart(dressing, (wall[1]:gsub("HallWall", "HallTrim")), wall[2] * Vector3.new(1, 0, 1) + Vector3.new(0.1, 0.4, 0.1),
			origin + wall[3] + Vector3.new(0, HALL_HEIGHT / 2 + 0.2, 0), TRIM, Enum.Material.Neon)
	end

	-- Pillars along the walls, each capped with trim.
	local pillarIndex = 0
	for _, x in { -half + 2, -half / 2, 0, half / 2, half - 2 } do
		for _, z in { -half + 2, half - 2 } do
			pillarIndex += 1
			local position = origin + Vector3.new(x, floorY + (HALL_HEIGHT + 2) / 2, z)
			hallPart(dressing, "Pillar" .. pillarIndex, Vector3.new(2.6, HALL_HEIGHT + 2, 2.6), position, STONE, Enum.Material.Slate)
			hallPart(dressing, "PillarCap" .. pillarIndex, Vector3.new(3.2, 0.5, 3.2),
				position + Vector3.new(0, (HALL_HEIGHT + 2) / 2 + 0.25, 0), TRIM, Enum.Material.Neon)
		end
	end

	-- Lamps in the four quarters of the hall.
	for index, corner in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		local base = origin + Vector3.new(corner[1] * 32, floorY, corner[2] * 32)
		hallPart(dressing, "LampPost" .. index, Vector3.new(0.6, 8, 0.6), base + Vector3.new(0, 4, 0),
			Color3.fromRGB(40, 42, 52), Enum.Material.Metal)
		local head = hallPart(dressing, "LampHead" .. index, Vector3.new(1.6, 1.6, 1.6), base + Vector3.new(0, 8.6, 0),
			LAMP_GLOW, Enum.Material.Neon)
		head.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = LAMP_GLOW
		light.Range = 26
		light.Brightness = 1.4
		light.Parent = head
	end

	-- The descent well: a glowing ring on the floor round the pedestal.
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
		hallPart(dressing, strip[1], strip[2], wellCentre + strip[3], Color3.fromRGB(120, 235, 255), Enum.Material.Neon)
	end

	-- A canopy over the shop kiosk.
	local kioskTop = origin + KIOSK_OFFSET + Vector3.new(0, floorY + KIOSK_SIZE.Y + 1.2, 0)
	hallPart(dressing, "KioskCanopy", Vector3.new(KIOSK_SIZE.X + 3, 0.4, KIOSK_SIZE.Z + 3), kioskTop,
		Color3.fromRGB(90, 70, 48), Enum.Material.WoodPlanks)
	hallPart(dressing, "KioskCanopyTrim", Vector3.new(KIOSK_SIZE.X + 3.2, 0.2, KIOSK_SIZE.Z + 3.2),
		kioskTop - Vector3.new(0, 0.3, 0), Color3.fromRGB(226, 196, 120), Enum.Material.Neon)

	-- The zones of the descent, in order, on the north wall behind the ready pads.
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
		local x = (index - 2) * 20
		local banner = hallPart(dressing, "ZoneBanner" .. index, Vector3.new(8, 9, 0.4),
			origin + Vector3.new(x, floorY + 6.5, -half + 0.4), bannerColors[zone.Id] or TRIM, Enum.Material.Fabric)
		sign(banner, zone.DisplayName:upper(), Color3.fromRGB(240, 240, 250)).StudsOffset = Vector3.new(0, 0, 0.6)
	end

	return dressing
end

return LobbyBuilder
