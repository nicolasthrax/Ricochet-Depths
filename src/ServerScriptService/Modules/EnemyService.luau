-- Server-authoritative enemy registry: spawning, movement, damage, contact and cleanup.
-- Enemy positions are integrated directly on anchored parts, so the server is the only writer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyBehaviour = require(script.Parent.EnemyBehaviour)
local EnemyConfig = require(ReplicatedStorage:WaitForChild("EnemyConfig"))
local EnemyPool = require(script.Parent.EnemyPool)
local PartPool = require(script.Parent.PartPool)
local RoomGeometry = require(ReplicatedStorage:WaitForChild("RoomGeometry"))

local function createOrbPart()
	local part = Instance.new("Part")
	part.Name = "Orb"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(EnemyConfig.OrbSize, EnemyConfig.OrbSize, EnemyConfig.OrbSize)
	part.Color = EnemyConfig.OrbColor
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false -- player shots pass through orbs
	part.CastShadow = false
	part.Transparency = 1
	part.Position = EnemyConfig.StoragePosition
	return part
end

local EnemyService = {}
EnemyService.__index = EnemyService

function EnemyService.new(parent, planeY, seed)
	local self = setmetatable({}, EnemyService)

	self._pool = EnemyPool.new(parent)
	self._orbPool = PartPool.new("OrbPool", parent, EnemyConfig.OrbPoolSize, createOrbPart)
	self._orbs = {}
	self._orbsFired = 0
	-- Solids (RoomGeometry footprints) that stop orbs. Set per room.
	self._obstacles = {}
	self._enemies = {}
	self._byPart = {}
	self._planeY = planeY
	self._nextId = 0
	self._random = Random.new(seed or 1)
	self._bounds = nil
	self._targetProvider = nil
	-- Enemies that actually moved on the last step. Only these can have slid over a
	-- projectile, so only these are worth testing for enclosure.
	self._movers = {}

	-- Set by the encounter layer.
	self.OnDeath = nil -- (enemy, shooter)
	self.OnPlayerContact = nil -- (player, damage, enemy, now)

	return self
end

-- Targets are supplied as { { player = Player, position = Vector3 }, ... }.
function EnemyService:SetTargetProvider(provider)
	self._targetProvider = provider
end

-- Keeps enemies inside the playable area; halfExtents is a Vector2 on the XZ plane.
-- diagonal, when given, caps |x| + |z| around the centre: rooms with bevelled corners use it
-- to keep enemies out of the sealed space behind each bevel, where no shot could reach them.
function EnemyService:SetBounds(center, halfExtents, diagonal)
	self._bounds = { center = center, half = halfExtents, diagonal = diagonal }
end

-- The room's cover, as RoomGeometry footprints. Orbs die on it.
function EnemyService:SetObstacles(footprints)
	self._obstacles = footprints or {}
end

function EnemyService:GetObstacles()
	return self._obstacles
end

-- The boss's current phase, 1-based.
EnemyService.BossPhase = EnemyBehaviour.BossPhase

function EnemyService:GetOrbs()
	return table.clone(self._orbs)
end

function EnemyService:GetFreeOrbCount()
	return self._orbPool:GetFreeCount()
end

-- Orbs fired since this service was made; for tests and telemetry.
function EnemyService:GetOrbsFired()
	return self._orbsFired
end

function EnemyService:_fireOrb(source, direction, speed, damage, now)
	local part = self._orbPool:Acquire()
	if not part then
		return nil
	end
	local start = source.position + direction * (source.archetype.Size.X / 2 + EnemyConfig.OrbSize)
	part.Position = start
	part.Transparency = 0
	local orb = {
		part = part,
		position = start,
		velocity = direction * speed,
		damage = damage,
		source = source,
		expiresAt = now + EnemyConfig.OrbLifetime,
	}
	table.insert(self._orbs, orb)
	self._orbsFired += 1
	return orb
end

