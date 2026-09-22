-- Owns every client view and the one connection to each server event. Keeping this in a single
-- script avoids duplicate remote handlers and ordering surprises between views.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardPickerView = require(script.Parent:WaitForChild("CardPickerView"))
local HudView = require(script.Parent:WaitForChild("HudView"))
local OnboardingView = require(script.Parent:WaitForChild("OnboardingView"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local ResultsView = require(script.Parent:WaitForChild("ResultsView"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local chooseUpgrade = Remotes.Get("ChooseUpgrade")
local requestReturnToLobby = Remotes.Get("RequestReturnToLobby")

local hud = HudView.new(playerGui)
local onboarding = OnboardingView.new(playerGui)
local cardPicker = CardPickerView.new(playerGui, function(offerId, cardId)
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

Remotes.Get("RunStateChanged").OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	hud:UpdateRun(snapshot)
	publishState(snapshot.State)

	if snapshot.State == RunConfig.States.Lobby then
		onboarding:Show("Lobby")
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
	if payload and payload.Auto then
		hud:Flash("Upgrade auto-selected")
	end
end)

Remotes.Get("RunResults").OnClientEvent:Connect(function(summary)
	if type(summary) ~= "table" then
		return
	end
	cardPicker:Hide()
	results:Show(summary)
end)

RunService.RenderStepped:Connect(function()
	cardPicker:UpdateTimer(os.clock())
end)
