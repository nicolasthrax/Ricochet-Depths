-- Combat-facing half of the run loop: fire requests, projectile impacts and enemy contact.
-- Installed onto MatchService, so these are ordinary methods on a match instance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local FireValidator = require(script.Parent.FireValidator)
local MatchArsenal = require(script.Parent.MatchArsenal)
local MatchEffects = require(script.Parent.MatchEffects)
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

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

	-- A throw spends an orb; with none in hand there is nothing to throw.
	if not self:_takeOrb(player, state) then
		return false, "no orbs"
	end

	local count = math.max(1, math.floor(state.stats.ProjectilesPerShot))
	-- The middle projectile of the fan is the orb itself; the rest are its echoes.
	local orbIndex = math.ceil(count / 2)
	local options = {
		damage = state.stats.Damage,
		bounces = math.floor(state.stats.BounceBudget),
		speedMultiplier = state.stats.SpeedMultiplier,
		lifetimeBonus = state.stats.LifetimeBonus,
		damagePerBounce = state.stats.DamagePerBounce,
		trail = state.meta.trail, -- cosmetic, from the salvage shop
		-- The shooter's stats as they stood when the shot left: crits, burns, arcs and the rest.
		stats = state.stats,
	}

	local fired, orbFlying = 0, false
	for index, heading in spreadDirections(validDirection, count, state.stats.SpreadDegrees) do
		options.carriesOrb = index == orbIndex and self:_orbsOn()
		if self._projectiles:Fire(player, rootPart.Position, heading, validPower, options) then
			fired += 1
			orbFlying = orbFlying or options.carriesOrb
		end
	end
	if self:_orbsOn() and not orbFlying then
		self:_returnOrb(player) -- the orb never left, so it is still in hand
	end

	state.shotsFired += 1
	state.projectilesFired += fired
	self:_funnel(player, "FirstInput")
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
	-- Breakable cover takes the hit first; the shot still ricochets off it.
	local mechanics = self._rooms:GetMechanics()
	local struck, detail = nil, nil
	if mechanics then
		struck, detail = mechanics:HandleImpact(result.Instance, entry)
	end
	if struck then
		if self._effects then
			self._effects:Queue(result.Position, result.Normal, struck == "Broken" and "Kill" or struck == "Exploded" and "Blast" or "Hit",
				entry.contacts, 0)
		end
		if struck == "Broken" or struck == "Exploded" then
			self:_onMechanicBroken(struck, detail, entry.shooter, now)
		end
		self:_onBounce(entry)
		return false
	end
	-- Objective pieces (crystals, gallery targets) take the hit next; shots bounce off them too.
	if self:_objectiveImpact(result, entry, now) then
		self:_onBounce(entry)
		return false
	end

	local stats = entry.stats or self:_statsOf(entry.shooter)
	local base = (entry.damage + entry.damagePerBounce * math.max(entry.contacts - 1, 0))
		* MatchArsenal.BounceMultiplier(stats, entry.wallBounces)
	local damage, crit = base, false
	local enemy = self._enemies:GetByPart(result.Instance)
	if enemy and not enemy.dead then
		damage, crit = MatchEffects.ShotDamage(stats, base, entry.contacts, enemy, now, self._random)
		local archetype = enemy.archetype
		-- Mirrors turn aside anything that has not bounced first.
		if archetype.RequiresBank and (entry.wallBounces or 0) == 0 then
			damage, crit = 0, false
		end
		-- Sponges soak up whatever bounces a shot had left.
		if archetype.AbsorbsBounces then
			entry.bouncesLeft = 0
		end
	end

	local hit = self._enemies:ApplyHit(result.Instance, damage, entry.direction, entry.shooter)
	local kind = impactKind(hit)
	if crit and kind == "Hit" then
		kind = "Crit"
	end
	if self._effects then
		self._effects:Queue(result.Position, result.Normal, kind, entry.contacts, hit and hit.damage or 0)
	end
	if not hit then
		self:_onBounce(entry)
		return false -- geometry: let it ricochet
	end

	if not hit.blocked then
		self:_funnel(entry.shooter, "FirstHit")
		local state = self._states[entry.shooter]
		if crit and state then
			state.crits += 1
		end
		self:_afterHit(hit, stats, entry.shooter, entry.contacts, hit.damage, "Shot", now, entry)
		if hit.killed then
			self:_checkTrickShot(entry, now)
		end
	end

	-- By default shots ricochet off enemies too, which is what lets a single shot chain kills.
	-- With ConsumeOnEnemyHit a damaging hit ends the shot; a shield block still bounces it.
	return ProjectileConfig.ConsumeOnEnemyHit and not hit.blocked
end

function Combat.methods:HandlePlayerContact(player, damage, _enemy, now)
	local state = self._states[player]
	if not state or not state.alive then
		return
	end

	local applied, fatal, savedByExtraLife = state:ApplyDamage(damage, now)
	if applied <= 0 then
		return
	end
	state:DamageCombo()
	self:_onPlayerHurt(player, now)
	self:_pushPlayerState(player)

	if savedByExtraLife then
		self:_fireClient("Notify", player, { Kind = "SecondWind", Text = "SECOND WIND!" })
		self:_log("ExtraLifeUsed", { RunId = self._runId, Room = self._roomIndex }, now)
	end
	if fatal then
		-- Downed players crawl, so they can drag themselves toward a teammate for a revive.
		self:_setWalkSpeed(player, RunConfig.DownedWalkSpeed)
		self:_log("PlayerDown", { RunId = self._runId, Room = self._roomIndex }, now)
	end
