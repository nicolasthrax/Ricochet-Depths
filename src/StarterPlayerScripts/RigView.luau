-- The rig picker: every rig with what it changes, its unlock level, and a Select button.
-- Display only; the server checks the level and saves the choice, and the next ProfileSync is
-- what this shows as selected.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigConfig = require(ReplicatedStorage:WaitForChild("RigConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local RigView = {}
RigView.__index = RigView

local ROW_HEIGHT = 86

function RigView.new(playerGui, onSelect)
	local self = setmetatable({}, RigView)
	self._onSelect = onSelect
	self._level = 1
	self._selected = RigConfig.DefaultId
	self.modal = UiTheme.modal("RicochetRigs", playerGui, "RIGS", Vector2.new(560, 560))

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = self.modal.content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	self.rows = {}
	for index, rig in RigConfig.Rigs do
		local frame = UiTheme.panel(rig.Id, list)
		frame.LayoutOrder = index
		frame.BackgroundColor3 = UiConfig.Colors.PanelRaised
		frame.BackgroundTransparency = 0
		frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		UiTheme.padding(frame, 10)

		local title = UiTheme.label("Title", frame, rig.Title, UiConfig.Text.CardTitle, rig.Color)
		title.Font = UiConfig.FontDisplay
		title.Size = UDim2.new(1, -130, 0, 24)
		local tagline = UiTheme.label("Tagline", frame, rig.Tagline, UiConfig.Text.Small, UiConfig.Colors.Text)
		tagline.Position = UDim2.new(0, 0, 0, 24)
		tagline.Size = UDim2.new(1, -130, 0, 18)
		tagline.TextWrapped = true
		local summary = UiTheme.label("Summary", frame, RigConfig.Summary(rig), UiConfig.Text.Small, UiConfig.Colors.TextMuted)
		summary.Position = UDim2.new(0, 0, 0, 44)
		summary.Size = UDim2.new(1, -130, 0, 22)
		summary.TextWrapped = true

		local button = UiTheme.button("Select", frame, "", "Primary")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
		button.Size = UDim2.fromOffset(116, UiConfig.MinTouchTarget)
		button.TextSize = UiConfig.Text.Small
		button.Activated:Connect(function()
			if RigConfig.IsUnlocked(rig, self._level) and self._selected ~= rig.Id then
				self._onSelect(rig.Id)
			end
		end)
		self.rows[rig.Id] = { frame = frame, button = button }
	end
	self:_render()
	return self
end

function RigView:_render()
	for _, rig in RigConfig.Rigs do
		local row = self.rows[rig.Id]
		local unlocked = RigConfig.IsUnlocked(rig, self._level)
		local selected = self._selected == rig.Id
		row.button.Text = selected and "SELECTED" or unlocked and "SELECT" or ("LEVEL " .. rig.Level)
		local actionable = unlocked and not selected
		row.button.AutoButtonColor = actionable
		row.button.BackgroundColor3 = actionable and UiConfig.Colors.PrimaryButton or UiConfig.Colors.PanelRaised
		row.button.TextColor3 = actionable and UiConfig.Colors.PrimaryText
			or selected and UiConfig.Colors.Health
			or UiConfig.Colors.TextMuted
		local stroke = row.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = selected and rig.Color or UiConfig.Colors.Edge
		end
	end
end

-- profile is the ProfileSync payload.
function RigView:SetProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	local progression = type(profile.Progression) == "table" and profile.Progression or {}
	self._level = tonumber(progression.Level) or 1
	self._selected = RigConfig.Resolve(profile.SelectedRig, self._level).Id
	self:_render()
end

function RigView:GetSelected()
	return self._selected
end

function RigView:Open()
	self.modal.Open()
end

function RigView:Close()
	self.modal.Close()
end

return RigView
