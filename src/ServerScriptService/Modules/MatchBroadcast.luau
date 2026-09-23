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
		RoomKind = definition and definition.Kind or "",
		EnemiesRemaining = self._rooms:GetRemaining(),
		Players = #self._participants,
		Boss = self:_bossSnapshot(current),
	}
end

-- The boss bar's data while a boss is alive in the current room; nil otherwise.
function Broadcast.methods:_bossSnapshot(current)
	local boss = current and current.boss
	if not boss or boss.dead then
		return nil
	end
	return {
		Name = boss.archetype.DisplayName,
		Health = math.max(boss.health, 0),
		MaxHealth = boss.maxHealth,
		Phase = self._enemies.BossPhase(boss),
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

function Broadcast.methods:_fireAll(name, ...)
	local remote = self._net[name]
	if remote then
		remote:FireAllClients(...)
	end
end

function Broadcast.Install(class)
	for name, method in Broadcast.methods do
		class[name] = method
	end
end

return Broadcast
