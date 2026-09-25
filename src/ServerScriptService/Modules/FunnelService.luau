-- Onboarding funnel and economy analytics. Each funnel step is reported once ever per player
-- (Flags.Funnel remembers it across sessions and servers), to our own TelemetryService and to
-- Roblox's AnalyticsService, whose funnel view is where the concept's go / no-go numbers are
-- read (docs/GO_NO_GO.md). Every coin and consumable that moves is also reported as an economy
-- event (a source or a sink). Everything Roblox-side runs under pcall: analytics may never break
-- the game.
local FunnelService = {}
FunnelService.__index = FunnelService

-- The funnel, in order. The index is the step number AnalyticsService is sent.
FunnelService.Steps = {
	"Join",
	"FirstInput",
	"FirstHit",
	"FirstUpgrade",
	"FirstFusion",
	"FirstRunEnd",
	"FirstBaseUpgrade",
}
local STEP_INDEX = {}
for index, step in FunnelService.Steps do
	STEP_INDEX[step] = index
end

-- What a grant's ledger key says about where the coins came from, as AnalyticsService
-- transaction types. Anything unlisted is ordinary play.
local SOURCE_TYPES = {
	daily = "TimedReward",
	dailymod = "TimedReward",
	offline = "TimedReward",
	receipt = "IAP",
	ad = "Gameplay",
	quest = "Gameplay",
	ach = "Gameplay",
	visit = "Gameplay",
	cheer = "Gameplay",
	code = "Gameplay",
}

-- The display names economy events are logged under.
local CURRENCY_NAMES = { Salvage = "Coins", Rerolls = "Rerolls", ReviveTokens = "ReviveTokens" }

-- options: persistence (PlayerDataService), telemetry (TelemetryService), analytics (Roblox's
-- AnalyticsService or a stand-in, optional), clock (os.clock by default).
function FunnelService.new(options)
	options = options or {}
	return setmetatable({
		_persistence = options.persistence,
		_telemetry = options.telemetry,
		_analytics = options.analytics,
		_clock = options.clock or os.clock,
		_seen = {}, -- player -> { [step] = true }, so repeat calls cost a lookup
	}, FunnelService)
end

-- Reports `step` for `player` the first time ever. Returns true when it was reported now.
function FunnelService:Step(player, step)
	local index = STEP_INDEX[step]
	if not index or not player then
		return false
	end
	local seen = self._seen[player]
	if not seen then
		seen = {}
		self._seen[player] = seen
	end
	if seen[step] then
		return false
	end
	local fresh = false
	local updated = self._persistence and self._persistence:Update(player, function(profile)
		if not profile.Flags.Funnel[step] then
			profile.Flags.Funnel[step] = true
			fresh = true
		end
	end)
	if not updated then
		-- Read-only or not loaded: "once ever" cannot be kept, so nothing is reported.
		return false
	end
	seen[step] = true
	if not fresh then
		return false
	end
	if self._telemetry then
		self._telemetry:Log("FunnelStep", { Step = step, Index = index }, self._clock())
	end
	if self._analytics then
		pcall(function()
			self._analytics:LogOnboardingFunnelStepEvent(player, index, step)
		end)
	end
	return true
end

-- The AnalyticsService transaction type for a grant's ledger key.
function FunnelService.SourceType(key)
	local prefix = type(key) == "string" and string.match(key, "^(%a+):") or nil
	return prefix and SOURCE_TYPES[prefix] or "Gameplay"
end

-- A coin or consumable movement, from PlayerDataService's economy hook. flow is "Source" or
-- "Sink"; detail is the grant's ledger key or the purchased item id.
function FunnelService:Economy(player, flow, currencyId, amount, balance, detail)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end
	local transaction = flow == "Source" and FunnelService.SourceType(detail) or "Shop"
	if flow == "Sink" and currencyId ~= "Salvage" then
		transaction = "Gameplay" -- a spent reroll or revive token
	end
	if self._telemetry then
		self._telemetry:Log("Economy", { Flow = flow, Currency = currencyId, Amount = amount, Type = transaction }, self._clock())
	end
	if self._analytics then
		pcall(function()
			self._analytics:LogEconomyEvent(
				player,
				flow == "Source" and Enum.AnalyticsEconomyFlowType.Source or Enum.AnalyticsEconomyFlowType.Sink,
				CURRENCY_NAMES[currencyId] or currencyId,
				amount,
				balance,
				transaction,
				flow == "Sink" and tostring(detail) or nil
			)
		end)
	end
end

function FunnelService:ClearPlayer(player)
	self._seen[player] = nil
end

return FunnelService
