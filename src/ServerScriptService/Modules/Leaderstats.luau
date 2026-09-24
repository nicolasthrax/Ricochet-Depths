-- The player-list columns: level, coin balance and deepest room reached. Roblox shows any values
-- in a player's "leaderstats" folder there, in the order they were created, and sorts by the first.
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

local function set(folder, name, amount)
	local holder = value(folder, name)
	if holder.Value ~= amount then
		holder.Value = amount
	end
end

-- `level` is optional so older callers keep working; without it the column is left alone.
function Leaderstats.Update(player, coins, bestDepth, level)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
		-- Created first so it is the leftmost column and the one the list sorts by.
		value(folder, "Level").Value = 1
	end
	if level then
		set(folder, "Level", level)
	end
	set(folder, "Coins", coins)
	set(folder, "Best Depth", bestDepth)
end

return Leaderstats
