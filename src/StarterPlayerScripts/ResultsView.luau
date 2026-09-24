-- End-of-run summary. Everything shown here was computed and sent by the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local ResultsView = {}
ResultsView.__index = ResultsView

local OUTCOME_TEXT = {
	Extracted = { title = "Extracted", color = UiConfig.Colors.Health },
	Defeated = { title = "Lost in the Depths", color = UiConfig.Colors.Danger },
	TimedOut = { title = "Out of Time", color = UiConfig.Colors.Warning },
	Abandoned = { title = "Run Abandoned", color = UiConfig.Colors.TextMuted },
	Aborted = { title = "Descent Collapsed", color = UiConfig.Colors.TextMuted },
}

function ResultsView.new(playerGui, onDismiss)
	local self = setmetatable({}, ResultsView)

	self.gui = UiTheme.screenGui("RicochetResults", playerGui, 30)
	self.gui.Enabled = false

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Parent = self.gui

	local panel = UiTheme.panel("Panel", backdrop)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.new(0.8, 0, 0.72, 0)
	panel.BackgroundTransparency = 0
	UiTheme.padding(panel, 18)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(460, 520)
	constraint.Parent = panel

	self.title = UiTheme.heading("Title", panel, "", UiConfig.Text.Title)
	self.title.Size = UDim2.new(1, 0, 0, 36)
	self.title.TextXAlignment = Enum.TextXAlignment.Center

	-- Scrolls when a long run's upgrade list does not fit.
	self.lines = Instance.new("ScrollingFrame")
	self.lines.Name = "Lines"
	self.lines.BackgroundTransparency = 1
	self.lines.BorderSizePixel = 0
	self.lines.Position = UDim2.new(0, 0, 0, 44)
	self.lines.Size = UDim2.new(1, 0, 1, -110)
	self.lines.CanvasSize = UDim2.new()
	self.lines.AutomaticCanvasSize = Enum.AutomaticSize.Y
	self.lines.ScrollBarThickness = 4
	self.lines.ScrollingDirection = Enum.ScrollingDirection.Y
	self.lines.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = self.lines

	self.button = UiTheme.button("Return", panel, "Return to Lobby", "Primary")
	self.button.AnchorPoint = Vector2.new(0.5, 1)
	self.button.Position = UDim2.new(0.5, 0, 1, 0)
	self.button.Size = UDim2.new(0.8, 0, 0, UiConfig.MinTouchTarget)
	self.button.Activated:Connect(onDismiss)

	self._rows = {}
	return self
end

function ResultsView:_row(index, text, color)
	local label = UiTheme.label("Row" .. index, self.lines, text, UiConfig.Text.Hud, color)
	label.Size = UDim2.new(1, 0, 0, 22)
	label.LayoutOrder = index
	table.insert(self._rows, label)
end

function ResultsView:Show(summary)
	for _, row in self._rows do
		row:Destroy()
	end
	table.clear(self._rows)

	local outcome = OUTCOME_TEXT[summary.Outcome] or OUTCOME_TEXT.Abandoned
	self.title.Text = outcome.title
	self.title.TextColor3 = outcome.color

	self:_row(1, string.format("Rooms cleared: %d / %d", summary.RoomsCleared, summary.RoomCount))
	self:_row(2, string.format("Enemies defeated: %d", summary.EnemiesDefeated))
	self:_row(3, string.format("Best ricochet chain: %d contacts", summary.BestChain))
	self:_row(4, string.format("Shots fired: %d", summary.ShotsFired))
	self:_row(5, string.format("Damage taken: %d", summary.DamageTaken))
	self:_row(6, string.format("Time: %.1fs", summary.DurationSeconds))
	self:_row(7, string.format("%s earned: %d", summary.CurrencyName, summary.Reward), UiConfig.Colors.Accent)

	local index = 7
	local xp = type(summary.XpEarned) == "number" and summary.XpEarned or 0
	local progress = type(summary.Progress) == "table" and summary.Progress or nil
	if xp > 0 then
		index += 1
		self:_row(index, string.format("Experience: +%d XP", xp), UiConfig.Colors.Warning)
	end
	if progress and progress.LeveledUp then
		index += 1
		local bonus = type(summary.LevelReward) == "number" and summary.LevelReward or 0
		local text = bonus > 0 and string.format("LEVEL UP!  Level %d  (+%d %s)", progress.Level, bonus, summary.CurrencyName)
			or string.format("LEVEL UP!  Level %d", progress.Level)
		self:_row(index, text, UiConfig.Colors.Health)
	elseif progress and progress.XpToNext and progress.XpToNext > 0 then
		index += 1
		self:_row(index, string.format("Level %d  -  %d / %d XP to next", progress.Level, progress.XpIntoLevel, progress.XpToNext),
			UiConfig.Colors.TextMuted)
	end

	index += 1
	self:_row(index, #summary.Upgrades > 0 and "Upgrades taken:" or "No upgrades taken", UiConfig.Colors.TextMuted)
	for _, upgrade in summary.Upgrades do
		index += 1
		self:_row(index, "  " .. upgrade.Title, UiConfig.Colors.TextMuted)
	end

	self.lines.CanvasPosition = Vector2.new(0, 0)
	self.gui.Enabled = true
end

function ResultsView:Hide()
	self.gui.Enabled = false
end

function ResultsView:Destroy()
	self.gui:Destroy()
end

return ResultsView
