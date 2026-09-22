-- Shared look and layout values for every client view.
local UiConfig = {}

UiConfig.Font = Enum.Font.GothamMedium
UiConfig.FontBold = Enum.Font.GothamBold

UiConfig.Colors = {
	Panel = Color3.fromRGB(20, 23, 31),
	PanelRaised = Color3.fromRGB(31, 36, 48),
	Text = Color3.fromRGB(238, 242, 250),
	TextMuted = Color3.fromRGB(158, 167, 186),
	Accent = Color3.fromRGB(120, 235, 255),
	Health = Color3.fromRGB(122, 224, 146),
	HealthLow = Color3.fromRGB(240, 118, 118),
	Warning = Color3.fromRGB(255, 206, 110),
	Danger = Color3.fromRGB(240, 118, 118),
}

-- Generous sizes so the UI stays usable on a phone; nothing depends on hover.
UiConfig.MinTouchTarget = 48
UiConfig.CornerRadius = 8
UiConfig.PanelTransparency = 0.12

UiConfig.Text = {
	Hud = 18,
	Title = 28,
	CardTitle = 22,
	CardBody = 16,
	Small = 14,
}

-- Health below this fraction switches the bar to the low-health colour.
UiConfig.LowHealthFraction = 0.35

UiConfig.CardSize = Vector2.new(230, 300)
UiConfig.CardGap = 16

return UiConfig
