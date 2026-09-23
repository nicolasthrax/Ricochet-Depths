-- Bridges the run loop to real characters. Injected into MatchService so the loop itself
-- never touches Roblox character internals and stays testable.
local WorldAdapter = {}

local function rootOf(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function WorldAdapter.GetPosition(player)
	local root = rootOf(player)
	return root and root.Position or nil
end

function WorldAdapter.Teleport(player, position)
	local root = rootOf(player)
	if not root then
		return false
	end
	-- Lifted clear of the floor so the character does not spawn embedded in geometry.
	root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	return true
end

function WorldAdapter.SetWalkSpeed(player, speed)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	humanoid.WalkSpeed = speed
	return true
end

return WorldAdapter
