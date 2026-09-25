-- The lobby shop: a tab per cosmetic kind (trails, base themes, signs, emotes, nameplate titles)
-- and the Store (Robux passes and products). Display only: it shows the catalogue against the
-- levels, balance, account level and passes the server last sent, and asks the server (or
-- Roblox, for Robux) to buy, equip or play. It never assumes a request succeeded; the next
-- ProfileSync is the truth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local ShopView = {}
ShopView.__index = ShopView

local ROW_HEIGHT = 74
-- Tab id -> the cosmetic kind it lists ("Store" lists Robux items).
local TABS = { "Trails", "Themes", "Signs", "Emotes", "Titles", "Store" }
local TAB_KIND = { Trails = "Trail", Themes = "Theme", Signs = "Sign", Emotes = "Emote", Titles = "Nameplate" }

-- Player-facing text for the reasons ShopService gives.
local REASONS = {
	["insufficient salvage"] = "Not enough coins",
	["max level"] = "You already own that",
	["shop closed"] = "The shop is closed during a run",
	["profile not loaded"] = "Your profile is offline; purchases are disabled",
	["not owned"] = "You do not own that yet",
	["not for sale"] = "That one is earned, not sold",
	["requires SupporterPack"] = "That comes with the Supporter Pack",
	["requires ExplorerPass"] = "That comes with the Explorer Pass",
}

local function passTitle(passKey)
	local pass = MonetizationConfig.Passes[passKey]
	return pass and pass.Title or passKey
end

