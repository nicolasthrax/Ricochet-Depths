-- The player's kit during a run: orbs (throwing, dropping, recovering, trick-shot refunds),
-- bounce power, the dash, the combo meter and Surge offers. Installed onto MatchService.
--
-- Each system is switched on per match by deps.arsenal ({ orbs, surge, combo }); production
-- turns them on from FeatureFlags, and a match built without them plays exactly as before.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArsenalConfig = require(ReplicatedStorage:WaitForChild("ArsenalConfig"))
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local UpgradeService = require(script.Parent.UpgradeService)

local Arsenal = { methods = {} }

--// bounce power ---------------------------------------------------------------

-- A shot's damage multiplier from the bounces it has made.
function Arsenal.BounceMultiplier(stats, wallBounces)
	return 1 + (stats.BouncePower or 0) * (wallBounces or 0)
end

-- A shot ricocheted off geometry: it speeds up, grows and heats up in colour.
function Arsenal.methods:_onBounce(entry)
	entry.wallBounces = (entry.wallBounces or 0) + 1
	local bounce = ArsenalConfig.Bounce
	if entry.baseSpeed then
		entry.speed = math.min(entry.speed * (1 + bounce.SpeedPerBounce), entry.baseSpeed * bounce.MaxSpeedMultiplier)
	end
	local part = entry.part
	if part then
		local growth = math.min(1 + bounce.GrowPerBounce * entry.wallBounces, bounce.MaxGrowth)
		part.Size = Vector3.one * (ProjectileConfig.Radius * 2 * growth)
		part.Color = ArsenalConfig.BounceColor(entry.wallBounces)
	end
end

--// orbs -----------------------------------------------------------------------

function Arsenal.methods:_orbsOn()
	return self._orbDrops ~= nil and self._arsenal.orbs == true
end

-- A throw is about to leave: spend an orb. Returns false when the hand is empty.
function Arsenal.methods:_takeOrb(player, state)
	if not self:_orbsOn() then
		return true
	end
	if not state:TakeOrb() then
		return false
	end
	self:_pushPlayerState(player)
	return true
end

-- The orb came back without landing: a failed throw, a trick shot, or a dry drop pool.
function Arsenal.methods:_returnOrb(player)
	local state = self._states[player]
	if state then
		state:ReturnOrb()
		self:_pushPlayerState(player)
	end
end

-- A shot finished its flight. If it carried an orb, the orb lands where it stopped.
function Arsenal.methods:_onShotExpired(entry, position)
	if not entry.carriesOrb or entry.orbReturned or not self:_orbsOn() then
		return
	end
	entry.orbReturned = true
	local owner = entry.shooter
	local state = owner and self._states[owner]
	if not state or not table.find(self._participants, owner) then
		return
	end
	local current = self._rooms:GetCurrent()
	local landed = self._state == RunConfig.States.Combat and current ~= nil
		and self._orbDrops:Drop(owner, position, current.bounds.center.Y, self._now)
	if not landed then
		self:_returnOrb(owner)
	end
end

-- A trick shot: a kill off enough bounces sends the orb straight back to hand.
function Arsenal.methods:_checkTrickShot(entry, now)
	if not entry.carriesOrb or entry.orbReturned or (entry.wallBounces or 0) < ArsenalConfig.Orbs.TrickShotBounces then
		return false
	end
	local state = self._states[entry.shooter]
	if not state then
		return false
	end
	entry.orbReturned = true
	state.trickShots += 1
	if self:_orbsOn() then
		self:_returnOrb(entry.shooter)
	end
	self:_fireClient("Notify", entry.shooter, { Kind = "Callout", Text = "TRICK SHOT!", Tone = "Accent" })
	self:_log("TrickShot", { RunId = self._runId, Bounces = entry.wallBounces }, now)
	return true
end

-- Every orb back in every hand: a room is starting or has just ended.
function Arsenal.methods:_resetOrbs()
	if self._orbDrops then
		self._orbDrops:Clear()
	end
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			state:RefillOrbs()
		end
	end
