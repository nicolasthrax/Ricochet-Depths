-- The player-list columns: coin balance and deepest room reached. Roblox shows any values in a
-- player's "leaderstats" folder there.
local Leaderstats = {}

local function value(folder, name)
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new("IntValue")
	created.Name = name
	created.Value = 0
	created.Parent = folder
	return created
end

function Leaderstats.Update(player, coins, bestDepth)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local coinValue, depthValue = value(folder, "Coins"), value(folder, "Best Depth")
	if coinValue.Value ~= coins then
		coinValue.Value = coins
	end
	if depthValue.Value ~= bestDepth then
		depthValue.Value = bestDepth
	end
end

return Leaderstats
