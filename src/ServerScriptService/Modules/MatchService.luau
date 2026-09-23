-- The run state machine. Owns run membership, room progression, upgrade rounds, win/loss and
-- teardown. Every collaborator is injected, so the whole loop is exercised headlessly in tests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchBroadcast = require(script.Parent.MatchBroadcast)
local MatchCombat = require(script.Parent.MatchCombat)
local MatchFlow = require(script.Parent.MatchFlow)
local MatchMembership = require(script.Parent.MatchMembership)
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local RunPlanner = require(ReplicatedStorage:WaitForChild("RunPlanner"))

local States = RunConfig.States

local MatchService = {}
MatchService.__index = MatchService

-- The run loop is assembled from four halves, each installing its methods onto this class:
-- membership, room-to-room flow, combat handling and client messaging. What remains here is
-- the state machine itself.
MatchMembership.Install(MatchService)
MatchFlow.Install(MatchService)
MatchCombat.Install(MatchService)
MatchBroadcast.Install(MatchService)

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
	-- player -> salvage-shop bonuses for a run starting now. Optional: without it every player
	-- starts from the base stats.
	self._metaProvider = deps.metaProvider
	-- runId -> the rooms for that run. Defaults to a fresh random draw from the zone pools;
	-- tests and tools pass a fixed plan.
	self._planRun = deps.planRun or function()
		return RunPlanner.Plan(Random.new())
	end
	self._plan = {}

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
	self._enemies.OnPlayerContact = function(player, damage, enemy, now)
		self:HandlePlayerContact(player, damage, enemy, now or self._now)
	end
	-- Room mechanics see every shot's travel (amp pads).
	self._projectiles.SegmentHook = function(entry, from, to)
		local mechanics = self._rooms:GetMechanics()
		if mechanics then
			mechanics:ApplySegment(entry, from, to)
		end
	end
	self._hazardNextAt = {}
	-- Lets a projectile that an enemy moved over still register, rather than passing through.
	self._projectiles.OverlapQuery = function(position, margin)
		return self._enemies:FindEnclosingMover(position, margin)
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

--// run control --------------------------------------------------------------

function MatchService:RequestStart(player, now)
	if self._state ~= States.Lobby then
		return false, "a run is already in progress"
	end
	self:RegisterPlayer(player)

	-- Shared ownership: everyone registered in the lobby joins the descent together.
	table.clear(self._participants)
	for candidate, state in self._states do
		self:_refreshMeta(candidate, state)
		state:ResetRun()
		table.insert(self._participants, candidate)
	end
	if #self._participants == 0 then
		return false, "no players"
	end
	table.clear(self._pendingJoins)

	self._runId += 1
	self._plan = self._planRun(self._runId)
	self._runStartedAt = now
	self._roomIndex = 0
	self._eliteCleared = false
	self:_setState(States.Starting, now)
	self:_log("RunStart", { RunId = self._runId, Players = #self._participants, Rooms = #self._plan }, now)
	return true
end

-- Any participant can dismiss the results for the whole team, which is why the requesting
-- player is not consulted. Shared run, shared results screen.
function MatchService:RequestReturnToLobby(_player, now)
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

-- Reads the player's shop bonuses as they stand now, for the run about to start.
function MatchService:_refreshMeta(player, state)
	if self._metaProvider then
		state:SetMeta(self._metaProvider(player))
	end
end

--// combat hooks -------------------------------------------------------------

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

function MatchService:Step(deltaTime, now)
	self._now = now
	local state = self._state

	if state == States.Starting then
		if now - self._stateEnteredAt >= RunConfig.StartCountdown then
			self:_beginRoom(1, now)
		end
	elseif state == States.Combat then
		self._rooms:Step(deltaTime, now)
		self:_applyHazards(now)
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

function MatchService:_log(eventName, payload, now)
	if self._telemetry then
		self._telemetry:Log(eventName, payload, now)
	end
end

return MatchService
