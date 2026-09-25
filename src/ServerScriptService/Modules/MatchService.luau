-- The run state machine. Owns run membership, room progression, upgrade rounds, win/loss and
-- teardown. Every collaborator is injected, so the whole loop is exercised headlessly in tests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchArsenal = require(script.Parent.MatchArsenal)
local MatchBroadcast = require(script.Parent.MatchBroadcast)
local MatchCombat = require(script.Parent.MatchCombat)
local MatchEffects = require(script.Parent.MatchEffects)
local MatchFlow = require(script.Parent.MatchFlow)
local MatchMembership = require(script.Parent.MatchMembership)
local MatchRoute = require(script.Parent.MatchRoute)
local PactConfig = require(ReplicatedStorage:WaitForChild("PactConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local RunPlanner = require(ReplicatedStorage:WaitForChild("RunPlanner"))
local UpgradeService = require(script.Parent.UpgradeService)

local States = RunConfig.States

local MatchService = {}
MatchService.__index = MatchService

-- The run loop is assembled from four halves, each installing its methods onto this class:
-- membership, room-to-room flow, combat handling and client messaging. What remains here is
-- the state machine itself.
MatchMembership.Install(MatchService)
MatchFlow.Install(MatchService)
MatchCombat.Install(MatchService)
MatchEffects.Install(MatchService)
MatchArsenal.Install(MatchService)
MatchRoute.Install(MatchService)
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
	-- player -> their saved Depth Pact. Optional: without it every run is at Heat 0.
	self._pactProvider = deps.pactProvider
	-- Crit rolls. Seeded per arena so a test can reproduce them.
	self._random = deps.random or Random.new(deps.seed or 1)
	-- Which arsenal systems this match runs: { orbs, surge, combo }. Each is off unless asked
	-- for, so a match built without them plays exactly as it always has.
	self._arsenal = deps.arsenal or {}
	-- Orbs on the floor (OrbDrops); required for orbs to be on.
	self._orbDrops = deps.orbDrops
	-- Surge perks come from their own pool and their own offer book.
	self._surges = deps.surges or UpgradeService.new((deps.seed or 1) + 101, "Minor")
	-- Coin pickups for this arena (CoinDrops). Optional: without it kills drop nothing.
	self._coins = deps.coins
	-- (player, summary) after each finished run is paid and recorded: quests, badges, boards.
	self._onRunEnd = deps.onRunEnd
	-- runId -> the rooms for that run. Defaults to a fresh random draw from the zone pools;
	-- tests and tools pass a fixed plan.
	self._planRun = deps.planRun or function()
		return RunPlanner.Plan(Random.new())
	end
	-- Only a plan drawn from RunConfig.RunShape knows which slot each room fills, which is what
	-- door choices need to find alternative rooms.
	self._planFollowsShape = deps.planRun == nil
	self._plan = {}
	-- Doors, challenges, room events, the haul at risk (with the Surface Lift) and depth
	-- pressure: { doors, challenges, events, haul, pressure }. Off unless asked for.
	self._route = deps.route or {}
	self._roomRewards = {}
	if self._route.events and self._rooms.SetEvents then
		self._rooms:SetEvents({ runners = true })
	end
	if self._route.pressure and self._rooms.SetPressure then
		self._rooms:SetPressure(RunConfig.Pressure)
		self._rooms.OnPressure = function()
			self:_fireAll("Notify", { Kind = "Callout", Text = "THE DEPTHS STIR. HUNTERS COMING!", Tone = "Warning" })
		end
	end

	self._states = {}
	self._participants = {}
	self._pendingJoins = {}
	self:_applyPact({})
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
		-- Magnet enemies bend shots that pass near them.
		self:_steerShot(entry, from, to)
	end
	self._hazardNextAt = {}
	self._regenPushAt = {}
	-- Lets a projectile that an enemy moved over still register, rather than passing through.
	self._projectiles.OverlapQuery = function(position, margin)
		return self._enemies:FindEnclosingMover(position, margin)
	end
	-- A shot that carried an orb drops it where it stopped.
	self._projectiles.OnExpire = function(entry, position)
		self:_onShotExpired(entry, position)
	end
	-- A Treasure Runner that got away.
	self._enemies.OnEscape = function(enemy)
		if enemy.archetype.Optional then
			self:_fireAll("Notify", { Kind = "Error", Text = "The Treasure Runner got away!" })
		end
	end
	-- Burn ticks land through the same damage path as every other hit.
	self._enemies.OnStatusDamage = function(enemy, damage, shooter, now)
		self:_secondaryDamage(enemy, damage, shooter, 0, "Burn", now or self._now)
	end

	return self
end

-- Where every live participant stands, for room objectives.
function MatchService:_livePositions()
	local positions = {}
	for _, target in self:_targets() do
		table.insert(positions, target.position)
	end
	return positions
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

	-- The group's Pact is settled before anyone's stats are, since it can change them.
	local pacts = {}
	for candidate in self._states do
		table.insert(pacts, self._pactProvider and self._pactProvider(candidate) or {})
	end
	self:_applyPact(PactConfig.Merge(pacts))

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
	self._plan = table.clone(self._planRun(self._runId))
	self._slots = self._planFollowsShape and table.clone(RunConfig.RunShape) or nil
	self._roomRewards = {}
	self._surges:ClearAll()
	self._doors = nil
	self._challenge = nil
	self._lastReward = nil
	self._activeReward = nil
	self._runStartedAt = now
	self._roomIndex = 0
	self._eliteCleared = false
	self._zonesCleared = 0
	self:_setState(States.Starting, now)
	self:_log("RunStart", {
		RunId = self._runId,
		Players = #self._participants,
		Rooms = #self._plan,
		Heat = self._pactEffects.Heat,
	}, now)
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

-- Reads the player's shop, pass and rig bonuses as they stand now, for the run about to start,
-- and folds in what the run's Pact does to every player (Frailty).
function MatchService:_refreshMeta(player, state)
	local meta = self._metaProvider and self._metaProvider(player) or {}
	local stats = table.clone(type(meta.stats) == "table" and meta.stats or {})
	local delta = self._pactEffects.MaxHealthDelta
	if delta ~= 0 then
		stats.MaxHealthBonus = (stats.MaxHealthBonus or 0) + delta
	end
	state:SetMeta({ stats = stats, trail = meta.trail, rig = meta.rig })
end

-- Sets the run's Depth Pact and applies what it does to enemies and rooms.
function MatchService:_applyPact(pact)
	self._pact = pact
	self._pactEffects = PactConfig.Effects(pact)
	local effects = self._pactEffects
	if self._enemies.SetModifiers then
		self._enemies:SetModifiers({ Health = effects.EnemyHealth, Speed = effects.EnemySpeed, Damage = effects.EnemyDamage })
	end
	if self._rooms.SetChampionBonus then
		self._rooms:SetChampionBonus(effects.ChampionBonus)
	end
end

function MatchService:GetPact()
	return table.clone(self._pact), self._pactEffects.Heat
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

	if state == States.Combat or state == States.UpgradeChoice or state == States.Transition then
		self:_rescueFallers(now)
	end

	if state == States.Starting then
		if now - self._stateEnteredAt >= RunConfig.StartCountdown then
			self:_beginRoom(1, now)
		end
	elseif state == States.Combat then
		self._rooms:Step(deltaTime, now, self:_livePositions())
		self:_stepChallenge(now)
		self:_applyHazards(now)
		self:_collectCoins(deltaTime, now)
		self:_applyRegen(deltaTime, now)
		self:_stepRevives(deltaTime, now)
		self:_stepArsenal(deltaTime, now)
		if self:_allDown() then
			self:_finish("Defeated", now)
		elseif now - self._runStartedAt >= RunConfig.HardRunTimeLimit then
			self:_finish("TimedOut", now)
		elseif self._rooms:IsCleared(now) then
			local current = self._rooms:GetCurrent()
			if current and current.timedOut and current.boss then
				-- Surviving the clock is not a win: the boss room ends the run out of time.
				self:_finish("TimedOut", now)
			else
				self:_onRoomCleared(now)
			end
		end
	elseif state == States.UpgradeChoice then
		self:_applyRegen(deltaTime, now)
		self:_resolveSurges(now, false)
		for _, resolution in self._upgrades:ResolveExpired(now, function(key)
			return self._states[key]
		end) do
			self:_fireClient("UpgradeResolved", resolution.playerKey, { CardId = resolution.card.Id, Auto = true })
			self:_pushPlayerState(resolution.playerKey)
		end
		if not self._upgrades:HasPendingOffers() and self:_doorsSettled(now) then
			local door = self:_resolveDoors()
			if door and door.Reward == "Lift" then
				-- The group took the Surface Lift: the run ends here and the haul is banked.
				self:_finish("Surfaced", now)
			else
				self:_setState(States.Transition, now)
			end
		end
	elseif state == States.Transition then
		self:_applyRegen(deltaTime, now)
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