-- onPurchase(itemId), onEquip(itemId, kind), onRobux(kind, id) ("Pass" or "Product"; the client
-- script prompts Roblox's purchase), onEmote(itemId).
function ShopView.new(playerGui, onPurchase, onEquip, onRobux, onEmote)
	local self = setmetatable({}, ShopView)
	self._onPurchase = onPurchase
	self._onEquip = onEquip
	self._onRobux = onRobux or function() end
	self._onEmote = onEmote or function() end
	self._levels = {}
	self._balance = 0
	self._level = 1
	self._worn = {}
	self._passes = {}
	self._rows = {}
	self._tab = TABS[1]

	self.gui = UiTheme.screenGui("RicochetShop", playerGui, 30)

	local panel = UiTheme.panel("Panel", self.gui)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.84, 0)
	panel.BackgroundTransparency = 0
	panel.Visible = false
	UiTheme.padding(panel, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 620)
	limit.Parent = panel
	self.panel = panel

	self.title = UiTheme.heading("Title", panel, "Cosmetics", UiConfig.Text.Title)
	self.title.Size = UDim2.new(1, -60, 0, 32)

	self.balanceLabel = UiTheme.label("Balance", panel, "", UiConfig.Text.Hud, UiConfig.Colors.Warning)
	self.balanceLabel.Position = UDim2.new(0, 0, 0, 34)
	self.balanceLabel.Size = UDim2.new(1, 0, 0, 22)

	local close = UiTheme.button("Close", panel, "X", "Danger")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(UiConfig.MinTouchTarget, UiConfig.MinTouchTarget)
	close.Activated:Connect(function()
		self:Close()
	end)

	self._tabButtons = {}
	for index, tab in TABS do
		local button = UiTheme.button("Tab" .. tab, panel, string.upper(tab))
		button.Position = UDim2.new((index - 1) / #TABS, index > 1 and 3 or 0, 0, 60)
		button.Size = UDim2.new(1 / #TABS, -3, 0, UiConfig.MinTouchTarget)
		button.TextSize = UiConfig.Text.Small - 2
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
		local row = self:_buildRow(list, order, item.Id, item.Title, item.Description, item.Kind, function()
			self:_activate(item)
		end)
		row.item = item
		self._rows[item.Id] = row
	end
	-- Robux items with real ids only; anything left at 0 in MonetizationConfig is never shown.
	for key, pass in MonetizationConfig.Passes do
		if pass.Id > 0 then
			order += 1
			local row = self:_buildRow(list, order, "Pass_" .. key, pass.Title, pass.Description, "Store", function()
				if not self._passes[key] then
					self._onRobux("Pass", pass.Id)
				end
			end)
			row.pass = key
			row.price = pass.Price
			self._rows["Pass_" .. key] = row
		end
	end
	for _, product in MonetizationConfig.Products do
		local offered = product.Id > 0 and (product.Kind ~= "Revive" or FeatureFlags.PaidRevive)
		if offered then
			order += 1
			local row = self:_buildRow(list, order, "Product_" .. product.Key, product.Title, product.Description, "Store", function()
				self._onRobux("Product", product.Id)
			end)
			row.product = product
			row.price = product.Price
			self._rows["Product_" .. product.Key] = row
		end
	end

	self.status = UiTheme.label("Status", panel, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.status.AnchorPoint = Vector2.new(0, 1)
	self.status.Position = UDim2.new(0, 0, 1, 0)
	self.status.Size = UDim2.new(1, 0, 0, 24)

	self:SetTab(TABS[1])
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
	local descriptionLabel = UiTheme.label("Description", row, description or "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
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

-- Shows one tab's rows and hides the rest. "Cosmetics" (the kiosk) opens the first tab.
function ShopView:SetTab(tab)
	if tab == "Cosmetics" then
		tab = TABS[1]
	end
	self._tab = tab
	self.title.Text = tab
	local kind = TAB_KIND[tab]
	local visible = 0
	for _, row in self._rows do
		row.frame.Visible = (kind and row.category == kind) or (tab == "Store" and row.category == "Store")
		if row.frame.Visible then
			visible += 1
		end
	end
	self._list.CanvasSize = UDim2.fromOffset(0, visible * (ROW_HEIGHT + 6))
	for name, button in self._tabButtons do
		button.TextColor3 = name == tab and UiConfig.Colors.Gold or UiConfig.Colors.Text
		local edge = button:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = name == tab and UiConfig.Colors.Gold or UiConfig.Colors.Accent
			edge.Transparency = name == tab and 0 or 0.55
		end
	end
	if tab == "Store" and visible == 0 then
		self.status.Text = "The Store opens soon."
		self.status.TextColor3 = UiConfig.Colors.TextMuted
	end
	self:_render()
end

function ShopView:_owns(item)
	return ShopConfig.Owns(item, self._levels, self._level, function(passKey)
		return self._passes[passKey] == true
	end)
end

function ShopView:_activate(item)
	if self:_owns(item) then
		if item.Kind == "Emote" then
			self._onEmote(item.Id)
		elseif ShopConfig.Equippable[item.Kind] then
			self._onEquip(self._worn[item.Kind] == item.Id and "" or item.Id, item.Kind)
		end
		return
	end
	if ShopConfig.MaxLevel(item) == 0 then
		return -- earned by level or a pass: nothing to buy here
	end
	self.status.Text = "Buying " .. item.Title .. "..."
	self.status.TextColor3 = UiConfig.Colors.TextMuted
	self._onPurchase(item.Id)
end

function ShopView:_render()
	self.balanceLabel.Text = string.format("%d coins", self._balance)
	for _, row in self._rows do
		local item = row.item
		if item then
			local owned = self:_owns(item)
			local worn = self._worn[item.Kind] == item.Id
			local cost = ShopConfig.CostFor(item, 1)
			local action, detail, active
			if owned then
				if item.Kind == "Emote" then
					action, detail = "Play", "Owned"
				else
					action, detail = worn and "Unequip" or "Equip", worn and "Equipped" or "Owned"
				end
				active = true
			elseif item.RequiresPass then
				action, detail, active = "Pass", passTitle(item.RequiresPass), false
			elseif item.UnlockLevel then
				action, detail, active = "Level " .. item.UnlockLevel, "Unlocks by playing", false
			else
				action = string.format("Buy  %d", cost or 0)
				detail = "Cosmetic"
				active = self._balance >= (cost or 0)
			end
			row.level.Text = detail
			row.button.Text = action
			row.button.AutoButtonColor = active
			row.button.TextColor3 = active and UiConfig.Colors.Text or UiConfig.Colors.TextMuted
		elseif row.pass then
			local owned = self._passes[row.pass] == true
			row.level.Text = owned and "Owned" or "Game pass"
			row.button.Text = owned and "Owned" or string.format("%d R$", row.price or 0)
		elseif row.product then
			row.level.Text = "Consumable"
			row.button.Text = string.format("%d R$", row.price or 0)
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
	local progression = type(profile.Progression) == "table" and profile.Progression or {}
	self._level = tonumber(progression.Level) or 1
	local base = type(profile.Base) == "table" and profile.Base or {}
	self._worn = {
		Trail = type(profile.EquippedTrail) == "string" and profile.EquippedTrail or "",
		Theme = type(base.Theme) == "string" and base.Theme or "",
		Sign = type(base.Sign) == "string" and base.Sign or "",
		Nameplate = type(profile.Nameplate) == "string" and profile.Nameplate or "",
	}
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
		self.status.Text = payload.Action == "Equip" and "Updated" or (name .. " purchased")
		self.status.TextColor3 = UiConfig.Colors.Health
	else
		self.status.Text = REASONS[payload.Reason] or "That did not go through"
		self.status.TextColor3 = UiConfig.Colors.Danger
	end
end

-- Opens on `tab` (a cosmetic tab, "Cosmetics" for the first one, or "Store").
function ShopView:Open(tab)
	self.status.Text = ""
	self:SetTab((tab == "Cosmetics" or table.find(TABS, tab)) and tab or self._tab)
	self.panel.Visible = true
end

function ShopView:Close()
	self.panel.Visible = false
end

return ShopView
