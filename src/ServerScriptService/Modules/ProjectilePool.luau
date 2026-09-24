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

	-- A cosmetic trail, built once with the part and only ever enabled or recoloured. Two
	-- attachments across the ball give it a ribbon the width of the projectile.
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, ProjectileConfig.Radius * 0.8, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -ProjectileConfig.Radius * 0.8, 0)
	bottom.Parent = part
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Enabled = false
	trail.Parent = part
	return part
end

function ProjectilePool.new(parent)
	local self = setmetatable({}, ProjectilePool)
	self._pool = PartPool.new("ProjectilePool", parent, ProjectileConfig.PoolSize, createProjectilePart)
	self.Folder = self._pool.Folder
	return self
end

-- Returns nil when the pool is dry. Callers drop the shot rather than allocating.
-- trail is an optional ShopConfig trail definition ({ Color, Lifetime }).
function ProjectilePool:Acquire(position, trail)
	local part = self._pool:Acquire()
	if not part then
		return nil
	end

	part.Position = position
	part.Anchored = false
	part.Transparency = 0
	-- Enabled only after the move from storage, so the ribbon never streaks in from there.
	local effect = part:FindFirstChild("Trail")
	if effect and trail then
		effect.Color = ColorSequence.new(trail.Color)
		effect.Lifetime = trail.Lifetime
		effect.Enabled = true
	end
	return part
end

function ProjectilePool:Release(part)
	-- Disabled before the move back to storage, for the same reason.
	local effect = part:FindFirstChild("Trail")
	if effect then
		effect.Enabled = false
	end
	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	-- Bounce power grows and recolours a shot in flight; the next one starts fresh.
	part.Size = Vector3.one * (ProjectileConfig.Radius * 2)
	part.Color = ProjectileConfig.Color
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
