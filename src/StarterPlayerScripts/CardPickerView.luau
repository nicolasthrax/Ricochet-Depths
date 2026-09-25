-- Three-card upgrade choice with a visible countdown. The server decides what is offered and
-- what a pick means; this view only sends back the id it was given.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))
local UiTheme = require(script.Parent.UiTheme)

local CardPickerView = {}
CardPickerView.__index = CardPickerView

-- onVote(doorId), optional: the player chose a door for the next room.
function CardPickerView.new(playerGui, onChoose, onVote)
	local self = setmetatable({}, CardPickerView)
	self._onChoose = onChoose
	self._onVote = onVote
	self._cards = {}

	self.gui = UiTheme.screenGui("RicochetCardPicker", playerGui, 20)
	self.gui.Enabled = false

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Parent = self.gui

	self.title = UiTheme.heading("Title", backdrop, "Choose an upgrade", UiConfig.Text.Title)
	self.title.Position = UDim2.new(0.5, 0, 0.16, 0)
	self.title.AnchorPoint = Vector2.new(0.5, 0.5)
	self.title.Size = UDim2.fromOffset(500, 36)
	self.title.TextXAlignment = Enum.TextXAlignment.Center

	self.timerLabel = UiTheme.label("Timer", backdrop, "", UiConfig.Text.Hud, UiConfig.Colors.Warning)
	self.timerLabel.Position = UDim2.new(0.5, 0, 0.16, 30)
	self.timerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	self.timerLabel.Size = UDim2.fromOffset(500, 24)
	self.timerLabel.TextXAlignment = Enum.TextXAlignment.Center

	local row = Instance.new("Frame")
	row.Name = "CardRow"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.5, 0.56)
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Size = UDim2.fromScale(0.94, 0.6)
	row.Parent = backdrop
	self.row = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, UiConfig.CardGap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	return self
end

function CardPickerView:_clear()
	for _, card in self._cards do
		card:Destroy()
	end
	table.clear(self._cards)
end

