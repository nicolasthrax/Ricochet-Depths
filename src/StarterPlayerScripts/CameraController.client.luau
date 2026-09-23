-- Tactical camera: while a run is active the default orbit camera is replaced by a high-angle
-- view that follows the character, so walls and the aim line are never hidden behind the
-- avatar. Players turn it with right-mouse drag or Q/E (twist on touch) and zoom with the wheel
-- (pinch on touch); pitch stays inside limits. The default camera is handed back in the lobby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraConfig = require(ReplicatedStorage:WaitForChild("CameraConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local CameraMath = require(script.Parent:WaitForChild("CameraMath"))
local CameraShake = require(script.Parent:WaitForChild("CameraShake"))

local RENDER_STEP = "RicochetCamera"

local player = Players.LocalPlayer
local shake = CameraShake.Shared()

-- The player's comfort setting, 0..1, published by ClientMain from the saved profile.
local function shakeScale()
	local value = player:GetAttribute("ScreenShake")
	return type(value) == "number" and value or 1
end

local active = false
local focus = nil
local distance = CameraConfig.DefaultDistance
local targetDistance = CameraConfig.DefaultDistance
local yaw, pitch = CameraConfig.Yaw, CameraConfig.Pitch
local rotating = false -- right mouse held
local pinchStartDistance = nil
local lastTwist = nil

local function rotate(yawDelta, pitchDelta)
	yaw, pitch = CameraMath.ApplyRotate(yaw, pitch, yawDelta, pitchDelta, CameraConfig)
end
local savedFieldOfView = nil

local function characterFocus()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return rootPart and rootPart.Position or nil
end

local function update(deltaTime)
	-- The descent cinematic owns the camera while it plays.
	if player:GetAttribute("Cinematic") then
		focus = nil -- snap back onto the character when it hands over
		return
	end
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

	local keyTurn = (UserInputService:IsKeyDown(Enum.KeyCode.E) and 1 or 0)
		- (UserInputService:IsKeyDown(Enum.KeyCode.Q) and 1 or 0)
	if keyTurn ~= 0 and not UserInputService:GetFocusedTextBox() then
		rotate(keyTurn * CameraConfig.KeyRotateSpeed * deltaTime, 0)
	end

	camera.CameraType = Enum.CameraType.Scriptable
	-- Shake moves the camera, never the focus, so aiming maths is unaffected by it.
	local frame = CameraMath.ComputeFrame(focus, pitch, yaw, distance)
	camera.CFrame = frame + shake:Sample(os.clock(), shakeScale())
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
	rotating = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if active and not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotating = true
		-- Pin the pointer while turning, as Roblox's own camera does.
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and rotating then
		rotating = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not active then
		return
	end
	if rotating and input.UserInputType == Enum.UserInputType.MouseMovement then
		-- Drag right turns the view right; drag down tilts it towards straight down.
		rotate(-input.Delta.X * CameraConfig.RotateSensitivity, input.Delta.Y * CameraConfig.RotateSensitivity)
		return
	end
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	-- Wheel up (positive Z) zooms in.
	targetDistance = CameraMath.ClampZoom(targetDistance - input.Position.Z * CameraConfig.ZoomStep, CameraConfig)
end)

-- Touch: twist two fingers to turn, pinch to zoom. AimController drops any aim drag when
-- either gesture starts, so a second finger never fires a shot.
UserInputService.TouchRotate:Connect(function(_, rotation, _, state, gameProcessed)
	if not active or gameProcessed then
		return
	end
	if state == Enum.UserInputState.Begin or lastTwist == nil then
		lastTwist = rotation
	end
	rotate(-(rotation - lastTwist), 0)
	lastTwist = rotation
	if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		lastTwist = nil
	end
end)

UserInputService.TouchPinch:Connect(function(_, scale, _, state, gameProcessed)
	if not active or gameProcessed then
		return
	end
	if state == Enum.UserInputState.Begin or pinchStartDistance == nil then
		pinchStartDistance = targetDistance
	end
	-- Fingers apart (scale > 1) zooms in.
	targetDistance = CameraMath.ClampZoom(pinchStartDistance / math.max(scale, 0.05), CameraConfig)
	if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		pinchStartDistance = nil
	end
end)
