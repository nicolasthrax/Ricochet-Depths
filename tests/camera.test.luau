-- Tactical camera maths: framing, smoothing and zoom limits.
local CameraConfig = __require("CameraConfig")
local CameraMath = __require("CameraMath")

describe("CameraMath.ComputeFrame", function()
	it("sits above and behind the focus at the configured pitch and distance", function()
		local focus = Vector3.new(10, 3, -4)
		local frame = CameraMath.ComputeFrame(focus, 60, 0, 50)
		local offset = frame.Position - focus
		expect(offset.Magnitude).toBeCloseTo(50)
		expect(offset.Y).toBeCloseTo(50 * math.sin(math.rad(60)))
		expect(offset.X).toBeCloseTo(0)
		expect(offset.Z).toBeGreaterThan(0)
	end)

	it("looks at the focus", function()
		local focus = Vector3.new(0, 3, 0)
		local frame = CameraMath.ComputeFrame(focus, CameraConfig.Pitch, CameraConfig.Yaw, CameraConfig.DefaultDistance)
		local toFocus = (focus - frame.Position).Unit
		expect(frame.LookVector:Dot(toFocus)).toBeCloseTo(1)
		-- High angle: the view points well below the horizon so walls are seen from above.
		expect(frame.LookVector.Y).toBeLessThan(-0.7)
	end)
end)

describe("CameraMath.SmoothAlpha", function()
	it("is 0 for no time, approaches 1, and never overshoots", function()
		expect(CameraMath.SmoothAlpha(10, 0)).toBe(0)
		expect(CameraMath.SmoothAlpha(10, -1)).toBe(0)
		expect(CameraMath.SmoothAlpha(10, 1 / 60)).toBeGreaterThan(0)
		expect(CameraMath.SmoothAlpha(10, 10)).toBeLessThan(1.0000001)
		expect(CameraMath.SmoothAlpha(10, 10)).toBeGreaterThan(0.999)
	end)
end)

describe("CameraMath.ClampZoom", function()
	it("keeps the distance inside the configured range", function()
		expect(CameraMath.ClampZoom(0, CameraConfig)).toBe(CameraConfig.MinDistance)
		expect(CameraMath.ClampZoom(1000, CameraConfig)).toBe(CameraConfig.MaxDistance)
		expect(CameraMath.ClampZoom(CameraConfig.DefaultDistance, CameraConfig)).toBe(CameraConfig.DefaultDistance)
	end)
end)
