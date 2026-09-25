--!strict
-- Client entry point. Starts the controllers and wires them together; the controllers never
-- require each other except through what is passed in here.
--
--   RunStateChanged -> camera, renderer, HUD, pick UI, and whether combat input is live
--   renderer.obstacles -> the combat aim guide
--   CombatController.Fired -> renderer.predictShot (own shots appear the moment they are fired)
--   UpgradeUIController.Opened / Closed -> combat input off / back on

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Network = require(ReplicatedStorage.Network)
local ProjectilePool = require(ReplicatedStorage.Modules.ProjectilePool)
local Controllers = script.Parent:WaitForChild("Controllers")
local LaneCamera = require(Controllers:WaitForChild("LaneCamera"))
local LaneRenderer = require(Controllers:WaitForChild("LaneRenderer"))
local HudController = require(Controllers:WaitForChild("HudController"))
local CombatController = require(Controllers:WaitForChild("CombatController"))
local UpgradeUIController = require(Controllers:WaitForChild("UpgradeUIController"))

local player = Players.LocalPlayer
local currentState: Network.RunState? = nil

local function refreshCombat()
	local state = currentState
	local live = state ~= nil and state.phase == "Combat" and not state.paused and not UpgradeUIController.isOpen()
	CombatController.setEnabled(live)
end

local function applyState(state: Network.RunState)
	local previous = currentState
	currentState = state
	local newRun = previous == nil or previous.runId ~= state.runId
	local newLane = previous == nil or previous.laneOrigin ~= state.laneOrigin
	if newRun or newLane then
		LaneCamera.setLane(state.laneOrigin, true)
		CombatController.setLane(state.laneOrigin, true)
	end
	LaneRenderer.applyState(state)
	HudController.applyState(state)
	UpgradeUIController.applyState(state)
	refreshCombat()
end

ProjectilePool.Prewarm(32)
LaneRenderer.init()
HudController.init()
CombatController.init()
UpgradeUIController.init()

CombatController.setObstacleProvider(LaneRenderer.obstacles)
CombatController.Fired:Connect(LaneRenderer.predictShot)
UpgradeUIController.Opened:Connect(function(_offerId: number)
	refreshCombat()
end)
UpgradeUIController.Closed:Connect(refreshCombat)

Network.RunStateChanged:connect(applyState)

-- A respawned character goes straight back onto the rail (CombatController pins it each frame);
-- the camera stays locked on the lane.
player.CharacterAdded:Connect(function()
	local state = currentState
	if state then
		LaneCamera.setLane(state.laneOrigin, false)
	end
end)

-- Catch up with a run already in progress (the server may have started it before this script
-- ran). Retries until the server has a run for this player.
task.spawn(function()
	for _ = 1, 20 do
		local snapshot = Network.FetchRunSnapshot:invoke({})
		if snapshot then
			local previous = currentState
			if previous == nil or previous.runId == snapshot.state.runId then
				LaneRenderer.applySnapshot(snapshot)
				HudController.applySnapshot(snapshot)
				CombatController.setLoadout(snapshot.loadout)
				currentState = nil
				applyState(snapshot.state)
			end
			return
		end
		task.wait(0.5)
	end
end)
