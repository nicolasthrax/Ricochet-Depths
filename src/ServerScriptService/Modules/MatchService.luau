-- The run state machine. Owns run membership, room progression, upgrade rounds, win/loss and
-- teardown. Every collaborator is injected, so the whole loop is exercised headlessly in tests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FireValidator = require(script.Parent.FireValidator)
local PlayerState = require(script.Parent.PlayerState)
local RunSummary = require(script.Parent.RunSummary)
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local States = RunConfig.States

local MatchService = {}
MatchService.__index = MatchService

function MatchService.new(deps)
	local self = setmetatable({}, MatchService)

	self._rooms = deps.rooms
	self._enemies = deps.enemies
	self._upgrades = deps.upgrades
	self._projectiles = deps.projectiles
	self._rewards = deps.rewards
	self._effects = deps.effects
	self._telemetry = deps.telemetry
	self._persistence = deps.persistence
	-- Run keys must be unique across servers, since the reward ledger is stored per profile.
	self._runKeyPrefix = deps.runKeyPrefix or "local"
	self._net = deps.net or {}
	self._world = deps.world -- teleport/position adapter, so tests need no characters

	self._states = {}
	self._participants = {}
	self._pendingJoins = {}
	self._state = States.Lobby
	self._stateEnteredAt = 0
	self._runStartedAt = 0
	self._roomIndex = 0
	self._runId = 0
	self._eliteCleared = false
	self._nextBroadcastAt = 0
	self._now = 0

	-- Enemies target live participants, and their contact damage lands on the run state.
	self._enemies:SetTargetProvider(function()
		return self:_targets()
	end)
	self._enemies.OnPlayerContact = function(player, damage, enemy)
		self:HandlePlayerContact(player, damage, enemy, self._now)
	end

	return self
end

-- Live participants, as EnemyService expects them.
function MatchService:_targets()
	local targets = {}
	for _, player in self._participants do
		local state = self._states[player]
		if state and state.alive and self._world then
			local position = self._world.GetPosition(player)
			if position then
				table.insert(targets, { player = player, position = position })
			end
		end
	end
	return targets
end

--// membership ---------------------------------------------------------------

-- Late join rule: a player who arrives while a run is in progress is queued and admitted at the
-- next room boundary, never mid-fight and never mid-upgrade-round. They start the room they join
-- with a fresh state and no upgrades.
function MatchService:RegisterPlayer(player)
	local state = self._states[player]
	if not state then
		state = PlayerState.new(player)
		self._states[player] = state
	end

	if self:IsRunActive() and not table.find(self._participants, player) and not table.find(self._pendingJoins, player) then
		state:ResetRun()
		table.insert(self._pendingJoins, player)
	end

	return state
end

function MatchService:IsPendingJoin(player)
	return table.find(self._pendingJoins, player) ~= nil
end

function MatchService:IsParticipant(player)
	return table.find(self._participants, player) ~= nil
end

function MatchService:GetPlayerState(player)
	return self._states[player]
end

function MatchService:GetParticipants()
	return table.clone(self._participants)
end

local function removeFrom(list, value)
	for index, entry in list do
		if entry == value then
			table.remove(list, index)
			return true
		end
	end
	return false
end

function MatchService:UnregisterPlayer(player, now)
	removeFrom(self._participants, player)
	removeFrom(self._pendingJoins, player)
	self._upgrades:Clear(player)
	self._states[player] = nil
	FireValidator.Clear(player)
	if self._telemetry then
		self._telemetry:Clear(player)
	end

	-- A run with nobody left in it ends rather than ticking on forever.
	if #self._participants == 0 and self:IsRunActive() then
		self:_finish("Abandoned", now or 0)
	end
end

function MatchService:IsRunActive()
	return self._state ~= States.Lobby and self._state ~= States.Results and self._state ~= States.Cleanup
end

function MatchService:GetState()
	return self._state
end

--// run control --------------------------------------------------------------

