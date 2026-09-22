-- Fixed-size projectile pool. Every part is built once at boot; Acquire never allocates.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	part.Massless = true
	part.Transparency = 1
	part.Position = ProjectileConfig.StoragePosition
	return part
end

function ProjectilePool.new(parent)
	local self = setmetatable({}, ProjectilePool)

	self.Folder = Instance.new("Folder")
	self.Folder.Name = "ProjectilePool"
	self.Folder.Parent = parent

	self._free = table.create(ProjectileConfig.PoolSize)
	for index = 1, ProjectileConfig.PoolSize do
		local part = createProjectilePart()
		part.Parent = self.Folder
		self._free[index] = part
	end
	self._freeCount = ProjectileConfig.PoolSize

	return self
end

-- Returns nil when the pool is dry. Callers drop the shot rather than allocating.
function ProjectilePool:Acquire(position)
	if self._freeCount == 0 then
		return nil
	end

	local part = self._free[self._freeCount]
	self._free[self._freeCount] = nil
	self._freeCount -= 1

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

	self._freeCount += 1
	self._free[self._freeCount] = part
end

function ProjectilePool:GetFreeCount()
	return self._freeCount
end

return ProjectilePool
