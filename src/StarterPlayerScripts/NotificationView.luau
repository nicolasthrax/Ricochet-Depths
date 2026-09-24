-- Toasts: short messages that slide in under the top bar, stack, and fade on their own. The
-- server sends them through the Notify remote (rewards, quests, errors); views can post too.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local NotificationView = {}
NotificationView.__index = NotificationView

NotificationView.MaxShown = 4
NotificationView.Lifetime = 4

local KIND_COLORS = {
	Reward = UiConfig.Colors.Gold,
	Quest = UiConfig.Colors.Health,
	Info = UiConfig.Colors.Accent,
	Error = UiConfig.Colors.Danger,
}

function NotificationView.new(playerGui)
	local self = setmetatable({}, NotificationView)
	self.gui = UiTheme.screenGui("RicochetToasts", playerGui, 40)

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 84)
	stack.Size = UDim2.fromOffset(440, 300)
	stack.Parent = self.gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = stack
	self.stack = stack

	self._toasts = {}
	self._order = 0
	return self
end

-- Shows `text`; kind picks the accent colour. Returns the toast frame.
function NotificationView:Show(text, kind)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	self._order += 1
	local color = KIND_COLORS[kind] or KIND_COLORS.Info

	local toast = UiTheme.panel("Toast", self.stack)
	toast.LayoutOrder = self._order
	toast.Size = UDim2.new(1, 0, 0, 44)
	toast.BackgroundTransparency = 0.05
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Transparency = 0.1
	end
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = color
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 6, 1, 0)
	accent.Parent = toast
	UiTheme.corner(accent, 3)
	local label = UiTheme.label("Text", toast, text, UiConfig.Text.Small + 1, UiConfig.Colors.Text)
	label.Position = UDim2.new(0, 16, 0, 0)
	label.Size = UDim2.new(1, -24, 1, 0)
	label.TextWrapped = true
	label.Font = UiConfig.FontBold

	local scale = Instance.new("UIScale")
	scale.Scale = 0.8
	scale.Parent = toast
	UiTheme.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)

	table.insert(self._toasts, toast)
	while #self._toasts > NotificationView.MaxShown do
		table.remove(self._toasts, 1):Destroy()
	end
	task.delay(NotificationView.Lifetime, function()
		local index = table.find(self._toasts, toast)
		if index then
			table.remove(self._toasts, index)
			UiTheme.tween(toast, 0.3, { BackgroundTransparency = 1 })
			UiTheme.tween(label, 0.3, { TextTransparency = 1 })
			task.delay(0.3, function()
				toast:Destroy()
			end)
		end
	end)
	return toast
end

function NotificationView:Count()
	return #self._toasts
end

return NotificationView
