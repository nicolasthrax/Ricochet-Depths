-- The home base panel: the 4x4 grid, the twelve buildings grouped by role with their level, the
-- next price and the Hearth level it needs, the Salvage Yard's claim, and the players on this
-- server to visit and cheer. Tap a building, then a tile, to build it there or move it there.
-- Display only: every request goes to the server, and the next BaseSync is the truth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage:WaitForChild("BaseConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local BaseView = {}
BaseView.__index = BaseView

local ROLES = { "Heart", "Power", "Economy" }
local ROLE_TITLES = { Heart = "HEART", Power = "POWER  (run bonuses)", Economy = "ECONOMY" }
local CARD_HEIGHT = 70
local TILE_GAP = 4

-- handlers: upgrade(buildingId, tile|nil), move(buildingId, tile), claim(), visit(userId|nil),
-- cheer(userId), feature(userId) (optional: private server owners only).
function BaseView.new(playerGui, handlers)
	local self = setmetatable({}, BaseView)
	self._handlers = handlers or {}
	self._state = nil
	self._selected = nil
	self.modal = UiTheme.modal("RicochetBase", playerGui, "YOUR OUTPOST", Vector2.new(820, 600))
	local content = self.modal.content

	-- Top line: balance and the Hearth.
	self.header = UiTheme.label("Header", content, "", UiConfig.Text.Hud, UiConfig.Colors.Gold)
	self.header.Size = UDim2.new(1, 0, 0, 22)

	-- The Salvage Yard: what is waiting, how full it is, and the claim.
	local yard = Instance.new("Frame")
	yard.Name = "Yard"
	yard.BackgroundTransparency = 1
	yard.Position = UDim2.new(0, 0, 0, 26)
	yard.Size = UDim2.new(1, 0, 0, UiConfig.MinTouchTarget)
	yard.Parent = content
	self.yardLabel = UiTheme.label("YardLabel", yard, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.yardLabel.Size = UDim2.new(1, -150, 0, 20)
	local track, fill = UiTheme.bar("YardBar", yard, UiConfig.Colors.Gold)
	track.Position = UDim2.new(0, 0, 0, 24)
	track.Size = UDim2.new(1, -150, 0, 10)
	self.yardFill = fill
	self.claimButton = UiTheme.button("Claim", yard, "CLAIM", "Primary")
	self.claimButton.AnchorPoint = Vector2.new(1, 0)
	self.claimButton.Position = UDim2.new(1, 0, 0, 0)
	self.claimButton.Size = UDim2.fromOffset(140, UiConfig.MinTouchTarget)
	self.claimButton.TextSize = UiConfig.Text.Small + 2
	self.claimButton.Activated:Connect(function()
		if self._handlers.claim then
			self._handlers.claim()
		end
	end)

	-- Left: the grid. Right: the building list. Bottom: hint and the visit list.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 0, 0, 82)
	body.Size = UDim2.new(1, 0, 1, -82 - 118)
	body.Parent = content

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(0.42, -8, 1, 0)
	grid.Parent = body
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(1 / BaseConfig.GridSize, -TILE_GAP, 1 / BaseConfig.GridSize, -TILE_GAP)
	gridLayout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = grid
	self.tiles = {}
	for tile = 1, BaseConfig.Tiles do
		local button = UiTheme.button("Tile" .. tile, grid, "")
		button.LayoutOrder = tile
		button.TextSize = UiConfig.Text.Small - 2
		button.TextWrapped = true
		button.Activated:Connect(function()
			self:TapTile(tile)
		end)
		self.tiles[tile] = button
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "Buildings"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0.42, 8, 0, 0)
	list.Size = UDim2.new(0.58, -8, 1, 0)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = body
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	self.cards = {}
	local order = 0
	for _, role in ROLES do
		order += 1
		local heading = UiTheme.heading(role .. "Heading", list, ROLE_TITLES[role], UiConfig.Text.Small + 2, UiConfig.Colors.Accent)
		heading.LayoutOrder = order
		heading.Size = UDim2.new(1, -8, 0, 22)
		for _, building in BaseConfig.Buildings do
			if building.Role == role then
				order += 1
				self.cards[building.Id] = self:_buildCard(list, order, building)
			end
		end
	end

	self.hint = UiTheme.label("Hint", content, "", UiConfig.Text.Small, UiConfig.Colors.Accent)
	self.hint.AnchorPoint = Vector2.new(0, 1)
	self.hint.Position = UDim2.new(0, 0, 1, -96)
	self.hint.Size = UDim2.new(1, 0, 0, 20)
	self.hint.TextWrapped = true

	-- Players on this server: visit their plot, cheer their base.
	local visits = Instance.new("ScrollingFrame")
	visits.Name = "Visits"
	visits.BackgroundTransparency = 1
	visits.BorderSizePixel = 0
	visits.AnchorPoint = Vector2.new(0, 1)
	visits.Position = UDim2.new(0, 0, 1, 0)
	visits.Size = UDim2.new(1, 0, 0, 90)
	visits.CanvasSize = UDim2.new()
	visits.AutomaticCanvasSize = Enum.AutomaticSize.X
	visits.ScrollBarThickness = 4
	visits.ScrollingDirection = Enum.ScrollingDirection.X
	visits.Parent = content
	local visitLayout = Instance.new("UIListLayout")
	visitLayout.FillDirection = Enum.FillDirection.Horizontal
	visitLayout.Padding = UDim.new(0, 6)
	visitLayout.SortOrder = Enum.SortOrder.LayoutOrder
	visitLayout.Parent = visits
	self.visits = visits
	self._visitRows = {}

	local mine = UiTheme.button("MyPlot", visits, "MY PLOT", "Primary")
	mine.LayoutOrder = 0
	mine.Size = UDim2.fromOffset(110, 84)
	mine.TextSize = UiConfig.Text.Small + 2
	mine.Activated:Connect(function()
		if self._handlers.visit then
			self._handlers.visit(nil)
		end
	end)
	self.myPlotButton = mine
	return self
