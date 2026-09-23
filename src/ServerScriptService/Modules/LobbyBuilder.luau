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

-- Studio's Baseplate template ships a floor and a SpawnLocation at the world origin, which is
-- where the rooms are built. Left in place, players spawn there at random instead of in the
-- lobby, and the template floor z-fights the arena's. Only the template's own top-level parts
-- are removed; returns how many.
function LobbyBuilder.ClearTemplate(root)
	local removed = 0
	for _, child in root:GetChildren() do
		if (child.Name == "Baseplate" and child:IsA("BasePart")) or child:IsA("SpawnLocation") then
			child:Destroy()
			removed += 1
		end
	end
	return removed
end

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

	return lobby, prompt, { readyPads = readyPads, shopPrompt = shopPrompt }
end

-- A floating label, for signs players read from a distance.
local function sign(parent, text, color)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
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

return LobbyBuilder
