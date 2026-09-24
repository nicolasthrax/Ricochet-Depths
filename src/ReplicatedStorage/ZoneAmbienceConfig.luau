-- Lighting for the lobby and each zone. ZoneAmbience (client) tweens between these as the run
-- moves through the zones. The Lobby entry matches the Lighting set in default.project.json.
local ZoneAmbienceConfig = {}

ZoneAmbienceConfig.TweenSeconds = 2

-- A night sky over the depths: the lobby at violet dusk, the Ruins at twilight, the Foundry in
-- an ember sunset, the Abyss at midnight. Ambient light stays high enough to read every wall.
-- Every ClockTime sits in the evening (17-24): a tween runs straight between two values, so one
-- just past midnight (0.5) would sweep back through noon and flash daylight on the way.
ZoneAmbienceConfig.Zones = {
	Lobby = {
		Ambient = Color3.new(0.2, 0.19, 0.27),
		OutdoorAmbient = Color3.new(0.34, 0.3, 0.46),
		Brightness = 1.6,
		ClockTime = 20.2,
		AtmosphereColor = Color3.new(0.46, 0.38, 0.66),
		AtmosphereDensity = 0.32,
		Tint = Color3.new(0.98, 0.96, 1),
	},
	Ruins = {
		Ambient = Color3.new(0.2, 0.21, 0.28),
		OutdoorAmbient = Color3.new(0.4, 0.4, 0.52),
		Brightness = 2,
		ClockTime = 18.6,
		AtmosphereColor = Color3.new(0.55, 0.56, 0.74),
		AtmosphereDensity = 0.3,
		Tint = Color3.new(0.96, 0.98, 1),
	},
	Foundry = {
		Ambient = Color3.new(0.26, 0.17, 0.12),
		OutdoorAmbient = Color3.new(0.5, 0.34, 0.24),
		Brightness = 1.8,
		ClockTime = 18.1,
		AtmosphereColor = Color3.new(0.8, 0.5, 0.32),
		AtmosphereDensity = 0.4,
		Tint = Color3.new(1, 0.93, 0.84),
	},
	Abyss = {
		Ambient = Color3.new(0.2, 0.15, 0.3),
		OutdoorAmbient = Color3.new(0.32, 0.24, 0.48),
		Brightness = 1.2,
		ClockTime = 23.6,
		AtmosphereColor = Color3.new(0.42, 0.3, 0.66),
		AtmosphereDensity = 0.45,
		Tint = Color3.new(0.92, 0.88, 1),
	},
}

function ZoneAmbienceConfig.For(zoneId)
	return ZoneAmbienceConfig.Zones[zoneId] or ZoneAmbienceConfig.Zones.Lobby
end

return ZoneAmbienceConfig
