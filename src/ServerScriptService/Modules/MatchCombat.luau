-- Combat-facing half of the run loop: fire requests, projectile impacts and enemy contact.
-- Installed onto MatchService, so these are ordinary methods on a match instance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FireValidator = require(script.Parent.FireValidator)
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))

local Combat = { methods = {} }

-- Fans count directions around the aim heading, rotating about the vertical axis.
local function spreadDirections(direction, count, spreadDegrees)
	if count <= 1 then
		return { direction }
	end
	local total = math.rad(spreadDegrees)
	local step = total / (count - 1)
	local directions = table.create(count)
	for index = 1, count do
		local angle = -total / 2 + step * (index - 1)
		local cosine, sine = math.cos(angle), math.sin(angle)
		directions[index] =
			Vector3.new(direction.X * cosine - direction.Z * sine, 0, direction.X * sine + direction.Z * cosine).Unit
	end
	return directions
end

-- The only entry point for a client fire request. Direction and power are the only client
-- inputs, and both are re-validated; everything else comes from server-held state.
function Combat.methods:HandleFire(player, direction, power, now)
	if not self:IsAcceptingFire() then
		return false, "not in combat"
	end
	local state = self._states[player]
	if not state or not state.alive then
		return false, "player is down"
	end

	local cooldown = ProjectileConfig.FireCooldown * state.stats.FireCooldownMultiplier
	local rootPart, validDirection, validPower = FireValidator.Validate(player, direction, power, cooldown)
	if not rootPart then
		return false, validDirection
	end

	local count = math.max(1, math.floor(state.stats.ProjectilesPerShot))
	local options = {
		damage = state.stats.Damage,
		bounces = math.floor(state.stats.BounceBudget),
		speedMultiplier = state.stats.SpeedMultiplier,
		lifetimeBonus = state.stats.LifetimeBonus,
		damagePerBounce = state.stats.DamagePerBounce,
		trail = state.meta.trail, -- cosmetic, from the salvage shop
	}

	local fired = 0
	for _, heading in spreadDirections(validDirection, count, state.stats.SpreadDegrees) do
		if self._projectiles:Fire(player, rootPart.Position, heading, validPower, options) then
			fired += 1
		end
	end

	state.shotsFired += 1
	state.projectilesFired += fired
	self:_log("ShotFired", { RunId = self._runId, Projectiles = fired }, now)
	return fired > 0, fired == 0 and "projectile pool exhausted" or nil
end

-- What an impact looks and sounds like on clients.
local function impactKind(hit)
	if not hit then
		return "Wall"
	elseif hit.killed then
		return "Kill"
	elseif hit.blocked then
		return "Block"
	end
	return "Hit"
end

function Combat.methods:HandleImpact(result, entry, now)
	local hit = self._enemies:ApplyHit(
		result.Instance,
		entry.damage + entry.damagePerBounce * math.max(entry.contacts - 1, 0),
		entry.direction,
		entry.shooter
	)
	if self._effects then
		self._effects:Queue(result.Position, result.Normal, impactKind(hit), entry.contacts, hit and hit.damage or 0)
	end
	if not hit then
		return false -- geometry: let it ricochet
	end

	if hit.killed then
		local state = self._states[entry.shooter]
		if state then
			state.kills += 1
			state.bestChain = math.max(state.bestChain, entry.contacts)
		end
		self:_fireAll("EnemyDefeated", hit.enemy.position, hit.enemy.archetypeId)
		self:_log("EnemyDefeated", {
			Archetype = hit.enemy.archetypeId,
			Contacts = entry.contacts,
			RunId = self._runId,
		}, now)
	end

	-- Shots ricochet off enemies too, which is what lets a single shot chain kills.
	return false
end

function Combat.methods:HandlePlayerContact(player, damage, _enemy, now)
	local state = self._states[player]
	if not state or not state.alive then
		return
	end

	local applied, fatal = state:ApplyDamage(damage, now)
	if applied <= 0 then
		return
	end
	self:_pushPlayerState(player)

	if fatal then
		self:_log("PlayerDown", { RunId = self._runId, Room = self._roomIndex }, now)
	end
end

-- Drops any fire-cooldown bookkeeping for a player who left.
function Combat.ClearPlayer(player)
	FireValidator.Clear(player)
end

function Combat.Install(class)
	for name, method in Combat.methods do
		class[name] = method
	end
end

return Combat
