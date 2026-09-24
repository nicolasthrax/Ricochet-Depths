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

	-- Set by the game loop: (raycastResult, entry) -> true to consume the projectile.
	-- The entry carries direction, damage, contacts and shooter, so no extra table is allocated.
	self.OnImpact = nil
	-- Optional (entry, from, to), called with each frame's travel before collision: how room
	-- mechanics such as amp pads see a shot pass over them.
	self.SegmentHook = nil

	-- Optional: (position, margin) -> instance, normal. Consulted only for a projectile that
	-- made no contact this frame, to catch a body that moved over it. See ResolveEnemyOverlap.
	self.OverlapQuery = nil
	-- Optional (entry, position): a projectile finished its flight (out of bounces, time, or
	-- consumed) at `position`. Not called for Clear, which ends every shot at once.
	self.OnExpire = nil

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

-- options carries the shooter's upgraded stats: damage, bounces, speedMultiplier,
-- lifetimeBonus and damagePerBounce. Omitted fields fall back to the config defaults.
function ProjectileService:Fire(shooter, origin, direction, power, options)
	local base = Vector3.new(origin.X, self._planeY, origin.Z)
	local part = self._pool:Acquire(self:_resolveMuzzle(base, direction), options and options.trail)
	if not part then
		return false
	end

	options = options or {}

	local multiplier = ProjectileConfig.MinSpeedMultiplier
		+ (ProjectileConfig.MaxSpeedMultiplier - ProjectileConfig.MinSpeedMultiplier) * power
	local speed = ProjectileConfig.BaseSpeed * multiplier * (options.speedMultiplier or 1)

	local spawnPosition = part.Position
	part.AssemblyLinearVelocity = direction * speed
	table.insert(self._active, {
		part = part,
		direction = direction,
		speed = speed,
		position = spawnPosition, -- authoritative position, swept against each frame
		bouncesLeft = options.bounces or ProjectileConfig.MaxBounces,
		expiresAt = os.clock() + ProjectileConfig.Lifetime + (options.lifetimeBonus or 0),
		shooter = shooter,
		damage = options.damage or 1,
		damagePerBounce = options.damagePerBounce or 0,
		-- The shooter's stats table at firing time (shot effects); nil for a plain shot.
		stats = options.stats,
		-- The one projectile of a throw that is the player's orb; it drops when it stops.
		carriesOrb = options.carriesOrb == true,
		baseSpeed = speed,
		-- Wall, cover and reflector bounces so far (enemy contacts are not bounces).
		wallBounces = 0,
		contacts = 0,
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
	if self.SegmentHook then
		self.SegmentHook(entry, from, to)
	end

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

		entry.contacts += 1
		if self.OnImpact and self.OnImpact(result, entry) then
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

	-- The loop can run out of its per-frame bounce allowance with travel still pending. If that
	-- last stretch would cross geometry, advancing to it would put the projectile outside the
	-- room, where a forward cast finds nothing and it is gone for good. Losing a fraction of a
	-- frame's travel is invisible; leaking out of the arena is not.
	if resolved >= ProjectileConfig.MaxBouncesPerStep then
		local pending = to - from
		if pending.Magnitude > 1e-4 then
			local castOrigin = from - entry.direction * ProjectileConfig.CastBackStep
			if workspace:Raycast(castOrigin, to - castOrigin, self._rayParams) then
				to = from -- hold at the last point known to be inside
			end
		end
	end

	-- Nothing was struck, so check whether something moved on top of us. A swept cast whose
	-- origin sits inside a part reports nothing, which would otherwise let the projectile pass
	-- straight through a body that slid over it.
	if resolved == 0 and ProjectileConfig.ResolveEnemyOverlap and self.OverlapQuery then
		local instance, normal = self.OverlapQuery(to, ProjectileConfig.Radius)
		if instance and normal then
			entry.contacts += 1
			local contact = { Position = to, Normal = normal, Instance = instance, Distance = 0 }
			if self.OnImpact and self.OnImpact(contact, entry) then
				entry.position = to
				return false
			end
			if entry.bouncesLeft <= 0 then
				return false
			end
			entry.bouncesLeft -= 1

			local reflected = entry.direction - 2 * entry.direction:Dot(normal) * normal
			reflected = Vector3.new(reflected.X, 0, reflected.Z)
			if reflected.Magnitude < 1e-4 then
				return false
			end
			entry.direction = reflected.Unit
			to = to + normal * (ProjectileConfig.Radius + ProjectileConfig.SurfaceSkin)
			resolved = 1
		end
	end

	-- A portal crossed this frame (RoomMechanics) moves the shot to its partner.
	if entry.teleportTo then
		to = entry.teleportTo
		entry.teleportTo = nil
		resolved = math.max(resolved, 1)
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
			if self.OnExpire then
				self.OnExpire(entry, entry.position)
			end
		end
	end
end

-- Despawns every live projectile, e.g. when a run ends. Leaves the pool full.
function ProjectileService:Clear()
	for index = #self._active, 1, -1 do
		self._pool:Release(self._active[index].part)
		self._active[index] = nil
	end
end

-- Every live projectile, for systems that steer shots (Magnets).
function ProjectileService:GetActive()
	return self._active
end

function ProjectileService:Destroy()
	self.SegmentHook = nil
	self.OnExpire = nil
	self:Clear()
	self._pool:Destroy()
	self.OnImpact = nil
end

function ProjectileService:GetActiveCount()
	return #self._active
end

function ProjectileService:GetFreeCount()
	return self._pool:GetFreeCount()
end

return ProjectileService
