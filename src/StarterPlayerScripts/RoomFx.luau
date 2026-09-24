-- Screen-level punctuation for the big moments: a white flash and a "ROOM CLEARED" stamp when a
-- room falls, and a quick field-of-view kick for callouts. Cosmetic, client-only, and quiet for
-- players who turned on Reduced Flash or turned effects down.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local RoomFx = {}
RoomFx.__index = RoomFx

RoomFx.FlashSeconds = 0.35
RoomFx.StampSeconds = 1.4
RoomFx.PunchDegrees = 6
RoomFx.PunchSeconds = 0.25

local function comfort()
	local player = Players.LocalPlayer
	local intensity = player and player:GetAttribute("EffectIntensity")
	local reduced = player and player:GetAttribute("ReducedFlash") == true
	return type(intensity) == "number" and math.clamp(intensity, 0, 1) or 1, reduced
end

function RoomFx.new(playerGui)
	local self = setmetatable({}, RoomFx)
	self.gui = UiTheme.screenGui("RicochetRoomFx", playerGui, 16)
	self.gui.IgnoreGuiInset = true

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = self.gui
	self.flash = flash

	local stamp = UiTheme.heading("Stamp", self.gui, "ROOM CLEARED", 54, UiConfig.Colors.Gold)
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.fromScale(0.5, 0.4)
	stamp.Size = UDim2.fromOffset(700, 70)
	stamp.TextXAlignment = Enum.TextXAlignment.Center
	stamp.Visible = false
	self.stamp = stamp
	self._stampScale = Instance.new("UIScale")
	self._stampScale.Parent = stamp
	return self
end

function RoomFx:RoomCleared()
	local intensity, reduced = comfort()
	local now = os.clock()
	if not reduced and intensity > 0 then
		self._flashAt = now
		self._flashStrength = 0.55 * intensity
	end
	self._stampAt = now
	self.stamp.Visible = true
	self.stamp.TextTransparency = 0
	self._stampScale.Scale = 1.8
	UiTheme.tween(self._stampScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	self:Punch(1)
end

-- A quick field-of-view kick, scaled by `strength` (0..1) and the player's effect setting.
function RoomFx:Punch(strength)
	local intensity, reduced = comfort()
	local camera = workspace.CurrentCamera
	if reduced or intensity <= 0 or not camera or self._punchAt then
		return
	end
	self._punchAt = os.clock()
	self._punchBase = camera.FieldOfView
	self._punchDegrees = RoomFx.PunchDegrees * (strength or 1) * intensity
end

function RoomFx:Step(now)
	if self._flashAt then
		local alpha = (now - self._flashAt) / RoomFx.FlashSeconds
		if alpha >= 1 then
			self._flashAt = nil
			self.flash.BackgroundTransparency = 1
		else
			self.flash.BackgroundTransparency = 1 - self._flashStrength * (1 - alpha)
		end
	end
	if self._stampAt then
		local alpha = (now - self._stampAt) / RoomFx.StampSeconds
		if alpha >= 1 then
			self._stampAt = nil
			self.stamp.Visible = false
		elseif alpha > 0.6 then
			self.stamp.TextTransparency = (alpha - 0.6) / 0.4
		end
	end
	if self._punchAt then
		local camera = workspace.CurrentCamera
		local alpha = (now - self._punchAt) / RoomFx.PunchSeconds
		if not camera or alpha >= 1 then
			if camera then
				camera.FieldOfView = self._punchBase
			end
			self._punchAt = nil
		else
			-- Out fast, back smoothly.
			camera.FieldOfView = self._punchBase + self._punchDegrees * math.sin(alpha * math.pi) * (1 - alpha * 0.5)
		end
	end
end

return RoomFx
