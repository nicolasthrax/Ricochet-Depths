-- Multiplayer gates in the lobby. Players walk into a gate; once it holds MinPlayers a countdown
-- runs (shorter when the gate is full), and when it ends the gate's members descend together.
-- A gate holds at most Capacity; anyone past that is reported as overflow, for the server to
-- move back out. Pure: positions come in through a function, so it runs headlessly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local PartyRooms = {}
PartyRooms.__index = PartyRooms

-- rooms: { { Id, Center = Vector3, HalfSize = Vector2 (XZ), Capacity, MinPlayers } }
function PartyRooms.new(rooms)
	local self = setmetatable({ _rooms = rooms, _state = {} }, PartyRooms)
	for _, room in rooms do
		self._state[room.Id] = { members = {}, deadline = nil }
	end
	return self
end

-- Room definitions from LobbyBuilder's gates.
function PartyRooms.FromGates(gates)
	local rooms = {}
	for _, gate in gates do
		table.insert(rooms, {
			Id = gate.Id,
			Center = gate.zone.Position,
			HalfSize = Vector2.new(gate.zone.Size.X / 2, gate.zone.Size.Z / 2),
			Capacity = gate.capacity,
			MinPlayers = gate.minPlayers,
		})
	end
	return rooms
end

local function contains(room, position)
	return math.abs(position.X - room.Center.X) <= room.HalfSize.X and math.abs(position.Z - room.Center.Z) <= room.HalfSize.Y
end

-- players: everyone in the lobby. getPosition(player) -> Vector3 or nil. isBusy(player), when
-- given, marks players who are already committed elsewhere (in a run), so gates ignore them.
-- Returns { [roomId] = { Members, Overflow, Countdown (seconds left, or nil), Start } }.
function PartyRooms:Step(now, players, getPosition, isBusy)
	local result = {}
	for _, room in self._rooms do
		local state = self._state[room.Id]
		local inside = {}
		for _, player in players do
			local position = (not isBusy or not isBusy(player)) and getPosition(player)
			if position and contains(room, position) then
				inside[player] = true
			end
		end

		-- Whoever held a place last step keeps it; newcomers fill what is left, in list order.
		local members, overflow = {}, {}
		for _, player in state.members do
			if inside[player] and #members < room.Capacity then
				table.insert(members, player)
				inside[player] = nil
			end
		end
		for _, player in players do
			if inside[player] then
				if #members < room.Capacity then
					table.insert(members, player)
				else
					table.insert(overflow, player)
				end
			end
		end
		state.members = members

		local entry = { Members = members, Overflow = overflow, Start = false }
		if #members >= room.MinPlayers then
			state.deadline = state.deadline or (now + RunConfig.Lobby.GateCountdown)
			if #members >= room.Capacity then
				state.deadline = math.min(state.deadline, now + RunConfig.Lobby.FullCountdown)
			end
			local remaining = math.max(state.deadline - now, 0)
			entry.Countdown = remaining
			if remaining <= 0 then
				entry.Start = true
				-- If they are still standing here next step (no arena was free), a fresh
				-- countdown runs.
				state.deadline = nil
			end
		else
			state.deadline = nil
		end
		result[room.Id] = entry
	end
	return result
end

return PartyRooms
