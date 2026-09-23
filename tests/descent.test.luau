-- The descent cinematic: what plays on each run-state change, and the camera path down the shaft.
local DescentPlan = __require("DescentPlan")
local RunConfig = __require("RunConfig")

local States = RunConfig.States

local function snap(state, roomIndex, roomName, zone)
	return { State = state, RoomIndex = roomIndex or 0, RoomCount = 7, RoomName = roomName or "", Zone = zone or "" }
end

describe("DescentPlan.For", function()
	it("plunges down the shaft into the first zone when a run starts", function()
		local action = DescentPlan.For(States.Lobby, snap(States.Starting))
		expect(action.Kind).toBe("Plunge")
		expect(action.Zone).toBe(RunConfig.RunShape[1].Zone)
		expect(action.Duration).toBeLessThanOrEqual(RunConfig.StartCountdown)
		expect(action.Text).toBe("DESCENDING  ·  UPPER RUINS")
	end)

	it("arrives with a title card when combat begins", function()
		local action = DescentPlan.For(States.Starting, snap(States.Combat, 1, "Collapsed Atrium", "Ruins"))
		expect(action.Kind).toBe("Arrive")
		expect(action.Title).toBe("Room 1  ·  Collapsed Atrium")
		expect(action.Subtitle).toBe("Upper Ruins")
	end)

	it("plunges again between rooms, into the next slot's zone", function()
		local action = DescentPlan.For(States.UpgradeChoice, snap(States.Transition, 2, "Crossing", "Ruins"))
		expect(action.Kind).toBe("Plunge")
		expect(action.Zone).toBe("Foundry")
		expect(action.Duration).toBeLessThanOrEqual(RunConfig.TransitionDuration)
	end)

	it("does nothing on other changes", function()
		expect(DescentPlan.For(States.Combat, snap(States.UpgradeChoice, 1))).toBeNil()
		expect(DescentPlan.For(States.Combat, snap(States.Combat, 1))).toBeNil()
		expect(DescentPlan.For(States.Results, snap(States.Lobby))).toBeNil()
	end)
end)

describe("DescentPlan.CameraAt", function()
	it("falls steadily down the shaft, easing in and out, and fades to black at the end", function()
		local top = Vector3.new(-3000, 0, 0)
		local depth = 150
		local start = DescentPlan.CameraAt(0, 3, top, depth)
		local middle = DescentPlan.CameraAt(1.5, 3, top, depth)
		local finish = DescentPlan.CameraAt(3, 3, top, depth)
		expect(start.position.Y).toBeGreaterThan(middle.position.Y)
		expect(middle.position.Y).toBeGreaterThan(finish.position.Y)
		expect(top.Y - finish.position.Y).toBeCloseTo(depth, 0)
		-- It looks down the shaft the whole way.
		expect(middle.look.Y).toBeLessThan(-0.5)
		expect(start.fade).toBeGreaterThan(0.5)
		expect(middle.fade).toBeLessThan(0.1)
		expect(finish.fade).toBeCloseTo(1)
	end)
end)
