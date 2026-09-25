-- Owns every client view and the one connection to each server event. Keeping this in a single
-- script avoids duplicate remote handlers and ordering surprises between views.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BasePreview = require(script.Parent:WaitForChild("BasePreview"))
local BaseView = require(script.Parent:WaitForChild("BaseView"))
local CalloutView = require(script.Parent:WaitForChild("CalloutView"))
local CardPickerView = require(script.Parent:WaitForChild("CardPickerView"))
local CodesView = require(script.Parent:WaitForChild("CodesView"))
local DailyView = require(script.Parent:WaitForChild("DailyView"))
local DescentCinematic = require(script.Parent:WaitForChild("DescentCinematic"))
local HudView = require(script.Parent:WaitForChild("HudView"))
local JournalView = require(script.Parent:WaitForChild("JournalView"))
local PactView = require(script.Parent:WaitForChild("PactView"))
local RigView = require(script.Parent:WaitForChild("RigView"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("AchievementConfig"))
local MenuDock = require(script.Parent:WaitForChild("MenuDock"))
local NotificationView = require(script.Parent:WaitForChild("NotificationView"))
local OnboardingView = require(script.Parent:WaitForChild("OnboardingView"))
local QuestsView = require(script.Parent:WaitForChild("QuestsView"))
local StatsView = require(script.Parent:WaitForChild("StatsView"))
local SurgePickerView = require(script.Parent:WaitForChild("SurgePickerView"))
local RoomFx = require(script.Parent:WaitForChild("RoomFx"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local ResultsView = require(script.Parent:WaitForChild("ResultsView"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local SettingsView = require(script.Parent:WaitForChild("SettingsView"))
local ShopView = require(script.Parent:WaitForChild("ShopView"))
local SoundPlayer = require(script.Parent:WaitForChild("SoundPlayer"))
local UiTheme = require(script.Parent:WaitForChild("UiTheme"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local chooseUpgrade = Remotes.Get("ChooseUpgrade")
local requestReturnToLobby = Remotes.Get("RequestReturnToLobby")
local updateSettings = Remotes.Get("UpdateSettings")
local purchaseShopItem = Remotes.Get("PurchaseShopItem")
local equipShopItem = Remotes.Get("EquipShopItem")
local claimDaily = Remotes.Get("ClaimDaily")
local claimQuest = Remotes.Get("ClaimQuest")
local redeemCode = Remotes.Get("RedeemCode")
local requestMeta = Remotes.Get("RequestMeta")
local selectRig = Remotes.Get("SelectRig")
local setPact = Remotes.Get("SetPact")
local claimAchievement = Remotes.Get("ClaimAchievement")
local chooseSurge = Remotes.Get("ChooseSurge")
local chooseDoor = Remotes.Get("ChooseDoor")
local upgradeBuilding = Remotes.Get("UpgradeBuilding")
local moveBuilding = Remotes.Get("MoveBuilding")
local claimBase = Remotes.Get("ClaimBase")
local visitBase = Remotes.Get("VisitBase")
local cheerBase = Remotes.Get("CheerBase")
local requestBase = Remotes.Get("RequestBase")
local featureBase = Remotes.Get("FeatureBase")
local rerollOffer = Remotes.Get("RerollOffer")
local respecCard = Remotes.Get("RespecCard")
local useRevive = Remotes.Get("UseRevive")
local savePreset = Remotes.Get("SavePreset")
local applyPreset = Remotes.Get("ApplyPreset")
local playEmote = Remotes.Get("PlayEmote")
local watchAd = Remotes.Get("WatchAd")
local requestStartRun = Remotes.Get("RequestStartRun")
local UserInputService = game:GetService("UserInputService")

-- Cosmetic scripts read these attributes rather than each opening their own remote.
local function publishSettings(settings)
	player:SetAttribute("EffectIntensity", settings.EffectIntensity)
	player:SetAttribute("ReducedFlash", settings.ReducedFlash)
	player:SetAttribute("ScreenShake", settings.ScreenShake)
	player:SetAttribute("SfxVolume", settings.SfxVolume)
end

local hud = HudView.new(playerGui)
hud:SetUserId(player.UserId)
local settingsView = SettingsView.new(playerGui, function(settings)
	-- Applied here at once, not only when the server echoes the saved profile back: a read-only
	-- session never echoes, and comfort options must still work there.
	publishSettings(settings)
	updateSettings:FireServer(settings)
end)
settingsView:SetVersion("Build " .. RunConfig.Version)
local onboarding = OnboardingView.new(playerGui)
local MarketplaceService = game:GetService("MarketplaceService")
local shopView = ShopView.new(playerGui, function(itemId)
	purchaseShopItem:FireServer(itemId)
end, function(itemId, kind)
	equipShopItem:FireServer(itemId, kind)
end, function(kind, id)
	-- Robux purchases go straight to Roblox; the server grants them from the receipt.
	if kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end, function(emoteId)
	playEmote:FireServer(emoteId)
end)
local sounds = SoundPlayer.Shared()
-- Every themed button clicks.
UiTheme.onClick = function()
	sounds:Play("UiClick")
end

local notifications = NotificationView.new(playerGui)
local callouts = CalloutView.new(playerGui)
local dailyView = DailyView.new(playerGui, function()
	claimDaily:FireServer()
end)
local questsView = QuestsView.new(playerGui, function(questId)
	claimQuest:FireServer(questId)
end)
local codesView = CodesView.new(playerGui, function(code)
	redeemCode:FireServer(code)
end)
local statsView = StatsView.new(playerGui, string.upper(player.DisplayName or player.Name))
local rigView = RigView.new(playerGui, function(rigId)
	selectRig:FireServer(rigId)
end, function(action, slot)
	if action == "Save" then
		savePreset:FireServer(slot)
	else
		applyPreset:FireServer(slot)
	end
end)
-- A private server's owner may feature a friend's base in the hall.
local function ownsPrivateServer()
	local ok, owns = pcall(function()
		return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == player.UserId
	end)
	return ok and owns == true
end
local baseView = BaseView.new(playerGui, {
	upgrade = function(buildingId, tile)
		upgradeBuilding:FireServer(buildingId, tile)
	end,
	move = function(buildingId, tile)
		moveBuilding:FireServer(buildingId, tile)
	end,
	claim = function()
		claimBase:FireServer()
	end,
	visit = function(userId)
		visitBase:FireServer(userId)
	end,
	cheer = function(userId)
		cheerBase:FireServer(userId)
	end,
	feature = ownsPrivateServer() and function(userId)
		featureBase:FireServer(userId)
	end or nil,
})
local function otherPlayers()
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(list, { UserId = other.UserId, Name = other.DisplayName or other.Name })
		end
	end
	return list
end
local pactView = PactView.new(playerGui, function(pact)
	setPact:FireServer(pact)
end)
local journalView = JournalView.new(playerGui, function(achievementId)
	claimAchievement:FireServer(achievementId)
end)
local modals = { dailyView, questsView, codesView, statsView, rigView, pactView, journalView, baseView }
local function closeModals()
	for _, view in modals do
		view:Close()
	end
end
local function openOnly(view)
	closeModals()
	shopView:Close()
	view:Open()
end

local function invite()
	local SocialService = game:GetService("SocialService")
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canInvite then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	else
		notifications:Show("Invites are not available right now.", "Error")
	end
end

local function openBase()
	requestBase:FireServer()
	baseView:SetPlayers(otherPlayers())
	openOnly(baseView)
	onboarding:Show("Base")
end

local menu = MenuDock.new(playerGui, {
	Base = openBase,
	Daily = function()
		requestMeta:FireServer()
		openOnly(dailyView)
	end,
	Quests = function()
		requestMeta:FireServer()
		openOnly(questsView)
	end,
	Codes = function()
		openOnly(codesView)
	end,
	Rigs = function()
		openOnly(rigView)
	end,
	Pact = function()
		openOnly(pactView)
	end,
	Journal = function()
		openOnly(journalView)
	end,
	Invite = invite,
})
hud:SetProfileHandler(function()
	openOnly(statsView)
end)
local descent = DescentCinematic.new(playerGui)
local cardPicker = CardPickerView.new(playerGui, function(offerId, cardId)
	sounds:Play("CardSelect")
	chooseUpgrade:FireServer(offerId, cardId)
end, function(doorId)
	sounds:Play("CardSelect")
	chooseDoor:FireServer(doorId)
end, {
	reroll = function()
		rerollOffer:FireServer()
	end,
	respec = function()
		respecCard:FireServer()
	end,
})
local surgePicker = SurgePickerView.new(playerGui, function(offerId, cardId)
	sounds:Play("CardSelect")
	chooseSurge:FireServer(offerId, cardId)
end)
local roomFx = RoomFx.new(playerGui)
-- The dash button asks AimController to dash by bumping an attribute it listens to.
hud:SetDashHandler(function()
	player:SetAttribute("DashRequest", (player:GetAttribute("DashRequest") or 0) + 1)
end, UserInputService.KeyboardEnabled)
-- Declared before construction so the dismiss callback closes over the local, not a global.
-- DESCEND waits for the lobby state before asking for a new run: the server is still tearing
-- the last one down when the results are dismissed.
local results
local descendWhenHome = false
results = ResultsView.new(playerGui, function()
	results:Hide()
	requestReturnToLobby:FireServer()
end, {
	descend = function()
		descendWhenHome = true
	end,
	toBase = function()
		descendWhenHome = false
		visitBase:FireServer(nil)
	end,
	watchAd = FeatureFlags.RewardedVideo and MonetizationConfig.Ads.RewardProductId > 0 and function()
		watchAd:FireServer()
	end or nil,
})

-- The HUD's BASE button goes straight to your plot.
hud:SetBaseHandler(FeatureFlags.BaseBuilding and function()
	visitBase:FireServer(nil)
end or nil)

-- AimController reads this to know when to accept input; attributes stay on this client.
local function publishState(state)
	player:SetAttribute("RunState", state)
end
publishState(RunConfig.States.Lobby)

local lastState = nil
-- Hints wait for the saved profile, which says whether this player has already seen them.
local profileArrived = false
Remotes.Get("RunStateChanged").OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	-- A room just cleared: combat gave way to the upgrade round (or the run ended in victory).
	if lastState == RunConfig.States.Combat
		and (snapshot.State == RunConfig.States.UpgradeChoice or snapshot.State == RunConfig.States.Results) then
		sounds:Play("RoomClear")
		roomFx:RoomCleared()
	end
	cardPicker:SetDoors(snapshot.State == RunConfig.States.UpgradeChoice and snapshot.Doors or nil)
	-- An extract point: say what the Bank loot door means the first time one appears.
	if snapshot.State == RunConfig.States.UpgradeChoice and type(snapshot.Doors) == "table" then
		for _, door in type(snapshot.Doors.Doors) == "table" and snapshot.Doors.Doors or {} do
			if door.Kind == "Extract" then
				onboarding:Show("BankLoot")
			end
		end
	end
	descent:OnRunState(lastState, snapshot)
	lastState = snapshot.State
	hud:UpdateRun(snapshot)
	publishState(snapshot.State)
	-- ZoneAmbience tweens the lighting from this.
	local inRun = snapshot.State ~= RunConfig.States.Lobby and snapshot.State ~= RunConfig.States.Results
	player:SetAttribute("Zone", inRun and type(snapshot.Zone) == "string" and snapshot.Zone ~= "" and snapshot.Zone or "Lobby")
	local inLobby = snapshot.State == RunConfig.States.Lobby
	menu:SetVisible(inLobby)
	if not inLobby then
		shopView:Close() -- the shop and the menus are lobby-only
		closeModals()
	end
	if snapshot.State == RunConfig.States.Starting then
		callouts:Reset()
	end

	if snapshot.State == RunConfig.States.Lobby then
		if profileArrived then
			onboarding:Show("Lobby")
		end
		results:Hide()
		cardPicker:Hide()
		if descendWhenHome then
			descendWhenHome = false
			requestStartRun:FireServer()
		end
	elseif snapshot.State == RunConfig.States.Combat then
		cardPicker:Hide()
		if snapshot.FirstDescent then
			onboarding:Show("FirstDescent")
		end
		onboarding:Show("Aim")
		onboarding:Show("Orbs")
		if type(snapshot.Wave) == "table" and snapshot.Wave.Incoming then
			onboarding:Show("Waves")
		end
		if type(snapshot.Objective) == "table" then
			onboarding:Show(snapshot.Objective.Kind)
		end
		if snapshot.RoomIndex >= 2 then
			onboarding:Show("Dash")
		end
		if snapshot.RoomIndex >= 2 then
			onboarding:Show("Ricochet")
		end
		if snapshot.RoomKind == "Elite" or snapshot.RoomIndex >= 3 then
			onboarding:Show("Shield")
		end
	elseif snapshot.State ~= RunConfig.States.UpgradeChoice then
		cardPicker:Hide()
	end
	if snapshot.State ~= RunConfig.States.Combat and snapshot.State ~= RunConfig.States.UpgradeChoice then
		surgePicker:Hide()
	end
end)

Remotes.Get("PlayerStateChanged").OnClientEvent:Connect(function(snapshot)
	hud:UpdatePlayer(snapshot)
	if type(snapshot) == "table" and type(snapshot.FireCooldown) == "number" then
		-- AimController predicts its own cooldown from this, purely for feedback.
		player:SetAttribute("FireCooldown", snapshot.FireCooldown)
	end
	if type(snapshot) == "table" then
		-- Orbs in hand and the dash's cooldown, for AimController's own checks.
		player:SetAttribute("Orbs", type(snapshot.OrbsMax) == "number" and snapshot.Orbs or nil)
		player:SetAttribute("DashCooldown", snapshot.DashCooldown)
	end
end)

Remotes.Get("ProfileSync").OnClientEvent:Connect(function(profile)
	if type(profile) ~= "table" then
		return
	end
	if type(profile.Flags) == "table" and profile.Flags.OnboardingSeen then
		onboarding:MarkAllSeen()
	end
	-- Lobby players get no run state until they descend, so the lobby hint is shown from here
	-- on the first profile, once it is known whether they have seen it.
	if not profileArrived then
		profileArrived = true
		if lastState == nil or lastState == RunConfig.States.Lobby then
			onboarding:Show("Lobby")
		end
	end
	shopView:SetProfile(profile)
	statsView:SetProfile(profile)
	rigView:SetProfile(profile)
	pactView:SetProfile(profile)
	journalView:SetProfile(profile)
	hud:SetLoadout(rigView:GetSelected(), pactView:GetPact())
	local claimable = false
	for _, entry in AchievementConfig.Describe(profile) do
		if entry.Complete and not entry.Claimed then
			claimable = true
		end
	end
	menu:SetJournalClaimable(claimable)
	hud:SetReadOnly(profile.ReadOnly)
	if hud:SetProgress(profile.Progression) then
		sounds:Play("LevelUp")
		notifications:Show(string.format("LEVEL UP! You reached level %d.", profile.Progression.Level), "Reward")
	end
	settingsView:Apply(profile.Settings)
	publishSettings(settingsView:GetSettings())
end)

Remotes.Get("ShopOpen").OnClientEvent:Connect(function(tab)
	closeModals()
	shopView:Open(tab)
end)
hud:SetStoreHandler(function()
	closeModals()
	shopView:Open("Store")
end)

Remotes.Get("ShopResult").OnClientEvent:Connect(function(payload)
	shopView:ShowResult(payload)
	if type(payload) == "table" and payload.Ok and payload.Action == "Purchase" then
		sounds:Play("CardSelect")
	end
end)

Remotes.Get("LobbyReadyState").OnClientEvent:Connect(function(snapshot)
	hud:SetLobbyReady(snapshot)
end)

Remotes.Get("UpgradeOffer").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.Cards) ~= "table" then
		return
	end
	onboarding:Show("Upgrade")
	cardPicker:Show(payload)
	if payload.Fusion then
		sounds:Play("LevelUp")
		roomFx:Punch(0.8)
	end
end)

Remotes.Get("UpgradeResolved").OnClientEvent:Connect(function(payload)
	-- With doors on, the card is only half the choice: the next room comes second.
	if not cardPicker:ShowDoors() then
		cardPicker:Hide()
	else
		onboarding:Show("Doors")
	end
	if payload and payload.Auto and not player:GetAttribute("ReducedFlash") then
		hud:Flash("Upgrade auto-selected")
	end
end)

Remotes.Get("SurgeOffer").OnClientEvent:Connect(function(payload)
	surgePicker:Show(payload)
	sounds:Play("LevelUp")
	onboarding:Show("Surge")
end)

Remotes.Get("SurgeResolved").OnClientEvent:Connect(function(payload)
	surgePicker:Hide()
	if type(payload) == "table" and payload.Title then
		callouts:Show(string.upper(tostring(payload.Title)), Color3.fromRGB(255, 120, 200))
	end
end)

-- 1 / 2 / 3 take a Surge perk without leaving the fight.
local SURGE_KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 }
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and SURGE_KEYS[input.KeyCode] and surgePicker:IsOpen() then
		surgePicker:Choose(SURGE_KEYS[input.KeyCode])
	end
end)

Remotes.Get("RunResults").OnClientEvent:Connect(function(summary)
	if type(summary) ~= "table" then
		return
	end
	cardPicker:Hide()
	if summary.Outcome == "Extracted" then
		sounds:Play("RoomClear")
	end
	results:Show(summary)
	-- Three seconds over the plot: this is what the haul builds.
	BasePreview.Play(player, workspace.CurrentCamera)
end)

-- The base: its panel, and the "your haul builds" line on the results screen.
Remotes.Get("BaseSync").OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		return
	end
	baseView:SetState(state)
	results:SetNextBuild(state.NextBuild, state.Balance)
	if state.Open then
		baseView:SetPlayers(otherPlayers())
		openOnly(baseView)
		onboarding:Show("Base")
	end
end)

Remotes.Get("MetaSync").OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		return
	end
	dailyView:SetState(state.Daily, state.ResetsIn)
	questsView:SetState(state.Quests, state.ResetsIn)
	local questReady = false
	for _, quest in type(state.Quests) == "table" and state.Quests or {} do
		if quest.Complete and not quest.Claimed then
			questReady = true
		end
	end
	menu:SetClaimable(type(state.Daily) == "table" and state.Daily.CanClaim, questReady)
	hud:SetLobbyModifier(state.Modifier)
end)

