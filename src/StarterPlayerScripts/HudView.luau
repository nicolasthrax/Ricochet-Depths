-- Health, run progress, objective and active upgrades. Display only: it renders whatever the
-- server last sent and never computes game state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local HudView = {}
HudView.__index = HudView

function HudView.new(playerGui)
	local self = setmetatable({}, HudView)

	self.gui = UiTheme.screenGui("RicochetHud", playerGui, 10)

	local health = UiTheme.panel("HealthPanel", self.gui)
	health.Position = UDim2.new(0, 16, 1, -92)
	health.Size = UDim2.fromOffset(260, 66)
	UiTheme.padding(health, 10)
	self.healthLabel = UiTheme.label("HealthLabel", health, "100 / 100", UiConfig.Text.Hud)
	self.healthLabel.Size = UDim2.new(1, 0, 0, 20)
	local track, fill = UiTheme.bar("HealthBar", health, UiConfig.Colors.Health)
	track.Position = UDim2.new(0, 0, 0, 26)
	track.Size = UDim2.new(1, 0, 0, 14)
	self.healthFill = fill

	local progress = UiTheme.panel("ProgressPanel", self.gui)
	progress.Position = UDim2.new(0.5, 0, 0, 12)
	progress.AnchorPoint = Vector2.new(0.5, 0)
	progress.Size = UDim2.fromOffset(300, 62)
	UiTheme.padding(progress, 10)
	self.roomLabel = UiTheme.label("RoomLabel", progress, "", UiConfig.Text.Hud)
	self.roomLabel.Size = UDim2.new(1, 0, 0, 22)
	self.roomLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.objectiveLabel = UiTheme.label("ObjectiveLabel", progress, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.objectiveLabel.Position = UDim2.new(0, 0, 0, 22)
	self.objectiveLabel.Size = UDim2.new(1, 0, 0, 20)
	self.objectiveLabel.TextXAlignment = Enum.TextXAlignment.Center

	local upgrades = UiTheme.panel("UpgradePanel", self.gui)
	upgrades.Position = UDim2.new(1, -16, 0, 12)
	upgrades.AnchorPoint = Vector2.new(1, 0)
	upgrades.Size = UDim2.fromOffset(210, 32)
	UiTheme.padding(upgrades, 8)
	self.upgradePanel = upgrades

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 2)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = upgrades
	self.upgradeEntries = {}

	local banner = UiTheme.panel("Banner", self.gui)
	banner.Position = UDim2.new(0.5, 0, 0.32, 0)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Size = UDim2.fromOffset(420, 56)
	banner.Visible = false
	UiTheme.padding(banner, 8)
	self.banner = banner
	self.bannerLabel = UiTheme.label("BannerLabel", banner, "", UiConfig.Text.Title)
	self.bannerLabel.Size = UDim2.fromScale(1, 1)
	self.bannerLabel.TextXAlignment = Enum.TextXAlignment.Center

	return self
end

function HudView:UpdatePlayer(snapshot)
	if not snapshot then
		return
	end
	local maxHealth = math.max(snapshot.MaxHealth, 1)
	local fraction = math.clamp(snapshot.Health / maxHealth, 0, 1)
	self.healthLabel.Text = string.format("%d / %d", math.floor(snapshot.Health + 0.5), math.floor(maxHealth + 0.5))
	self.healthFill.Size = UDim2.fromScale(fraction, 1)
	self.healthFill.BackgroundColor3 = fraction <= UiConfig.LowHealthFraction and UiConfig.Colors.HealthLow
		or UiConfig.Colors.Health

	if not snapshot.Alive then
		self.healthLabel.Text = "DOWN"
	end

	self:_renderUpgrades(snapshot.Upgrades or {})
end

function HudView:_renderUpgrades(upgrades)
	for _, entry in self.upgradeEntries do
		entry:Destroy()
	end
	table.clear(self.upgradeEntries)

	local header = UiTheme.label("Header", self.upgradePanel, "Upgrades", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	header.Size = UDim2.new(1, 0, 0, 16)
	header.LayoutOrder = 0
	table.insert(self.upgradeEntries, header)

	for index, upgrade in upgrades do
		local text = upgrade.Stacks > 1 and string.format("%s x%d", upgrade.Title, upgrade.Stacks) or upgrade.Title
		local label = UiTheme.label("Upgrade" .. index, self.upgradePanel, text, UiConfig.Text.Small)
		label.Size = UDim2.new(1, 0, 0, 16)
		label.LayoutOrder = index
		table.insert(self.upgradeEntries, label)
	end

	self.upgradePanel.Size = UDim2.fromOffset(210, 24 + (#upgrades + 1) * 18)
end

local BANNERS = {
	[RunConfig.States.Starting] = "Descending...",
	[RunConfig.States.UpgradeChoice] = "Choose an upgrade",
	[RunConfig.States.Transition] = "Moving deeper...",
}

function HudView:UpdateRun(snapshot)
	if not snapshot then
		return
	end

	local inRun = snapshot.State ~= RunConfig.States.Lobby
	self.roomLabel.Text = inRun and string.format("Room %d / %d  -  %s", snapshot.RoomIndex, snapshot.RoomCount, snapshot.RoomName)
		or "Ricochet Depths"

	if snapshot.State == RunConfig.States.Combat then
		self.objectiveLabel.Text = snapshot.EnemiesRemaining == 1 and "1 target left"
			or string.format("%d targets left", snapshot.EnemiesRemaining)
		self.objectiveLabel.TextColor3 = UiConfig.Colors.TextMuted
	elseif snapshot.State == RunConfig.States.Lobby then
		self:_renderLobbyObjective()
	else
		self.objectiveLabel.Text = ""
	end

	local banner = BANNERS[snapshot.State]
	self.banner.Visible = banner ~= nil
	if banner then
		self.bannerLabel.Text = banner
	end
end

-- The lobby line: ready-pad progress when anyone is gathering, otherwise how to start.
function HudView:_renderLobbyObjective()
	local ready = self._lobbyReady
	if ready and ready.Countdown then
		self.objectiveLabel.Text = string.format("Descending in %d...", ready.Countdown)
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Health
	elseif ready and ready.Ready > 0 then
		self.objectiveLabel.Text = string.format("Ready %d / %d  -  everyone onto a pad", ready.Ready, ready.Total)
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Accent
	else
		self.objectiveLabel.Text = "Stand on a ready pad, or use the pedestal to descend"
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Accent
	end
end

-- snapshot is the LobbyReadyState payload.
function HudView:SetLobbyReady(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	self._lobbyReady = snapshot.Active and snapshot or nil
	if snapshot.Active then
		self:_renderLobbyObjective()
	end
end

function HudView:Flash(message, color)
	self.banner.Visible = true
	self.bannerLabel.Text = message
	self.bannerLabel.TextColor3 = color or UiConfig.Colors.Warning
	self._flashToken = (self._flashToken or 0) + 1
	local token = self._flashToken
	task.delay(1.6, function()
		if self._flashToken == token then
			self.banner.Visible = false
			self.bannerLabel.TextColor3 = UiConfig.Colors.Text
		end
	end)
end

function HudView:Destroy()
	self.gui:Destroy()
end

return HudView
