-- The player's profile card: level, experience and lifetime stats. Opened by tapping the level
-- badge. Display only, from the last ProfileSync.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local StatsView = {}
StatsView.__index = StatsView

local STATS = {
	{ Key = "RunsStarted", Label = "Descents" },
	{ Key = "RunsExtracted", Label = "Extractions" },
	{ Key = "EnemiesDefeated", Label = "Enemies defeated" },
	{ Key = "BestChain", Label = "Best ricochet chain" },
	{ Key = "BestRoomsCleared", Label = "Deepest room" },
	{ Key = "CoinsEarned", Label = "Coins earned" },
	{ Key = "ChampionsDefeated", Label = "Champions slain" },
	{ Key = "BestHeat", Label = "Highest Heat extracted" },
}

function StatsView.new(playerGui, playerName)
	local self = setmetatable({}, StatsView)
	self.modal = UiTheme.modal("RicochetStats", playerGui, playerName or "PROFILE", Vector2.new(460, 500))
	local content = self.modal.content

	self.levelLabel = UiTheme.heading("Level", content, "LEVEL 1", UiConfig.Text.Title, UiConfig.Colors.Gold)
	self.levelLabel.Size = UDim2.new(1, 0, 0, 34)
	local track, fill = UiTheme.bar("Xp", content, UiConfig.Colors.Gold)
	track.Position = UDim2.new(0, 0, 0, 40)
	track.Size = UDim2.new(1, 0, 0, 16)
	self.xpFill = fill
	self.xpLabel = UiTheme.label("XpText", content, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.xpLabel.Position = UDim2.new(0, 0, 0, 58)
	self.xpLabel.Size = UDim2.new(1, 0, 0, 18)

	local grid = Instance.new("Frame")
	grid.Name = "Stats"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.new(0, 0, 0, 86)
	grid.Size = UDim2.new(1, 0, 1, -86)
	grid.Parent = content
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -4, 0, 64)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	self.values = {}
	for index, stat in STATS do
		local cell = UiTheme.panel(stat.Key, grid)
		cell.LayoutOrder = index
		cell.BackgroundColor3 = UiConfig.Colors.PanelRaised
		cell.BackgroundTransparency = 0
		UiTheme.padding(cell, 8)
		local value = UiTheme.label("Value", cell, "0", UiConfig.Text.CardTitle, UiConfig.Colors.Text)
		value.Font = UiConfig.FontDisplay
		value.Size = UDim2.new(1, 0, 0, 26)
		local caption = UiTheme.label("Caption", cell, stat.Label, UiConfig.Text.Small, UiConfig.Colors.TextMuted)
		caption.Position = UDim2.new(0, 0, 0, 26)
		caption.Size = UDim2.new(1, 0, 0, 20)
		self.values[stat.Key] = value
	end
	return self
end

-- profile is the ProfileSync payload.
function StatsView:SetProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	local progression = type(profile.Progression) == "table" and profile.Progression or {}
	self.levelLabel.Text = "LEVEL " .. tostring(progression.Level or 1)
	local into, need = progression.XpIntoLevel or 0, progression.XpToNext or 0
	self.xpFill.Size = UDim2.fromScale(need > 0 and math.clamp(into / need, 0, 1) or 1, 1)
	self.xpLabel.Text = need > 0 and string.format("%d / %d XP to level %d", into, need, (progression.Level or 1) + 1)
		or "Max level!"
	local stats = type(profile.Stats) == "table" and profile.Stats or {}
	for key, label in self.values do
		label.Text = tostring(math.floor(tonumber(stats[key]) or 0))
	end
end

function StatsView:Open()
	self.modal.Open()
end

function StatsView:Close()
	self.modal.Close()
end

return StatsView
