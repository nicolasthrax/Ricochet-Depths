-- Lane game, client math: the locked camera fits the whole lane on every screen shape.
__freshMvp()
local GameConfig = __require("GameConfig")
local LaneGeometry = __require("LaneGeometry")
local LaneCamera = __require("LaneCamera")

local Camera = GameConfig.Camera
local Lane = GameConfig.Lane
local World = GameConfig.World

local function laneWidthFraction(viewport, distance)
	local tanHalfV = math.tan(math.rad(Camera.fovDegrees) / 2)
	local tanHalfH = tanHalfV * viewport.X / viewport.Y
	local width = Lane.halfWidth * 2 + World.wallThickness * 2
	return width / (2 * tanHalfH * distance)
end

describe("LaneCamera", function()
	it("never lets the lane width pass its share of the screen, from 4:3 to 20:9", function()
		for _, viewport in { Vector2.new(1024, 768), Vector2.new(1920, 1080), Vector2.new(2400, 1080), Vector2.new(844, 390) } do
			local distance = LaneCamera.solveDistance(viewport, Camera.pitchDegrees)
			expect(distance).toBeGreaterThan(0)
			expect(laneWidthFraction(viewport, distance) <= Camera.laneScreenWidthFraction + 1e-9).toBe(true)
		end
	end)

	it("pulls back further on narrower screens", function()
		local wide = LaneCamera.solveDistance(Vector2.new(2400, 1080), Camera.pitchDegrees)
		local narrow = LaneCamera.solveDistance(Vector2.new(1024, 768), Camera.pitchDegrees)
		expect(narrow >= wide).toBe(true)
	end)

	it("sits behind the rail and above the floor, looking up the lane", function()
		local origin = World.firstLaneOrigin
		local distance = LaneCamera.solveDistance(Vector2.new(1920, 1080), Camera.pitchDegrees)
		local cframe = LaneCamera.cframeFor(origin, Camera.pitchDegrees, distance)
		local _, laneY = LaneGeometry.toLane(origin, cframe.Position)
		expect(laneY < 0).toBe(true)
		expect(cframe.Position.Y > origin.Position.Y).toBe(true)
		expect(cframe.LookVector.Y < 0).toBe(true)
	end)
end)
