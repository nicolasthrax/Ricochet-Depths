-- Drag-to-aim: gesture tracking and the world-space aim line.
local AimConfig = __require("AimConfig")
local AimIndicator = __require("AimIndicator")
local AimMath = __require("AimMath")

local function fakeInput(userInputType, x, y)
	return { UserInputType = userInputType, Position = Vector3.new(x or 0, y or 0, 0) }
end

describe("AimMath.IsSameGesture", function()
	it("tracks a mouse drag through MouseMovement objects (regression: no aim line on desktop)", function()
		local press = fakeInput(Enum.UserInputType.MouseButton1)
		local move = fakeInput(Enum.UserInputType.MouseMovement, 40, 0)
		expect(AimMath.IsSameGesture(press, move)).toBe(true)
		expect(AimMath.IsSameGesture(press, press)).toBe(true)
	end)

	it("ignores a second finger and unrelated input", function()
		local finger = fakeInput(Enum.UserInputType.Touch)
		local otherFinger = fakeInput(Enum.UserInputType.Touch)
		expect(AimMath.IsSameGesture(finger, finger)).toBe(true)
		expect(AimMath.IsSameGesture(finger, otherFinger)).toBe(false)
		expect(AimMath.IsSameGesture(finger, fakeInput(Enum.UserInputType.MouseMovement))).toBe(false)
		expect(AimMath.IsSameGesture(nil, finger)).toBe(false)
	end)
end)

describe("AimMath.ReadDrag", function()
	it("ignores drags inside the deadzone", function()
		local direction, power = AimMath.ReadDrag(Vector2.new(100, 100), Vector2.new(105, 100), AimConfig)
		expect(direction).toBeNil()
		expect(power).toBe(0)
	end)

	it("fires opposite the pull with clamped power", function()
		local origin = Vector2.new(100, 100)
		local direction, power = AimMath.ReadDrag(origin, Vector2.new(100, 100 + AimConfig.MaxDragPixels * 3), AimConfig)
		expect(direction.X).toBeCloseTo(0)
		expect(direction.Y).toBeCloseTo(-1)
		expect(power).toBe(1)
	end)
end)

describe("AimMath.ScreenToWorldDirection", function()
	it("maps screen-up to the camera's flattened forward", function()
		local camera = CFrame.lookAlong(Vector3.new(0, 20, 0), Vector3.new(0, -1, -1))
		local world = AimMath.ScreenToWorldDirection(camera, Vector2.new(0, -1))
		expect(world.X).toBeCloseTo(0)
		expect(world.Y).toBeCloseTo(0)
		expect(world.Z).toBeCloseTo(-1)
	end)
end)

describe("AimIndicator world line", function()
	local function newIndicator()
		local world = Instance.new("Folder")
		local indicator = AimIndicator.new(Instance.new("Folder"), world)
		local folder = world:FindFirstChild("AimWorldVisual")
		return indicator, folder:FindFirstChild("AimLine"), folder:FindFirstChild("AimTip")
	end

	it("starts parented and hidden", function()
		local _, line, tip = newIndicator()
		expect(line).toBeTruthy()
		expect(tip).toBeTruthy()
		expect(line.Transparency).toBe(1)
		expect(line.CanQuery).toBe(false)
		expect(line.CanCollide).toBe(false)
	end)

	it("spans from the muzzle along the shot, scaled by power, and hides again", function()
		local indicator, line, tip = newIndicator()
		local muzzle = Vector3.new(10, 3, 5)
		indicator:Show(Vector2.new(0, 0), Vector2.new(0, -1), 1, true, muzzle, Vector3.new(1, 0, 0))

		expect(line.Transparency).toBe(AimConfig.WorldLineTransparency)
		expect(line.Size.Z).toBeCloseTo(AimConfig.WorldLineMaxLength)
		expect(line.Size.X).toBeGreaterThan(0)
		expect(line.CFrame.Position.X).toBeCloseTo(10 + AimConfig.WorldLineMaxLength / 2)
		expect(line.CFrame.Position.Y).toBeCloseTo(3)
		expect(tip.CFrame.Position.X).toBeCloseTo(10 + AimConfig.WorldLineMaxLength)

		indicator:Hide()
		expect(line.Transparency).toBe(1)
		expect(tip.Transparency).toBe(1)
	end)

	it("hides the world line when there is no character", function()
		local indicator, line = newIndicator()
		indicator:Show(Vector2.new(0, 0), Vector2.new(0, -1), 0.5, true, nil, Vector3.new(1, 0, 0))
		expect(line.Transparency).toBe(1)
	end)
end)

