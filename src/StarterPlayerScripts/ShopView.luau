-- The salvage shop, opened from the lobby kiosk. Display only: it shows the catalogue against the
-- levels and balance the server last sent, and asks the server to buy or equip. It never assumes
-- a request succeeded; the next ProfileSync is the truth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local ShopView = {}
ShopView.__index = ShopView

local ROW_HEIGHT = 74

-- Player-facing text for the reasons ShopService gives.
local REASONS = {
	["insufficient salvage"] = "Not enough salvage",
	["max level"] = "Already at max level",
	["shop closed"] = "The shop is closed during a run",
	["profile not loaded"] = "Your profile is offline; purchases are disabled",
	["not owned"] = "You do not own that yet",
}

function ShopView.new(playerGui, onPurchase, onEquip)
	local self = setmetatable({}, ShopView)
	self._onPurchase = onPurchase
	self._onEquip = onEquip
	self._levels = {}
	self._balance = 0
	self._equipped = ""
	self._rows = {}

	self.gui = UiTheme.screenGui("RicochetShop", playerGui, 30)

	local panel = UiTheme.panel("Panel", self.gui)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.8, 0)
	panel.BackgroundTransparency = 0
	panel.Visible = false
	UiTheme.padding(panel, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 560)
	limit.Parent = panel
	self.panel = panel

	local title = UiTheme.label("Title", panel, "Salvage Shop", UiConfig.Text.Title)
	title.Size = UDim2.new(1, -60, 0, 32)

	self.balanceLabel = UiTheme.label("Balance", panel, "", UiConfig.Text.Hud, UiConfig.Colors.Warning)
	self.balanceLabel.Position = UDim2.new(0, 0, 0, 34)
	self.balanceLabel.Size = UDim2.new(1, 0, 0, 22)

	local close = UiTheme.button("Close", panel, "X")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(UiConfig.MinTouchTarget, UiConfig.MinTouchTarget)
	close.Activated:Connect(function()
		self:Close()
	end)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Items"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, 64)
	list.Size = UDim2.new(1, 0, 1, -94)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromOffset(0, #ShopConfig.Items * (ROW_HEIGHT + 6))
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index, item in ShopConfig.Items do
		self._rows[item.Id] = self:_buildRow(list, index, item)
	end

	self.status = UiTheme.label("Status", panel, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.status.AnchorPoint = Vector2.new(0, 1)
	self.status.Position = UDim2.new(0, 0, 1, 0)
	self.status.Size = UDim2.new(1, 0, 0, 24)

	self:_render()
	return self
end

function ShopView:_buildRow(parent, index, item)
	local row = UiTheme.panel(item.Id, parent)
	row.LayoutOrder = index
	row.BackgroundColor3 = UiConfig.Colors.PanelRaised
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	UiTheme.padding(row, 8)

	local name = UiTheme.label("Name", row, item.Title, UiConfig.Text.Hud)
	name.Size = UDim2.new(1, -130, 0, 22)
	local description = UiTheme.label("Description", row, item.Description, UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	description.Position = UDim2.new(0, 0, 0, 22)
	description.Size = UDim2.new(1, -130, 0, 18)
	description.TextWrapped = true
	local level = UiTheme.label("Level", row, "", UiConfig.Text.Small, UiConfig.Colors.Accent)
	level.Position = UDim2.new(0, 0, 0, 40)
	level.Size = UDim2.new(1, -130, 0, 18)

	local button = UiTheme.button("Action", row, "")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.Size = UDim2.fromOffset(120, UiConfig.MinTouchTarget)
	button.TextSize = UiConfig.Text.Small
	button.Activated:Connect(function()
		self:_activate(item)
	end)

	return { level = level, button = button }
end

function ShopView:_owned(item)
	return self._levels[item.Id] or 0
end

function ShopView:_activate(item)
	local owned = self:_owned(item)
	if item.Kind == "Trail" and owned >= 1 then
		self._onEquip(self._equipped == item.Id and "" or item.Id)
		return
	end
	if owned >= ShopConfig.MaxLevel(item) then
		return
	end
	self.status.Text = "Buying " .. item.Title .. "..."
	self.status.TextColor3 = UiConfig.Colors.TextMuted
	self._onPurchase(item.Id)
end

function ShopView:_render()
	self.balanceLabel.Text = string.format("%d salvage", self._balance)
	for _, item in ShopConfig.Items do
		local row = self._rows[item.Id]
		local owned = self:_owned(item)
		local max = ShopConfig.MaxLevel(item)
		local nextCost = ShopConfig.CostFor(item, owned + 1)

		if item.Kind == "Trail" then
			row.level.Text = owned >= 1 and (self._equipped == item.Id and "Equipped" or "Owned") or "Cosmetic"
			if owned >= 1 then
				row.button.Text = self._equipped == item.Id and "Unequip" or "Equip"
			else
				row.button.Text = string.format("Buy  %d", nextCost)
			end
		else
			row.level.Text = string.format("Level %d / %d", owned, max)
			row.button.Text = nextCost and string.format("Buy  %d", nextCost) or "Maxed"
		end

		local affordable = nextCost == nil or self._balance >= nextCost or (item.Kind == "Trail" and owned >= 1)
		row.button.AutoButtonColor = affordable
		row.button.TextColor3 = affordable and UiConfig.Colors.Text or UiConfig.Colors.TextMuted
	end
end

-- profile is the ProfileSync payload.
function ShopView:SetProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	self._balance = type(profile.Salvage) == "number" and profile.Salvage or 0
	self._levels = type(profile.MetaUpgrades) == "table" and profile.MetaUpgrades or {}
	self._equipped = type(profile.EquippedTrail) == "string" and profile.EquippedTrail or ""
	self:_render()
end

-- payload is a ShopResult: { Ok, Action, ItemId, Level, Reason }.
function ShopView:ShowResult(payload)
	if type(payload) ~= "table" then
		return
	end
	local item = type(payload.ItemId) == "string" and ShopConfig.Get(payload.ItemId) or nil
	local name = item and item.Title or "Item"
	if payload.Action == "Refunded" then
		self.status.Text = name .. " was refunded: that salvage was already spent elsewhere"
		self.status.TextColor3 = UiConfig.Colors.Warning
	elseif payload.Ok then
		self.status.Text = payload.Action == "Equip" and "Trail updated" or (name .. " purchased")
		self.status.TextColor3 = UiConfig.Colors.Health
	else
		self.status.Text = REASONS[payload.Reason] or "That did not go through"
		self.status.TextColor3 = UiConfig.Colors.Danger
	end
end

function ShopView:Open()
	self.status.Text = ""
	self.panel.Visible = true
end

function ShopView:Close()
	self.panel.Visible = false
end

return ShopView
