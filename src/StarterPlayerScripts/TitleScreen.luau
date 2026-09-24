-- The title card a player sees on joining: the logo, a tagline and a Play button over the
-- lobby. Dismissing it fades it away; it never comes back in that session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local TitleScreen = {}
TitleScreen.__index = TitleScreen

function TitleScreen.new(playerGui, onPlay)
	local self = setmetatable({}, TitleScreen)
	self.gui = UiTheme.screenGui("RicochetTitle", playerGui, 100)
	self.gui.IgnoreGuiInset = true
	self.gui.Enabled = true

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 10, 22)
	backdrop.BackgroundTransparency = 0.15
	backdrop.BorderSizePixel = 0
	backdrop.Active = true -- swallow clicks meant for the world behind
	backdrop.Parent = self.gui
	UiTheme.gradient(backdrop, Color3.fromRGB(120, 110, 200), Color3.fromRGB(255, 255, 255))
	self.backdrop = backdrop

	local logo = UiTheme.heading("Logo", backdrop, "RICOCHET DEPTHS", 72, UiConfig.Colors.Gold)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.34)
	logo.Size = UDim2.new(0.9, 0, 0, 90)
	logo.TextScaled = true
	logo.TextXAlignment = Enum.TextXAlignment.Center
	local logoSize = Instance.new("UITextSizeConstraint")
	logoSize.MaxTextSize = 84
	logoSize.Parent = logo
	self.logo = logo

	local tagline = UiTheme.label("Tagline", backdrop, "Bank your shots. Chain your kills. Escape the depths.",
		UiConfig.Text.CardTitle, UiConfig.Colors.Accent)
	tagline.AnchorPoint = Vector2.new(0.5, 0.5)
	tagline.Position = UDim2.new(0.5, 0, 0.34, 64)
	tagline.Size = UDim2.new(0.9, 0, 0, 30)
	tagline.TextXAlignment = Enum.TextXAlignment.Center
	tagline.TextWrapped = true

	self.playButton = UiTheme.button("Play", backdrop, "PLAY", "Primary")
	self.playButton.AnchorPoint = Vector2.new(0.5, 0.5)
	self.playButton.Position = UDim2.fromScale(0.5, 0.62)
	self.playButton.Size = UDim2.fromOffset(260, 66)
	self.playButton.TextSize = 32
	self.playButton.Font = UiConfig.FontDisplay
	self.playButton.Activated:Connect(function()
		self:Dismiss()
		if onPlay then
			onPlay()
		end
	end)

	local build = UiTheme.label("Build", backdrop, "Build " .. RunConfig.Version, UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	build.AnchorPoint = Vector2.new(1, 1)
	build.Position = UDim2.new(1, -16, 1, -12)
	build.Size = UDim2.fromOffset(200, 18)
	build.TextXAlignment = Enum.TextXAlignment.Right

	return self
end

function TitleScreen:IsShowing()
	return self.gui.Enabled and not self._dismissed
end

function TitleScreen:Dismiss()
	if self._dismissed then
		return
	end
	self._dismissed = true
	UiTheme.tween(self.backdrop, 0.45, { BackgroundTransparency = 1 })
	for _, child in self.backdrop:GetChildren() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			UiTheme.tween(child, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
		end
	end
	task.delay(0.5, function()
		self.gui.Enabled = false
	end)
end

return TitleScreen
