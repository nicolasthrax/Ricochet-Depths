-- Projectile pool: parts are built once at boot and reused forever.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartPool = require(script.Parent.PartPool)
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))

local ProjectilePool = {}
ProjectilePool.__index = ProjectilePool

local function createProjectilePart()
	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * (ProjectileConfig.Radius * 2)
	part.Color = ProjectileConfig.Color
	part.Material = ProjectileConfig.Material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Position = ProjectileConfig.StoragePosition
	return part
end

function ProjectilePool.new(parent)
	local self = setmetatable({}, ProjectilePool)
	self._pool = PartPool.new("ProjectilePool", parent, ProjectileConfig.PoolSize, createProjectilePart)
	self.Folder = self._pool.Folder
	return self
end

-- Returns nil when the pool is dry. Callers drop the shot rather than allocating.
function ProjectilePool:Acquire(position)
	local part = self._pool:Acquire()
	if not part then
		return nil
	end

	part.Position = position
	part.Anchored = false
	part.Transparency = 0
	return part
end

function ProjectilePool:Release(part)
	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.Transparency = 1
	part.Position = ProjectileConfig.StoragePosition
	self._pool:Release(part)
end

function ProjectilePool:GetFreeCount()
	return self._pool:GetFreeCount()
end

function ProjectilePool:Destroy()
	self._pool:Destroy()
end

return ProjectilePool