end

function Arsenal.methods:_stepOrbs(deltaTime, now)
	if not self:_orbsOn() or not self._world or not self._world.GetPosition then
		return
	end
	local carriers = {}
	for _, player in self._participants do
		local state = self._states[player]
		local position = state and self._world.GetPosition(player)
		if position then
			carriers[player] = { position = position, returnMultiplier = state.stats.OrbReturnMultiplier or 1 }
		end
	end
	for _, owner in self._orbDrops:Step(deltaTime, now, carriers) do
		self:_returnOrb(owner)
	end
end

--// magnets --------------------------------------------------------------------

-- Turns a shot toward every Magnet whose field it is inside, by Strength radians a second.
function Arsenal.methods:_steerShot(entry, from, to)
	local magnets = self._enemies.GetMagnets and self._enemies:GetMagnets()
	if not magnets or #magnets == 0 or not entry.speed or entry.speed <= 0 then
		return
	end
	local travelled = (to - from).Magnitude
	if travelled < 1e-4 then
		return
	end
	local dt = travelled / entry.speed
	local heading = entry.direction
	for _, magnet in magnets do
		local field = not magnet.dead and magnet.archetype.Magnet
		if field then
			local offset = Vector3.new(magnet.position.X - to.X, 0, magnet.position.Z - to.Z)
			local distance = offset.Magnitude
			if distance <= field.Radius and distance > 0.5 then
				heading += offset.Unit * field.Strength * dt
			end
		end
	end
	heading = Vector3.new(heading.X, 0, heading.Z)
	if heading.Magnitude > 1e-4 then
		entry.direction = heading.Unit
	end
end

--// dash -------------------------------------------------------------------------

-- The client has already moved its character (it owns its physics); the server checks the
-- cooldown, grants the i-frames, and does whatever the dash's cards add. Returns true if taken.
function Arsenal.methods:HandleDash(player, direction, now)
	if self._arsenal.dash == false then
		return false, "dash disabled"
	end
	if not self:IsAcceptingFire() then
		return false, "not in combat"
	end
	local state = self._states[player]
	if not state or not state.alive then
		return false, "player is down"
	end
	local dash = ArsenalConfig.Dash
	local cooldown = dash.Cooldown * (state.stats.DashCooldownMultiplier or 1)
	if now - state.lastDashAt < cooldown - dash.ClockSlack then
		return false, "cooling down"
	end
	state.lastDashAt = now
	state.invulnerableUntil = math.max(state.invulnerableUntil, now + dash.Invulnerability)

	if (state.stats.DashRecall or 0) > 0 and self:_orbsOn() then
		self._orbDrops:Recall(player)
	end

	local heading = typeof(direction) == "Vector3" and Vector3.new(direction.X, 0, direction.Z) or nil
	local damage = state.stats.DashStrikeDamage or 0
	local position = self._world and self._world.GetPosition and self._world.GetPosition(player)
	if damage > 0 and position and heading and heading.Magnitude > 0.1 and heading.Magnitude == heading.Magnitude then
		-- The dash may already be under way when this arrives, so the struck path runs from a
		-- little behind the character to a full dash ahead of it.
		local unit = heading.Unit
		local from = position - unit * dash.Distance * 0.5
		local to = position + unit * dash.Distance
		for _, enemy in self._enemies:GetEnemies() do
			local reach = dash.StrikeRadius + math.max(enemy.archetype.Size.X, enemy.archetype.Size.Z) / 2
			if Arsenal.DistanceToSegment(enemy.position, from, to) <= reach then
				self:_secondaryDamage(enemy, damage, player, 0, "Dash", now)
			end
		end
	end
	self:_pushPlayerState(player)
	self:_log("Dash", { RunId = self._runId }, now)
	return true
end