end

function Combat.methods:_setWalkSpeed(player, speed)
	if self._world and self._world.SetWalkSpeed then
		self._world.SetWalkSpeed(player, speed)
	end
end

-- Co-op revives: a downed participant with a live teammate close by is picked back up after
-- Revive.Seconds, faster with more helpers. Progress drains while nobody is near. Solo runs
-- have nobody to revive them, so this never runs for them.
function Combat.methods:_stepRevives(deltaTime, now)
	if #self._participants < 2 or not self._world or not self._world.GetPosition then
		return
	end
	local revive = CombatConfig.Revive
	for _, player in self._participants do
		local state = self._states[player]
		if state and not state.alive then
			local position = self._world.GetPosition(player)
			local helpers = {}
			for _, other in self._participants do
				local helper = self._states[other]
				local at = position and other ~= player and helper and helper.alive and self._world.GetPosition(other)
				if at and Vector3.new(at.X - position.X, 0, at.Z - position.Z).Magnitude <= revive.Radius then
					table.insert(helpers, other)
				end
			end

			local before = state.reviveProgress
			if #helpers > 0 then
				local rate = (1 + (#helpers - 1) * revive.HelperBonus) / revive.Seconds
				state.reviveProgress = math.min(before + rate * deltaTime, 1)
			else
				state.reviveProgress = math.max(before - revive.DecayPerSecond * deltaTime, 0)
			end

			if state.reviveProgress >= 1 then
				state:Revive(now, revive.HealthFraction, revive.Invulnerability)
				self:_setWalkSpeed(player, RunConfig.BaseWalkSpeed + (state.stats.MoveSpeedBonus or 0))
				for _, helper in helpers do
					self._states[helper].revivesGiven += 1
				end
				self:_fireAll("Notify", { Kind = "Revive", Text = state.name .. " is back up!" })
				self:_log("PlayerRevived", { RunId = self._runId, Room = self._roomIndex, Helpers = #helpers }, now)
				self:_pushPlayerState(player)
			elseif state.reviveProgress ~= before and now >= (self._regenPushAt[player] or 0) then
				self._regenPushAt[player] = now + RunConfig.Regen.PushInterval
				self:_pushPlayerState(player)
			end
		end
	end
end

-- Laser gates and other hazards: each live participant standing in one is burned, at most
-- once per GateTick, through the same damage path as enemy contact.
function Combat.methods:_applyHazards(now)
	local mechanics = self._rooms:GetMechanics()
	if not mechanics or not self._world or not self._world.GetPosition then
		return
	end
	for _, player in self._participants do
		local state = self._states[player]
		if state and state.alive and now >= (self._hazardNextAt[player] or 0) then
			local position = self._world.GetPosition(player)
			local damage = position and mechanics:HazardAt(position, now) or 0
			if damage > 0 then
				self._hazardNextAt[player] = now + RoomConfig.Mechanics.GateTick
				self:HandlePlayerContact(player, damage, nil, now)
			end
		end
	end
end

-- Slow healing between fights: a live participant untouched for Regen.Delay seconds heals
-- PerSecond plus their Mending bonus. The HUD is updated at most every PushInterval.
function Combat.methods:_applyRegen(deltaTime, now)
	if self._pactEffects and self._pactEffects.NoRegen then
		return -- the Pact's Drought
	end
	local regen = RunConfig.Regen
	for _, player in self._participants do
		local state = self._states[player]
		if state and state.alive and state.health < state.maxHealth and now - state.lastDamagedAt >= regen.Delay then
			local healed = state:Heal((regen.PerSecond + (state.stats.RegenBonus or 0)) * deltaTime)
			if healed > 0 and (now >= (self._regenPushAt[player] or 0) or state.health >= state.maxHealth) then
				self._regenPushAt[player] = now + regen.PushInterval
				self:_pushPlayerState(player)
			end
		end
	end
end

-- The live participants as coin collectors: where they stand and how far their magnet reaches.
-- includeDowned counts downed participants too, for the sweep when a run ends.
function Combat.methods:_coinCollectors(includeDowned)
	local collectors = {}
	if not self._world or not self._world.GetPosition then
		return collectors
	end
	for _, player in self._participants do
		local state = self._states[player]
		local position = state and (state.alive or includeDowned) and self._world.GetPosition(player)
		if position then
			table.insert(collectors, { player = player, position = position, magnet = state.stats.MagnetBonus or 0 })
		end
	end
	return collectors
end

function Combat.methods:_creditCoins(events)
	local touched = {}
	for _, event in events do
		local state = self._states[event.player]
		if state then
			state.coins += event.value
			touched[event.player] = true
		end
	end
	for player in touched do
		self:_pushPlayerState(player)
	end
end

function Combat.methods:_collectCoins(deltaTime, now)
	if self._coins then
		self:_creditCoins(self._coins:Step(deltaTime, now, self:_coinCollectors()))
	end
end

-- Room cleared: every coin still on the floor goes to the nearest live player.
function Combat.methods:_sweepCoins()
	if self._coins then
		self:_creditCoins(self._coins:Sweep(self:_coinCollectors()))
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
