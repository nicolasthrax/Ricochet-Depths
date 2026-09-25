-- Daily rewards: the week's seven rewards as tiles, the streak, and a Claim button. Display
-- only; the server decides what a claim pays and replies with a fresh MetaSync.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local DailyView = {}
DailyView.__index = DailyView

function DailyView.new(playerGui, onClaim)
	local self = setmetatable({}, DailyView)
	self.modal = UiTheme.modal("RicochetDaily", playerGui, "DAILY REWARDS", Vector2.new(600, 380))
	local content = self.modal.content

	self.streakLabel = UiTheme.label("Streak", content, "", UiConfig.Text.Hud, UiConfig.Colors.Accent)
	self.streakLabel.Size = UDim2.new(1, 0, 0, 22)

	local grid = Instance.new("Frame")
	grid.Name = "Days"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.new(0, 0, 0, 30)
	grid.Size = UDim2.new(1, 0, 0, 110)
	grid.Parent = content
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / #MetaConfig.DailyRewards, -6, 1, 0)
	layout.CellPadding = UDim2.fromOffset(6, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	self.tiles = {}
	for index, reward in MetaConfig.DailyRewards do
		local tile = UiTheme.panel("Day" .. index, grid)
		tile.LayoutOrder = index
		tile.BackgroundColor3 = UiConfig.Colors.PanelRaised
		tile.BackgroundTransparency = 0
		local day = UiTheme.label("Day", tile, "DAY " .. index, UiConfig.Text.Small, UiConfig.Colors.TextMuted)
		day.Size = UDim2.new(1, 0, 0, 24)
		day.TextXAlignment = Enum.TextXAlignment.Center
		day.Font = UiConfig.FontBold
		local coins = UiTheme.label("Coins", tile, tostring(reward.Coins), UiConfig.Text.CardTitle, UiConfig.Colors.Gold)
		coins.Position = UDim2.new(0, 0, 0, 30)
		coins.Size = UDim2.new(1, 0, 0, 28)
		coins.TextXAlignment = Enum.TextXAlignment.Center
		coins.Font = UiConfig.FontDisplay
		local lines = { "coins" }
		if reward.Xp then
			table.insert(lines, "+" .. reward.Xp .. " XP")
		end
		local extras = reward.Extras or {}
		if extras.ReviveTokens then
			table.insert(lines, string.format("+%d Revive", extras.ReviveTokens))
		end
		if extras.Rerolls then
			table.insert(lines, string.format("+%d Rerolls", extras.Rerolls))
		end
		local detail = UiTheme.label("Detail", tile, table.concat(lines, "\n"), UiConfig.Text.Small - 2, UiConfig.Colors.TextMuted)
		detail.Position = UDim2.new(0, 0, 0, 58)
		detail.Size = UDim2.new(1, 0, 0, 34)
		detail.TextXAlignment = Enum.TextXAlignment.Center
		detail.TextWrapped = true
		local state = UiTheme.label("State", tile, "", UiConfig.Text.Small, UiConfig.Colors.Health)
		state.AnchorPoint = Vector2.new(0, 1)
		state.Position = UDim2.new(0, 0, 1, -2)
		state.Size = UDim2.new(1, 0, 0, 18)
		state.TextXAlignment = Enum.TextXAlignment.Center
		state.Font = UiConfig.FontBold
		self.tiles[index] = { frame = tile, state = state, stroke = tile:FindFirstChildOfClass("UIStroke") }
	end

	self.claimButton = UiTheme.button("Claim", content, "CLAIM", "Primary")
	self.claimButton.AnchorPoint = Vector2.new(0.5, 0)
	self.claimButton.Position = UDim2.new(0.5, 0, 0, 152)
	self.claimButton.Size = UDim2.fromOffset(240, 54)
	self.claimButton.Activated:Connect(function()
		if self._canClaim then
			onClaim()
		end
	end)

	self.resetLabel = UiTheme.label("Reset", content, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.resetLabel.Position = UDim2.new(0, 0, 0, 214)
	self.resetLabel.Size = UDim2.new(1, 0, 0, 20)
	self.resetLabel.TextXAlignment = Enum.TextXAlignment.Center

	self._canClaim = false
	return self
end

-- state is MetaSync's Daily plus its ResetsIn: { CanClaim, Streak, DayIndex }, resetsIn.
function DailyView:SetState(daily, resetsIn)
	if type(daily) ~= "table" then
		return
	end
	self._canClaim = daily.CanClaim == true
	local streak = tonumber(daily.Streak) or 0
	local current = tonumber(daily.DayIndex) or 1
	-- The forgiving track: a missed day never sends anyone back to day 1.
	self.streakLabel.Text = streak > 0 and string.format("%d reward%s claimed. Missed a day? You never lose your place.",
		streak, streak == 1 and "" or "s") or "A reward every day you play. Miss a day and you keep your place."
	for index, tile in self.tiles do
		local claimed = index < current or (index == current and not self._canClaim)
		local today = index == current and self._canClaim
		tile.state.Text = claimed and "CLAIMED" or (today and "TODAY" or "")
		tile.state.TextColor3 = today and UiConfig.Colors.Gold or UiConfig.Colors.Health
		tile.frame.BackgroundTransparency = claimed and 0.5 or 0
		if tile.stroke then
			tile.stroke.Color = today and UiConfig.Colors.Gold or UiConfig.Colors.Edge
			tile.stroke.Thickness = today and 3 or 1.5
		end
	end
	self.claimButton.Text = self._canClaim and "CLAIM" or "CLAIMED"
	self.claimButton.AutoButtonColor = self._canClaim
	self.resetLabel.Text = self._canClaim and "Your reward is ready!"
		or ("Next reward in " .. UiTheme.duration(resetsIn))
end

function DailyView:Open()
	self.modal.Open()
end

function DailyView:Close()
	self.modal.Close()
end

function DailyView:CanClaim()
	return self._canClaim
end

return DailyView