Remotes.Get("Notify").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	-- Down with a revive available: a token is spent by the server; with none, the paid Revive
	-- (when it is switched on) is bought and spent in one go.
	if payload.Kind == "ReviveOffer" then
		hud:OfferRevive(payload.Tokens, function(tokens)
			if tokens > 0 then
				useRevive:FireServer()
				return
			end
			for _, product in MonetizationConfig.Products do
				if product.Kind == "Revive" and product.Id > 0 and FeatureFlags.PaidRevive then
					MarketplaceService:PromptProductPurchase(player, product.Id)
				end
			end
		end)
		notifications:Show(payload.Text, "Error")
		return
	end
	if payload.Kind == "SecondWind" then
		callouts:Show(payload.Text, UiConfig.Colors.Health)
		sounds:Play("LevelUp")
		return
	end
	-- Big centre calls from the run: trick shots, combo tiers, trials, runners.
	if payload.Kind == "Callout" then
		callouts:Show(tostring(payload.Text), UiConfig.Colors[payload.Tone or "Gold"] or UiConfig.Colors.Gold)
		sounds:Play("Combo")
		roomFx:Punch(0.5)
		return
	end
	notifications:Show(payload.Text, payload.Kind)
	if payload.Kind == "Reward" or payload.Kind == "Revive" then
		sounds:Play("Reward")
	end
end)

-- Kill streaks and long ricochets, for this player's own kills. A champion kill gets its own.
Remotes.Get("EnemyDefeated").OnClientEvent:Connect(function(_position, _archetypeId, shooterId, contacts, champion)
	if shooterId ~= player.UserId then
		return
	end
	if type(champion) == "string" then
		callouts:OnKill(tonumber(contacts) or 0)
		callouts:Show(string.upper(champion) .. " CHAMPION SLAIN", UiConfig.Colors.Purple)
		sounds:Play("Combo")
	elseif callouts:OnKill(tonumber(contacts) or 0) then
		sounds:Play("Combo")
	end
end)

-- First sightings of enemies with rules of their own (EnemyVisuals marks them).
for _, name in { "Mirror", "Magnet", "Sponge", "TreasureRunner" } do
	player:GetAttributeChangedSignal("Saw" .. name):Connect(function()
		onboarding:Show(name, 7)
	end)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	cardPicker:UpdateTimer(now)
	surgePicker:UpdateTimer(now)
	hud:Tick(now, player:GetAttribute("DashReadyAt"))
	roomFx:Step(now)
end)
