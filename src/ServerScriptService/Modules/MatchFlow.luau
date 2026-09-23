-- Room-to-room progression: starting a room, clearing it, opening an upgrade round, finishing
-- a run and tearing it down. Installed onto MatchService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunSummary = require(script.Parent.RunSummary)
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local States = RunConfig.States

local Flow = { methods = {} }

function Flow.methods:_beginRoom(index, now)
	local definition = self._plan[index]
	if not definition then
		return self:_finish("Extracted", now)
	end

	-- Anyone who joined mid-run is admitted here, at a room boundary, never mid-fight.
	for _, player in self._pendingJoins do
		local joiner = self._states[player]
		if joiner and not table.find(self._participants, player) then
			self:_refreshMeta(player, joiner)
			joiner:ResetRun()
			-- No credit for rooms cleared before they arrived. roomsCleared only ever grows in
			-- _onRoomCleared, for participants present at the clear, so it counts rooms this
			-- player was actually in. Pre-crediting let a player wait out a run and join at the
			-- elite room to collect the whole team's room payout.
			joiner.joinedAtRoom = index
			table.insert(self._participants, player)
			self:_log("LateJoin", { RunId = self._runId, Room = index }, now)
		end
	end
	table.clear(self._pendingJoins)

	self._roomIndex = index

	local loaded, reason = self._rooms:Load(definition, now)
	if not loaded then
		-- Nothing was built, so there is nothing to clear: IsCleared stays false and the run
		-- would sit in Combat until the hard time limit. End it instead of hanging.
		if self._telemetry then
			self._telemetry:LogError("RoomLoadFailed", reason, now)
		end
		return self:_finish("Aborted", now)
	end

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
				if self._world.SetWalkSpeed then
					self._world.SetWalkSpeed(player, RunConfig.BaseWalkSpeed + state.stats.MoveSpeedBonus)
				end
			end
			self:_pushPlayerState(player)
		end
	end

	self:_setState(States.Combat, now)
	self:_log("RoomStart", { RunId = self._runId, Room = index, RoomId = definition.Id }, now)
	return nil
end

-- A participant whose character respawned mid-run (a reset, or a fall out of the world)
-- appears at the lobby's SpawnLocation; this puts them back in the current room. It also covers
-- a room start that could not teleport someone who was mid-respawn at the time.
function Flow.methods:HandleCharacterAdded(player)
	local state = self._states[player]
	if not state or not self:IsRunActive() or not table.find(self._participants, player) then
		return false
	end
	if not self._rooms:GetCurrent() or not self._world then
		return false -- no room yet: the room start teleports everyone
	end
	self._world.Teleport(player, self._rooms:GetSpawnPoint())
	if self._world.SetWalkSpeed then
		self._world.SetWalkSpeed(player, RunConfig.BaseWalkSpeed + state.stats.MoveSpeedBonus)
	end
	return true
end

function Flow.methods:_onRoomCleared(now)
	local definition = self._plan[self._roomIndex]
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

	if self._roomIndex >= #self._plan then
		return self:_finish("Extracted", now)
	end

	self._projectiles:Clear()
	self:_openUpgradeChoice(now)
	return nil
end

function Flow.methods:_openUpgradeChoice(now)
	local offered = 0
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			local offer = self._upgrades:BuildOffer(player, state, now)
			self:_fireClient("UpgradeOffer", player, self._upgrades.ToClientPayload(offer, now))
			offered += 1
			self:_log("CardOffered", { RunId = self._runId, Room = self._roomIndex }, now)
		end
	end

	-- Nobody to offer to: skip straight on rather than waiting for choices that cannot arrive.
	self:_setState(offered > 0 and States.UpgradeChoice or States.Transition, now)
end

function Flow.methods:_finish(outcome, now)
	self._projectiles:Clear()
	self._rooms:Unload()
	self._upgrades:ClearAll()

	local context = {
		runId = self._runId,
		outcome = outcome,
		duration = now - self._runStartedAt,
		roomCount = #self._plan,
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
			if self._persistence then
				if summary.Reward > 0 then
					summary.Reward = self._persistence:GrantReward(player, runKey, summary.Reward)
				end
				-- Every finished run counts, paid or not: stats advance and onboarding retires.
				self._persistence:RecordRunEnd(player, summary)
				-- Written now, not left for autosave or leave: a payout is the one change whose
				-- loss really hurts, and this single write carries it with the run's stats.
				self._persistence:SaveInBackground(player, now)
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

function Flow.methods:_cleanup(now)
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
				if self._world.SetWalkSpeed then
					self._world.SetWalkSpeed(player, RunConfig.BaseWalkSpeed)
				end
			end
			self:_pushPlayerState(player)
		end
	end

	table.clear(self._participants)
	table.clear(self._pendingJoins)
	self._roomIndex = 0
	self:_setState(States.Lobby, now)
end

function Flow.Install(class)
	for name, method in Flow.methods do
		class[name] = method
	end
end

return Flow
