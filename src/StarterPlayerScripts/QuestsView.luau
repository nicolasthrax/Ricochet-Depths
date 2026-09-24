-- Today's three quests with progress bars and Claim buttons. Display only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local QuestsView = {}
QuestsView.__index = QuestsView

local ROW_HEIGHT = 84

function QuestsView.new(playerGui, onClaim)
	local self = setmetatable({}, QuestsView)
	self._onClaim = onClaim
	self.modal = UiTheme.modal("RicochetQuests", playerGui, "DAILY QUESTS", Vector2.new(520, 420))
	local content = self.modal.content

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 1, -26)
	list.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	self.list = list

	self.resetLabel = UiTheme.label("Reset", content, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.resetLabel.AnchorPoint = Vector2.new(0, 1)
	self.resetLabel.Position = UDim2.new(0, 0, 1, 0)
	self.resetLabel.Size = UDim2.new(1, 0, 0, 20)
	self.resetLabel.TextXAlignment = Enum.TextXAlignment.Center

	self.rows = {}
	return self
end

function QuestsView:_row(index)
	local existing = self.rows[index]
	if existing then
		return existing
	end
	local frame = UiTheme.panel("Quest" .. index, self.list)
	frame.LayoutOrder = index
	frame.BackgroundColor3 = UiConfig.Colors.PanelRaised
	frame.BackgroundTransparency = 0
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	UiTheme.padding(frame, 10)
	local title = UiTheme.label("Title", frame, "", UiConfig.Text.Hud)
	title.Font = UiConfig.FontBold
	title.Size = UDim2.new(1, -130, 0, 22)
	local reward = UiTheme.label("Reward", frame, "", UiConfig.Text.Small, UiConfig.Colors.Gold)
	reward.Position = UDim2.new(0, 0, 0, 22)
	reward.Size = UDim2.new(1, -130, 0, 18)
	local track, fill = UiTheme.bar("Progress", frame, UiConfig.Colors.Health)
	track.Position = UDim2.new(0, 0, 0, 46)
	track.Size = UDim2.new(1, -130, 0, 14)
	local count = UiTheme.label("Count", track, "", UiConfig.Text.Small - 2, UiConfig.Colors.Text)
	count.Size = UDim2.fromScale(1, 1)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.ZIndex = 3
	local button = UiTheme.button("Claim", frame, "", "Primary")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.Size = UDim2.fromOffset(116, UiConfig.MinTouchTarget)
	button.TextSize = UiConfig.Text.Small
	local row = { frame = frame, title = title, reward = reward, fill = fill, count = count, button = button }
	button.Activated:Connect(function()
		if row.claimable and row.id then
			self._onClaim(row.id)
		end
	end)
	self.rows[index] = row
	return row
end

-- quests is MetaSync's Quests list; resetsIn is seconds until they are redrawn.
function QuestsView:SetState(quests, resetsIn)
	if type(quests) ~= "table" then
		return
	end
	for index, quest in quests do
		local row = self:_row(index)
		row.id = quest.Id
		row.frame.Visible = true
		row.title.Text = quest.Title
		local xp = quest.Xp and quest.Xp > 0 and string.format("  +%d XP", quest.Xp) or ""
		row.reward.Text = string.format("Reward: %d coins%s", quest.Coins or 0, xp)
		local target = math.max(tonumber(quest.Target) or 1, 1)
		local progress = math.clamp(tonumber(quest.Progress) or 0, 0, target)
		row.fill.Size = UDim2.fromScale(progress / target, 1)
		row.count.Text = string.format("%d / %d", progress, target)
		row.claimable = quest.Complete == true and quest.Claimed ~= true
		row.button.Text = quest.Claimed and "DONE" or (quest.Complete and "CLAIM" or "IN PROGRESS")
		row.button.AutoButtonColor = row.claimable
		row.button.BackgroundColor3 = row.claimable and UiConfig.Colors.PrimaryButton or UiConfig.Colors.PanelRaised
		row.button.TextColor3 = row.claimable and UiConfig.Colors.PrimaryText or UiConfig.Colors.TextMuted
	end
	for index = #quests + 1, #self.rows do
		self.rows[index].frame.Visible = false
	end
	self.resetLabel.Text = "New quests in " .. UiTheme.duration(resetsIn)
end

function QuestsView:Open()
	self.modal.Open()
end

function QuestsView:Close()
	self.modal.Close()
end

return QuestsView