end

function BaseView:_buildCard(parent, order, building)
	local card = UiTheme.button(building.Id, parent, "")
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -8, 0, CARD_HEIGHT)
	card.AutoButtonColor = true
	UiTheme.padding(card, 8)
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.new(0, 6, 1, 0)
	swatch.BackgroundColor3 = building.Color
	swatch.BorderSizePixel = 0
	swatch.Parent = card
	local title = UiTheme.label("Title", card, building.Title, UiConfig.Text.Hud)
	title.Font = UiConfig.FontBold
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Size = UDim2.new(1, -140, 0, 22)
	local label = UiTheme.label("Label", card, building.Label, UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	label.Position = UDim2.new(0, 12, 0, 22)
	label.Size = UDim2.new(1, -140, 0, 18)
	local level = UiTheme.label("Level", card, "", UiConfig.Text.Small, UiConfig.Colors.Accent)
	level.Position = UDim2.new(0, 12, 0, 40)
	level.Size = UDim2.new(1, -140, 0, 18)
	local action = UiTheme.button("Action", card, "", "Primary")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, 0, 0.5, 0)
	action.Size = UDim2.fromOffset(124, UiConfig.MinTouchTarget)
	action.TextSize = UiConfig.Text.Small
	card.Activated:Connect(function()
		self:SelectBuilding(building.Id)
	end)
	action.Activated:Connect(function()
		self:_upgrade(building.Id)
	end)
	return { frame = card, level = level, action = action }
end

-- What the next level of a building costs and whether it can be bought now:
-- returns cost|nil, needs (Hearth level)|nil, and a status word.
function BaseView:_nextFor(building)
	local state = self._state
	local levels = state and state.Levels or {}
	local current = levels[building.Id] or building.StartLevel
	local nextLevel = current + 1
	local cost = BaseConfig.CostFor(building, nextLevel)
	if not cost then
		return nil, nil, "Max"
	end
	local needs = BaseConfig.HearthNeeded(building, nextLevel)
	if needs > (state and state.Hearth or 1) then
		return cost, needs, "Locked"
	end
	if (state and state.Balance or 0) < cost then
		return cost, needs, "Short"
	end
	return cost, needs, "Ready"
