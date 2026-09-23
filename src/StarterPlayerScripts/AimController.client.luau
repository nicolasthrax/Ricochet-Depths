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

local RENDER_STEP = "RicochetAim"
-- Same plane the server flies projectiles on, so the world line matches the real shot.
local PLANE_Y = RoomConfig.FloorY + ProjectileConfig.PlaneHeight

local player = Players.LocalPlayer
local fireProjectile = Remotes.Get("FireProjectile")
local indicator = AimIndicator.new(player:WaitForChild("PlayerGui"))

local dragOrigin = nil
local dragCurrent = nil
local activeInput = nil
local lastFireAt = -math.huge

-- Mirrors the server's cooldown so a refused shot is visible before it is sent.
local function isReady()
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

local function muzzlePosition()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end
	return Vector3.new(rootPart.Position.X, PLANE_Y, rootPart.Position.Z)
end

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
	local aimScreen, power = AimMath.ReadDrag(dragOrigin, dragCurrent, AimConfig)
	if not aimScreen then
		indicator:Hide()
		return
	end
	indicator:Show(dragOrigin, aimScreen, power, isReady(), muzzlePosition(), worldDirectionFor(aimScreen))
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or activeInput or not isAimInput(input) or not canAim() then
		return
	end
	activeInput = input
	dragOrigin = Vector2.new(input.Position.X, input.Position.Y)
	dragCurrent = dragOrigin
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, renderAim)
end)

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

	local origin = dragOrigin
	endDrag()

	local aimScreen, power = AimMath.ReadDrag(origin, Vector2.new(input.Position.X, input.Position.Y), AimConfig)
	if not aimScreen or not canAim() then
		return
	end

	if not isReady() then
		return -- the server would refuse it; do not spend bandwidth on the attempt
	end

	local worldDirection = worldDirectionFor(aimScreen)
	if worldDirection then
		lastFireAt = os.clock()
		fireProjectile:FireServer(worldDirection, power)
	end
end)
