-- Server-authoritative enemy registry: spawning, movement, damage, contact and cleanup.
-- Enemy positions are integrated directly on anchored parts, so the server is the only writer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
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
	-- Run-wide difficulty (the Depth Pact): multipliers on health, movement and damage dealt.
	self._modifiers = { Health = 1, Speed = 1, Damage = 1 }
	-- The clock of the last Step, for work that happens between steps (a death ring on a kill).
	self._now = 0

	-- Set by the encounter layer.
	self.OnDeath = nil -- (enemy, shooter)
	self.OnPlayerContact = nil -- (player, damage, enemy, now)
	-- Magnet enemies alive after the last step, for steering shots.
	self._magnets = {}
	-- (enemy, damage, shooter, now): a burn tick landed. The encounter layer applies it through
	-- its own damage path, so a burn kill counts, pays and explodes like any other.
	self.OnStatusDamage = nil

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

-- Run-wide multipliers from the Depth Pact. Missing fields stay at 1.
function EnemyService:SetModifiers(modifiers)
	modifiers = type(modifiers) == "table" and modifiers or {}
	self._modifiers = {
		Health = tonumber(modifiers.Health) or 1,
		Speed = tonumber(modifiers.Speed) or 1,
		Damage = tonumber(modifiers.Damage) or 1,
	}
end

function EnemyService:GetModifiers()
	return table.clone(self._modifiers)
end

-- The room's cover, as RoomGeometry footprints. Orbs die on it.
function EnemyService:SetObstacles(footprints)
	self._obstacles = footprints or {}
end

-- Where an enemy's shield points: its own spin for a spinning shield, else the way it faces.
function EnemyService.ShieldFacing(enemy)
	return enemy.shieldFacing or enemy.facing
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
		damage = damage * self._modifiers.Damage,
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

-- Health for clients' health bars, written only when it changes.
function EnemyService._publishHealth(enemy)
	local shown = math.max(math.ceil(enemy.health - 1e-6), 0)
	if enemy.shownHealth ~= shown then
		enemy.shownHealth = shown
		enemy.part:SetAttribute("Health", shown)
	end
end

-- Carries out what a behaviour asked for this step: orbs to fire, allies to summon, and a slam
-- that hits every player within its radius.
function EnemyService:_serviceRequests(enemy, now, targets)
	local slam = enemy.slamRequest
	if slam then
		enemy.slamRequest = nil
		for _, target in targets or {} do
			local offset = Vector3.new(target.position.X - enemy.position.X, 0, target.position.Z - enemy.position.Z)
			if offset.Magnitude <= slam.radius and self.OnPlayerContact then
				self.OnPlayerContact(target.player, slam.damage * self._modifiers.Damage, enemy, now)
			end
		end
	end
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

