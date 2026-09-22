-- Central switch for developer tooling. Nothing behind these flags is reachable by a normal
-- player in a published build: Studio is trusted, and live servers require an allowlisted id.
local RunService = game:GetService("RunService")

local DebugConfig = {}

-- Studio only by default. Set to true only for a private test build.
DebugConfig.ForceEnabled = false

-- User ids allowed to open developer tooling on a live server. Keep empty in source control;
-- it is populated per test build, not committed with real ids.
DebugConfig.AllowedUserIds = {}

DebugConfig.LogTelemetry = true
DebugConfig.OverlayUpdateInterval = 0.25

function DebugConfig.IsStudio()
	return RunService:IsStudio()
end

function DebugConfig.IsEnabled()
	return DebugConfig.ForceEnabled or RunService:IsStudio()
end

function DebugConfig.IsDebugUser(player)
	if DebugConfig.IsEnabled() then
		return true
	end
	if not player then
		return false
	end
	for _, userId in DebugConfig.AllowedUserIds do
		if userId == player.UserId then
			return true
		end
	end
	return false
end

return DebugConfig
