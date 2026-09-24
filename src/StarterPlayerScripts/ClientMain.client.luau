-- Owns every client view and the one connection to each server event. Keeping this in a single
-- script avoids duplicate remote handlers and ordering surprises between views.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CalloutView = require(script.Parent:WaitForChild("CalloutView"))
local CardPickerView = require(script.Parent:WaitForChild("CardPickerView"))
local CodesView = require(script.Parent:WaitForChild("CodesView"))
local DailyView = require(script.Parent:WaitForChild("DailyView"))
local DescentCinematic = require(script.Parent:WaitForChild("DescentCinematic"))
local HudView = require(script.Parent:WaitForChild("HudView"))
local MenuDock = require(script.Parent:WaitForChild("MenuDock"))
local NotificationView = require(script.Parent:WaitForChild("NotificationView"))
local OnboardingView = require(script.Parent:WaitForChild("OnboardingView"))
local QuestsView = require(script.Parent:WaitForChild("QuestsView"))
local StatsView = require(script.Parent:WaitForChild("StatsView"))
local TitleScreen = require(script.Parent:WaitForChild("TitleScreen"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local ResultsView = require(script.Parent:WaitForChild("ResultsView"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local SettingsView = require(script.Parent:WaitForChild("SettingsView"))
local ShopView = require(script.Parent:WaitForChild("ShopView"))
local SoundPlayer = require(script.Parent:WaitForChild("SoundPlayer"))
local UiTheme = require(script.Parent:WaitForChild("UiTheme"))

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

-- Cosmetic scripts read these attributes rather than each opening their own remote.
local function publishSettings(settings)
	player:SetAttribute("EffectIntensity", settings.EffectIntensity)
	player:SetAttribute("ReducedFlash", settings.ReducedFlash)
	player:SetAttribute("ScreenShake", settings.ScreenShake)
	player:SetAttribute("SfxVolume", settings.SfxVolume)
end

local hud = HudView.new(playerGui)
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
end, function(itemId)
	equipShopItem:FireServer(itemId)
end, function(kind, id)
	-- Robux purchases go straight to Roblox; the server grants them from the receipt.
	if kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
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
local modals = { dailyView, questsView, codesView, statsView }
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

local menu = MenuDock.new(playerGui, {
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
	Invite = invite,
})
hud:SetProfileHandler(function()
	openOnly(statsView)
end)
local descent = DescentCinematic.new(playerGui)
local cardPicker = CardPickerView.new(playerGui, function(offerId, cardId)
	sounds:Play("CardSelect")
	chooseUpgrade:FireServer(offerId, cardId)
end)
-- Declared before construction so the dismiss callback closes over the local, not a global.
local results
results = ResultsView.new(playerGui, function()
	results:Hide()
	requestReturnToLobby:FireServer()
end)

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
	-- A room just cleared: combat gave way to the upgrade round.
	if lastState == RunConfig.States.Combat and snapshot.State == RunConfig.States.UpgradeChoice then
		sounds:Play("RoomClear")
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
	elseif snapshot.State == RunConfig.States.Combat then
		cardPicker:Hide()
		onboarding:Show("Aim")
		if snapshot.RoomIndex >= 2 then
			onboarding:Show("Ricochet")
		end
		if snapshot.RoomKind == "Elite" or snapshot.RoomIndex >= 3 then
			onboarding:Show("Shield")
		end
	elseif snapshot.State ~= RunConfig.States.UpgradeChoice then
		cardPicker:Hide()
	end
end)

Remotes.Get("PlayerStateChanged").OnClientEvent:Connect(function(snapshot)
	hud:UpdatePlayer(snapshot)
	if type(snapshot) == "table" and type(snapshot.FireCooldown) == "number" then
		-- AimController predicts its own cooldown from this, purely for feedback.
		player:SetAttribute("FireCooldown", snapshot.FireCooldown)
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
end)

Remotes.Get("UpgradeResolved").OnClientEvent:Connect(function(payload)
	cardPicker:Hide()
	if payload and payload.Auto and not player:GetAttribute("ReducedFlash") then
		hud:Flash("Upgrade auto-selected")
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
end)

Remotes.Get("Notify").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	notifications:Show(payload.Text, payload.Kind)
	if payload.Kind == "Reward" then
		sounds:Play("Reward")
	end
end)

-- Kill streaks and long ricochets, for this player's own kills.
Remotes.Get("EnemyDefeated").OnClientEvent:Connect(function(_position, _archetypeId, shooterId, contacts)
	if shooterId == player.UserId and callouts:OnKill(tonumber(contacts) or 0) then
		sounds:Play("Combo")
	end
end)

-- The title card, over everything until the player presses Play.
TitleScreen.new(playerGui, function()
	sounds:Play("Reward")
end)

RunService.RenderStepped:Connect(function()
	cardPicker:UpdateTimer(os.clock())
end)
