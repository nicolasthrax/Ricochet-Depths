-- Enemy body pool. Each body owns a cosmetic shield slab; the shield never blocks raycasts,
-- because shielding is decided by the arc maths in EnemyService, not by geometry.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage:WaitForChild("EnemyConfig"))
local PartPool = require(script.Parent.PartPool)

local EnemyPool = {}
EnemyPool.__index = EnemyPool

local function createEnemyPart()
	local part = Instance.new("Part")
	part.Name = "Enemy"
	part.Size = Vector3.new(3, EnemyConfig.BodyHeight, 3)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.CanQuery = false -- idle bodies are invisible to raycasts until they are spawned
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Position = EnemyConfig.StoragePosition

	local shield = Instance.new("Part")
	shield.Name = "Shield"
	shield.Anchored = true
	shield.CanCollide = false
	shield.CanTouch = false
	shield.CanQuery = false -- cosmetic only
	shield.CastShadow = false
	shield.Transparency = 1
	shield.Position = EnemyConfig.StoragePosition
	shield.Parent = part

	return part
end

function EnemyPool.new(parent)
	local self = setmetatable({}, EnemyPool)
	self._pool = PartPool.new("EnemyPool", parent, EnemyConfig.PoolSize, createEnemyPart)
	self.Folder = self._pool.Folder
	return self
end

function EnemyPool:Acquire(archetype, position)
	local part = self._pool:Acquire()
	if not part then
		return nil
	end

	part.Size = archetype.Size
	part.Color = archetype.Color
	part.Material = archetype.Material
	part.Transparency = 0
	part.CanQuery = true
	part.Position = position
	part.Name = archetype.Id

	local shield = part:FindFirstChild("Shield")
	if archetype.Shield then
		shield.Size = Vector3.new(archetype.Size.X * 1.15, EnemyConfig.BodyHeight * 0.85, archetype.Shield.Thickness)
		shield.Color = archetype.Shield.Color
		shield.Transparency = 0.25
	else
		shield.Transparency = 1
		shield.Position = EnemyConfig.StoragePosition
	end

	return part
end

function EnemyPool:Release(part)
	part.Transparency = 1
	part.CanQuery = false
	part:SetAttribute("Phasing", nil)
	part:SetAttribute("Facing", nil)
	-- Champion affix and status effects are per life, never carried into the next spawn.
	part:SetAttribute("Champion", nil)
	part:SetAttribute("Burning", nil)
	part:SetAttribute("Chilled", nil)
	part.Position = EnemyConfig.StoragePosition
	local shield = part:FindFirstChild("Shield")
	if shield then
		shield.Transparency = 1
		shield.Position = EnemyConfig.StoragePosition
	end
	self._pool:Release(part)
end

function EnemyPool:GetFreeCount()
	return self._pool:GetFreeCount()
end

function EnemyPool:Destroy()
	self._pool:Destroy()
end

return EnemyPool
