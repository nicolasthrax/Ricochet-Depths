-- Server-side sanity checks on fire requests. The client is never trusted for anything
-- but an aim direction and a power scalar, and both are re-clamped here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))

local FireValidator = {}
local lastFireTime = {}

local function isFiniteNumber(value)
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Returns rootPart, direction, power on success, or nil plus a reason string.
function FireValidator.Validate(player, direction, power)
	local now = os.clock()
	local last = lastFireTime[player]
	if last and now - last < ProjectileConfig.FireCooldown then
		return nil, "rate limited"
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return nil, "no live character"
	end

	if typeof(direction) ~= "Vector3" then
		return nil, "direction is not a Vector3"
	end
	if not (isFiniteNumber(direction.X) and isFiniteNumber(direction.Y) and isFiniteNumber(direction.Z)) then
		return nil, "direction is not finite"
	end

	-- Aim is resolved on the horizontal plane; the client's Y component is discarded outright.
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return nil, "direction has no horizontal component"
	end

	if not isFiniteNumber(power) then
		return nil, "power is not finite"
	end
	local clampedPower = math.clamp(power, ProjectileConfig.MinPower, ProjectileConfig.MaxPower)

	lastFireTime[player] = now
	return rootPart, flat.Unit, clampedPower
end

function FireValidator.Clear(player)
	lastFireTime[player] = nil
end

return FireValidator
