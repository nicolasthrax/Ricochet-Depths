-- Everything the run loop sends to clients. Snapshots are built here so MatchService holds
-- only state-machine logic, and so the wire format lives in one place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local Broadcast = { methods = {} }

function Broadcast.methods:GetRunSnapshot()
	local current = self._rooms:GetCurrent()
	local definition = current and current.definition
	return {
		State = self._state,
		RunId = self._runId,
		RoomIndex = self._roomIndex,
		RoomCount = #self._plan > 0 and #self._plan or RunConfig.RoomCount(),
		RoomName = definition and definition.DisplayName or "",
		Zone = definition and definition.Zone or "",
		-- The zone of the room after this one, for the descent between them. Taken from the plan,
		-- not the run shape, since a bonus room can shift the order.
		NextZone = self._plan[self._roomIndex + 1] and self._plan[self._roomIndex + 1].Zone or nil,
		RoomKind = definition and definition.Kind or "",
		EnemiesRemaining = self._rooms:GetRemaining(),
		Players = #self._participants,
		Boss = self:_bossSnapshot(current),
		Heat = self._pactEffects and self._pactEffects.Heat or 0,
		Downed = self:_downedSnapshot(),
		Wave = self._rooms.GetWaveInfo and self._rooms:GetWaveInfo() or nil,
		Objective = self:_objectiveSnapshot(),
		Challenge = self._challengeSnapshot and self:_challengeSnapshot() or nil,
		Doors = self._state == RunConfig.States.UpgradeChoice and self._doorsSnapshot and self:_doorsSnapshot(self._now) or nil,
		Pressure = self._state == RunConfig.States.Combat and self._rooms.GetPressureInfo
			and self._rooms:GetPressureInfo(self._now) or nil,
		-- Today's biome modifier (the HUD chip), and whether this is a player's first descent.
		Modifier = self.GetModifier and self:GetModifier() or nil,
		FirstDescent = self._runOptions and self._runOptions.firstDescent or nil,
	}
end

function Broadcast.methods:_objectiveSnapshot()
	local objective = self._rooms.GetObjective and self._rooms:GetObjective()
	return objective and objective:Snapshot(self._now) or nil
end

-- Downed teammates and how far along their revive is, while anyone is down in a group run.
function Broadcast.methods:_downedSnapshot()
	if #self._participants < 2 then
		return nil
	end
	local downed = nil
	for _, player in self._participants do
		local state = self._states[player]
		if state and not state.alive then
			downed = downed or {}
			table.insert(downed, {
				UserId = state.userId,
				Name = state.name,
				Progress = math.floor(state.reviveProgress * 100) / 100,
			})
		end
	end
	return downed
end

-- The boss bar's data while a boss is alive in the current room; nil otherwise.
function Broadcast.methods:_bossSnapshot(current)
	local boss = current and (current.boss or current.miniBoss)
	if not boss or boss.dead then
		return nil
	end
	return {
		Name = boss.archetype.DisplayName,
		Health = math.max(boss.health, 0),
		MaxHealth = boss.maxHealth,
		Phase = boss.archetype.Phases and self._enemies.BossPhase(boss) or nil,
	}
end

function Broadcast.methods:_broadcastRunState(now, force)
	if not force and now < self._nextBroadcastAt then
		return
	end
	self._nextBroadcastAt = now + RunConfig.RunStateBroadcastInterval
	self:_fireAll("RunStateChanged", self:GetRunSnapshot())
end

function Broadcast.methods:_pushPlayerState(player)
	local state = self._states[player]
	if state then
		self:_fireClient("PlayerStateChanged", player, state:ToSnapshot())
	end
end

function Broadcast.methods:_fireClient(name, player, payload)
	local remote = self._net[name]
	if remote then
		remote:FireClient(player, payload)
	end
end

-- To everyone in this match, not the whole server: other arenas run other matches.
function Broadcast.methods:_fireAll(name, ...)
	local remote = self._net[name]
	if remote then
		for player in self._states do
			remote:FireClient(player, ...)
		end
	end
end

function Broadcast.Install(class)
	for name, method in Broadcast.methods do
		class[name] = method
	end
end

return Broadcast
