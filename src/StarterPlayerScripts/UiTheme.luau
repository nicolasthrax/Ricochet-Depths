-- Small builders that keep every view visually consistent and phone-friendly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))

local UiTheme = {}

function UiTheme.corner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or UiConfig.CornerRadius)
	corner.Parent = instance
	return corner
end

function UiTheme.padding(instance, amount)
	local padding = Instance.new("UIPadding")
	local offset = UDim.new(0, amount or 10)
	padding.PaddingTop = offset
	padding.PaddingBottom = offset
	padding.PaddingLeft = offset
	padding.PaddingRight = offset
	padding.Parent = instance
	return padding
end

function UiTheme.panel(name, parent)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = UiConfig.Colors.Panel
	frame.BackgroundTransparency = UiConfig.PanelTransparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UiTheme.corner(frame)
	return frame
end

function UiTheme.label(name, parent, text, size, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = UiConfig.Font
	label.TextSize = size or UiConfig.Text.Hud
	label.TextColor3 = color or UiConfig.Colors.Text
	label.Text = text or ""
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

function UiTheme.button(name, parent, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = UiConfig.Colors.PanelRaised
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = UiConfig.FontBold
	button.TextSize = UiConfig.Text.CardTitle
	button.TextColor3 = UiConfig.Colors.Text
	button.Text = text or ""
	button.Parent = parent
	UiTheme.corner(button)

	-- Never smaller than a comfortable finger target, whatever the layout asks for.
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(UiConfig.MinTouchTarget, UiConfig.MinTouchTarget)
	constraint.Parent = button

	return button
end

function UiTheme.bar(name, parent, color)
	local track = Instance.new("Frame")
	track.Name = name
	track.BackgroundColor3 = UiConfig.Colors.Panel
	track.BorderSizePixel = 0
	track.Parent = parent
	UiTheme.corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color or UiConfig.Colors.Accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	UiTheme.corner(fill, 4)

	return track, fill
end

function UiTheme.screenGui(name, parent, displayOrder)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = displayOrder or 0
	gui.Parent = parent
	return gui
end

return UiTheme