function CardPickerView:Show(payload)
	self._stage = "Cards"
	self.title.Text = "Choose an upgrade"
	self:_clear()
	self._offerId = payload.OfferId
	-- The server sends how long is left, and the deadline is computed against this machine's
	-- clock. Comparing against a server timestamp would be meaningless.
	local secondsRemaining = tonumber(payload.SecondsRemaining) or UpgradeConfig.ChoiceTimeout
	self._deadline = os.clock() + math.max(secondsRemaining, 0)
	self._locked = false

	for index, card in payload.Cards do
		local category = UpgradeConfig.Categories[card.Category]
		local rarity = UpgradeConfig.Rarities[card.Rarity]

		local button = UiTheme.button("Card" .. index, self.row, "")
		button.LayoutOrder = index
		-- Sized in scale so three (or an Armoury's four) cards still fit on a narrow phone screen.
		button.Size = UDim2.new(#payload.Cards > 3 and 0.23 or 0.3, 0, 1, 0)
		button.BackgroundColor3 = UiConfig.Colors.PanelRaised
		UiTheme.padding(button, 12)

		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MaxSize = UiConfig.CardSize
		sizeConstraint.MinSize = Vector2.new(96, 150)
		sizeConstraint.Parent = button

		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.Size = UDim2.new(1, 0, 0, 5)
		stripe.BackgroundColor3 = (category and category.Color) or UiConfig.Colors.Accent
		stripe.BorderSizePixel = 0
		stripe.Parent = button
		UiTheme.corner(stripe, 3)

		local title = UiTheme.label("Title", button, card.Title, UiConfig.Text.CardTitle)
		title.Position = UDim2.new(0, 0, 0, 14)
		title.Size = UDim2.new(1, 0, 0, 30)
		title.TextWrapped = true

		local kind = UiTheme.label(
			"Kind",
			button,
			string.format("%s  -  %s", category and category.DisplayName or card.Category, card.Rarity),
			UiConfig.Text.Small,
			(rarity and rarity.Color) or UiConfig.Colors.TextMuted
		)
		kind.Position = UDim2.new(0, 0, 0, 46)
		kind.Size = UDim2.new(1, 0, 0, 18)

		local body = UiTheme.label("Body", button, card.Description, UiConfig.Text.CardBody, UiConfig.Colors.TextMuted)
		body.Position = UDim2.new(0, 0, 0, 70)
		body.Size = UDim2.new(1, 0, 1, -76)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top

		button.Activated:Connect(function()
			if self._locked then
				return
			end
			self._locked = true -- one pick per offer; the server rejects the rest anyway
			self._onChoose(self._offerId, card.Id)
		end)

		table.insert(self._cards, button)
	end

	self.gui.Enabled = true
end

function CardPickerView:UpdateTimer(now)
	if not self.gui.Enabled or not self._deadline or self._stage == "Doors" then
		return
	end
	local remaining = math.max(self._deadline - now, 0)
	self.timerLabel.Text = string.format("Auto-picks in %.0fs", remaining)
end

--// doors ------------------------------------------------------------------------

local ZONE_COLORS = {
	Ruins = Color3.fromRGB(190, 210, 255),
	Foundry = Color3.fromRGB(255, 176, 96),
	Abyss = Color3.fromRGB(200, 150, 255),
}

-- The latest doors from the run snapshot ({ Doors, SecondsLeft }), or nil when there are none.
-- While the door stage is showing it redraws with the new votes.
function CardPickerView:SetDoors(doors)
	self._doors = type(doors) == "table" and type(doors.Doors) == "table" and doors or nil
	if self._stage == "Doors" and self.gui.Enabled then
		self:_renderDoors()
	end
end

function CardPickerView:HasDoors()
	return self._doors ~= nil
end

-- After the card: the doors to the next room. Returns false when there are none to show.
function CardPickerView:ShowDoors()
	if not self._doors then
		return false
	end
	self._stage = "Doors"
	self._voted = nil
	self:_renderDoors()
	self.gui.Enabled = true
	return true
end

function CardPickerView:_renderDoors()
	self:_clear()
	local doors = self._doors
	self.title.Text = "Choose your path"
	self.timerLabel.Text = self._voted and string.format("Waiting for the others...  %ds", doors.SecondsLeft or 0)
		or string.format("The group votes. Closes in %ds", doors.SecondsLeft or 0)
	for index, door in doors.Doors do
		local button = UiTheme.button("Door" .. index, self.row, "")
		button.LayoutOrder = index
		-- Two doors side by side, or three narrower ones when the Surface Lift joins them.
		button.Size = UDim2.new(math.min(0.42, 0.94 / #doors.Doors), 0, 1, 0)
		button.BackgroundColor3 = UiConfig.Colors.PanelRaised
		UiTheme.padding(button, 12)
		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MaxSize = Vector2.new(280, 300)
		sizeConstraint.Parent = button
		local chosen = self._voted == door.Id
		local edge = button:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = chosen and UiConfig.Colors.Gold
				or (door.Kind == "Lift" and UiConfig.Colors.Health or ZONE_COLORS[door.Zone] or UiConfig.Colors.Accent)
			edge.Thickness = chosen and 3 or 1.5
			edge.Transparency = chosen and 0 or 0.4
		end

		local room = UiTheme.label("Room", button, door.RoomName, UiConfig.Text.CardTitle, ZONE_COLORS[door.Zone] or UiConfig.Colors.Text)
		room.Font = UiConfig.FontDisplay
		room.Size = UDim2.new(1, 0, 0, 30)
		room.TextWrapped = true
		local kind = door.Kind == "MiniBoss" and "MINI-BOSS" or door.Kind == "Boss" and "BOSS"
			or door.Kind == "Elite" and "ELITE" or door.Kind == "Bonus" and "BONUS ROOM"
			or door.Kind == "Lift" and "LEAVE THE RUN" or ""
		local sub = UiTheme.label("Kind", button, kind, UiConfig.Text.Small,
			door.Kind == "Lift" and UiConfig.Colors.Health or UiConfig.Colors.Danger)
		sub.Position = UDim2.new(0, 0, 0, 30)
		sub.Size = UDim2.new(1, 0, 0, 16)
		local reward = UiTheme.label("Reward", button, door.RewardTitle, UiConfig.Text.Hud, UiConfig.Colors.Gold)
		reward.Font = UiConfig.FontBold
		reward.Position = UDim2.new(0, 0, 0, 54)
		reward.Size = UDim2.new(1, 0, 0, 22)
		local body = UiTheme.label("Body", button, door.RewardText, UiConfig.Text.CardBody, UiConfig.Colors.TextMuted)
		body.Position = UDim2.new(0, 0, 0, 78)
		body.Size = UDim2.new(1, 0, 1, -104)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		local votes = UiTheme.label("Votes", button, (door.Votes or 0) > 0 and string.format("%d vote%s", door.Votes,
			door.Votes == 1 and "" or "s") or "", UiConfig.Text.Small, UiConfig.Colors.Health)
		votes.AnchorPoint = Vector2.new(0, 1)
		votes.Position = UDim2.new(0, 0, 1, 0)
		votes.Size = UDim2.new(1, 0, 0, 18)

		button.Activated:Connect(function()
			if self._voted == door.Id then
				return
			end
			self._voted = door.Id
			if self._onVote then
				self._onVote(door.Id)
			end
			self:_renderDoors()
		end)
		table.insert(self._cards, button)
	end
end

function CardPickerView:Hide()
	self.gui.Enabled = false
	self._stage = nil
	self._voted = nil
	self:_clear()
	self._offerId = nil
	self._deadline = nil
end

function CardPickerView:Destroy()
	self:_clear()
	self.gui:Destroy()
end

return CardPickerView
