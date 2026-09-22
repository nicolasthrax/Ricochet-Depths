-- Owns every live projectile: pooling, per-frame motion, ricochet resolution and despawn.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local ProjectilePool = require(script.Parent.ProjectilePool)

local ProjectileService = {}
ProjectileService.__index = ProjectileService

function ProjectileService.new(poolParent, collisionRoot, planeY)
	local self = setmetatable({}, ProjectileService)

	self._pool = ProjectilePool.new(poolParent)
	self._active = {}
	self._planeY = planeY

	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Include
	self._rayParams.FilterDescendantsInstances = { collisionRoot }
	self._rayParams.IgnoreWater = true

	-- Set by the game loop: (position, normal, hitPart, shooter) -> true to consume the projectile.
	self.OnImpact = nil

	return self
end

-- Resolves the spawn point ahead of the shooter, pulled back to the near face of anything in
-- between. A projectile spawned inside geometry would never register a hit and would escape.
function ProjectileService:_resolveMuzzle(base, direction)
	local blocked = workspace:Raycast(base, direction * ProjectileConfig.MuzzleOffset, self._rayParams)
	if not blocked then
		return base + direction * ProjectileConfig.MuzzleOffset
	end

	local clearance = math.max(blocked.Distance - (ProjectileConfig.Radius + ProjectileConfig.SurfaceSkin), 0)
	return base + direction * clearance
end

function ProjectileService:Fire(shooter, origin, direction, power)
	local base = Vector3.new(origin.X, self._planeY, origin.Z)
	local part = self._pool:Acquire(self:_resolveMuzzle(base, direction))
	if not part then
		return false
	end

	local multiplier = ProjectileConfig.MinSpeedMultiplier
		+ (ProjectileConfig.MaxSpeedMultiplier - ProjectileConfig.MinSpeedMultiplier) * power
	local speed = ProjectileConfig.BaseSpeed * multiplier

	local spawnPosition = part.Position
	part.AssemblyLinearVelocity = direction * speed
	table.insert(self._active, {
		part = part,
		direction = direction,
		speed = speed,
		position = spawnPosition, -- authoritative position, swept against each frame
		bouncesLeft = ProjectileConfig.MaxBounces,
		expiresAt = os.clock() + ProjectileConfig.Lifetime,
		shooter = shooter,
	})

	return true
end

-- Advances one projectile. Returns false when it should be returned to the pool.
-- Collision is resolved as a swept segment from the projectile's last known position to where
-- physics has moved it, so nothing can tunnel or leak out through a corner between frames.
function ProjectileService:_stepEntry(entry, dt, now)
	if now >= entry.expiresAt then
		return false
	end

	local part = entry.part
	local planeY = self._planeY
	local from = entry.position
	local to = Vector3.new(part.Position.X, planeY, part.Position.Z)
	local resolved = 0

	while resolved < ProjectileConfig.MaxBouncesPerStep do
		local segment = to - from
		if segment.Magnitude < 1e-4 then
			break
		end

		local castOrigin = from - entry.direction * ProjectileConfig.CastBackStep
		local result = workspace:Raycast(castOrigin, to - castOrigin, self._rayParams)
		if not result then
			break
		end

		if self.OnImpact and self.OnImpact(result.Position, result.Normal, result.Instance, entry.shooter) then
			entry.position = result.Position
			return false
		end

		if entry.bouncesLeft <= 0 then
			entry.position = result.Position
			return false
		end
		entry.bouncesLeft -= 1

		-- Elastic reflection about the contact normal: r = d - 2(d.n)n
		local reflected = entry.direction - 2 * entry.direction:Dot(result.Normal) * result.Normal
		reflected = Vector3.new(reflected.X, 0, reflected.Z)
		if reflected.Magnitude < 1e-4 then
			return false
		end
		entry.direction = reflected.Unit

		-- Spend the rest of the frame's travel along the new heading, starting just off the surface.
		local leftover = (to - result.Position).Magnitude
		from = Vector3.new(result.Position.X, planeY, result.Position.Z)
			+ result.Normal * (ProjectileConfig.Radius + ProjectileConfig.SurfaceSkin)
		to = from + entry.direction * leftover
		resolved += 1
	end

	entry.position = to
	if resolved > 0 then
		part.Position = to
	end

	-- Velocity is re-asserted every frame: it overwrites the downward dv gravity added and folds
	-- in a correction term that pulls the projectile back onto its travel plane.
	local yError = planeY - part.Position.Y
	part.AssemblyLinearVelocity =
		Vector3.new(entry.direction.X * entry.speed, yError / dt, entry.direction.Z * entry.speed)

	return true
end

function ProjectileService:Step(deltaTime)
	local dt = math.max(deltaTime, 1 / 240)
	local now = os.clock()

	for index = #self._active, 1, -1 do
		local entry = self._active[index]
		if not self:_stepEntry(entry, dt, now) then
			self._pool:Release(entry.part)
			table.remove(self._active, index)
		end
	end
end

function ProjectileService:GetActiveCount()
	return #self._active
end

function ProjectileService:GetFreeCount()
	return self._pool:GetFreeCount()
end

return ProjectileService
