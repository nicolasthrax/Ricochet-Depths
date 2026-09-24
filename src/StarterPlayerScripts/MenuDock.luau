-- The lobby's side menu: Rigs, Pact, Journal, Daily, Quests, Codes and Invite, in two columns on
-- the right edge where a thumb can reach them. A red dot marks anything waiting to be claimed.
-- Lobby only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local MenuDock = {}
MenuDock.__index = MenuDock

local BUTTON_WIDTH = 108

local ENTRIES = {
	{ Id = "Rigs", Text = "RIGS", Flag = "Loadouts" },
	{ Id = "Pact", Text = "PACT", Flag = "Loadouts" },
	{ Id = "Journal", Text = "JOURNAL", Flag = "Loadouts" },
	{ Id = "Daily", Text = "DAILY", Flag = "DailyRewards" },
	{ Id = "Quests", Text = "QUESTS", Flag = "DailyRewards" },
	{ Id = "Codes", Text = "CODES", Flag = "DailyRewards" },
	{ Id = "Invite", Text = "INVITE" },
}

-- handlers: Id -> function, called when that button is pressed.
function MenuDock.new(playerGui, handlers)
	local self = setmetatable({}, MenuDock)
	self.gui = UiTheme.screenGui("RicochetMenu", playerGui, 12)

	local dock = Instance.new("Frame")
	dock.Name = "Dock"
	dock.BackgroundTransparency = 1
	dock.AnchorPoint = Vector2.new(1, 0.5)
	dock.Position = UDim2.new(1, -16, 0.5, -24)
	-- Two columns keep seven buttons short enough for a phone held sideways.
	local rows = math.ceil(#ENTRIES / 2)
	dock.Size = UDim2.fromOffset(2 * BUTTON_WIDTH + 8, rows * (UiConfig.MinTouchTarget + 8))
	dock.Parent = self.gui
	self.dock = dock

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(BUTTON_WIDTH, UiConfig.MinTouchTarget)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dock

	self.buttons, self.dots = {}, {}
	for index, entry in ENTRIES do
		if entry.Flag and not FeatureFlags.IsEnabled(entry.Flag) then
			continue
		end
		local button = UiTheme.button(entry.Id .. "Button", dock, entry.Text)
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(BUTTON_WIDTH, UiConfig.MinTouchTarget)
		button.TextSize = UiConfig.Text.Hud
		button.Activated:Connect(function()
			local handler = handlers and handlers[entry.Id]
			if handler then
				handler()
			end
		end)
		self.buttons[entry.Id] = button
		self.dots[entry.Id] = UiTheme.dot("Dot", button)
	end
	return self
end

function MenuDock:SetVisible(visible)
	self.dock.Visible = visible
end

-- Shows or hides the claim dot on the Journal.
function MenuDock:SetJournalClaimable(ready)
	if self.dots.Journal then
		self.dots.Journal.Visible = ready == true
	end
end

-- Shows or hides the claim dot on Daily and Quests.
function MenuDock:SetClaimable(dailyReady, questReady)
	if self.dots.Daily then
		self.dots.Daily.Visible = dailyReady == true
	end
	if self.dots.Quests then
		self.dots.Quests.Visible = questReady == true
	end
end

return MenuDock