function MatchService:RequestStart(player, now)
	if self._state ~= States.Lobby then
		return false, "a run is already in progress"
	end
	self:RegisterPlayer(player)

	-- Shared ownership: everyone registered in the lobby joins the descent together.
	table.clear(self._participants)
	for candidate, state in self._states do
		state:ResetRun()
		table.insert(self._participants, candidate)
	end
	if #self._participants == 0 then
		return false, "no players"
	end
	table.clear(self._pendingJoins)

	self._runId += 1
	self._runStartedAt = now
	self._roomIndex = 0
	self._eliteCleared = false
	self:_setState(States.Starting, now)
	self:_log("RunStart", { RunId = self._runId, Players = #self._participants }, now)
	return true
end

function MatchService:RequestReturnToLobby(player, now)
	if self._state ~= States.Results then
		return false, "no results to dismiss"
	end
	self:_setState(States.Cleanup, now)
	return true
end

function MatchService:ChooseUpgrade(player, offerId, cardId, now)
	if self._state ~= States.UpgradeChoice then
		return nil, "not choosing upgrades"
	end
	local state = self._states[player]
	if not state then
		return nil, "unknown player"
	end

	local card, reason = self._upgrades:Choose(player, state, offerId, cardId)
	if not card then
		return nil, reason
	end

	self:_fireClient("UpgradeResolved", player, { CardId = card.Id, Auto = false })
	self:_pushPlayerState(player)
	self:_log("CardChosen", { CardId = card.Id, RunId = self._runId, Room = self._roomIndex }, now)
	return card
end

--// combat hooks -------------------------------------------------------------

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
function MatchService:HandleFire(player, direction, power, now)
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

function MatchService:HandleImpact(result, entry, now)
	if self._effects then
		self._effects:Queue(result.Position, result.Normal)
	end

	local hit = self._enemies:ApplyHit(
		result.Instance,
		entry.damage + entry.damagePerBounce * math.max(entry.contacts - 1, 0),
		entry.direction,
		entry.shooter
	)
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

function MatchService:HandlePlayerContact(player, damage, _enemy, now)
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

function MatchService:IsAcceptingFire()
	return self._state == States.Combat
end

--// state machine ------------------------------------------------------------

function MatchService:_setState(state, now)
	self._state = state
	self._stateEnteredAt = now
	self:_broadcastRunState(now, true)
end

function MatchService:_allDown()
	for _, player in self._participants do
		local state = self._states[player]
		if state and state.alive then
			return false
		end
	end
	return true
end

function MatchService:_beginRoom(index, now)
	local definition = RunConfig.GetRoom(index)
	if not definition then
		return self:_finish("Extracted", now)
	end

	-- Anyone who joined mid-run is admitted here, at a room boundary, never mid-fight.
	for _, player in self._pendingJoins do
		local joiner = self._states[player]
		if joiner and not table.find(self._participants, player) then
			joiner:ResetRun()
			joiner.roomsCleared = index - 1 -- credited with the rooms the team already cleared
			table.insert(self._participants, player)
			self:_log("LateJoin", { RunId = self._runId, Room = index }, now)
		end
	end
	table.clear(self._pendingJoins)

	self._roomIndex = index
	self._rooms:Load(definition, now)

	local spawnPoint = self._rooms:GetSpawnPoint()
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			if not state.alive then
				state:Revive(now) -- downed players return at the start of the next room
			end
			state:GrantInvulnerability(now)
			if self._world then
				self._world.Teleport(player, spawnPoint)
			end
			self:_pushPlayerState(player)
		end
	end

	self:_setState(States.Combat, now)
	self:_log("RoomStart", { RunId = self._runId, Room = index, RoomId = definition.Id }, now)
	return nil
end

function MatchService:_onRoomCleared(now)
	local definition = RunConfig.GetRoom(self._roomIndex)
	if definition and definition.Kind == "Elite" then
		self._eliteCleared = true
	end

	for _, player in self._participants do
		local state = self._states[player]
		if state then
			state.roomsCleared += 1
			if state.alive and state.stats.RoomClearHeal > 0 then
				state:Heal(state.stats.RoomClearHeal)
			end
			self:_pushPlayerState(player)
		end
	end
	self:_log("RoomClear", { RunId = self._runId, Room = self._roomIndex }, now)

	if self._roomIndex >= RunConfig.RoomCount() then
		return self:_finish("Extracted", now)
	end

	self._projectiles:Clear()
	self:_openUpgradeChoice(now)
	return nil
end

function MatchService:_openUpgradeChoice(now)
	local offered = 0
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			local offer = self._upgrades:BuildOffer(player, state, now)
			self:_fireClient("UpgradeOffer", player, self._upgrades.ToClientPayload(offer))
			offered += 1
			self:_log("CardOffered", { RunId = self._runId, Room = self._roomIndex }, now)
		end
	end

	-- Nobody to offer to: skip straight on rather than waiting for choices that cannot arrive.
	self:_setState(offered > 0 and States.UpgradeChoice or States.Transition, now)
end

function MatchService:_finish(outcome, now)
	self._projectiles:Clear()
	self._rooms:Unload()
	self._upgrades:ClearAll()

	local context = {
		runId = self._runId,
		outcome = outcome,
		duration = now - self._runStartedAt,
		roomCount = RunConfig.RoomCount(),
		eliteCleared = self._eliteCleared,
	}

	local runKey = string.format("%s-%d", self._runKeyPrefix, self._runId)
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			local summary = RunSummary.ForPlayer(state, context)

			-- Two guards in series: the in-memory ledger stops a repeated completion event on
			-- this server, and the profile ledger stops a repeat across reconnects or servers.
			summary.Reward = self._rewards:Grant(self._runId, player, summary.Reward)
			if summary.Reward > 0 and self._persistence then
				summary.Reward = self._persistence:GrantReward(player, runKey, summary.Reward)
				self._persistence:RecordRunEnd(player, summary)
			end
			summary.RunKey = runKey

			self:_fireClient("RunResults", player, summary)
		end
	end

	self:_log("RunEnd", {
		RunId = self._runId,
		Outcome = outcome,
		Rooms = self._roomIndex,
		Duration = math.floor(context.duration),
	}, now)
	self:_setState(States.Results, now)
end

function MatchService:_cleanup(now)
	self._projectiles:Clear()
	self._rooms:Unload()
	self._enemies:Clear()
	self._upgrades:ClearAll()

	for _, player in self._participants do
		local state = self._states[player]
		if state then
			state:ResetRun()
			if self._world then
				self._world.Teleport(player, RunConfig.LobbyPosition)
			end
			self:_pushPlayerState(player)
		end
	end

	table.clear(self._participants)
	table.clear(self._pendingJoins)
	self._roomIndex = 0
	self:_setState(States.Lobby, now)
end

function MatchService:Step(deltaTime, now)
	self._now = now
	local state = self._state

	if state == States.Starting then
		if now - self._stateEnteredAt >= RunConfig.StartCountdown then
			self:_beginRoom(1, now)
		end
	elseif state == States.Combat then
		self._rooms:Step(deltaTime, now)
		if self:_allDown() then
			self:_finish("Defeated", now)
		elseif now - self._runStartedAt >= RunConfig.HardRunTimeLimit then
			self:_finish("TimedOut", now)
		elseif self._rooms:IsCleared(now) then
			self:_onRoomCleared(now)
		end
	elseif state == States.UpgradeChoice then
		for _, resolution in self._upgrades:ResolveExpired(now, function(key)
			return self._states[key]
		end) do
			self:_fireClient("UpgradeResolved", resolution.playerKey, { CardId = resolution.card.Id, Auto = true })
			self:_pushPlayerState(resolution.playerKey)
		end
		if not self._upgrades:HasPendingOffers() then
			self:_setState(States.Transition, now)
		end
	elseif state == States.Transition then
		if now - self._stateEnteredAt >= RunConfig.TransitionDuration then
			self:_beginRoom(self._roomIndex + 1, now)
		end
	elseif state == States.Results then
		if now - self._stateEnteredAt >= RunConfig.ResultsDuration then
			self:_setState(States.Cleanup, now)
		end
	elseif state == States.Cleanup then
		self:_cleanup(now)
	end

	self:_broadcastRunState(now, false)
end

--// messaging ----------------------------------------------------------------

function MatchService:GetRunSnapshot()
	local current = self._rooms:GetCurrent()
	local definition = current and current.definition
	return {
		State = self._state,
		RunId = self._runId,
		RoomIndex = self._roomIndex,
		RoomCount = RunConfig.RoomCount(),
		RoomName = definition and definition.DisplayName or "",
		RoomKind = definition and definition.Kind or "",
		EnemiesRemaining = self._rooms:GetRemaining(),
		Players = #self._participants,
		StateEndsAt = self:_stateEndsAt(),
	}
end

function MatchService:_stateEndsAt()
	local durations = {
		[States.Starting] = RunConfig.StartCountdown,
		[States.Transition] = RunConfig.TransitionDuration,
		[States.Results] = RunConfig.ResultsDuration,
	}
	local duration = durations[self._state]
	return duration and (self._stateEnteredAt + duration) or nil
end

function MatchService:_broadcastRunState(now, force)
	if not force and now < self._nextBroadcastAt then
		return
	end
	self._nextBroadcastAt = now + RunConfig.RunStateBroadcastInterval
	self:_fireAll("RunStateChanged", self:GetRunSnapshot())
end

function MatchService:_pushPlayerState(player)
	local state = self._states[player]
	if state then
		self:_fireClient("PlayerStateChanged", player, state:ToSnapshot())
	end
end

function MatchService:_fireClient(name, player, payload)
	local remote = self._net[name]
	if remote then
		remote:FireClient(player, payload)
	end
end

function MatchService:_fireAll(name, ...)
	local remote = self._net[name]
	if remote then
		remote:FireAllClients(...)
	end
end

function MatchService:_log(eventName, payload, now)
	if self._telemetry then
		self._telemetry:Log(eventName, payload, now)
	end
end

return MatchService
