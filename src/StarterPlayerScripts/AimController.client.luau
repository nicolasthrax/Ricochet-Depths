-- Drag to aim (slingshot: pull back, fire forward), release to shoot.
-- Sends only a direction and a power scalar; the server decides everything else.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AimConfig = require(ReplicatedStorage:WaitForChild("AimConfig"))
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local AimIndicator = require(script.Parent:WaitForChild("AimIndicator"))
local AimMath = require(script.Parent:WaitForChild("AimMath"))
local SoundPlayer = require(script.Parent:WaitForChild("SoundPlayer"))

local RENDER_STEP = "RicochetAim"
-- Same plane the server flies projectiles on, so the world line matches the real shot.
local PLANE_Y = RoomConfig.FloorY + ProjectileConfig.PlaneHeight

local player = Players.LocalPlayer
local fireProjectile = Remotes.Get("FireProjectile")
local indicator = AimIndicator.new(player:WaitForChild("PlayerGui"), workspace, RoomConfig.FloorY)

local dragOrigin = nil
local dragCurrent = nil
local activeInput = nil
local activeDeadzone = AimConfig.DeadzonePixels
local lastFireAt = -math.huge

-- Mirrors the server's cooldown and orb count so a refused shot is visible before it is sent.
-- Orbs is published by ClientMain from the player's state; nil (orbs off) never blocks.
local function isReady()
	local orbs = player:GetAttribute("Orbs")
	if type(orbs) == "number" and orbs < 1 then
		return false
	end
	local cooldown = player:GetAttribute("FireCooldown")
	if type(cooldown) ~= "number" then
		return true
	end
	return os.clock() - lastFireAt >= cooldown
end

local function isAimInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- ClientMain publishes the run state as an attribute; aiming is only live during combat.
local function canAim()
	return player:GetAttribute("RunState") == RunConfig.States.Combat
end

local function worldDirectionFor(aimScreen)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	return AimMath.ScreenToWorldDirection(camera.CFrame, aimScreen)
end

-- Where the server spawns the shot: MuzzleOffset ahead of the character on the projectile
-- plane, so the line starts clear of the body instead of running through the torso.
local function muzzlePosition(worldDirection)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not worldDirection then
		return nil
	end
	local base = Vector3.new(rootPart.Position.X, PLANE_Y, rootPart.Position.Z)
	return base + worldDirection * ProjectileConfig.MuzzleOffset
end

-- The first descent's pulsing hint line, shown until the first shot (ClientMain sets the
-- FirstDescent attribute from the run state).
local hintDone = false
local hintShowing = false
RunService.RenderStepped:Connect(function()
	local want = not hintDone and not activeInput and canAim() and player:GetAttribute("FirstDescent") == true
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if want and rootPart then
		local look = rootPart.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			local direction = flat.Unit
			indicator:Pulse(muzzlePosition(direction), direction, AimIndicator.PulseAlpha(os.clock()))
			hintShowing = true
			return
		end
	end
	if hintShowing and not activeInput then
		hintShowing = false
		indicator:Hide()
	end
end)

local function endDrag()
	RunService:UnbindFromRenderStep(RENDER_STEP)
	activeInput = nil
	dragOrigin = nil
	dragCurrent = nil
	indicator:Hide()
end

-- Redrawn every frame, not only on input, so the line follows the character and camera
-- while the pointer is held still.
local function renderAim()
	if not activeInput then
		return
	end
	if not canAim() then
		-- The run moved on mid-drag; drop the gesture rather than firing into a cleared room.
		endDrag()
		return
	end
	local aimScreen, power = AimMath.ReadDrag(dragOrigin, dragCurrent, AimConfig, activeDeadzone)
	if not aimScreen then
		indicator:Hide()
		return
	end
	local worldDirection = worldDirectionFor(aimScreen)
	indicator:Show(power, isReady(), muzzlePosition(worldDirection), worldDirection)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or activeInput or not isAimInput(input) or not canAim() then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local camera = workspace.CurrentCamera
	-- Left-side touches drive the movement thumbstick; only right-side touches aim.
	if not AimMath.IsInAimZone(input.UserInputType, position, camera and camera.ViewportSize, AimConfig) then
		return
	end
	activeInput = input
	activeDeadzone = AimMath.DeadzoneFor(input.UserInputType, AimConfig)
	dragOrigin = position
	dragCurrent = dragOrigin
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, renderAim)
end)

