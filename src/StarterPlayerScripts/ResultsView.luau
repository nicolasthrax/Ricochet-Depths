-- End-of-run summary. Everything shown here was computed and sent by the server. 3.0: the haul
-- (banked in full, or half lost in the depths), the day's modifier bonus, what the coins build
-- at home, and two calls to action: DESCEND again, or go BUILD at the base.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PactConfig = require(ReplicatedStorage:WaitForChild("PactConfig"))
local RigConfig = require(ReplicatedStorage:WaitForChild("RigConfig"))
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

-- onDismiss(): leave the results. actions (optional): { descend = function(), toBase = function(),
-- watchAd = function() }, each called after onDismiss.
function ResultsView.new(playerGui, onDismiss, actions)
	local self = setmetatable({}, ResultsView)
	actions = actions or {}

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
	self.lines.Size = UDim2.new(1, 0, 1, -44 - 34 - UiConfig.MinTouchTarget - 16)
	self.lines.CanvasSize = UDim2.new()
	self.lines.AutomaticCanvasSize = Enum.AutomaticSize.Y
	self.lines.ScrollBarThickness = 4
	self.lines.ScrollingDirection = Enum.ScrollingDirection.Y
	self.lines.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = self.lines

	-- What the haul builds at home, just above the buttons.
	self.buildLabel = UiTheme.label("Builds", panel, "", UiConfig.Text.Small + 2, UiConfig.Colors.Gold)
	self.buildLabel.AnchorPoint = Vector2.new(0, 1)
	self.buildLabel.Position = UDim2.new(0, 0, 1, -UiConfig.MinTouchTarget - 8)
	self.buildLabel.Size = UDim2.new(1, 0, 0, 26)
	self.buildLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.buildLabel.TextWrapped = true

	local function cta(name, text, style, x, handler)
		local button = UiTheme.button(name, panel, text, style)
		button.AnchorPoint = Vector2.new(x, 1)
		button.Position = UDim2.new(x, 0, 1, 0)
		button.Size = UDim2.new(0.48, 0, 0, UiConfig.MinTouchTarget)
		button.Activated:Connect(function()
			onDismiss()
			if handler then
				handler()
			end
		end)
		return button
	end
	self.descendButton = cta("Descend", "DESCEND", "Primary", 0, actions.descend)
	self.baseButton = cta("ToBase", "BUILD AT BASE", nil, 1, actions.toBase)
	-- The old single button, kept as the base button for anything that still looks for it.
	self.button = self.baseButton

	-- Rewarded video: a small fixed bonus, one tap, only where it is switched on.
	self.adButton = UiTheme.button("WatchAd", panel, "WATCH AN AD: +BONUS")
	self.adButton.AnchorPoint = Vector2.new(1, 0)
	self.adButton.Position = UDim2.new(1, 0, 0, 0)
	self.adButton.Size = UDim2.fromOffset(150, UiConfig.MinTouchTarget)
	self.adButton.TextSize = UiConfig.Text.Small - 2
	self.adButton.TextWrapped = true
	self.adButton.Visible = false
	self._watchAd = actions.watchAd
	self.adButton.Activated:Connect(function()
		if self._watchAd then
			self.adButton.Visible = false
			self._watchAd()
		end
	end)

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
	local function extra(text, color)
		index += 1
		self:_row(index, text, color)
	end
	-- The haul at risk: banked whole, or partly lost with the run.
	local haul = tonumber(summary.Haul) or 0
	local lost = tonumber(summary.HaulLost) or 0
	if summary.Banked then
		extra(string.format("Loot banked! Kept all %d coins you picked up.", haul), UiConfig.Colors.Health)
	elseif lost > 0 then
		extra(string.format("Haul lost in the depths: %d of %d coins. Bank loot at an extract point to keep it all.",
			lost, haul), UiConfig.Colors.Danger)
	end
	if (tonumber(summary.DailyBonus) or 0) > 0 then
		extra(string.format("Daily modifier bonus: +%d coins", summary.DailyBonus), UiConfig.Colors.Gold)
	end
	local rig = type(summary.Rig) == "string" and RigConfig.Get(summary.Rig)
	local heat = tonumber(summary.Heat) or 0
	if rig or heat > 0 then
		extra(string.format("%s%s", rig and ("Rig: " .. rig.Title) or "",
			heat > 0 and string.format("%sHeat %d (+%d%% rewards)", rig and "   -   " or "", heat,
				math.floor(heat * PactConfig.RewardPerHeat * 100 + 0.5)) or ""), rig and rig.Color or UiConfig.Colors.Danger)
	end
	if (tonumber(summary.ChampionsDefeated) or 0) > 0 then
		extra(string.format("Champions slain: %d", summary.ChampionsDefeated), UiConfig.Colors.Purple)
	end
	if (tonumber(summary.Crits) or 0) > 0 then
		extra(string.format("Critical hits: %d", summary.Crits))
	end
	if (tonumber(summary.BestCombo) or 0) >= 2 then
		extra(string.format("Best combo: %d", summary.BestCombo), UiConfig.Colors.Gold)
	end
	if (tonumber(summary.TrickShots) or 0) > 0 then
		extra(string.format("Trick shots: %d", summary.TrickShots), UiConfig.Colors.Accent)
	end
	if (tonumber(summary.SurgeLevel) or 0) > 0 then
		extra(string.format("Surge perks: %d", summary.SurgeLevel), Color3.fromRGB(255, 120, 200))
	end
	if (tonumber(summary.RevivesGiven) or 0) > 0 then
		extra(string.format("Teammates revived: %d", summary.RevivesGiven), UiConfig.Colors.Health)
	end
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
	self.adButton.Visible = self._watchAd ~= nil
	self.gui.Enabled = true
end

-- "Your haul builds X": the base's next build (BaseSync's NextBuild) against the balance now.
function ResultsView:SetNextBuild(nextBuild, balance)
	if type(nextBuild) ~= "table" then
		self.buildLabel.Text = ""
		return
	end
	local short = (tonumber(nextBuild.Cost) or 0) - (tonumber(balance) or 0)
	if short <= 0 then
		self.buildLabel.Text = string.format("Your haul builds: %s Lv%d!", nextBuild.Title, nextBuild.Level)
		self.buildLabel.TextColor3 = UiConfig.Colors.Health
	else
		self.buildLabel.Text = string.format("%d more coins build %s Lv%d", short, nextBuild.Title, nextBuild.Level)
		self.buildLabel.TextColor3 = UiConfig.Colors.Gold
	end
end

function ResultsView:Hide()
	self.gui.Enabled = false
end

function ResultsView:Destroy()
	self.gui:Destroy()
end

return ResultsView