-- options.champion, when given, is a CombatConfig.Champions id: a tougher version with one affix.
-- options.optional: this one never holds a room open. options.coins: what it drops, in place of
-- its archetype's. options.hunter: sent by depth pressure, so it earns no champion credit.
function EnemyService:Spawn(archetypeId, position, options)
	local archetype = EnemyConfig.Get(archetypeId)
	if not archetype then
		return nil, "unknown archetype"
	end
	local champion = options and options.champion and CombatConfig.Champions[options.champion] or nil
	if #self._enemies >= EnemyConfig.MaxActive then
		return nil, "enemy cap reached"
	end

	local spawnPosition = Vector3.new(position.X, self._planeY, position.Z)
	local part = self._pool:Acquire(archetype, spawnPosition)
	if not part then
		return nil, "enemy pool dry"
	end

	self._nextId += 1
	local health = math.max(math.ceil(archetype.Health * self._modifiers.Health
		* (champion and champion.HealthMultiplier or 1) - 1e-6), 1)
	local enemy = {
		id = self._nextId,
		archetypeId = archetypeId,
		archetype = archetype,
		champion = champion,
		-- Coins dropped on death; champions pay more.
		coins = options and options.coins
			or (archetype.Coins or 0) * (champion and CombatConfig.ChampionCoinMultiplier or 1),
		optional = options and options.optional == true or nil,
		hunter = options and options.hunter == true or nil,
		speedScale = champion and champion.SpeedMultiplier or 1,
		spawnedAt = self._now,
		part = part,
		health = health,
		maxHealth = health,
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
	part:SetAttribute("MaxHealth", health)
	EnemyService._publishHealth(enemy)
	if champion then
		part:SetAttribute("Champion", champion.Id)
		if champion.Regen then
			enemy.regenAt = self._now + champion.Regen.Interval
		end
	end
	return enemy
end

-- Sets a hit enemy burning and/or chilled. A new burn replaces a weaker one and refreshes the
-- timer; chill only ever extends.
function EnemyService:ApplyStatus(enemy, burnDamage, chillSeconds, shooter, now)
	if not enemy or enemy.dead then
		return
	end
	now = now or self._now
	if (burnDamage or 0) > 0 then
		local burn = enemy.burn
		if not burn or burnDamage >= burn.dps or now >= burn.untilAt then
			enemy.burn = {
				dps = burnDamage,
				untilAt = now + CombatConfig.BurnDuration,
				nextTick = burn and burn.nextTick > now and burn.nextTick or now + CombatConfig.BurnTick,
				shooter = shooter,
			}
		else
			burn.untilAt = now + CombatConfig.BurnDuration
		end
	end
	if (chillSeconds or 0) > 0 then
		enemy.chillUntil = math.max(enemy.chillUntil or 0, now + chillSeconds)
	end
end

function EnemyService.IsChilled(enemy, now)
	return (enemy.chillUntil or 0) > now
end

-- Live enemies within `radius` of `position` on the travel plane, nearest first, never
-- `exclude`. At most `limit` of them when a limit is given.
function EnemyService:FindNear(position, radius, exclude, limit)
	local found = {}
	for _, enemy in self._enemies do
		if enemy ~= exclude and not enemy.dead and enemy.phase ~= "Blinking" then
			local offset = Vector3.new(enemy.position.X - position.X, 0, enemy.position.Z - position.Z)
			local distance = offset.Magnitude
			if distance <= radius then
				table.insert(found, { enemy = enemy, distance = distance })
			end
		end
	end
	table.sort(found, function(a, b)
		if a.distance == b.distance then
			return a.enemy.id < b.enemy.id
		end
		return a.distance < b.distance
	end)
	local result = {}
	for index, entry in found do
		if limit and index > limit then
			break
		end
		table.insert(result, entry.enemy)
	end
	return result
end

function EnemyService:GetByPart(part)
	return self._byPart[part]
end

function EnemyService:GetActiveCount()
	return #self._enemies
end

-- Enemies a room needs dead to clear: everything but Optional ones (the Treasure Runner).
function EnemyService:GetRequiredCount()
	local count = 0
	for _, enemy in self._enemies do
		if not enemy.archetype.Optional and not enemy.optional then
			count += 1
		end
	end
	return count
end

function EnemyService:GetMagnets()
	return self._magnets
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
	local shieldFacing = EnemyService.ShieldFacing(enemy)
	if shield and direction and direction.Magnitude > 1e-4 and shieldFacing.Magnitude > 1e-4 then
		-- Blocked when the shot arrives within the shield's half-angle of dead-on. A shot
		-- travelling opposite the enemy's facing is a direct hit, so its dot is near -1.
		local alignment = direction.Unit:Dot(shieldFacing.Unit)
		if alignment < -math.cos(math.rad(shield.HalfAngleDegrees)) then
			multiplier = shield.DamageMultiplier
		end
	end

	local applied = math.max(damage * multiplier, 0)
	enemy.health -= applied
	EnemyService._publishHealth(enemy)

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
		local ring = enemy.champion and enemy.champion.DeathRing
		if ring then
			for step = 1, ring.Count do
				local angle = (step - 1) * 2 * math.pi / ring.Count
				self:_fireOrb(enemy, Vector3.new(math.cos(angle), 0, math.sin(angle)), ring.Speed, ring.Damage, self._now)
			end
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
	local telegraph = archetype.Lunge or archetype.Fire or archetype.Blink or archetype.Stomp or archetype.Slam
	if enemy.phase == "Telegraph" and telegraph then
		wanted = telegraph.TelegraphColor
	end
	-- A press about to slam marks the floor it will hit, so clients can draw the warning.
	if archetype.Slam then
		local slamming = enemy.phase == "Telegraph"
		if slamming ~= (enemy.shownSlamming or false) then
			enemy.shownSlamming = slamming
			enemy.part:SetAttribute("SlamRadius", slamming and archetype.Slam.Radius or nil)
		end
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

	local shieldFacing = EnemyService.ShieldFacing(enemy)
	if archetype.Shield and shieldFacing.Magnitude > 1e-4 then
		local shield = enemy.part:FindFirstChild("Shield")
		if shield and enemy.shieldOff then
			if shield.Transparency < 1 then
				shield.Transparency = 1
			end
		elseif shield then
			shield.CFrame = CFrame.lookAlong(enemy.position + shieldFacing.Unit * archetype.Shield.Offset, shieldFacing.Unit)
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

-- Burn ticks, champion regeneration and the Burning/Chilled attributes clients draw from.
-- Burn damage is collected first and applied after, because a burn kill can explode and take
-- other enemies with it, which must not happen mid-iteration.
function EnemyService:_stepStatuses(now)
	local ticks = nil
	for _, enemy in self._enemies do
		local burn = enemy.burn
		if burn then
			-- The tick due at the moment the burn ends still lands, so a 3s burn deals all 3s.
			if now >= burn.nextTick and burn.nextTick <= burn.untilAt + 1e-6 then
				burn.nextTick += CombatConfig.BurnTick
				ticks = ticks or {}
				table.insert(ticks, { enemy = enemy, damage = burn.dps * CombatConfig.BurnTick, shooter = burn.shooter })
			end
			if burn.nextTick > burn.untilAt + 1e-6 then
				enemy.burn = nil
			end
		end
		local regen = enemy.champion and enemy.champion.Regen
		if regen and now >= (enemy.regenAt or math.huge) then
			enemy.regenAt = now + regen.Interval
			enemy.health = math.min(enemy.maxHealth, enemy.health + regen.Amount)
			EnemyService._publishHealth(enemy)
		end
		local burning, chilled = enemy.burn ~= nil, EnemyService.IsChilled(enemy, now)
		if burning ~= (enemy.shownBurning or false) then
			enemy.shownBurning = burning
			enemy.part:SetAttribute("Burning", burning or nil)
		end
		if chilled ~= (enemy.shownChilled or false) then
			enemy.shownChilled = chilled
			enemy.part:SetAttribute("Chilled", chilled or nil)
		end
	end
	for _, tick in ticks or {} do
		if not tick.enemy.dead and self.OnStatusDamage then
			self.OnStatusDamage(tick.enemy, tick.damage, tick.shooter, now)
		end
	end
end

function EnemyService:Step(deltaTime, now)
	self._now = now
	local targets = self._targetProvider and self._targetProvider() or {}
	table.clear(self._movers)
	table.clear(self._magnets)
	local randomSource = function()
		return self._random:NextNumber()
	end

	self:_stepOrbs(deltaTime, now, targets)

	for index = #self._enemies, 1, -1 do
		local enemy = self._enemies[index]
		local archetype = enemy.archetype
		local target = nearestTarget(targets, enemy.position)

		-- The Pact, a Swift champion and chill all scale how far an enemy moves this step. Only
		-- movement: telegraphs and fire timers run on the clock, so they stay readable.
		local moveScale = self._modifiers.Speed * (enemy.speedScale or 1)
			* (EnemyService.IsChilled(enemy, now) and CombatConfig.ChillSpeedFactor or 1)
		local behaviour = EnemyBehaviour.Get(archetype.Behaviour)
		if behaviour then
			behaviour(enemy, archetype, deltaTime * moveScale, target, now, randomSource)
		end
		local spin = archetype.Shield and archetype.Shield.SpinSpeed
		if spin then
			-- Starts wherever it first faced, then turns steadily.
			if not enemy.shieldAngle then
				local facing = enemy.facing
				enemy.shieldAngle = math.atan2(facing.X, facing.Z)
			end
			enemy.shieldAngle += math.rad(spin) * deltaTime
			enemy.shieldFacing = Vector3.new(math.sin(enemy.shieldAngle), 0, math.cos(enemy.shieldAngle))
		end

		local previousPosition = enemy.part.Position
		enemy.position = self:_clampToBounds(Vector3.new(enemy.position.X, self._planeY, enemy.position.Z))
		enemy.part.Position = enemy.position
		if (enemy.position - previousPosition).Magnitude > 1e-4 then
			table.insert(self._movers, enemy)
		end
		self:_applyVisuals(enemy)
		self:_serviceRequests(enemy, now, targets)
		if archetype.Magnet then
			table.insert(self._magnets, enemy)
		end

		if target and (archetype.ContactDamage or 0) > 0 and now >= enemy.contactReadyAt then
			local offset = Vector3.new(target.position.X - enemy.position.X, 0, target.position.Z - enemy.position.Z)
			if offset.Magnitude <= (archetype.ContactRange or 0) then
				enemy.contactReadyAt = now + (archetype.ContactCooldown or EnemyConfig.DefaultContactCooldown)
				if self.OnPlayerContact then
					-- Pass the step's clock through: the handler runs before the run loop's own
					-- Step, so anything it reads from the match would be a frame stale.
					self.OnPlayerContact(target.player, archetype.ContactDamage * self._modifiers.Damage, enemy, now)
				end
			end
		end
	end

	self:_stepStatuses(now)

	-- A runner that has not been caught gets away with its loot.
	for index = #self._enemies, 1, -1 do
		local enemy = self._enemies[index]
		local escape = enemy and enemy.archetype.EscapeAfter
		if escape and now - enemy.spawnedAt >= escape then
			self:Despawn(enemy, "escaped")
			if self.OnEscape then
				self.OnEscape(enemy)
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