-- Alt-tabbing mid-drag means the release is never seen. Drop the gesture rather than leave it
-- live, where the next click's release would fire it from the stale press point.
UserInputService.WindowFocusReleased:Connect(function()
	if activeInput then
		endDrag()
	end
end)

-- A second finger means a camera twist or pinch, not a shot.
local function dropForCameraGesture(_, _, _, state)
	if activeInput and state == Enum.UserInputState.Begin then
		endDrag()
	end
end
UserInputService.TouchRotate:Connect(dropForCameraGesture)
UserInputService.TouchPinch:Connect(dropForCameraGesture)

UserInputService.InputChanged:Connect(function(input)
	if not AimMath.IsSameGesture(activeInput, input) then
		return
	end
	dragCurrent = Vector2.new(input.Position.X, input.Position.Y)
end)

UserInputService.InputEnded:Connect(function(input)
	if not activeInput or input.UserInputType ~= activeInput.UserInputType then
		return
	end
	if not AimMath.IsSameGesture(activeInput, input) then
		return
	end

	local origin, deadzone = dragOrigin, activeDeadzone
	endDrag()

	local released = Vector2.new(input.Position.X, input.Position.Y)
	local aimScreen, power = AimMath.ReadDrag(origin, released, AimConfig, deadzone)
	if not aimScreen or not canAim() then
		return
	end

	if not isReady() then
		if type(player:GetAttribute("Orbs")) == "number" and player:GetAttribute("Orbs") < 1 then
			SoundPlayer.Shared():Play("ShieldBlock", { volume = 0.4 })
		end
		return -- the server would refuse it; do not spend bandwidth on the attempt
	end

	local worldDirection = worldDirectionFor(aimScreen)
	if worldDirection then
		lastFireAt = os.clock()
		-- Spent at once on this client, so a quick second tap is not wasted on an empty hand;
		-- the server's count arrives a moment later and replaces this guess.
		local orbs = player:GetAttribute("Orbs")
		if type(orbs) == "number" then
			player:SetAttribute("Orbs", math.max(orbs - 1, 0))
		end
		fireProjectile:FireServer(worldDirection, power)
		hintDone = true
		-- Heard the instant the shot is sent: waiting for the server would make it feel laggy.
		SoundPlayer.Shared():Play("Fire")
	end
end)

--// dash ---------------------------------------------------------------------------
-- Q, Left Shift or the gamepad's B. The client moves its own character (it owns its physics)
-- with a short burst of velocity; the server keeps the cooldown and grants the i-frames.
local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local ArsenalConfig = require(ReplicatedStorage:WaitForChild("ArsenalConfig"))
local dashRemote = Remotes.Get("Dash")
local DASH_KEYS = { [Enum.KeyCode.Q] = true, [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.ButtonB] = true }
local lastDashAt = -math.huge

local function dashHeading(rootPart, humanoid)
	local moving = humanoid and humanoid.MoveDirection
	if moving and moving.Magnitude > 0.1 then
		return Vector3.new(moving.X, 0, moving.Z).Unit
	end
	local look = rootPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
end

local function dash()
	if not FeatureFlags.IsEnabled("Dash") or not canAim() then
		return
	end
	local cooldown = player:GetAttribute("DashCooldown")
	cooldown = type(cooldown) == "number" and cooldown or ArsenalConfig.Dash.Cooldown
	if os.clock() - lastDashAt < cooldown then
		return
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end
	lastDashAt = os.clock()
	player:SetAttribute("DashReadyAt", lastDashAt + cooldown)
	local heading = dashHeading(rootPart, humanoid)
	local config = ArsenalConfig.Dash

	local attachment = rootPart:FindFirstChild("DashAttachment") or Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = rootPart
	local push = rootPart:FindFirstChild("DashVelocity") or Instance.new("LinearVelocity")
	push.Name = "DashVelocity"
	push.Attachment0 = attachment
	push.MaxForce = math.huge
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	push.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	local speed = config.Distance / config.Duration
	push.PlaneVelocity = Vector2.new(heading.X * speed, heading.Z * speed)
	push.Parent = rootPart
	push.Enabled = true
	dashRemote:FireServer(heading)
	SoundPlayer.Shared():Play("WallBounce", { pitch = 0.7 })
	task.delay(config.Duration, function()
		push.Enabled = false
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if DASH_KEYS[input.KeyCode] then
		dash()
	end
end)

-- The HUD's DASH button (touch) asks through this attribute's signal.
player:GetAttributeChangedSignal("DashRequest"):Connect(function()
	dash()
end)