-- Distance on the travel plane from point p to segment a-b.
function Arsenal.DistanceToSegment(p, a, b)
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local lengthSquared = ab:Dot(ab)
	local t = lengthSquared > 0 and math.clamp(ap:Dot(ab) / lengthSquared, 0, 1) or 0
	return (ap - ab * t).Magnitude
end

--// combo ------------------------------------------------------------------------

-- A kill joins its shooter's combo; a tier-up is announced. Returns the multiplier its drops get.
function Arsenal.methods:_comboKill(state, player, ricochet, now)
	local before, after = state:AddCombo(1 + (ricochet and ArsenalConfig.Combo.RicochetBonus or 0), now)
	if not self._arsenal.combo then
		return 1
	end
	local tier = ArsenalConfig.ComboTier(state.combo)
	if after > before then
		self:_fireClient("Notify", player, {
			Kind = "Callout",
			Text = string.format("%s  x%s", tier.Name, tostring(tier.Multiplier)),
			Tone = "Gold",
		})
	end
	return tier.Multiplier
end

function Arsenal.methods:_stepCombos(now)
	for _, player in self._participants do
		local state = self._states[player]
		if state and state:ExpireCombo(now) then
			self:_pushPlayerState(player)
		end
	end
end

--// surge ------------------------------------------------------------------------

function Arsenal.methods:_surgeOn()
	return self._surges ~= nil and self._arsenal.surge == true
end

-- Kills fill the meter; a full meter opens a Surge offer unless one is already waiting.
function Arsenal.methods:_grantSurge(player, points, now)
	local state = self._states[player]
	if not self:_surgeOn() or not state then
		return
	end
	if state:AddSurge(points) and not self._surges:GetOffer(player) then
		self:_openSurge(player, state, now)
	end
end

function Arsenal.methods:_openSurge(player, state, now)
	if not state:SpendSurge() then
		return
	end
	local offer = self._surges:BuildOffer(player, state, now, ArsenalConfig.Surge.Offers,
		{ timeout = ArsenalConfig.Surge.ChoiceTimeout })
	local payload = UpgradeService.ToClientPayload(offer, now)
	payload.Level = state.surgeLevel - 1
	self:_fireClient("SurgeOffer", player, payload)
	self:_pushPlayerState(player)
	self:_log("SurgeOffered", { RunId = self._runId, Level = state.surgeLevel - 1 }, now)
end

-- The meter may already hold enough for the next level once one resolves.
function Arsenal.methods:_afterSurge(player, card, auto, now)
	self:_fireClient("SurgeResolved", player, { CardId = card.Id, Title = card.Title, Auto = auto })
	self:_pushPlayerState(player)
	local state = self._states[player]
	if state and state:AddSurge(0) and self:IsRunActive() then
		self:_openSurge(player, state, now)
	end
end

function Arsenal.methods:ChooseSurge(player, offerId, cardId, now)
	if not self:_surgeOn() or not self:IsRunActive() then
		return nil, "no surge"
	end
	local state = self._states[player]
	if not state then
		return nil, "unknown player"
	end
	local card, reason = self._surges:Choose(player, state, offerId, cardId)
	if not card then
		return nil, reason
	end
	self:_afterSurge(player, card, false, now)
	return card
end

-- Offers left too long pick themselves; `force` resolves every one now (a room ended).
function Arsenal.methods:_resolveSurges(now, force)
	if not self:_surgeOn() then
		return
	end
	for _, resolution in self._surges:ResolveExpired(force and math.huge or now, function(key)
		return self._states[key]
	end) do
		self:_afterSurge(resolution.playerKey, resolution.card, true, now)
	end
end

--// the per-frame step ---------------------------------------------------------

function Arsenal.methods:_stepArsenal(deltaTime, now)
	self:_stepOrbs(deltaTime, now)
	self:_stepCombos(now)
	self:_resolveSurges(now, false)
end

function Arsenal.Install(class)
	for name, method in Arsenal.methods do
		class[name] = method
	end
end

return Arsenal
