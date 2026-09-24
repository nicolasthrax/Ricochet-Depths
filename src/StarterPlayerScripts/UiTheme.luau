-- Small builders that keep every view visually consistent and phone-friendly: layered panels
-- with a soft gradient and a lit edge, buttons that press in and glow on hover, and modal
-- windows that pop open. Animations degrade to instant changes where tweening is unavailable.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))

local UiTheme = {}

-- Set by ClientMain to play the UI click sound; every themed button calls it when activated.
UiTheme.onClick = nil

-- Tweens `props` onto `instance` over `seconds`, or applies them at once when tweens are not
-- available. Returns the tween, if there was one.
function UiTheme.tween(instance, seconds, props, style, direction)
	if TweenService.Create and TweenInfo then
		local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
		local tween = TweenService:Create(instance, info, props)
		tween:Play()
		return tween
	end
	for key, value in props do
		instance[key] = value
	end
	return nil
end

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

function UiTheme.stroke(instance, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or UiConfig.Colors.Edge
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = transparency or 0.25
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

-- A top-to-bottom shade over the background colour (the gradient multiplies it).
function UiTheme.gradient(instance, top, bottom)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top or Color3.new(1, 1, 1), bottom or UiConfig.Colors.Shade)
	gradient.Rotation = 90
	gradient.Parent = instance
	return gradient
end

function UiTheme.panel(name, parent)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = UiConfig.Colors.Panel
	frame.BackgroundTransparency = UiConfig.PanelTransparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UiTheme.corner(frame)
	UiTheme.gradient(frame)
	UiTheme.stroke(frame)
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

-- A heading: the bold display font with a dark outline so it reads over anything.
function UiTheme.heading(name, parent, text, size, color)
	local label = UiTheme.label(name, parent, text, size or UiConfig.Text.Title, color or UiConfig.Colors.Gold)
	label.Font = UiConfig.FontDisplay
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	return label
end

-- style: nil for the standard button, "Primary" for the gold call to action, "Danger" for red.
function UiTheme.button(name, parent, text, style)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = style == "Primary" and UiConfig.Colors.PrimaryButton
		or style == "Danger" and UiConfig.Colors.Danger
		or UiConfig.Colors.PanelRaised
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = UiConfig.FontBold
	button.TextSize = UiConfig.Text.CardTitle
	button.TextColor3 = style == "Primary" and UiConfig.Colors.PrimaryText or UiConfig.Colors.Text
	button.Text = text or ""
	button.Parent = parent
	UiTheme.corner(button)
	UiTheme.gradient(button, Color3.new(1, 1, 1), UiConfig.Colors.ButtonShade)
	local edge = UiTheme.stroke(button, style == "Primary" and UiConfig.Colors.Gold or UiConfig.Colors.Accent, 1.5, 0.55)

	-- Never smaller than a comfortable finger target, whatever the layout asks for.
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(UiConfig.MinTouchTarget, UiConfig.MinTouchTarget)
	constraint.Parent = button

	-- Press in, spring back, light the edge on hover.
	local scale = Instance.new("UIScale")
	scale.Parent = button
	if button.MouseButton1Down then
		button.MouseButton1Down:Connect(function()
			UiTheme.tween(scale, 0.06, { Scale = 0.94 })
		end)
	end
	if button.MouseButton1Up then
		button.MouseButton1Up:Connect(function()
			UiTheme.tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	if button.MouseEnter then
		button.MouseEnter:Connect(function()
			UiTheme.tween(edge, 0.1, { Transparency = 0.05 })
		end)
	end
	if button.MouseLeave then
		button.MouseLeave:Connect(function()
			UiTheme.tween(edge, 0.15, { Transparency = 0.55 })
			UiTheme.tween(scale, 0.12, { Scale = 1 })
		end)
	end
	button.Activated:Connect(function()
		if UiTheme.onClick then
			UiTheme.onClick()
		end
	end)

	return button
end

function UiTheme.bar(name, parent, color)
	local track = Instance.new("Frame")
	track.Name = name
	track.BackgroundColor3 = UiConfig.Colors.Track
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
	UiTheme.gradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))

	return track, fill
end

-- A small red dot for "something to claim here".
function UiTheme.dot(name, parent)
	local dot = Instance.new("Frame")
	dot.Name = name
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -4, 0, 4)
	dot.Size = UDim2.fromOffset(14, 14)
	dot.BackgroundColor3 = UiConfig.Colors.Danger
	dot.BorderSizePixel = 0
	dot.ZIndex = 5
	dot.Visible = false
	dot.Parent = parent
	UiTheme.corner(dot, 7)
	UiTheme.stroke(dot, Color3.new(1, 1, 1), 1.5, 0)
	return dot
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

-- A centred window over a dimmed backdrop, with a title and a close button. Returns a table:
-- gui, panel, content (lay things out in here), title, and Open / Close / IsOpen / OnClose.
function UiTheme.modal(name, parent, titleText, maxSize, displayOrder)
	local gui = UiTheme.screenGui(name, parent, displayOrder or 35)
	gui.Enabled = false

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	local panel = UiTheme.panel("Panel", gui)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.92, 0.86)
	panel.BackgroundTransparency = 0
	panel.ZIndex = 2 -- over the backdrop
	UiTheme.padding(panel, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = maxSize or Vector2.new(560, 520)
	limit.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = UiTheme.heading("Title", panel, titleText, UiConfig.Text.Title)
	title.Size = UDim2.new(1, -60, 0, 40)

	local close = UiTheme.button("Close", panel, "X", "Danger")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(UiConfig.MinTouchTarget, UiConfig.MinTouchTarget)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.new(0, 0, 0, 56)
	content.Size = UDim2.new(1, 0, 1, -56)
	content.Parent = panel

	local modal = { gui = gui, panel = panel, content = content, title = title, closeButton = close }
	function modal.Open()
		gui.Enabled = true
		scale.Scale = 0.88
		UiTheme.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	function modal.Close()
		gui.Enabled = false
		if modal.onClose then
			modal.onClose()
		end
	end
	function modal.IsOpen()
		return gui.Enabled
	end
	close.Activated:Connect(modal.Close)
	backdrop.Activated:Connect(modal.Close)
	return modal
end

-- "5h 12m", "12m 30s" or "45s".
function UiTheme.duration(seconds)
	seconds = math.max(math.floor(tonumber(seconds) or 0), 0)
	local hours, minutes, secs = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

return UiTheme
