-- Tweens the lighting to the current zone's look (ZoneAmbienceConfig) as a run moves from the
-- Ruins through the Foundry into the Abyss, and back to the lobby look afterwards. ClientMain
-- publishes the zone as the "Zone" attribute on the local player.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ZoneAmbienceConfig = require(ReplicatedStorage:WaitForChild("ZoneAmbienceConfig"))

local player = Players.LocalPlayer
local info = TweenInfo.new(ZoneAmbienceConfig.TweenSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local current = nil

local function apply(zoneId)
	local ambience = ZoneAmbienceConfig.For(zoneId)
	if ambience == current then
		return
	end
	current = ambience
	TweenService:Create(Lighting, info, {
		Ambient = ambience.Ambient,
		OutdoorAmbient = ambience.OutdoorAmbient,
		Brightness = ambience.Brightness,
		ClockTime = ambience.ClockTime,
	}):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, { Color = ambience.AtmosphereColor, Density = ambience.AtmosphereDensity }):Play()
	end
	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if grade then
		TweenService:Create(grade, info, { TintColor = ambience.Tint }):Play()
	end
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	apply(player:GetAttribute("Zone"))
end)
apply(player:GetAttribute("Zone") or "Lobby")