end

function BaseView:_upgrade(buildingId)
	local building = BaseConfig.Get(buildingId)
	local _, _, status = self:_nextFor(building)
	if status ~= "Ready" or not self._handlers.upgrade then
		self:SelectBuilding(buildingId)
		return
	end
	local built = self._state and (self._state.Levels[buildingId] or 0) > 0
	-- A new building goes on the selected empty tile if there is one, else the first free one.
	self._handlers.upgrade(buildingId, not built and self._pendingTile or nil)
	self._pendingTile = nil
end

-- Picks a building; the next tile tap builds or moves it there.
function BaseView:SelectBuilding(buildingId)
	self._selected = self._selected ~= buildingId and buildingId or nil
	self:_render()
end

-- A tile tap: with a building picked, build it here (if new) or move it here; without one, pick
-- whatever stands on the tile.
function BaseView:TapTile(tile)
	local layout = self._state and self._state.Layout or {}
	local selected = self._selected
	if selected then
		local built = self._state and (self._state.Levels[selected] or 0) > 0
		if built then
			if layout[selected] ~= tile and self._handlers.move then
				self._handlers.move(selected, tile)
			end
		elseif not BaseConfig.BuildingAt(layout, tile) then
			self._pendingTile = tile
			self:_upgrade(selected)
		end
		self._selected = nil
		self:_render()
		return
	end
	local occupant = BaseConfig.BuildingAt(layout, tile)
	if occupant then
		self:SelectBuilding(occupant)
	end
end

function BaseView:_render()
	local state = self._state
	if not state then
		return
	end
	self.header.Text = string.format("%d coins   -   Camp Hearth Lv%d", state.Balance or 0, state.Hearth or 1)

	local offline = state.Offline or {}
	if (offline.PerHour or 0) > 0 then
		self.yardLabel.Text = string.format("Salvage Yard: %d coins waiting  (%d/h, holds %dh)", offline.Coins or 0,
			offline.PerHour, offline.CapHours or 8)
	else
		self.yardLabel.Text = "Build a Salvage Yard to earn coins while you are away."
	end
	self.yardFill.Size = UDim2.fromScale(math.clamp(tonumber(offline.Fill) or 0, 0, 1), 1)
	self.claimButton.Text = (offline.Coins or 0) > 0 and string.format("CLAIM %d", offline.Coins) or "CLAIM"
	self.claimButton.AutoButtonColor = (offline.Coins or 0) > 0

	local layout = state.Layout or {}
	for tile, button in self.tiles do
		local occupant = BaseConfig.BuildingAt(layout, tile)
		local building = occupant and BaseConfig.Get(occupant)
		button.Text = building and string.format("%s\n%d", building.Title, state.Levels[occupant] or 0) or "+"
		button.BackgroundColor3 = building and building.Color:Lerp(UiConfig.Colors.PanelRaised, 0.55) or UiConfig.Colors.PanelRaised
		local edge = button:FindFirstChildOfClass("UIStroke")
		if edge then
			local picked = occupant ~= nil and occupant == self._selected
			edge.Color = picked and UiConfig.Colors.Gold or UiConfig.Colors.Accent
			edge.Transparency = picked and 0 or 0.55
		end
	end

	for _, building in BaseConfig.Buildings do
		local card = self.cards[building.Id]
		local level = state.Levels[building.Id] or 0
		local cost, needs, status = self:_nextFor(building)
		card.level.Text = string.format("Lv %d / %d", level, BaseConfig.MaxLevel(building))
		if status == "Max" then
			card.action.Text = "MAXED"
		elseif status == "Locked" then
			card.action.Text = string.format("HEARTH %d", needs)
		else
			card.action.Text = string.format("%s  %d", level == 0 and "BUILD" or "UPGRADE", cost)
		end
		local ready = status == "Ready"
		card.action.AutoButtonColor = ready
		card.action.BackgroundColor3 = ready and UiConfig.Colors.PrimaryButton or UiConfig.Colors.PanelRaised
		card.action.TextColor3 = ready and UiConfig.Colors.PrimaryText or UiConfig.Colors.TextMuted
		local edge = card.frame:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = self._selected == building.Id and UiConfig.Colors.Gold or UiConfig.Colors.Accent
			edge.Transparency = self._selected == building.Id and 0 or 0.55
		end
	end

	local selected = self._selected and BaseConfig.Get(self._selected)
	if selected then
		local built = (state.Levels[selected.Id] or 0) > 0
		self.hint.Text = built and string.format("Tap a tile to move the %s there.", selected.Title)
			or string.format("Tap an empty tile to build the %s there.", selected.Title)
	elseif state.NextBuild then
		self.hint.Text = string.format("Next: %s Lv%d for %d coins. Tap a building, then a tile.", state.NextBuild.Title,
			state.NextBuild.Level, state.NextBuild.Cost)
	else
		self.hint.Text = "Tap a building, then a tile, to build or move it."
	end