describe("AimIndicator ground cues", function()
	it("projects the line onto the floor and marks the landing point", function()
		local world = Instance.new("Folder")
		local indicator = AimIndicator.new(Instance.new("Folder"), world, 0)
		local folder = world:FindFirstChild("AimWorldVisual")
		local groundLine = folder:FindFirstChild("AimGroundLine")
		local drop = folder:FindFirstChild("AimDropLine")
		local reticle = folder:FindFirstChild("AimReticle")

		indicator:Show(Vector2.new(0, 0), Vector2.new(0, -1), 0, true, Vector3.new(0, 3, 0), Vector3.new(0, 0, -1))
		local tipZ = -AimConfig.WorldLineMinLength

		expect(reticle.Transparency).toBe(AimConfig.ReticleTransparency)
		expect(reticle.CFrame.Position.Z).toBeCloseTo(tipZ)
		expect(reticle.CFrame.Position.Y).toBeLessThan(0.1)
		expect(groundLine.CFrame.Position.Z).toBeCloseTo(tipZ / 2)
		expect(groundLine.Size.Z).toBeCloseTo(AimConfig.WorldLineMinLength)
		-- The drop line spans the gap between the floor and the aim tip on the projectile plane.
		expect(drop.Size.Y + AimConfig.GroundLift / 2).toBeCloseTo(3)
		expect(drop.CFrame.Position.Z).toBeCloseTo(tipZ)

		indicator:Hide()
		for _, part in folder:GetChildren() do
			expect(part.Transparency).toBe(1)
			expect(part.CanQuery).toBe(false)
		end
	end)
end)

describe("dual-zone touch input", function()
	local viewport = Vector2.new(1000, 500)

	it("leaves the left of the screen to the movement thumbstick", function()
		expect(AimMath.IsInAimZone(Enum.UserInputType.Touch, Vector2.new(100, 300), viewport, AimConfig)).toBe(false)
		local edge = viewport.X * AimConfig.TouchAimZoneStart
		expect(AimMath.IsInAimZone(Enum.UserInputType.Touch, Vector2.new(edge - 1, 300), viewport, AimConfig)).toBe(false)
	end)

	it("aims with touches that start on the right of the screen", function()
		local edge = viewport.X * AimConfig.TouchAimZoneStart
		expect(AimMath.IsInAimZone(Enum.UserInputType.Touch, Vector2.new(edge + 1, 300), viewport, AimConfig)).toBe(true)
		expect(AimMath.IsInAimZone(Enum.UserInputType.Touch, Vector2.new(990, 20), viewport, AimConfig)).toBe(true)
	end)

	it("never zones the mouse: a desktop player can aim from anywhere", function()
		expect(AimMath.IsInAimZone(Enum.UserInputType.MouseButton1, Vector2.new(5, 5), viewport, AimConfig)).toBe(true)
	end)

	it("aims anywhere when the viewport size is unknown rather than refusing every touch", function()
		expect(AimMath.IsInAimZone(Enum.UserInputType.Touch, Vector2.new(5, 5), nil, AimConfig)).toBe(true)
	end)
end)

describe("touch deadzone", function()
	it("is wider for a finger than for a mouse, so a tap never fires", function()
		expect(AimConfig.TouchDeadzonePixels).toBeGreaterThan(AimConfig.DeadzonePixels)
		expect(AimMath.DeadzoneFor(Enum.UserInputType.Touch, AimConfig)).toBe(AimConfig.TouchDeadzonePixels)
		expect(AimMath.DeadzoneFor(Enum.UserInputType.MouseButton1, AimConfig)).toBe(AimConfig.DeadzonePixels)
	end)

	it("ignores a short touch wobble that a mouse drag of the same length would fire", function()
		local origin = Vector2.new(600, 300)
		local wobble = Vector2.new(600 + (AimConfig.DeadzonePixels + AimConfig.TouchDeadzonePixels) / 2, 300)
		local mouseDirection = AimMath.ReadDrag(origin, wobble, AimConfig, AimConfig.DeadzonePixels)
		local touchDirection = AimMath.ReadDrag(origin, wobble, AimConfig, AimConfig.TouchDeadzonePixels)
		expect(mouseDirection).toBeTruthy()
		expect(touchDirection).toBeNil()
	end)
end)
