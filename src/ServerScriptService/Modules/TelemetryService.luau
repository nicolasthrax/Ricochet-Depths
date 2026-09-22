-- Rate-limited gameplay event logging. Deliberately thin: it never records names, user ids or
-- anything else that identifies a person, only an opaque per-session participant index.
local TelemetryService = {}
TelemetryService.__index = TelemetryService

local DEFAULT_RULES = {
	-- Events per minute, per event name. Anything past the budget is counted, not emitted.
	DefaultBudget = 120,
	Budgets = {
		ShotFired = 30,
		EnemyDefeated = 60,
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
		_participants = {},
		_nextParticipant = 0,
		_enabled = true,
	}, TelemetryService)
end

function TelemetryService:SetEnabled(enabled)
	self._enabled = enabled
end

-- Maps a player to a stable, meaningless index for the lifetime of this server.
function TelemetryService:ParticipantId(player)
	if player == nil then
		return 0
	end
	local existing = self._participants[player]
	if existing then
		return existing
	end
	self._nextParticipant += 1
	self._participants[player] = self._nextParticipant
	return self._nextParticipant
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

function TelemetryService:GetStats()
	return { emitted = self._emitted, dropped = self._dropped }
end

function TelemetryService:Clear(player)
	self._participants[player] = nil
end

return TelemetryService
