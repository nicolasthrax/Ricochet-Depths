-- The lobby's side menu: a slim rail on the right edge where a thumb can reach it. The rail holds
-- what a player reaches for before every run or every day (Base, Rigs, Pact, Daily, Quests); the rest
-- (Journal, Codes, Invite) sit behind MORE, which pops out beside it. A red dot marks anything
-- waiting to be claimed, and MORE shows a dot when anything behind it has one. Lobby only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local MenuDock = {}
MenuDock.__index = MenuDock

local BUTTON_WIDTH = 104
local GAP = 6
-- See-through enough that the lobby shows behind the rail, so it reads as a quiet sidebar
-- rather than a wall of boxes.
local BUTTON_TRANSPARENCY = 0.3

-- Group "Rail" is always shown; "More" lives in the pop-out.
local ENTRIES = {
	{ Id = "Base", Text = "BASE", Flag = "BaseBuilding", Group = "Rail" },
	{ Id = "Rigs", Text = "RIGS", Flag = "Loadouts", Group = "Rail" },
	{ Id = "Pact", Text = "PACT", Flag = "Loadouts", Group = "Rail" },
	{ Id = "Daily", Text = "DAILY", Flag = "DailyRewards", Group = "Rail" },
	{ Id = "Quests", Text = "QUESTS", Flag = "DailyRewards", Group = "Rail" },
	{ Id = "Journal", Text = "JOURNAL", Flag = "Loadouts", Group = "More" },
	{ Id = "Codes", Text = "CODES", Flag = "DailyRewards", Group = "More" },
	{ Id = "Invite", Text = "INVITE", Group = "More" },
}

local function column(name, parent, count)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(BUTTON_WIDTH, count * UiConfig.MinTouchTarget + math.max(count - 1, 0) * GAP)
	frame.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

local function menuButton(name, parent, text, order)
	local button = UiTheme.button(name, parent, text)
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(BUTTON_WIDTH, UiConfig.MinTouchTarget)
	button.TextSize = UiConfig.Text.Small + 2
	button.BackgroundTransparency = BUTTON_TRANSPARENCY
	return button
end

-- handlers: Id -> function, called when that button is pressed.
function MenuDock.new(playerGui, handlers)
	local self = setmetatable({}, MenuDock)
	self.gui = UiTheme.screenGui("RicochetMenu", playerGui, 12)

	local enabled = { Rail = {}, More = {} }
	for _, entry in ENTRIES do
		if not entry.Flag or FeatureFlags.IsEnabled(entry.Flag) then
			table.insert(enabled[entry.Group], entry)
		end
	end
	local hasMore = #enabled.More > 0
	local railCount = #enabled.Rail + (hasMore and 1 or 0)

	local dock = column("Dock", self.gui, railCount)
	dock.AnchorPoint = Vector2.new(1, 0.5)
	dock.Position = UDim2.new(1, -16, 0.5, 0)
	self.dock = dock

	-- The pop-out opens to the left of the rail, its bottom level with MORE. It sits outside the
	-- rail's own list, so the rail's layout never moves it.
	local more = column("More", self.gui, #enabled.More)
	more.AnchorPoint = Vector2.new(1, 1)
	more.Visible = false
	self.more = more
	self._moreIds = {}

	self.buttons, self.dots = {}, {}
	local function add(entry, parent, order)
		local button = menuButton(entry.Id .. "Button", parent, entry.Text, order)
		button.Activated:Connect(function()
			self:SetMoreOpen(false)
			local handler = handlers and handlers[entry.Id]
			if handler then
				handler()
			end
		end)
		self.buttons[entry.Id] = button
		self.dots[entry.Id] = UiTheme.dot("Dot", button)
	end
	for order, entry in enabled.Rail do
		add(entry, dock, order)
	end
	for order, entry in enabled.More do
		add(entry, more, order)
		table.insert(self._moreIds, entry.Id)
	end

	if hasMore then
		local toggle = menuButton("MoreButton", dock, "MORE", #enabled.Rail + 1)
		toggle.Activated:Connect(function()
			self:SetMoreOpen(not self:IsMoreOpen())
		end)
		self.moreButton = toggle
		self.moreDot = UiTheme.dot("Dot", toggle)
	end
	self:_placeMore()
	return self
end

-- Keeps the pop-out beside the rail, bottom-aligned with the MORE button.
function MenuDock:_placeMore()
	local height = self.dock.Size.Y.Offset
	self.more.Position = UDim2.new(1, -16 - BUTTON_WIDTH - GAP, 0.5, height / 2)
end

function MenuDock:SetMoreOpen(open)
	-- Only while the rail itself is showing: never pop out over a run.
	self.more.Visible = open == true and self.dock.Visible ~= false
	if self.moreButton then
		self.moreButton.Text = self.more.Visible and "CLOSE" or "MORE"
	end
end

function MenuDock:IsMoreOpen()
	return self.more.Visible == true
end

function MenuDock:SetVisible(visible)
	self.dock.Visible = visible
	if not visible then
		self:SetMoreOpen(false)
	end
end

-- MORE carries a dot whenever something behind it has one, so a claim is never hidden.
function MenuDock:_refreshMoreDot()
	if not self.moreDot then
		return
	end
	local any = false
	for _, id in self._moreIds do
		if self.dots[id].Visible then
			any = true
		end
	end
	self.moreDot.Visible = any
end

-- Shows or hides the claim dot on the Journal.
function MenuDock:SetJournalClaimable(ready)
	if self.dots.Journal then
		self.dots.Journal.Visible = ready == true
	end
	self:_refreshMoreDot()
end

-- Shows or hides the claim dot on Daily and Quests.
function MenuDock:SetClaimable(dailyReady, questReady)
	if self.dots.Daily then
		self.dots.Daily.Visible = dailyReady == true
	end
	if self.dots.Quests then
		self.dots.Quests.Visible = questReady == true
	end
	self:_refreshMoreDot()
end

return MenuDock
