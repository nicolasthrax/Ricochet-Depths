-- Screen-space aim UI: a line from the drag origin plus a power bar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AimConfig = require(ReplicatedStorage:WaitForChild("AimConfig"))

local AimIndicator = {}
AimIndicator.__index = AimIndicator

function AimIndicator.new(playerGui)
	local self = setmetatable({}, AimIndicator)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AimUi"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	local line = Instance.new("Frame")
	line.Name = "AimLine"
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.BackgroundColor3 = AimConfig.LineColor
	line.BackgroundTransparency = AimConfig.LineTransparency
	line.BorderSizePixel = 0
	line.Visible = false
	line.Parent = screenGui

	local bar = Instance.new("Frame")
	bar.Name = "PowerBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, AimConfig.PowerBarOffsetY)
	bar.Size = UDim2.fromOffset(AimConfig.PowerBarSize.X, AimConfig.PowerBarSize.Y)
	bar.BackgroundColor3 = AimConfig.PowerBarBackColor
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = screenGui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = AimConfig.PowerBarFillColor
	fill.BorderSizePixel = 0
	fill.Parent = bar

	self._line = line
	self._bar = bar
	self._fill = fill

	return self
end

-- aimDirection is a unit Vector2 in screen space; power is 0..1. ready is false while the
-- shot would be refused for cooldown, which tints the line instead of silently doing nothing.
function AimIndicator:Show(originPixels, aimDirection, power, ready)
	local length = AimConfig.LineMinLength + (AimConfig.LineMaxLength - AimConfig.LineMinLength) * power

	self._line.Position = UDim2.fromOffset(originPixels.X, originPixels.Y)
	self._line.Size = UDim2.fromOffset(length, AimConfig.LineThickness)
	-- Frames rotate about their AnchorPoint, which is pinned to the drag origin.
	self._line.Rotation = math.deg(math.atan2(aimDirection.Y, aimDirection.X))
	self._line.Visible = true
	self._line.BackgroundColor3 = ready == false and AimConfig.CooldownColor or AimConfig.LineColor

	self._fill.Size = UDim2.fromScale(power, 1)
	self._fill.BackgroundColor3 = ready == false and AimConfig.CooldownColor or AimConfig.PowerBarFillColor
	self._bar.Visible = true
end

function AimIndicator:Hide()
	self._line.Visible = false
	self._bar.Visible = false
end

return AimIndicator
