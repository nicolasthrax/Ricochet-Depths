-- Which players on this server are Roblox friends, for the party bonus. Asking Roblox
-- (Player:IsFriendsWith) is a web call that yields, and a run starts inside Heartbeat, where
-- nothing may yield. So friendships are looked up in the background as players join, and a run
-- only ever reads what is already known. A pair not looked up yet counts as not friends.
local FriendCache = {}
FriendCache.__index = FriendCache

-- check(a, b) -> bool, may yield and may throw (it is called under pcall).
function FriendCache.new(check)
	return setmetatable({ _check = check, _pairs = {} }, FriendCache)
end

local function pairKey(a, b)
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return tostring(low) .. ":" .. tostring(high)
end

-- Looks up `player` against everyone in `others`, each in its own thread.
function FriendCache:Learn(player, others)
	for _, other in others do
		if other ~= player then
			task.spawn(function()
				local ok, friends = pcall(self._check, player, other)
				self._pairs[pairKey(player, other)] = ok and friends == true
			end)
		end
	end
end

function FriendCache:AreFriends(a, b)
	if a == nil or b == nil or a == b then
		return false
	end
	return self._pairs[pairKey(a, b)] == true
end

-- Forgets every pair a departing player was in.
function FriendCache:Forget(player)
	local id = tostring(player.UserId)
	for key in self._pairs do
		local low, high = string.match(key, "^(%d+):(%d+)$")
		if low == id or high == id then
			self._pairs[key] = nil
		end
	end
end

return FriendCache
