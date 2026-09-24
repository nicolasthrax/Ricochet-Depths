-- Health, run progress, objective and active upgrades. Display only: it renders whatever the
-- server last sent and never computes game state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArsenalConfig = require(ReplicatedStorage:WaitForChild("ArsenalConfig"))
local PactConfig = require(ReplicatedStorage:WaitForChild("PactConfig"))
local RigConfig = require(ReplicatedStorage:WaitForChild("RigConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local HudView = {}
HudView.__index = HudView

function HudView.new(playerGui)
	local self = setmetatable({}, HudView)

	self.gui = UiTheme.screenGui("RicochetHud", playerGui, 10)

	local health = UiTheme.panel("HealthPanel", self.gui)
	health.Position = UDim2.new(0, 16, 1, -112)
	health.Size = UDim2.fromOffset(260, 86)
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

	-- Orbs in hand: one pip each, lit when the orb is ready to throw.
	local pips = Instance.new("Frame")
	pips.Name = "OrbPips"
	pips.BackgroundTransparency = 1
	pips.Position = UDim2.new(0, 0, 0, 46)
	pips.Size = UDim2.new(0.6, 0, 0, 14)
	pips.Parent = health
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.Padding = UDim.new(0, 5)
	pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipLayout.Parent = pips
	self.orbPips = pips
	self._pips = {}
	self.orbLabel = UiTheme.label("OrbLabel", health, "", UiConfig.Text.Small - 2, UiConfig.Colors.TextMuted)
	self.orbLabel.AnchorPoint = Vector2.new(1, 0)
	self.orbLabel.Position = UDim2.new(1, 0, 0, 44)
	self.orbLabel.Size = UDim2.new(0.4, 0, 0, 16)
	self.orbLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- The Surge meter: kills fill it; full, it offers a perk.
	local surgeTrack, surgeFill = UiTheme.bar("SurgeBar", health, Color3.fromRGB(255, 120, 200))
	surgeTrack.Position = UDim2.new(0, 0, 0, 64)
	surgeTrack.Size = UDim2.new(1, 0, 0, 6)
	surgeFill.Size = UDim2.fromScale(0, 1)
	self.surgeFill = surgeFill

	-- The combo meter, right of centre: the count, its tier, and how long it has left.
	local combo = Instance.new("Frame")
	combo.Name = "Combo"
	combo.BackgroundTransparency = 1
	combo.AnchorPoint = Vector2.new(1, 0.5)
	combo.Position = UDim2.new(1, -24, 0.42, 0)
	combo.Size = UDim2.fromOffset(170, 74)
	combo.Visible = false
	combo.Parent = self.gui
	self.comboFrame = combo
	self.comboCount = UiTheme.heading("Count", combo, "", 40, UiConfig.Colors.Gold)
	self.comboCount.Size = UDim2.new(1, 0, 0, 44)
	self.comboCount.TextXAlignment = Enum.TextXAlignment.Right
	self.comboTier = UiTheme.heading("Tier", combo, "", UiConfig.Text.Small + 2, UiConfig.Colors.Warning)
	self.comboTier.Position = UDim2.new(0, 0, 0, 44)
	self.comboTier.Size = UDim2.new(1, 0, 0, 18)
	self.comboTier.TextXAlignment = Enum.TextXAlignment.Right
	local comboTrack, comboFill = UiTheme.bar("ComboTimer", combo, UiConfig.Colors.Gold)
	comboTrack.AnchorPoint = Vector2.new(1, 0)
	comboTrack.Position = UDim2.new(1, 0, 0, 64)
	comboTrack.Size = UDim2.new(0.7, 0, 0, 5)
	self.comboFill = comboFill
	self._comboScale = Instance.new("UIScale")
	self._comboScale.Parent = self.comboCount

	-- The dash: a big thumb button for touch, which also shows the cooldown.
	local dash = UiTheme.button("DashButton", self.gui, "DASH", "Primary")
	dash.AnchorPoint = Vector2.new(1, 1)
	dash.Position = UDim2.new(1, -24, 1, -150)
	dash.Size = UDim2.fromOffset(84, 84)
	dash.TextSize = UiConfig.Text.Hud
	dash.Visible = false
	UiTheme.corner(dash, 42)
	dash.Activated:Connect(function()
		if self._onDash then
			self._onDash()
		end
	end)
	self.dashButton = dash

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
	-- A room's challenge (a Trial), under the room panel.
	self.challengeLabel = UiTheme.label("ChallengeLabel", self.gui, "", UiConfig.Text.Small, UiConfig.Colors.Warning)
	self.challengeLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.challengeLabel.Position = UDim2.new(0.5, 0, 0, 76)
	self.challengeLabel.Size = UDim2.fromOffset(460, 18)
	self.challengeLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.challengeLabel.TextStrokeTransparency = 0.4
	self.challengeLabel.Visible = false

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
	local store = UiTheme.button("StoreButton", self.gui, "STORE", "Primary")
	store.Position = UDim2.new(0, 16, 0, 12)
	store.Size = UDim2.fromOffset(110, UiConfig.MinTouchTarget)
	store.Activated:Connect(function()
		if self._onStore then
			self._onStore()
		end
	end)
	self.storeButton = store

	-- Level badge and experience bar, under the Store button. Lobby only, like the Store: in a
	-- run the top of the screen belongs to the room and boss bars.
	local levelPanel = UiTheme.panel("LevelPanel", self.gui)
	levelPanel.Position = UDim2.new(0, 16, 0, 76)
	levelPanel.Size = UDim2.fromOffset(200, 50)
	UiTheme.padding(levelPanel, 8)
	self.levelPanel = levelPanel
	self.levelLabel = UiTheme.label("LevelLabel", levelPanel, "LEVEL 1", UiConfig.Text.Hud, UiConfig.Colors.Warning)
	self.levelLabel.Font = UiConfig.FontBold
	self.levelLabel.Size = UDim2.new(0.5, 0, 0, 18)
	self.xpLabel = UiTheme.label("XpLabel", levelPanel, "0 / 100 XP", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.xpLabel.AnchorPoint = Vector2.new(1, 0)
	self.xpLabel.Position = UDim2.new(1, 0, 0, 0)
	self.xpLabel.Size = UDim2.new(0.5, 0, 0, 18)
	self.xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	local xpTrack, xpFill = UiTheme.bar("XpBar", levelPanel, UiConfig.Colors.Warning)
	xpTrack.Position = UDim2.new(0, 0, 0, 24)
	xpTrack.Size = UDim2.new(1, 0, 0, 10)
	xpFill.Size = UDim2.fromScale(0, 1)
	self.xpFill = xpFill
	-- The whole badge is a button that opens the profile card.
	local profileButton = Instance.new("TextButton")
	profileButton.Name = "ProfileButton"
	profileButton.Text = ""
	profileButton.BackgroundTransparency = 1
	profileButton.Size = UDim2.new(1, 16, 1, 16)
	profileButton.Position = UDim2.fromOffset(-8, -8)
	profileButton.ZIndex = 4
	profileButton.Parent = levelPanel
	profileButton.Activated:Connect(function()
		if self._onProfile then
			self._onProfile()
		end
	end)
	-- The rig and Heat this player will descend with, under the level badge.
	self.loadoutLabel = UiTheme.label("LoadoutLabel", self.gui, "", UiConfig.Text.Small, UiConfig.Colors.Accent)
	self.loadoutLabel.Position = UDim2.new(0, 18, 0, 130)
	self.loadoutLabel.Size = UDim2.fromOffset(260, 18)
	self.loadoutLabel.TextStrokeTransparency = 0.5

	-- Shown only when the profile could not be loaded, so nothing earned will be kept.
	self.saveWarning = UiTheme.label("SaveWarning", self.gui, "Progress is not saving right now. Rejoin to try again.",
		UiConfig.Text.Small, UiConfig.Colors.Danger)
	self.saveWarning.AnchorPoint = Vector2.new(0.5, 1)
	self.saveWarning.Position = UDim2.new(0.5, 0, 1, -8)
	self.saveWarning.Size = UDim2.fromOffset(420, 18)
	self.saveWarning.TextXAlignment = Enum.TextXAlignment.Center
	self.saveWarning.Visible = false

	self._upgradeKey = nil
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
	self.bannerLabel = UiTheme.heading("BannerLabel", banner, "", UiConfig.Text.Title, UiConfig.Colors.Text)
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

	local lives = tonumber(snapshot.ExtraLivesLeft) or 0
	if lives > 0 then
		self.healthLabel.Text ..= "   Second Wind ready"
	end
	if not snapshot.Alive then
		local progress = tonumber(snapshot.ReviveProgress) or 0
		self.healthLabel.Text = progress > 0 and string.format("DOWN  -  being revived %d%%", math.floor(progress * 100))
			or "DOWN  -  crawl to a teammate"
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
	self:_renderArsenal(snapshot)
end

-- Orb pips, the Surge meter and the combo meter from a player snapshot.
function HudView:_renderArsenal(snapshot)
	local orbsMax = tonumber(snapshot.OrbsMax)
	local orbs = tonumber(snapshot.Orbs) or 0
	self.orbPips.Visible = orbsMax ~= nil
	self.orbLabel.Visible = orbsMax ~= nil
	if orbsMax then
		for index = #self._pips + 1, orbsMax do
			local pip = Instance.new("Frame")
			pip.Name = "Pip" .. index
			pip.LayoutOrder = index
			pip.Size = UDim2.fromOffset(14, 14)
			pip.BorderSizePixel = 0
			pip.Parent = self.orbPips
			UiTheme.corner(pip, 7)
			self._pips[index] = pip
		end
		for index, pip in self._pips do
			pip.Visible = index <= orbsMax
			pip.BackgroundColor3 = index <= orbs and ArsenalConfig.Orbs.Color or UiConfig.Colors.Track
		end
		self.orbLabel.Text = orbs > 0 and "ORBS" or "PICK UP ORBS"
		self.orbLabel.TextColor3 = orbs > 0 and UiConfig.Colors.TextMuted or UiConfig.Colors.Warning
	end

	local need = tonumber(snapshot.SurgeNeeded) or 0
	self.surgeFill.Size = UDim2.fromScale(need > 0 and math.clamp((tonumber(snapshot.Surge) or 0) / need, 0, 1) or 0, 1)

	local combo = tonumber(snapshot.Combo) or 0
	self.comboFrame.Visible = combo >= 2
	if combo >= 2 then
		local tier = ArsenalConfig.ComboTier(combo)
		if combo > (self._lastCombo or 0) then
			self._comboScale.Scale = 1.35
			UiTheme.tween(self._comboScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		self.comboCount.Text = combo .. " COMBO"
		self.comboTier.Text = tier.Multiplier > 1 and string.format("%s  x%s", tier.Name, tostring(tier.Multiplier)) or ""
		self._comboUntil = os.clock() + (tonumber(snapshot.ComboWindow) or ArsenalConfig.Combo.Window)
		self._comboWindow = tonumber(snapshot.ComboWindow) or ArsenalConfig.Combo.Window
	end
	self._lastCombo = combo
end

-- Drains the combo timer and counts down the dash. Called every frame.
function HudView:Tick(now, dashReadyAt)
	if self.comboFrame.Visible and self._comboUntil then
		local left = math.max(self._comboUntil - now, 0)
		self.comboFill.Size = UDim2.fromScale(left / math.max(self._comboWindow or 1, 0.1), 1)
		if left <= 0 then
			self.comboFrame.Visible = false
		end
	end
	if self.dashButton.Visible then
		local wait = (dashReadyAt or 0) - now
		self.dashButton.Text = wait > 0 and string.format("%.1f", wait) or self._dashText
		self.dashButton.BackgroundTransparency = wait > 0 and 0.5 or 0
	end
end

function HudView:SetDashHandler(callback, keyboardHint)
	self._onDash = callback
	self._dashText = keyboardHint and "DASH\n(Q)" or "DASH"
	self.dashButton.Text = self._dashText
end

function HudView:_renderUpgrades(upgrades)
	-- Player snapshots now arrive on every throw and kill; rebuild the list only when it changed.
	local parts = {}
	for _, upgrade in upgrades do
		table.insert(parts, tostring(upgrade.Title) .. "x" .. tostring(upgrade.Stacks))
	end
	local key = table.concat(parts, "|")
	if key == self._upgradeKey then
		return
	end
	self._upgradeKey = key
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
	self.levelPanel.Visible = not inRun
	self.loadoutLabel.Visible = not inRun
	self.dashButton.Visible = snapshot.State == RunConfig.States.Combat and self._onDash ~= nil
	if not inRun then
		self.comboFrame.Visible = false
	end
	local challenge = type(snapshot.Challenge) == "table" and snapshot.Challenge or nil
	self.challengeLabel.Visible = challenge ~= nil and inRun
	if challenge then
		local done = challenge.State == "Done"
		local failed = challenge.State == "Failed"
		self.challengeLabel.Text = (failed and "TRIAL FAILED: " or done and "TRIAL DONE: " or "TRIAL: ") .. tostring(challenge.Text)
		self.challengeLabel.TextColor3 = failed and UiConfig.Colors.Danger or done and UiConfig.Colors.Health or UiConfig.Colors.Warning
	end
	if not inRun and #self.upgradeEntries > 1 then
		self:_renderUpgrades({})
	end
	local zone = RunConfig.Zones[snapshot.Zone or ""]
	local where = zone and string.format("%s: %s", zone.DisplayName, snapshot.RoomName) or snapshot.RoomName
	local heat = tonumber(snapshot.Heat) or 0
	self.roomLabel.Text = inRun and string.format("Room %d / %d  -  %s%s", snapshot.RoomIndex, snapshot.RoomCount, where,
		heat > 0 and string.format("  -  Heat %d", heat) or "")
		or "Ricochet Depths"

	local downed = type(snapshot.Downed) == "table" and snapshot.Downed[1] or nil
	if snapshot.State == RunConfig.States.Combat and downed and downed.UserId ~= self._userId then
		-- A teammate is down: getting them up matters more than the target count.
		self.objectiveLabel.Text = string.format("%s is down! Stand next to them to revive (%d%%)", tostring(downed.Name),
			math.floor((tonumber(downed.Progress) or 0) * 100))
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Danger
	elseif snapshot.State == RunConfig.States.Combat and type(snapshot.Objective) == "table" then
		self.objectiveLabel.Text = tostring(snapshot.Objective.Text)
		self.objectiveLabel.TextColor3 = UiConfig.Colors.Accent
	elseif snapshot.State == RunConfig.States.Combat then
		local wave = type(snapshot.Wave) == "table" and snapshot.Wave or nil
		local targets = snapshot.EnemiesRemaining == 1 and "1 target left"
			or string.format("%d targets left", snapshot.EnemiesRemaining)
		if wave and wave.Incoming then
			self.objectiveLabel.Text = string.format("WAVE %d / %d INCOMING!", wave.Wave + 1, wave.Waves)
			self.objectiveLabel.TextColor3 = UiConfig.Colors.Danger
		elseif wave then
			self.objectiveLabel.Text = string.format("Wave %d / %d  -  %s", math.min(wave.Wave, wave.Waves), wave.Waves, targets)
			self.objectiveLabel.TextColor3 = UiConfig.Colors.TextMuted
		else
			self.objectiveLabel.Text = targets
			self.objectiveLabel.TextColor3 = UiConfig.Colors.TextMuted
		end
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

-- progression is the profile's Progression: { Level, Xp, XpIntoLevel, XpToNext }. Returns true
-- when this is a level up since the last profile, after announcing it.
function HudView:SetProgress(progression)
	if type(progression) ~= "table" or type(progression.Level) ~= "number" then
		return false
	end
	local level = progression.Level
	local into = type(progression.XpIntoLevel) == "number" and progression.XpIntoLevel or 0
	local need = type(progression.XpToNext) == "number" and progression.XpToNext or 0
	self.levelLabel.Text = "LEVEL " .. level
	if need > 0 then
		self.xpLabel.Text = string.format("%d / %d XP", into, need)
		self.xpFill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1)
	else
		self.xpLabel.Text = "MAX"
		self.xpFill.Size = UDim2.fromScale(1, 1)
	end

	local leveledUp = self._level ~= nil and level > self._level
	self._level = level
	if leveledUp then
		self:Flash("LEVEL UP!  You are level " .. level, UiConfig.Colors.Warning)
	end
	return leveledUp
end

-- The lobby's loadout line: the selected rig and the Pact's Heat.
function HudView:SetLoadout(rigId, pact)
	local rig = RigConfig.Get(rigId) or RigConfig.Get(RigConfig.DefaultId)
	local heat = PactConfig.Heat(pact)
	self.loadoutLabel.Text = heat > 0 and string.format("Rig: %s   -   Heat %d", rig.Title, heat)
		or string.format("Rig: %s", rig.Title)
	self.loadoutLabel.TextColor3 = rig.Color
end

-- This player's user id, so the HUD never asks them to revive themselves.
function HudView:SetUserId(userId)
	self._userId = userId
end

function HudView:SetReadOnly(readOnly)
	self.saveWarning.Visible = readOnly == true
end

function HudView:SetProfileHandler(callback)
	self._onProfile = callback
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
