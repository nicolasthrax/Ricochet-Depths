-- Shared look and layout values for every client view.
local UiConfig = {}

UiConfig.Font = Enum.Font.GothamMedium
UiConfig.FontBold = Enum.Font.GothamBold
-- Titles, callouts and the logo.
UiConfig.FontDisplay = Enum.Font.GothamBlack

UiConfig.Colors = {
	Panel = Color3.fromRGB(20, 23, 34),
	PanelRaised = Color3.fromRGB(36, 42, 60),
	Track = Color3.fromRGB(12, 14, 20),
	-- Multiplied over panels and buttons by their gradients, for a lit-from-above look.
	Shade = Color3.fromRGB(175, 180, 200),
	ButtonShade = Color3.fromRGB(160, 165, 185),
	Edge = Color3.fromRGB(78, 92, 130),
	Text = Color3.fromRGB(238, 242, 250),
	TextMuted = Color3.fromRGB(158, 167, 186),
	Accent = Color3.fromRGB(120, 235, 255),
	Gold = Color3.fromRGB(255, 214, 120),
	PrimaryButton = Color3.fromRGB(255, 196, 72),
	PrimaryText = Color3.fromRGB(40, 26, 6),
	Health = Color3.fromRGB(122, 224, 146),
	HealthLow = Color3.fromRGB(240, 118, 118),
	Warning = Color3.fromRGB(255, 206, 110),
	Danger = Color3.fromRGB(226, 84, 84),
	Purple = Color3.fromRGB(200, 150, 255),
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
