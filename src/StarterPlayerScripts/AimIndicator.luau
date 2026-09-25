-- Aim feedback: a neon line in the world from the character along the shot, ground cues under
-- it, and a power bar. Nothing is drawn at the pointer: the world line is the aim.
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

-- groundY is the floor height the depth cues are drawn on.
function AimIndicator.new(playerGui, worldParent, groundY)
	local self = setmetatable({}, AimIndicator)
	self._groundY = groundY or 0

	-- Created on the client, so these parts exist only for this player.
	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "AimWorldVisual"
	worldFolder.Parent = worldParent or workspace

	local thickness = AimConfig.WorldLineThickness
	local tip = AimConfig.WorldTipSize
	local reticle = AimConfig.ReticleSize
	local core = AimConfig.ReticleCoreSize
	local flat = AimConfig.GroundCueThickness
	self._worldLine = makeWorldPart("AimLine", Enum.PartType.Block, Vector3.new(thickness, thickness, 1), worldFolder)
	self._worldTip = makeWorldPart("AimTip", Enum.PartType.Ball, Vector3.new(tip, tip, tip), worldFolder)
	self._groundLine = makeWorldPart("AimGroundLine", Enum.PartType.Block, Vector3.new(1, flat, 1), worldFolder)
	self._dropLine = makeWorldPart("AimDropLine", Enum.PartType.Block, Vector3.new(1, 1, 1), worldFolder)
	self._reticle = makeWorldPart("AimReticle", Enum.PartType.Block, Vector3.new(reticle, flat * 1.2, reticle), worldFolder)
	self._reticleCore = makeWorldPart("AimReticleCore", Enum.PartType.Block, Vector3.new(core, flat * 1.5, core), worldFolder)

	-- Transparency each part takes while shown; hidden is always 1.
	self._worldParts = {
		[self._worldLine] = AimConfig.WorldLineTransparency,
		[self._worldTip] = AimConfig.WorldLineTransparency,
		[self._groundLine] = AimConfig.GroundLineTransparency,
		[self._dropLine] = AimConfig.DropLineTransparency,
		[self._reticle] = AimConfig.ReticleTransparency,
		[self._reticleCore] = AimConfig.WorldLineTransparency,
	}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AimUi"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

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
	self._worldTip.CFrame = CFrame.new(tipPosition)

	-- Ground cues: the same segment projected onto the floor, joined to the tip by a drop line.
	local groundY = self._groundY + AimConfig.GroundCueHeight
	local groundStart = Vector3.new(muzzle.X, groundY, muzzle.Z)
	local groundTip = Vector3.new(tipPosition.X, groundY, tipPosition.Z)
	self._groundLine.Size = Vector3.new(AimConfig.GroundLineWidth, AimConfig.GroundCueThickness, length)
	self._groundLine.CFrame = CFrame.lookAt((groundStart + groundTip) / 2, groundTip)

	local dropHeight = math.max(tipPosition.Y - groundY, 0.01)
	self._dropLine.Size = Vector3.new(AimConfig.DropLineWidth, dropHeight, AimConfig.DropLineWidth)
	self._dropLine.CFrame = CFrame.new(groundTip + Vector3.new(0, dropHeight / 2, 0))

	-- The reticle is turned 45 degrees off the shot so it reads as a diamond marker.
	local diagonal = worldDirection + Vector3.new(worldDirection.Z, 0, -worldDirection.X)
	self._reticle.CFrame = CFrame.lookAt(groundTip, groundTip + diagonal)
	self._reticleCore.CFrame = CFrame.lookAt(groundTip, groundTip + diagonal)

	for part, transparency in self._worldParts do
		part.Color = color
		part.Transparency = transparency
	end
end

function AimIndicator:_hideWorld()
	for part in self._worldParts do
		part.Transparency = 1
	end
end

-- power is 0..1. ready is false while the shot would be refused for cooldown, which tints the
-- line instead of silently doing nothing. muzzle (on the projectile plane) and worldDirection
-- place the world line; either may be nil (no character yet).
function AimIndicator:Show(power, ready, muzzle, worldDirection)
	self._fill.Size = UDim2.fromScale(power, 1)
	self._fill.BackgroundColor3 = ready == false and AimConfig.CooldownColor or AimConfig.PowerBarFillColor
	self._bar.Visible = true

	self:_showWorld(muzzle, worldDirection, power, ready == false and AimConfig.CooldownColor or AimConfig.LineColor)
end

-- The first-descent hint: before a new player's first shot, a line pulses out ahead of them
-- (they land facing the targets), showing where a shot would go. alpha (0..1) is the pulse,
-- from AimIndicator.PulseAlpha. Hidden again by Hide or by the first real aim.
function AimIndicator:Pulse(muzzle, worldDirection, alpha)
	if not muzzle or not worldDirection then
		return
	end
	self:_showWorld(muzzle, worldDirection, 0.6, AimConfig.LineColor)
	local fade = 0.25 + 0.6 * (1 - math.clamp(alpha or 1, 0, 1))
	for part, transparency in self._worldParts do
		part.Transparency = math.clamp(transparency + fade, 0, 1)
	end
end

-- A 0..1 pulse over time: bright, fade, bright, about once a second.
function AimIndicator.PulseAlpha(now)
	return (math.sin(now * math.pi * 2) + 1) / 2
end

function AimIndicator:Hide()
	self:_hideWorld()
	self._bar.Visible = false
end

return AimIndicator
