-- Rate-limited gameplay event logging. Deliberately thin: no event carries a name, a user id or
-- anything else that identifies a person.
local TelemetryService = {}
TelemetryService.__index = TelemetryService

local DEFAULT_RULES = {
	-- Events per minute, per event name. Anything past the budget is counted, not emitted.
	DefaultBudget = 120,
	Budgets = {
		ShotFired = 30,
		EnemyDefeated = 60,
		Error = 20,
	},
	WindowSeconds = 60,
}

function TelemetryService.new(sink, rules)
	return setmetatable({
		_sink = sink,
		_rules = rules or DEFAULT_RULES,
		_windows = {},
		_dropped = 0,
		_emitted = 0,
		_enabled = true,
	}, TelemetryService)
end

function TelemetryService:SetEnabled(enabled)
	self._enabled = enabled
end

function TelemetryService:_budgetFor(eventName)
	return self._rules.Budgets[eventName] or self._rules.DefaultBudget
end

function TelemetryService:Log(eventName, payload, now)
	if not self._enabled then
		return false
	end

	local window = self._windows[eventName]
	if not window or now - window.startedAt >= self._rules.WindowSeconds then
		window = { startedAt = now, count = 0 }
		self._windows[eventName] = window
	end

	if window.count >= self:_budgetFor(eventName) then
		self._dropped += 1
		return false
	end
	window.count += 1
	self._emitted += 1

	if self._sink then
		self._sink(eventName, payload or {}, now)
	end
	return true
end

-- Errors are logged by category, never with a message that could carry player data.
function TelemetryService:LogError(category, detail, now)
	return self:Log("Error", {
		Category = tostring(category),
		Detail = detail ~= nil and tostring(detail):sub(1, 120) or nil,
	}, now)
end

function TelemetryService:GetStats()
	return { emitted = self._emitted, dropped = self._dropped }
end

return TelemetryService
