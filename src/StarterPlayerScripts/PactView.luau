-- The Depth Pact: each condition with its ranks and - / + buttons, and the Heat and reward they
-- add up to. Edits are shown at once and sent to the server a moment after the last tap, so a
-- burst of taps is one request. The server sanitises and saves; ProfileSync is the truth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PactConfig = require(ReplicatedStorage:WaitForChild("PactConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local PactView = {}
PactView.__index = PactView

local ROW_HEIGHT = 64
local SEND_DELAY = 0.6

-- "Heat 5  -  +50% coins and XP" for a pact.
function PactView.HeatText(pact)
	local heat = PactConfig.Heat(pact)
	if heat == 0 then
		return "Heat 0  -  add conditions for bigger rewards"
	end
	return string.format("Heat %d  -  +%d%% coins and XP", heat, math.floor(heat * PactConfig.RewardPerHeat * 100 + 0.5))
end

-- Plain text, so it renders in any font on any device.
function PactView.RankText(rank, maxRank)
	return string.format("%d / %d", rank, maxRank)
end

function PactView.new(playerGui, onChange)
	local self = setmetatable({}, PactView)
	self._onChange = onChange
	self._pact = {}
	self._unlocked = false
	self._sendToken = 0
	self.modal = UiTheme.modal("RicochetPact", playerGui, "DEPTH PACT", Vector2.new(560, 600))
	local content = self.modal.content

	self.heatLabel = UiTheme.heading("Heat", content, "", UiConfig.Text.CardTitle, UiConfig.Colors.Danger)
	self.heatLabel.Size = UDim2.new(1, 0, 0, 28)
	self.hintLabel = UiTheme.label("Hint", content,
		"In a group, each condition runs at the lowest rank anyone chose.", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.hintLabel.Position = UDim2.new(0, 0, 0, 30)
	self.hintLabel.Size = UDim2.new(1, 0, 0, 18)
	self.hintLabel.TextWrapped = true

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, 56)
	list.Size = UDim2.new(1, 0, 1, -56)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	self.list = list

	self.rows = {}
	for index, condition in PactConfig.Conditions do
		local frame = UiTheme.panel(condition.Id, list)
		frame.LayoutOrder = index
		frame.BackgroundColor3 = UiConfig.Colors.PanelRaised
		frame.BackgroundTransparency = 0
		frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		UiTheme.padding(frame, 8)
		local title = UiTheme.label("Title", frame, condition.Title, UiConfig.Text.Hud)
		title.Font = UiConfig.FontBold
		title.Size = UDim2.new(1, -170, 0, 22)
		local body = UiTheme.label("Body", frame, string.format("%s  (+%d Heat each)", condition.Description, condition.HeatPerRank),
			UiConfig.Text.Small, UiConfig.Colors.TextMuted)
		body.Position = UDim2.new(0, 0, 0, 22)
		body.Size = UDim2.new(1, -170, 0, 26)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top

		local minus = UiTheme.button("Minus", frame, "-")
		minus.AnchorPoint = Vector2.new(1, 0.5)
		minus.Position = UDim2.new(1, -112, 0.5, 0)
		minus.Size = UDim2.fromOffset(UiConfig.MinTouchTarget, UiConfig.MinTouchTarget)
		local rank = UiTheme.label("Rank", frame, "", UiConfig.Text.Hud, UiConfig.Colors.Danger)
		rank.AnchorPoint = Vector2.new(1, 0.5)
		rank.Position = UDim2.new(1, -52, 0.5, 0)
		rank.Size = UDim2.fromOffset(58, 24)
		rank.TextXAlignment = Enum.TextXAlignment.Center
		local plus = UiTheme.button("Plus", frame, "+")
		plus.AnchorPoint = Vector2.new(1, 0.5)
		plus.Position = UDim2.new(1, 0, 0.5, 0)
		plus.Size = UDim2.fromOffset(UiConfig.MinTouchTarget, UiConfig.MinTouchTarget)

		minus.Activated:Connect(function()
			self:_adjust(condition, -1)
		end)
		plus.Activated:Connect(function()
			self:_adjust(condition, 1)
		end)
		self.rows[condition.Id] = { rank = rank, minus = minus, plus = plus }
	end
	self:_render()
	return self
end

function PactView:_adjust(condition, delta)
	if not self._unlocked then
		return
	end
	local current = self._pact[condition.Id] or 0
	local nextRank = math.clamp(current + delta, 0, condition.MaxRank)
	if nextRank == current then
		return
	end
	local pact = table.clone(self._pact)
	pact[condition.Id] = nextRank > 0 and nextRank or nil
	self._pact = pact
	self:_render()

	-- Send once the taps stop; the latest pact wins.
	self._sendToken += 1
	local token = self._sendToken
	self._pending = true
	task.delay(SEND_DELAY, function()
		if self._sendToken == token then
			self._pending = false
			self._onChange(table.clone(self._pact))
		end
	end)
end

function PactView:_render()
	self.heatLabel.Text = self._unlocked and PactView.HeatText(self._pact)
		or string.format("Locked  -  extract %d time to open the Pact", PactConfig.UnlockExtractions)
	for _, condition in PactConfig.Conditions do
		local row = self.rows[condition.Id]
		local rank = self._pact[condition.Id] or 0
		row.rank.Text = PactView.RankText(rank, condition.MaxRank)
		row.minus.Visible = self._unlocked
		row.plus.Visible = self._unlocked
	end
end

-- profile is the ProfileSync payload. A pact still waiting to be sent is not overwritten.
function PactView:SetProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	local stats = type(profile.Stats) == "table" and profile.Stats or {}
	self._unlocked = PactConfig.IsUnlocked(stats.RunsExtracted)
	if not self._pending then
		self._pact = PactConfig.Sanitise(profile.Pact)
	end
	self:_render()
end

function PactView:GetPact()
	return table.clone(self._pact)
end

function PactView:Open()
	self.modal.Open()
end

function PactView:Close()
	self.modal.Close()
end

return PactView
