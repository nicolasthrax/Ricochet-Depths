-- Aim feedback: a neon line in the world from the character along the shot, plus a
-- screen-space drag line from the pointer and a power bar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AimConfig = require(ReplicatedStorage:WaitForChild("AimConfig"))

local AimIndicator = {}
AimIndicator.__index = AimIndicator

local function makeWorldPart(name, shape, size, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = AimConfig.LineColor
	part.Transparency = 1
	part.Parent = parent
	return part
end

function AimIndicator.new(playerGui, worldParent)
	local self = setmetatable({}, AimIndicator)

	-- Created on the client, so these parts exist only for this player.
	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "AimWorldVisual"
	worldFolder.Parent = worldParent or workspace

	local thickness = AimConfig.WorldLineThickness
	self._worldLine = makeWorldPart("AimLine", Enum.PartType.Block, Vector3.new(thickness, thickness, 1), worldFolder)
	local tip = AimConfig.WorldTipSize
	self._worldTip = makeWorldPart("AimTip", Enum.PartType.Ball, Vector3.new(tip, tip, tip), worldFolder)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AimUi"
	screenGui.ResetOnSpawn = false
	-- InputObject.Position is measured below the top-bar inset, so the GUI must be too, or
	-- the drag line starts offset from the pointer.
	screenGui.IgnoreGuiInset = false
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

-- Transparency, not Parent or Visible, toggles the world parts so they never leave the tree.
function AimIndicator:_showWorld(muzzle, worldDirection, power, color)
	if not muzzle or not worldDirection then
		self:_hideWorld()
		return
	end
	local length = AimConfig.WorldLineMinLength
		+ (AimConfig.WorldLineMaxLength - AimConfig.WorldLineMinLength) * power
	local tipPosition = muzzle + worldDirection * length
	local thickness = AimConfig.WorldLineThickness

	self._worldLine.Size = Vector3.new(thickness, thickness, length)
	-- lookAt points -Z along the shot, so the part's long Z axis spans muzzle to tip.
	self._worldLine.CFrame = CFrame.lookAt(muzzle + worldDirection * (length / 2), tipPosition)
	self._worldLine.Color = color
	self._worldLine.Transparency = AimConfig.WorldLineTransparency

	self._worldTip.CFrame = CFrame.new(tipPosition)
	self._worldTip.Color = color
	self._worldTip.Transparency = AimConfig.WorldLineTransparency
end

function AimIndicator:_hideWorld()
	self._worldLine.Transparency = 1
	self._worldTip.Transparency = 1
end

-- aimDirection is a unit Vector2 in screen space; power is 0..1. ready is false while the
-- shot would be refused for cooldown, which tints the line instead of silently doing nothing.
-- muzzle and worldDirection place the world line; either may be nil (no character yet).
function AimIndicator:Show(originPixels, aimDirection, power, ready, muzzle, worldDirection)
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

	self:_showWorld(muzzle, worldDirection, power, ready == false and AimConfig.CooldownColor or AimConfig.LineColor)
end

function AimIndicator:Hide()
	self:_hideWorld()
	self._line.Visible = false
	self._bar.Visible = false
end

return AimIndicator
