-- Tactical camera: while a run is active the default orbit camera is replaced by a fixed
-- high-angle view that follows the character, so walls and the aim line are never hidden
-- behind the avatar. The default camera is handed back in the lobby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraConfig = require(ReplicatedStorage:WaitForChild("CameraConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local CameraMath = require(script.Parent:WaitForChild("CameraMath"))

local RENDER_STEP = "RicochetCamera"

local player = Players.LocalPlayer

local active = false
local focus = nil
local distance = CameraConfig.DefaultDistance
local targetDistance = CameraConfig.DefaultDistance
local savedFieldOfView = nil

local function characterFocus()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return rootPart and rootPart.Position or nil
end

local function update(deltaTime)
	local camera = workspace.CurrentCamera
	local target = characterFocus()
	if not camera or not target then
		return
	end

	if not focus or (target - focus).Magnitude > CameraConfig.SnapDistance then
		focus = target
	else
		focus = focus:Lerp(target, CameraMath.SmoothAlpha(CameraConfig.FollowRate, deltaTime))
	end
	distance += (targetDistance - distance) * CameraMath.SmoothAlpha(CameraConfig.ZoomRate, deltaTime)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CameraMath.ComputeFrame(focus, CameraConfig.Pitch, CameraConfig.Yaw, distance)
end

local function activate()
	if active then
		return
	end
	active = true
	focus = nil -- snap to the character on the first frame
	local camera = workspace.CurrentCamera
	if camera then
		savedFieldOfView = camera.FieldOfView
		camera.FieldOfView = CameraConfig.FieldOfView
	end
	-- Camera priority, so AimController (bound just after it) draws against this frame's view.
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value, update)
end

local function deactivate()
	if not active then
		return
	end
	active = false
	RunService:UnbindFromRenderStep(RENDER_STEP)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if savedFieldOfView then
			camera.FieldOfView = savedFieldOfView
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

-- ClientMain publishes the run state; every state except the lobby is spent in the arena.
local function onRunStateChanged()
	local state = player:GetAttribute("RunState")
	if state ~= nil and state ~= RunConfig.States.Lobby then
		activate()
	else
		deactivate()
	end
end

player:GetAttributeChangedSignal("RunState"):Connect(onRunStateChanged)
onRunStateChanged()

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not active or gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	-- Wheel up (positive Z) zooms in.
	targetDistance = CameraMath.ClampZoom(targetDistance - input.Position.Z * CameraConfig.ZoomStep, CameraConfig)
end)