function EnemyService:_releaseOrb(index)
	local orb = self._orbs[index]
	table.remove(self._orbs, index)
	orb.part.Transparency = 1
	orb.part.Position = EnemyConfig.StoragePosition
	self._orbPool:Release(orb.part)
end

function EnemyService:_outOfBounds(position)
	local bounds = self._bounds
	if not bounds then
		return false
	end
	return math.abs(position.X - bounds.center.X) > bounds.half.X + 4 or math.abs(position.Z - bounds.center.Z) > bounds.half.Y + 4
end

function EnemyService:_stepOrbs(dt, now, targets)
	for index = #self._orbs, 1, -1 do
		local orb = self._orbs[index]
		local from = orb.position
		local to = from + orb.velocity * dt
		local spent = now >= orb.expiresAt or self:_outOfBounds(to)
			or RoomGeometry.SegmentBlocked(self._obstacles, Vector2.new(from.X, from.Z), Vector2.new(to.X, to.Z))
		if not spent then
			orb.position = to
			orb.part.Position = to
			for _, target in targets do
				local offset = Vector3.new(target.position.X - to.X, 0, target.position.Z - to.Z)
				if offset.Magnitude <= EnemyConfig.OrbHitRadius then
					if self.OnPlayerContact then
						self.OnPlayerContact(target.player, orb.damage, orb.source, now)
					end
					spent = true
					break
				end
			end
		end
		if spent then
			self:_releaseOrb(index)
		end
	end
end

-- Carries out what a behaviour asked for this step: orbs to fire and allies to summon.
function EnemyService:_serviceRequests(enemy, now)
	local requests = enemy.fireRequests
	if requests then
		enemy.fireRequests = nil
		for _, request in requests do
			self:_fireOrb(enemy, request.direction, request.speed, request.damage, now)
		end
	end
	local summon = enemy.summonRequest
	if summon then
		enemy.summonRequest = nil
		local alive = 0
		for _, other in self._enemies do
			if other.archetypeId == summon.archetype then
				alive += 1
			end
		end
		for index = 1, math.min(summon.count, summon.max - alive) do
			local angle = self._random:NextNumber() * math.pi * 2
			local reach = enemy.archetype.Size.X / 2 + 3
			self:Spawn(summon.archetype, enemy.position + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach))
			local _ = index
		end
	end
end

function EnemyService:Spawn(archetypeId, position)
	local archetype = EnemyConfig.Get(archetypeId)
	if not archetype then
		return nil, "unknown archetype"
	end
	if #self._enemies >= EnemyConfig.MaxActive then
		return nil, "enemy cap reached"
	end

	local spawnPosition = Vector3.new(position.X, self._planeY, position.Z)
	local part = self._pool:Acquire(archetype, spawnPosition)
	if not part then
		return nil, "enemy pool dry"
	end

	self._nextId += 1
	local enemy = {
		id = self._nextId,
		archetypeId = archetypeId,
		archetype = archetype,
		part = part,
		health = archetype.Health,
		maxHealth = archetype.Health,
		position = spawnPosition,
		anchor = spawnPosition,
		facing = Vector3.new(0, 0, 1),
		phase = "Approach",
		contactReadyAt = 0,
		color = archetype.Color,
		dead = false,
	}

	self._byPart[part] = enemy
	table.insert(self._enemies, enemy)
	return enemy
end

function EnemyService:GetByPart(part)
	return self._byPart[part]
end

function EnemyService:GetActiveCount()
	return #self._enemies
end

function EnemyService:GetEnemies()
	return table.clone(self._enemies)
end

function EnemyService:Despawn(enemy, reason)
	if enemy.dead then
		return false
	end
	enemy.dead = true

	for index, candidate in self._enemies do
		if candidate == enemy then
			table.remove(self._enemies, index)
			break
		end
	end

	self._byPart[enemy.part] = nil
	self._pool:Release(enemy.part)
	enemy.despawnReason = reason
	return true
end

