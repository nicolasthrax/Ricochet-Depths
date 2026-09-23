-- The lobby shop, in three tabs: the Armory (permanent upgrades), Cosmetics (trails) and the
-- Store (Robux passes and coin packs). Display only: it shows the catalogue against the levels,
-- balance and passes the server last sent, and asks the server (or Roblox, for Robux) to buy.
-- It never assumes a request succeeded; the next ProfileSync is the truth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local ShopView = {}
ShopView.__index = ShopView

local ROW_HEIGHT = 74
local TABS = { "Armory", "Cosmetics", "Store" }

-- Player-facing text for the reasons ShopService gives.
local REASONS = {
	["insufficient salvage"] = "Not enough coins",
	["max level"] = "Already at max level",
	["shop closed"] = "The shop is closed during a run",
	["profile not loaded"] = "Your profile is offline; purchases are disabled",
	["not owned"] = "You do not own that yet",
	["requires VIP"] = "The Gold trail is for VIP pass holders",
}

-- onRobux(kind, id): kind is "Pass" or "Product"; the client script prompts Roblox's purchase.
function ShopView.new(playerGui, onPurchase, onEquip, onRobux)
	local self = setmetatable({}, ShopView)
	self._onPurchase = onPurchase
	self._onEquip = onEquip
	self._onRobux = onRobux or function() end
	self._levels = {}
	self._balance = 0
	self._equipped = ""
	self._passes = {}
	self._rows = {}
	self._tab = "Armory"

	self.gui = UiTheme.screenGui("RicochetShop", playerGui, 30)

	local panel = UiTheme.panel("Panel", self.gui)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.84, 0)
	panel.BackgroundTransparency = 0
	panel.Visible = false
	UiTheme.padding(panel, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 620)
	limit.Parent = panel
	self.panel = panel

	self.title = UiTheme.label("Title", panel, "Armory", UiConfig.Text.Title)
	self.title.Size = UDim2.new(1, -60, 0, 32)

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

	-- Tab buttons.
	self._tabButtons = {}
	for index, tab in TABS do
		local button = UiTheme.button("Tab" .. tab, panel, tab)
		button.Position = UDim2.new((index - 1) / #TABS, index > 1 and 4 or 0, 0, 60)
		button.Size = UDim2.new(1 / #TABS, -4, 0, UiConfig.MinTouchTarget)
		button.TextSize = UiConfig.Text.Small
		button.Activated:Connect(function()
			self:SetTab(tab)
		end)
		self._tabButtons[tab] = button
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "Items"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, 60 + UiConfig.MinTouchTarget + 8)
	list.Size = UDim2.new(1, 0, 1, -(60 + UiConfig.MinTouchTarget + 8 + 30))
	list.ScrollBarThickness = 6
	list.Parent = panel
	self._list = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local order = 0
	for _, item in ShopConfig.Items do
		order += 1
		self._rows[item.Id] = self:_buildRow(list, order, item.Id, item.Title, item.Description, item.Category, function()
			self:_activate(item)
		end)
	end
	-- Robux items with real ids only; anything left at 0 in MonetizationConfig is never shown.
	for key, pass in MonetizationConfig.Passes do
		if pass.Id > 0 then
			order += 1
			self._rows["Pass_" .. key] = self:_buildRow(list, order, "Pass_" .. key, pass.Title, pass.Description, "Store", function()
				if not self._passes[key] then
					self._onRobux("Pass", pass.Id)
				end
			end)
			self._rows["Pass_" .. key].pass = key
		end
	end
	for _, product in MonetizationConfig.Products do
		if product.Id > 0 then
			order += 1
			self._rows["Product_" .. product.Key] = self:_buildRow(list, order, "Product_" .. product.Key, product.Title,
				"Coins, added to your balance straight away.", "Store", function()
					self._onRobux("Product", product.Id)
				end)
		end
	end

	self.status = UiTheme.label("Status", panel, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.status.AnchorPoint = Vector2.new(0, 1)
	self.status.Position = UDim2.new(0, 0, 1, 0)
	self.status.Size = UDim2.new(1, 0, 0, 24)

	self:SetTab("Armory")
	return self
end

function ShopView:_buildRow(parent, index, name, title, description, category, onActivate)
	local row = UiTheme.panel(name, parent)
	row.LayoutOrder = index
	row.BackgroundColor3 = UiConfig.Colors.PanelRaised
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	UiTheme.padding(row, 8)

	local nameLabel = UiTheme.label("Name", row, title, UiConfig.Text.Hud)
	nameLabel.Size = UDim2.new(1, -130, 0, 22)
	local descriptionLabel = UiTheme.label("Description", row, description, UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	descriptionLabel.Position = UDim2.new(0, 0, 0, 22)
	descriptionLabel.Size = UDim2.new(1, -130, 0, 18)
	descriptionLabel.TextWrapped = true
	local level = UiTheme.label("Level", row, "", UiConfig.Text.Small, UiConfig.Colors.Accent)
	level.Position = UDim2.new(0, 0, 0, 40)
	level.Size = UDim2.new(1, -130, 0, 18)

	local button = UiTheme.button("Action", row, "")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.Size = UDim2.fromOffset(120, UiConfig.MinTouchTarget)
	button.TextSize = UiConfig.Text.Small
	button.Activated:Connect(onActivate)

	return { frame = row, level = level, button = button, category = category }
end

-- Shows one tab's rows and hides the rest.
function ShopView:SetTab(tab)
	self._tab = tab
	self.title.Text = tab
	local visible = 0
	for _, row in self._rows do
		row.frame.Visible = row.category == tab
		if row.frame.Visible then
			visible += 1
		end
	end
	self._list.CanvasSize = UDim2.fromOffset(0, visible * (ROW_HEIGHT + 6))
	for name, button in self._tabButtons do
		button.TextColor3 = name == tab and UiConfig.Colors.Accent or UiConfig.Colors.Text
	end
	if tab == "Store" and visible == 0 then
		self.status.Text = "The Store opens soon."
		self.status.TextColor3 = UiConfig.Colors.TextMuted
	end
	self:_render()
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
	self.balanceLabel.Text = string.format("%d coins", self._balance)
	for _, item in ShopConfig.Items do
		local row = self._rows[item.Id]
		local owned = self:_owned(item)
		local max = ShopConfig.MaxLevel(item)
		local nextCost = ShopConfig.CostFor(item, owned + 1)
		local locked = item.RequiresPass and not self._passes[item.RequiresPass]

		if item.Kind == "Trail" then
			row.level.Text = owned >= 1 and (self._equipped == item.Id and "Equipped" or "Owned")
				or (locked and (item.RequiresPass .. " only") or "Cosmetic")
			if owned >= 1 then
				row.button.Text = self._equipped == item.Id and "Unequip" or "Equip"
			elseif locked then
				row.button.Text = "Locked"
			else
				row.button.Text = string.format("Buy  %d", nextCost)
			end
		else
			row.level.Text = string.format("Level %d / %d", owned, max)
			row.button.Text = nextCost and string.format("Buy  %d", nextCost) or "Maxed"
		end

		local affordable = not locked and (nextCost == nil or self._balance >= nextCost or (item.Kind == "Trail" and owned >= 1))
		row.button.AutoButtonColor = affordable
		row.button.TextColor3 = affordable and UiConfig.Colors.Text or UiConfig.Colors.TextMuted
	end
	for _, row in self._rows do
		if row.pass then
			local owned = self._passes[row.pass] == true
			row.level.Text = owned and "Owned" or "Game pass"
			row.button.Text = owned and "Owned" or "Buy (Robux)"
		elseif row.category == "Store" then
			row.level.Text = "Coin pack"
			row.button.Text = "Buy (Robux)"
		end
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
	self._passes = {}
	for _, key in type(profile.Passes) == "table" and profile.Passes or {} do
		self._passes[key] = true
	end
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
		self.status.Text = name .. " was refunded: those coins were already spent elsewhere"
		self.status.TextColor3 = UiConfig.Colors.Warning
	elseif payload.Ok then
		self.status.Text = payload.Action == "Equip" and "Trail updated" or (name .. " purchased")
		self.status.TextColor3 = UiConfig.Colors.Health
	else
		self.status.Text = REASONS[payload.Reason] or "That did not go through"
		self.status.TextColor3 = UiConfig.Colors.Danger
	end
end

-- Opens on `tab` (Armory, Cosmetics or Store); the kiosk the player used decides.
function ShopView:Open(tab)
	self.status.Text = ""
	self:SetTab(table.find(TABS, tab) and tab or self._tab)
	self.panel.Visible = true
end

function ShopView:Close()
	self.panel.Visible = false
end

return ShopView
