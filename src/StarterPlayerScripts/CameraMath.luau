-- Pure tactical-camera maths, kept free of services so the headless suite can cover it.
local CameraMath = {}

-- The camera sits back along a ray that leaves the focus at `pitch` degrees above the horizon,
-- heading `yaw` degrees around +Y, and looks straight at the focus.
function CameraMath.ComputeFrame(focus, pitch, yaw, distance)
	local pitchRad = math.rad(pitch)
	local yawRad = math.rad(yaw)
	local horizontal = math.cos(pitchRad) * distance
	local offset = Vector3.new(math.sin(yawRad) * horizontal, math.sin(pitchRad) * distance, math.cos(yawRad) * horizontal)
	return CFrame.lookAt(focus + offset, focus)
end

-- Frame-rate independent blend factor for exponential smoothing at `rate` per second.
function CameraMath.SmoothAlpha(rate, deltaTime)
	return 1 - math.exp(-rate * math.max(deltaTime, 0))
end

function CameraMath.ClampZoom(distance, config)
	return math.clamp(distance, config.MinDistance, config.MaxDistance)
end

-- Turns the view by (yawDelta, pitchDelta) degrees. Yaw is free and wrapped into [0, 360);
-- pitch is held between the config limits so the view never goes flat or straight down.
function CameraMath.ApplyRotate(yaw, pitch, yawDelta, pitchDelta, config)
	return (yaw + yawDelta) % 360, math.clamp(pitch + pitchDelta, config.MinPitch, config.MaxPitch)
end

return CameraMath
