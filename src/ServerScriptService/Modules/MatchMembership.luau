-- Who is in a run: registration, late-join queueing, and removal. Installed onto MatchService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchCombat = require(script.Parent.MatchCombat)
local PlayerState = require(script.Parent.PlayerState)
local RewardService = require(script.Parent.RewardService)
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local States = RunConfig.States

local Membership = { methods = {} }

local function removeFrom(list, value)
	for index, entry in list do
		if entry == value then
			table.remove(list, index)
			return true
		end
	end
	return false
end

-- Late join rule: a player who arrives while a run is in progress is queued and admitted at the
-- next room boundary, never mid-fight and never mid-upgrade-round. They start the room they join
-- with a fresh state and no upgrades.
function Membership.methods:RegisterPlayer(player)
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

function Membership.methods:IsPendingJoin(player)
	return table.find(self._pendingJoins, player) ~= nil
end

function Membership.methods:IsParticipant(player)
	return table.find(self._participants, player) ~= nil
end

function Membership.methods:GetPlayerState(player)
	return self._states[player]
end

function Membership.methods:GetParticipants()
	return table.clone(self._participants)
end

function Membership.methods:UnregisterPlayer(player, now)
	-- Leaving mid-run still pays for the coins already picked up, and the experience earned so
	-- far. The profile is still loaded here (the server releases it after this), and the key
	-- makes a repeat pay nothing.
	local state = self._states[player]
	if state and self:IsRunActive() and table.find(self._participants, player) and self._persistence then
		local amount = RewardService.Multiply(state, state.coins)
		local xp = RewardService.Experience(state, "Left", false)
		if amount > 0 or xp > 0 then
			local runKey = string.format("%s-%d-left", self._runKeyPrefix, self._runId)
			self:_payout(player, runKey, amount, xp)
		end
		state.coins = 0
	end
	removeFrom(self._participants, player)
	removeFrom(self._pendingJoins, player)
	self._upgrades:Clear(player)
	if self._surges then
		self._surges:Clear(player)
	end
	self._states[player] = nil
	MatchCombat.ClearPlayer(player)

	-- A run with nobody left in it ends rather than ticking on forever.
	if #self._participants == 0 and self:IsRunActive() then
		self:_finish("Abandoned", now or self._now)
	end
end

function Membership.methods:IsRunActive()
	return self._state ~= States.Lobby and self._state ~= States.Results and self._state ~= States.Cleanup
end

function Membership.methods:GetState()
	return self._state
end

function Membership.Install(class)
	for name, method in Membership.methods do
		class[name] = method
	end
end

return Membership
