-- Lighting for the lobby and each zone. ZoneAmbience (client) tweens between these as the run
-- moves through the zones. The Lobby entry matches the Lighting set in default.project.json.
local ZoneAmbienceConfig = {}

ZoneAmbienceConfig.TweenSeconds = 2

ZoneAmbienceConfig.Zones = {
	Lobby = {
		Ambient = Color3.new(0.13, 0.14, 0.18),
		OutdoorAmbient = Color3.new(0.36, 0.38, 0.46),
		Brightness = 2.4,
		ClockTime = 14.2,
		AtmosphereColor = Color3.new(0.62, 0.66, 0.78),
		AtmosphereDensity = 0.28,
		Tint = Color3.new(1, 1, 1),
	},
	-- Cool daylight through a broken roof.
	Ruins = {
		Ambient = Color3.new(0.14, 0.15, 0.2),
		OutdoorAmbient = Color3.new(0.38, 0.4, 0.5),
		Brightness = 2.3,
		ClockTime = 14.5,
		AtmosphereColor = Color3.new(0.62, 0.68, 0.8),
		AtmosphereDensity = 0.3,
		Tint = Color3.new(0.96, 0.98, 1),
	},
	-- Low, warm furnace light and a smoky haze.
	Foundry = {
		Ambient = Color3.new(0.2, 0.13, 0.08),
		OutdoorAmbient = Color3.new(0.46, 0.32, 0.22),
		Brightness = 1.9,
		ClockTime = 17.6,
		AtmosphereColor = Color3.new(0.78, 0.52, 0.34),
		AtmosphereDensity = 0.4,
		Tint = Color3.new(1, 0.93, 0.84),
	},
	-- Night, violet and deep.
	Abyss = {
		Ambient = Color3.new(0.12, 0.08, 0.2),
		OutdoorAmbient = Color3.new(0.28, 0.2, 0.42),
		Brightness = 1.4,
		ClockTime = 0.5,
		AtmosphereColor = Color3.new(0.42, 0.3, 0.66),
		AtmosphereDensity = 0.45,
		Tint = Color3.new(0.92, 0.88, 1),
	},
}

function ZoneAmbienceConfig.For(zoneId)
	return ZoneAmbienceConfig.Zones[zoneId] or ZoneAmbienceConfig.Zones.Lobby
end

return ZoneAmbienceConfig
