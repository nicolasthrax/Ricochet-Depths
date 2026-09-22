-- Drag to aim (slingshot: pull back, fire forward), release to shoot.
-- Sends only a direction and a power scalar; the server decides everything else.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AimConfig = require(ReplicatedStorage:WaitForChild("AimConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local AimIndicator = require(script.Parent:WaitForChild("AimIndicator"))

local player = Players.LocalPlayer
local fireProjectile = Remotes.Get("FireProjectile")
local indicator = AimIndicator.new(player:WaitForChild("PlayerGui"))

local dragOrigin = nil
local activeInput = nil

local function isAimInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Screen drag maps onto the camera's flattened basis: +x is camera-right, screen-up is forward.
local function screenToWorldDirection(aimScreen)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local cameraFrame = camera.CFrame
	local forward = Vector3.new(cameraFrame.LookVector.X, 0, cameraFrame.LookVector.Z)
	local right = Vector3.new(cameraFrame.RightVector.X, 0, cameraFrame.RightVector.Z)
	if forward.Magnitude < 1e-3 then
		-- Near top-down camera: LookVector is almost vertical, so use UpVector as the forward hint.
		forward = Vector3.new(cameraFrame.UpVector.X, 0, cameraFrame.UpVector.Z)
	end
	if forward.Magnitude < 1e-3 or right.Magnitude < 1e-3 then
		return nil
	end

	local world = right.Unit * aimScreen.X + forward.Unit * (-aimScreen.Y)
	if world.Magnitude < 1e-3 then
		return nil
	end
	return world.Unit
end

-- Returns the screen-space aim direction and power for the current drag, or nil inside the deadzone.
local function readDrag(input)
	local pull = Vector2.new(input.Position.X - dragOrigin.X, input.Position.Y - dragOrigin.Y)
	if pull.Magnitude < AimConfig.DeadzonePixels then
		return nil, 0
	end
	return -pull.Unit, math.clamp(pull.Magnitude / AimConfig.MaxDragPixels, 0, 1)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or activeInput or not isAimInput(input) then
		return
	end
	activeInput = input
	dragOrigin = Vector2.new(input.Position.X, input.Position.Y)
end)

UserInputService.InputChanged:Connect(function(input)
	if input ~= activeInput then
		return
	end
	local aimScreen, power = readDrag(input)
	if aimScreen then
		indicator:Show(dragOrigin, aimScreen, power)
	else
		indicator:Hide()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input ~= activeInput then
		return
	end

	local aimScreen, power = readDrag(input)
	activeInput = nil
	dragOrigin = nil
	indicator:Hide()

	if not aimScreen then
		return
	end

	local worldDirection = screenToWorldDirection(aimScreen)
	if worldDirection then
		fireProjectile:FireServer(worldDirection, power)
	end
end)
