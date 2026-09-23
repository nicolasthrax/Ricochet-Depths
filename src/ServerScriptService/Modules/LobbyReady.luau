-- Co-op ready-up. Players stand on the lobby's ready pads; once every player in the lobby is on
-- a pad (or every pad is taken, when more have gathered than a run holds) a short countdown
-- runs, and the descent starts when it ends. Stepping off, or losing your character, resets it.
-- Pure: positions come in through a function, so it runs headlessly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local LobbyReady = {}
LobbyReady.__index = LobbyReady

-- pads: { { Center = Vector3, HalfSize = Vector2 (XZ) } }. options.countdown in seconds.
function LobbyReady.new(pads, options)
	options = options or {}
	return setmetatable({
		_pads = pads,
		_countdown = options.countdown or RunConfig.Lobby.ReadyCountdown,
		_since = nil,
		_fired = false,
	}, LobbyReady)
end

function LobbyReady.PadsFromParts(parts)
	local pads = {}
	for index, part in parts do
		pads[index] = { Center = part.Position, HalfSize = Vector2.new(part.Size.X / 2, part.Size.Z / 2) }
	end
	return pads
end

function LobbyReady:_padAt(position)
	for index, pad in self._pads do
		if
			math.abs(position.X - pad.Center.X) <= pad.HalfSize.X
			and math.abs(position.Z - pad.Center.Z) <= pad.HalfSize.Y
		then
			return index
		end
	end
	return nil
end

-- players: everyone currently in the lobby. getPosition(player) -> Vector3 or nil.
-- Returns { Ready, Total, Countdown (seconds left, or nil when not everyone is ready), Start,
-- Starter (the first ready player, on the frame the countdown ends), Occupied = { bool } }.
function LobbyReady:Step(now, players, getPosition)
	local occupied = table.create(#self._pads, false)
	local ready = {}
	for _, player in players do
		local position = getPosition(player)
		local index = position and self:_padAt(position)
		-- One pad, one player: crowding a pad does not make two people ready.
		if index and not occupied[index] then
			occupied[index] = true
			table.insert(ready, player)
		end
	end

	local snapshot = { Ready = #ready, Total = #players, Occupied = occupied, Start = false }
	local everyone = #players > 0 and (#ready == #players or #ready == #self._pads)
	if not everyone then
		self._since = nil
		self._fired = false
		return snapshot
	end

	self._since = self._since or now
	local remaining = math.max(self._countdown - (now - self._since), 0)
	snapshot.Countdown = remaining
	if remaining <= 0 and not self._fired then
		self._fired = true
		snapshot.Start = true
		snapshot.Starter = ready[1]
	end
	return snapshot
end

return LobbyReady
