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

	-- Coins picked up this run, with a brief "+N" as they come in.
	self.coinLabel = UiTheme.label("CoinLabel", health, "", UiConfig.Text.Hud, UiConfig.Colors.Warning)
	self.coinLabel.AnchorPoint = Vector2.new(1, 0)
	self.coinLabel.Position = UDim2.new(1, 0, 0, 0)
	self.coinLabel.Size = UDim2.new(0.5, 0, 0, 20)
	self.coinLabel.TextXAlignment = Enum.TextXAlignment.Right
	self._coins = 0

	local progress = UiTheme.panel("ProgressPanel", self.gui)
	progress.Position = UDim2.new(0.5, 0, 0, 12)
	progress.AnchorPoint = Vector2.new(0.5, 0)
	progress.Size = UDim2.fromOffset(380, 62)
	UiTheme.padding(progress, 10)
	self.roomLabel = UiTheme.label("RoomLabel", progress, "", UiConfig.Text.Hud)
	self.roomLabel.Size = UDim2.new(1, 0, 0, 22)
	self.roomLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.objectiveLabel = UiTheme.label("ObjectiveLabel", progress, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.objectiveLabel.Position = UDim2.new(0, 0, 0, 22)
	self.objectiveLabel.Size = UDim2.new(1, 0, 0, 20)
	self.objectiveLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- The boss bar, under the room label while a boss is alive.
	local boss = UiTheme.panel("BossPanel", self.gui)
	boss.Position = UDim2.new(0.5, 0, 0, 80)
	boss.AnchorPoint = Vector2.new(0.5, 0)
	boss.Size = UDim2.fromOffset(380, 52)
	boss.Visible = false
	UiTheme.padding(boss, 8)
	self.bossPanel = boss
	self.bossLabel = UiTheme.label("BossLabel", boss, "", UiConfig.Text.Hud, UiConfig.Colors.Danger)
	self.bossLabel.Size = UDim2.new(1, 0, 0, 18)
	self.bossLabel.TextXAlignment = Enum.TextXAlignment.Center
	local bossTrack, bossFill = UiTheme.bar("BossBar", boss, UiConfig.Colors.Danger)
	bossTrack.Position = UDim2.new(0, 0, 0, 22)
	bossTrack.Size = UDim2.new(1, 0, 0, 12)
	self.bossFill = bossFill

	-- The Store button, shown in the lobby only.
	local store = UiTheme.button("StoreButton", self.gui, "STORE")
	store.Position = UDim2.new(0, 16, 0, 12)
	store.Size = UDim2.fromOffset(110, UiConfig.MinTouchTarget)
	store.Activated:Connect(function()
		if self._onStore then
			self._onStore()
		end
	end)
	self.storeButton = store

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

	-- Players in the lobby belong to no match, so no run state reaches them before their first
	-- descent: start in the lobby layout (Store shown, upgrades hidden) rather than a blank one.
	self:UpdateRun({ State = RunConfig.States.Lobby, RoomIndex = 0, RoomCount = 0, RoomName = "", EnemiesRemaining = 0 })

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

	local coins = type(snapshot.Coins) == "number" and snapshot.Coins or 0
	local gained = coins - self._coins
	self._coins = coins
	if gained > 0 then
		self.coinLabel.Text = string.format("+%d  Coins %d", gained, coins)
		self._coinToken = (self._coinToken or 0) + 1
		local token = self._coinToken
		task.delay(1.2, function()
			if self._coinToken == token then
				self.coinLabel.Text = string.format("Coins %d", self._coins)
			end
		end)
	else
		self.coinLabel.Text = string.format("Coins %d", coins)
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

-- Starting and Transition have the descent cinematic's own caption instead.
local BANNERS = {
	[RunConfig.States.UpgradeChoice] = "Choose an upgrade",
}

function HudView:UpdateRun(snapshot)
	if not snapshot then
		return
	end

	local inRun = snapshot.State ~= RunConfig.States.Lobby
	-- Upgrades belong to a run: hidden in the lobby, and cleared when a run ends. The Store
	-- button is the reverse.
	self.upgradePanel.Visible = inRun
	self.storeButton.Visible = not inRun
	if not inRun and #self.upgradeEntries > 1 then
		self:_renderUpgrades({})
	end
	local zone = RunConfig.Zones[snapshot.Zone or ""]
	local where = zone and string.format("%s: %s", zone.DisplayName, snapshot.RoomName) or snapshot.RoomName
	self.roomLabel.Text = inRun and string.format("Room %d / %d  -  %s", snapshot.RoomIndex, snapshot.RoomCount, where)
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

	local boss = snapshot.Boss
	self.bossPanel.Visible = type(boss) == "table"
	if type(boss) == "table" then
		local phase = boss.Phase and boss.Phase > 1 and string.format("  -  phase %d", boss.Phase) or ""
		self.bossLabel.Text = boss.Name .. phase
		self.bossFill.Size = UDim2.fromScale(math.clamp(boss.Health / math.max(boss.MaxHealth, 1), 0, 1), 1)
	end

	local banner = BANNERS[snapshot.State]
	self.banner.Visible = banner ~= nil
	if banner then
		self.bannerLabel.Text = banner
	end
end

-- The lobby line: your gate's party and countdown when you are in one, otherwise how to start.
function HudView:_renderLobbyObjective()
	local status = self._lobbyStatus
	if status and status.Notice then
		self.objectiveLabel.Text = status.Notice
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Warning
	elseif status and status.Gate and status.Countdown then
		self.objectiveLabel.Text = string.format("%s  %d/%d  -  descending in %d...", status.Gate, status.Count,
			status.Capacity, status.Countdown)
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Health
	elseif status and status.Gate then
		self.objectiveLabel.Text = string.format("%s  %d/%d  -  waiting for %d more", status.Gate, status.Count,
			status.Capacity, math.max(status.MinPlayers - status.Count, 1))
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Accent
	else
		self.objectiveLabel.Text = "Step into a Gate with friends (2-8), or use the Solo Portal"
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Accent
	end
end

-- snapshot is the LobbyReadyState payload: this player's gate status.
function HudView:SetLobbyReady(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	self._lobbyStatus = snapshot
	if snapshot.Active then
		self:_renderLobbyObjective()
	end
end

function HudView:SetStoreHandler(callback)
	self._onStore = callback
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
