-- Server-authoritative enemy registry: spawning, movement, damage, contact and cleanup.
-- Enemy positions are integrated directly on anchored parts, so the server is the only writer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyBehaviour = require(script.Parent.EnemyBehaviour)
local EnemyConfig = require(ReplicatedStorage:WaitForChild("EnemyConfig"))
local EnemyPool = require(script.Parent.EnemyPool)

local EnemyService = {}
EnemyService.__index = EnemyService

function EnemyService.new(parent, planeY, seed)
	local self = setmetatable({}, EnemyService)

	self._pool = EnemyPool.new(parent)
	self._enemies = {}
	self._byPart = {}
	self._planeY = planeY
	self._nextId = 0
	self._random = Random.new(seed or 1)
	self._bounds = nil
	self._targetProvider = nil

	-- Set by the encounter layer.
	self.OnDeath = nil -- (enemy, shooter)
	self.OnPlayerContact = nil -- (player, damage, enemy)

	return self
end

-- Targets are supplied as { { player = Player, position = Vector3 }, ... }.
function EnemyService:SetTargetProvider(provider)
	self._targetProvider = provider
end

-- Keeps enemies inside the playable area; halfExtents is a Vector2 on the XZ plane.
function EnemyService:SetBounds(center, halfExtents)
	self._bounds = { center = center, half = halfExtents }
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
	if not enemy or enemy.dead then
		return nil
	end

	local multiplier = 1
	local shield = enemy.archetype.Shield
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
	return Vector3.new(
		math.clamp(position.X, center.X - half.X, center.X + half.X),
		position.Y,
		math.clamp(position.Z, center.Z - half.Y, center.Z + half.Y)
	)
end

function EnemyService:_applyVisuals(enemy)
	local archetype = enemy.archetype
	local wanted = archetype.Color
	if enemy.phase == "Telegraph" and archetype.Lunge then
		wanted = archetype.Lunge.TelegraphColor
	end
	-- Only write when it actually changes, to keep property replication quiet.
	if wanted ~= enemy.color then
		enemy.color = wanted
		enemy.part.Color = wanted
	end

	if archetype.Shield and enemy.facing.Magnitude > 1e-4 then
		local shield = enemy.part:FindFirstChild("Shield")
		if shield then
			shield.CFrame = CFrame.lookAlong(enemy.position + enemy.facing.Unit * archetype.Shield.Offset, enemy.facing.Unit)
		end
	end
end

function EnemyService:Step(deltaTime, now)
	local targets = self._targetProvider and self._targetProvider() or {}
	local randomSource = function()
		return self._random:NextNumber()
	end

	for index = #self._enemies, 1, -1 do
		local enemy = self._enemies[index]
		local archetype = enemy.archetype
		local target = nearestTarget(targets, enemy.position)

		local behaviour = EnemyBehaviour.Get(archetype.Behaviour)
		if behaviour then
			behaviour(enemy, archetype, deltaTime, target, now, randomSource)
		end

		enemy.position = self:_clampToBounds(Vector3.new(enemy.position.X, self._planeY, enemy.position.Z))
		enemy.part.Position = enemy.position
		self:_applyVisuals(enemy)

		if target and (archetype.ContactDamage or 0) > 0 and now >= enemy.contactReadyAt then
			local offset = Vector3.new(target.position.X - enemy.position.X, 0, target.position.Z - enemy.position.Z)
			if offset.Magnitude <= (archetype.ContactRange or 0) then
				enemy.contactReadyAt = now + (archetype.ContactCooldown or EnemyConfig.DefaultContactCooldown)
				if self.OnPlayerContact then
					self.OnPlayerContact(target.player, archetype.ContactDamage, enemy)
				end
			end
		end
	end
end

function EnemyService:Clear()
	for index = #self._enemies, 1, -1 do
		self:Despawn(self._enemies[index], "cleared")
	end
	table.clear(self._byPart)
end

function EnemyService:Destroy()
	self:Clear()
	self._pool:Destroy()
	self._targetProvider = nil
	self.OnDeath = nil
	self.OnPlayerContact = nil
end

return EnemyService
