-- Run planning: every descent draws its rooms from zone pools, in a fixed zone order, so runs
-- vary while difficulty still climbs.
local RoomConfig = __require("RoomConfig")
local RoomGeometry = __require("RoomGeometry")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")

local function ids(plan)
	local out = {}
	for _, room in plan do
		table.insert(out, room.Id)
	end
	return table.concat(out, ",")
end

describe("zones and the room catalogue", function()
	it("ships three zones, each with at least three layouts of its own", function()
		local zones = 0
		for zoneId in RunConfig.Zones do
			zones += 1
			local layouts = {}
			for _, room in RunConfig.Rooms do
				if room.Zone == zoneId then
					layouts[room.Layout] = true
				end
			end
			local count = 0
			for _ in layouts do
				count += 1
			end
			expect(count).toBeGreaterThanOrEqual(3)
		end
		expect(zones).toBe(3)
	end)

	it("uses every layout, with at least twelve in all", function()
		local used = {}
		for _, room in RunConfig.Rooms do
			used[room.Layout] = true
			expect(RunConfig.Zones[room.Zone]).toBeTruthy()
		end
		local count = 0
		for layoutId in RoomConfig.Layouts do
			if not used[layoutId] then
				error("layout " .. layoutId .. " is never used by a room")
			end
			count += 1
		end
		expect(count).toBeGreaterThanOrEqual(12)
	end)

	it("finds a room by id", function()
		expect(RunConfig.GetRoomById("Crossing").Layout).toBe("Crossing")
		expect(RunConfig.GetRoomById("nope")).toBeNil()
	end)
end)

describe("RunPlanner.Plan", function()
	it("fills every slot of the run shape from the matching zone and tier", function()
		for seed = 1, 40 do
			local plan = RunPlanner.Plan(Random.new(seed))
			expect(#plan).toBe(RunConfig.RoomCount())
			for index, slot in RunConfig.RunShape do
				local room = plan[index]
				if slot.Room then
					expect(room.Id).toBe(slot.Room)
				else
					expect(room.Zone).toBe(slot.Zone)
					expect(room.Tier).toBe(slot.Tier)
				end
			end
		end
	end)

	it("never repeats a room within a run", function()
		for seed = 1, 40 do
			local seen = {}
			for _, room in RunPlanner.Plan(Random.new(seed)) do
				expect(seen[room.Id]).toBeNil()
				seen[room.Id] = true
			end
		end
	end)

	it("is deterministic per seed and varies between seeds", function()
		expect(ids(RunPlanner.Plan(Random.new(7)))).toBe(ids(RunPlanner.Plan(Random.new(7))))
		local distinct, count = {}, 0
		for seed = 1, 30 do
			local key = ids(RunPlanner.Plan(Random.new(seed)))
			if not distinct[key] then
				distinct[key] = true
				count += 1
			end
		end
		expect(count).toBeGreaterThanOrEqual(6)
	end)

	it("climbs through the zones in order", function()
		local plan = RunPlanner.Plan(Random.new(3))
		local last = 0
		for _, room in plan do
			local order = RunConfig.Zones[room.Zone].Order
			expect(order).toBeGreaterThanOrEqual(last)
			last = order
		end
	end)

	it("builds a fixed plan from room ids for tests and tools", function()
		local plan = RunPlanner.Fixed({ "Atrium", "Crossing" })
		expect(#plan).toBe(2)
		expect(plan[2].Id).toBe("Crossing")
	end)
end)

describe("every layout leaves the spawn open", function()
	it("has a clear 20-stud line from the spawn in all eight directions", function()
		for layoutId, layout in RoomConfig.Layouts do
			local footprints = RoomGeometry.Footprints(layout, RoomConfig)
			for step = 0, 7 do
				local angle = step * math.pi / 4
				local target = Vector2.new(math.cos(angle) * 20, math.sin(angle) * 20)
				if RoomGeometry.SegmentBlocked(footprints, Vector2.zero, target) then
					error(("%s: the spawn is closed towards %d degrees"):format(layoutId, step * 45))
				end
			end
		end
	end)
end)
