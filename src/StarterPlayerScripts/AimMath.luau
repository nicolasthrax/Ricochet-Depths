-- Pure drag-to-aim maths, kept free of services so the headless suite can cover it.
local AimMath = {}

local MOUSE_BUTTON = Enum.UserInputType.MouseButton1
local MOUSE_MOVE = Enum.UserInputType.MouseMovement

-- Whether an InputChanged/InputEnded event belongs to the drag that `active` started.
-- A touch keeps one InputObject for its whole life, but the mouse does not: holding
-- MouseButton1 and moving reports MouseMovement objects, never the button's own object.
-- Matching by identity alone therefore never saw a desktop drag move.
function AimMath.IsSameGesture(active, input)
	if not active or not input then
		return false
	end
	if input == active then
		return true
	end
	if active.UserInputType == MOUSE_BUTTON then
		return input.UserInputType == MOUSE_BUTTON or input.UserInputType == MOUSE_MOVE
	end
	return false
end

-- Whether a press starting at `position` should begin an aim. On touch the left of the screen
-- belongs to the movement thumbstick; the mouse aims from anywhere. With no viewport size to go
-- on, every touch aims rather than none.
function AimMath.IsInAimZone(inputType, position, viewportSize, config)
	if inputType ~= Enum.UserInputType.Touch then
		return true
	end
	if not viewportSize or viewportSize.X <= 0 then
		return true
	end
	return position.X >= viewportSize.X * config.TouchAimZoneStart
end

-- Minimum pull, in pixels, before a drag counts as an aim.
function AimMath.DeadzoneFor(inputType, config)
	if inputType == Enum.UserInputType.Touch then
		return config.TouchDeadzonePixels
	end
	return config.DeadzonePixels
end

-- Slingshot: the shot goes opposite the pull. Returns a unit screen direction and 0..1
-- power, or nil inside the deadzone. deadzone defaults to the mouse deadzone.
function AimMath.ReadDrag(origin, current, config, deadzone)
	local pull = Vector2.new(current.X - origin.X, current.Y - origin.Y)
	if pull.Magnitude < (deadzone or config.DeadzonePixels) then
		return nil, 0
	end
	return -pull.Unit, math.clamp(pull.Magnitude / config.MaxDragPixels, 0, 1)
end

-- Screen drag maps onto the camera's flattened basis: +x is camera-right, screen-up is forward.
function AimMath.ScreenToWorldDirection(cameraFrame, aimScreen)
	local forward = Vector3.new(cameraFrame.LookVector.X, 0, cameraFrame.LookVector.Z)
	local right = Vector3.new(cameraFrame.RightVector.X, 0, cameraFrame.RightVector.Z)
	if forward.Magnitude < 1e-3 then
		-- Near top-down camera: LookVector is almost vertical, so use UpVector as the forward hint.
		forward = Vector3.new(cameraFrame.UpVector.X, 0, cameraFrame.UpVector.Z)
	end
	if forward.Magnitude < 1e-3 or right.Magnitude < 1e-3 then
		return nil
	end

	local world = right.Unit * aimScreen.X + forward.Unit * -aimScreen.Y
	if world.Magnitude < 1e-3 then
		return nil
	end
	return world.Unit
end

return AimMath
