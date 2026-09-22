-- Per-player, per-action rate limiting for RemoteEvents. Every remote the client can spam
-- goes through this before any state is touched.
local RemoteGuard = {}
RemoteGuard.__index = RemoteGuard

function RemoteGuard.new(rules)
	return setmetatable({
		_rules = rules or {},
		_buckets = {},
	}, RemoteGuard)
end

-- Rules are { [action] = { Cooldown = seconds, Burst = count } }.
function RemoteGuard:Check(player, action, now)
	local rule = self._rules[action]
	if not rule then
		return true
	end

	local byPlayer = self._buckets[player]
	if not byPlayer then
		byPlayer = {}
		self._buckets[player] = byPlayer
	end

	local bucket = byPlayer[action]
	if not bucket then
		bucket = { tokens = rule.Burst or 1, updatedAt = now }
		byPlayer[action] = bucket
	end

	-- Token bucket: refills at one token per cooldown, capped at the burst allowance.
	local burst = rule.Burst or 1
	local refill = (now - bucket.updatedAt) / rule.Cooldown
	bucket.tokens = math.min(burst, bucket.tokens + refill)
	bucket.updatedAt = now

	if bucket.tokens < 1 then
		return false, "rate limited"
	end
	bucket.tokens -= 1
	return true
end

function RemoteGuard:Clear(player)
	self._buckets[player] = nil
end

function RemoteGuard:ClearAll()
	table.clear(self._buckets)
end

return RemoteGuard