-- Returns a result table describing what the contact did, or nil if the part is not an enemy.
function EnemyService:ApplyHit(part, damage, direction, shooter)
	local enemy = self._byPart[part]
	if not enemy or enemy.dead or enemy.phase == "Blinking" then
		return nil
	end

	local multiplier = 1
	local shield = not enemy.shieldOff and enemy.archetype.Shield
	if shield and direction and direction.Magnitude > 1e-4 and enemy.facing.Magnitude > 1e-4 then
		-- Blocked when the shot arrives within the shield's half-angle of dead-on. A shot
		-- travelling opposite the enemy's facing is a direct hit, so its dot is near -1.
		local alignment = direction.Unit:Dot(enemy.facing.Unit)
		if alignment < -math.cos(math.rad(shield.HalfAngleDegrees)) then
			multiplier = shield.DamageMultiplier
		end
	end

	local applied = math.max(damage * multiplier, 0)
	enemy.health -= applied

	local result = {
		enemy = enemy,
		blocked = applied <= 0,
		damage = applied,
		killed = false,
	}

	if enemy.health <= 0 then
		result.killed = true
		self:Despawn(enemy, "killed")
		if self.OnDeath then
			self.OnDeath(enemy, shooter)
		end
		local split = enemy.archetype.SplitInto
		if split then
			for index = 1, split.Count do
				local angle = (index - 1) * 2 * math.pi / split.Count
				local offset = Vector3.new(math.cos(angle) * split.Spread, 0, math.sin(angle) * split.Spread)
				self:Spawn(split.Archetype, self:_clampToBounds(enemy.position + offset))
			end
		end
	end

	return result
end

local function nearestTarget(targets, position)
	local best, bestDistance
	for _, target in targets do
		local offset = Vector3.new(target.position.X - position.X, 0, target.position.Z - position.Z)
		local distance = offset.Magnitude
		if not bestDistance or distance < bestDistance then
			best, bestDistance = target, distance
		end
	end
	return best, bestDistance
end

function EnemyService:_clampToBounds(position)
	if not self._bounds then
		return position
	end
	local center, half = self._bounds.center, self._bounds.half
	local x = math.clamp(position.X - center.X, -half.X, half.X)
	local z = math.clamp(position.Z - center.Z, -half.Y, half.Y)

	-- Pull a corner position back along the diagonal onto the bevel-safe line.
	local diagonal = self._bounds.diagonal
	if diagonal then
		local excess = math.abs(x) + math.abs(z) - diagonal
		if excess > 0 then
			x -= math.sign(x) * excess / 2
			z -= math.sign(z) * excess / 2
		end
	end
	return Vector3.new(center.X + x, position.Y, center.Z + z)
end

function EnemyService:_applyVisuals(enemy)
	local archetype = enemy.archetype
	local wanted = archetype.Color
	local telegraph = archetype.Lunge or archetype.Fire or archetype.Blink
	if enemy.phase == "Telegraph" and telegraph then
		wanted = telegraph.TelegraphColor
	end
	-- Blinking: see-through and out of reach of every raycast until it lands.
	local blinking = enemy.phase == "Blinking"
	if blinking ~= (enemy.blinking or false) then
		enemy.blinking = blinking
		enemy.part.CanQuery = not blinking
		enemy.part.Transparency = blinking and 0.8 or 0
		enemy.part:SetAttribute("Phasing", blinking)
	end
	-- Turrets never move, so clients cannot infer their heading; publish it when it turns.
	if archetype.ReplicateFacing and enemy.facing.Magnitude > 1e-4 then
		local facing = enemy.facing.Unit
		local last = enemy.publishedFacing
		if not last or last:Dot(facing) < 0.995 then
			enemy.publishedFacing = facing
			enemy.part:SetAttribute("Facing", facing)
		end
	end
	-- Only write when it actually changes, to keep property replication quiet.
	if wanted ~= enemy.color then
		enemy.color = wanted
		enemy.part.Color = wanted
	end

	if archetype.Shield and enemy.facing.Magnitude > 1e-4 then
		local shield = enemy.part:FindFirstChild("Shield")
		if shield and enemy.shieldOff then
			if shield.Transparency < 1 then
				shield.Transparency = 1
			end
		elseif shield then
			shield.CFrame = CFrame.lookAlong(enemy.position + enemy.facing.Unit * archetype.Shield.Offset, enemy.facing.Unit)
		end
	end
