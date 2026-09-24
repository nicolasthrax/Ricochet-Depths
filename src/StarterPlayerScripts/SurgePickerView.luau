-- The Surge pick: three small perks in a strip along the bottom of the screen, taken with a tap
-- or the 1 / 2 / 3 keys while the fight goes on. Nothing is paused and nothing is covered; if
-- the player ignores it, the server picks the first perk when the timer runs out.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArsenalConfig = require(ReplicatedStorage:WaitForChild("ArsenalConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local SurgePickerView = {}
SurgePickerView.__index = SurgePickerView

local SURGE_COLOR = Color3.fromRGB(255, 120, 200)

function SurgePickerView.new(playerGui, onChoose)
	local self = setmetatable({}, SurgePickerView)
	self._onChoose = onChoose
	self._buttons = {}
	self.gui = UiTheme.screenGui("RicochetSurge", playerGui, 18)
	self.gui.Enabled = false

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0.5, 1)
	-- Above the hint panel and the health panel, below the combat: never over the aim zone's
	-- heart and never on the thumbstick.
	strip.Position = UDim2.new(0.5, 0, 1, -164)
	strip.Size = UDim2.new(0.62, 0, 0, 86)
	strip.Parent = self.gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 86)
	limit.Parent = strip
	self.strip = strip

	self.title = UiTheme.heading("Title", strip, "SURGE!", UiConfig.Text.Hud, SURGE_COLOR)
	self.title.AnchorPoint = Vector2.new(0.5, 1)
	self.title.Position = UDim2.new(0.5, 0, 0, -2)
	self.title.Size = UDim2.new(1, 0, 0, 22)
	self.title.TextXAlignment = Enum.TextXAlignment.Center

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = strip
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	self.row = row
	return self
end

function SurgePickerView:_clear()
	for _, button in self._buttons do
		button:Destroy()
	end
	table.clear(self._buttons)
end

-- payload is the SurgeOffer: { OfferId, Cards, SecondsRemaining, Level }.
function SurgePickerView:Show(payload)
	if type(payload) ~= "table" or type(payload.Cards) ~= "table" then
		return
	end
	self:_clear()
	self._offerId = payload.OfferId
	self._cards = payload.Cards
	self._deadline = os.clock() + (tonumber(payload.SecondsRemaining) or ArsenalConfig.Surge.ChoiceTimeout)
	self._locked = false
	for index, card in payload.Cards do
		local button = UiTheme.button("Perk" .. index, self.row, "")
		button.LayoutOrder = index
		button.Size = UDim2.new(0.32, 0, 1, 0)
		button.BackgroundTransparency = 0.1
		UiTheme.padding(button, 6)
		local edge = button:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = SURGE_COLOR
		end
		local key = UiTheme.label("Key", button, tostring(index), UiConfig.Text.Small, SURGE_COLOR)
		key.Font = UiConfig.FontDisplay
		key.Size = UDim2.new(0, 16, 0, 18)
		local title = UiTheme.label("Title", button, card.Title, UiConfig.Text.Hud)
		title.Font = UiConfig.FontBold
		title.Position = UDim2.new(0, 18, 0, 0)
		title.Size = UDim2.new(1, -18, 0, 20)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local body = UiTheme.label("Body", button, card.Description, UiConfig.Text.Small - 1, UiConfig.Colors.TextMuted)
		body.Position = UDim2.new(0, 0, 0, 22)
		body.Size = UDim2.new(1, 0, 1, -22)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		button.Activated:Connect(function()
			self:Choose(index)
		end)
		table.insert(self._buttons, button)
	end
	self.title.Text = string.format("SURGE  Lv %d  -  pick one (1 / 2 / 3)", tonumber(payload.Level) or 1)
	self.gui.Enabled = true
end

-- Takes perk `index` of the current offer, once.
function SurgePickerView:Choose(index)
	if not self.gui.Enabled or self._locked or not self._cards then
		return false
	end
	local card = self._cards[index]
	if not card then
		return false
	end
	self._locked = true
	self._onChoose(self._offerId, card.Id)
	return true
end

function SurgePickerView:IsOpen()
	return self.gui.Enabled
end

function SurgePickerView:UpdateTimer(now)
	if not self.gui.Enabled or not self._deadline then
		return
	end
	if now >= self._deadline then
		self.title.Text = "SURGE  -  picking for you..."
	end
end

function SurgePickerView:Hide()
	self.gui.Enabled = false
	self:_clear()
	self._cards = nil
	self._offerId = nil
end

return SurgePickerView