end

-- state is the BaseSync payload.
function BaseView:SetState(state)
	if type(state) ~= "table" then
		return
	end
	self._state = state
	self:_render()
end

-- The other players on this server: { { UserId, Name } }.
function BaseView:SetPlayers(players)
	for _, row in self._visitRows do
		row:Destroy()
	end
	table.clear(self._visitRows)
	for index, entry in type(players) == "table" and players or {} do
		local row = UiTheme.panel("Visit" .. entry.UserId, self.visits)
		row.LayoutOrder = index
		row.BackgroundColor3 = UiConfig.Colors.PanelRaised
		row.BackgroundTransparency = 0
		row.Size = UDim2.fromOffset(170, 84)
		UiTheme.padding(row, 6)
		local name = UiTheme.label("Name", row, tostring(entry.Name), UiConfig.Text.Small + 2)
		name.Font = UiConfig.FontBold
		name.Size = UDim2.new(1, 0, 0, 20)
		local visit = UiTheme.button("Visit", row, "VISIT")
		visit.AnchorPoint = Vector2.new(0, 1)
		visit.Position = UDim2.new(0, 0, 1, 0)
		visit.Size = UDim2.new(0.5, -3, 0, UiConfig.MinTouchTarget)
		visit.TextSize = UiConfig.Text.Small
		visit.Activated:Connect(function()
			if self._handlers.visit then
				self._handlers.visit(entry.UserId)
			end
		end)
		local cheer = UiTheme.button("Cheer", row, "CHEER", "Primary")
		cheer.AnchorPoint = Vector2.new(1, 1)
		cheer.Position = UDim2.new(1, 0, 1, 0)
		cheer.Size = UDim2.new(0.5, -3, 0, UiConfig.MinTouchTarget)
		cheer.TextSize = UiConfig.Text.Small
		cheer.Activated:Connect(function()
			if self._handlers.cheer then
				self._handlers.cheer(entry.UserId)
			end
		end)
		if self._handlers.feature then
			-- A text link under the name: only a private server's owner sees it.
			local feature = Instance.new("TextButton")
			feature.Name = "Feature"
			feature.BackgroundTransparency = 1
			feature.Font = UiConfig.FontBold
			feature.Text = "FEATURE IN HALL"
			feature.TextColor3 = UiConfig.Colors.Gold
			feature.TextSize = UiConfig.Text.Small - 2
			feature.TextXAlignment = Enum.TextXAlignment.Left
			feature.Position = UDim2.new(0, 0, 0, 20)
			feature.Size = UDim2.new(1, 0, 0, 16)
			feature.Parent = row
			feature.Activated:Connect(function()
				self._handlers.feature(entry.UserId)
			end)
		end
		table.insert(self._visitRows, row)
	end
end

function BaseView:Open()
	self.modal.Open()
end

function BaseView:Close()
	self.modal.Close()
end

function BaseView:IsOpen()
	return self.modal.IsOpen()
end

return BaseView
