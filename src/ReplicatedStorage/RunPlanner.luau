-- Picks the rooms for one descent from RunConfig.RunShape: each slot draws a room of its Zone
-- and Tier that the run has not used yet, or takes the fixed Room it names.
local RunConfig = require(script.Parent:WaitForChild("RunConfig"))

local RunPlanner = {}

-- random is a Random; the same seed always yields the same run.
function RunPlanner.Plan(random)
	local plan, used = {}, {}
	for index, slot in RunConfig.RunShape do
		local room
		if slot.Room then
			room = RunConfig.GetRoomById(slot.Room)
		else
			local candidates = {}
			for _, candidate in RunConfig.Rooms do
				if candidate.Zone == slot.Zone and candidate.Tier == slot.Tier and not used[candidate.Id] then
					table.insert(candidates, candidate)
				end
			end
			if #candidates > 0 then
				room = candidates[random:NextInteger(1, #candidates)]
			end
		end
		if not room then
			error(("run shape slot %d has no room to draw"):format(index))
		end
		used[room.Id] = true
		table.insert(plan, room)
	end
	return plan
end

-- Rooms that could fill `slot` besides those in `used`, shuffled with `random`.
function RunPlanner.Candidates(slot, used, random)
	local candidates = {}
	if slot.Room then
		return candidates
	end
	for _, candidate in RunConfig.Rooms do
		if candidate.Zone == slot.Zone and candidate.Tier == slot.Tier and not used[candidate.Id] then
			table.insert(candidates, candidate)
		end
	end
	for index = #candidates, 2, -1 do
		local swap = random:NextInteger(1, index)
		candidates[index], candidates[swap] = candidates[swap], candidates[index]
	end
	return candidates
end

-- A plan of named rooms, in order. For tests and tools that need a known sequence.
function RunPlanner.Fixed(roomIds)
	local plan = {}
	for _, roomId in roomIds do
		local room = RunConfig.GetRoomById(roomId)
		assert(room, "unknown room " .. roomId)
		table.insert(plan, room)
	end
	return plan
end

return RunPlanner
