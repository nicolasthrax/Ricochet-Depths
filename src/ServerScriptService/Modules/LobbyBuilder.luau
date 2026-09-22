-- The hub players return to between runs, with the interaction that starts a descent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local LobbyBuilder = {}

local SIZE = Vector3.new(80, 1, 80)
local PEDESTAL_SIZE = Vector3.new(6, 5, 6)
local PEDESTAL_OFFSET = Vector3.new(0, 0, -14)

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

	return lobby, prompt
end

return LobbyBuilder
