-- Server bootstrap: builds the room, warms the projectile pool, and owns the fire loop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = script.Parent:WaitForChild("Modules")
local FireValidator = require(Modules.FireValidator)
local ProjectileService = require(Modules.ProjectileService)
local RoomBuilder = require(Modules.RoomBuilder)

local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local fireProjectile = Remotes.Get("FireProjectile")
local projectileImpact = Remotes.Get("ProjectileImpact")

-- Everything a projectile can collide with lives under Arena, so one Include filter covers it.
local arena = Instance.new("Folder")
arena.Name = "Arena"
arena.Parent = workspace

RoomBuilder.Build(arena)

local enemies = Instance.new("Folder")
enemies.Name = "Enemies"
enemies.Parent = arena

local planeY = RoomConfig.FloorY + ProjectileConfig.PlaneHeight
local projectiles = ProjectileService.new(workspace, arena, planeY)

projectiles.OnImpact = function(position, normal, _hitPart, _shooter)
	projectileImpact:FireAllClients(position, normal)
	return false -- walls only for now; Task 3 consumes the projectile on an enemy hit
end

fireProjectile.OnServerEvent:Connect(function(player, direction, power)
	local rootPart, validDirection, validPower = FireValidator.Validate(player, direction, power)
	if not rootPart then
		return
	end

	local origin = rootPart.Position + validDirection * ProjectileConfig.MuzzleOffset
	projectiles:Fire(player, origin, validDirection, validPower)
end)

Players.PlayerRemoving:Connect(FireValidator.Clear)

RunService.Heartbeat:Connect(function(deltaTime)
	projectiles:Step(deltaTime)
end)

_G.RicochetDepths = { Projectiles = projectiles } -- debug handle for Studio command bar