end

-- Returns the enemy body containing this point and the outward normal of its nearest face,
-- or nil. Only enemies that moved on the last step are considered: a stationary enemy cannot
-- have engulfed a projectile that a swept cast would otherwise have caught.
function EnemyService:FindEnclosingMover(position, margin)
	margin = margin or 0
	for _, enemy in self._movers do
		if not enemy.dead then
			local size = enemy.archetype.Size
			local halfX = size.X / 2 + margin
			local halfZ = size.Z / 2 + margin
			local offsetX = position.X - enemy.position.X
			local offsetZ = position.Z - enemy.position.Z

			if math.abs(offsetX) <= halfX and math.abs(offsetZ) <= halfZ then
				-- Push out through whichever face is nearest, so the bounce reads correctly.
				local depthX = halfX - math.abs(offsetX)
				local depthZ = halfZ - math.abs(offsetZ)
				local normal
				if depthX <= depthZ then
					normal = Vector3.new(offsetX >= 0 and 1 or -1, 0, 0)
				else
					normal = Vector3.new(0, 0, offsetZ >= 0 and 1 or -1)
				end
				return enemy.part, normal, enemy
			end
		end
	end
	return nil
end

function EnemyService:Step(deltaTime, now)
	local targets = self._targetProvider and self._targetProvider() or {}
	table.clear(self._movers)
	local randomSource = function()
		return self._random:NextNumber()
	end

	self:_stepOrbs(deltaTime, now, targets)

	for index = #self._enemies, 1, -1 do
		local enemy = self._enemies[index]
		local archetype = enemy.archetype
		local target = nearestTarget(targets, enemy.position)

		local behaviour = EnemyBehaviour.Get(archetype.Behaviour)
		if behaviour then
			behaviour(enemy, archetype, deltaTime, target, now, randomSource)
		end

		local previousPosition = enemy.part.Position
		enemy.position = self:_clampToBounds(Vector3.new(enemy.position.X, self._planeY, enemy.position.Z))
		enemy.part.Position = enemy.position
		if (enemy.position - previousPosition).Magnitude > 1e-4 then
			table.insert(self._movers, enemy)
		end
		self:_applyVisuals(enemy)
		self:_serviceRequests(enemy, now)

		if target and (archetype.ContactDamage or 0) > 0 and now >= enemy.contactReadyAt then
			local offset = Vector3.new(target.position.X - enemy.position.X, 0, target.position.Z - enemy.position.Z)
			if offset.Magnitude <= (archetype.ContactRange or 0) then
				enemy.contactReadyAt = now + (archetype.ContactCooldown or EnemyConfig.DefaultContactCooldown)
				if self.OnPlayerContact then
					-- Pass the step's clock through: the handler runs before the run loop's own
					-- Step, so anything it reads from the match would be a frame stale.
					self.OnPlayerContact(target.player, archetype.ContactDamage, enemy, now)
				end
			end
		end
	end
end

function EnemyService:Clear()
	for index = #self._enemies, 1, -1 do
		self:Despawn(self._enemies[index], "cleared")
	end
	for index = #self._orbs, 1, -1 do
		self:_releaseOrb(index)
	end
	table.clear(self._byPart)
	table.clear(self._movers)
end

function EnemyService:Destroy()
	self:Clear()
	self._pool:Destroy()
	self._orbPool:Destroy()
	self._targetProvider = nil
	self.OnDeath = nil
	self.OnPlayerContact = nil
end

return EnemyService
