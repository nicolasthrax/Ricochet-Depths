-- Developer-only counters overlay. It builds nothing at all unless DebugConfig says this user
-- may see it, so in a published build it is inert for normal players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent:WaitForChild("UiTheme"))

local player = Players.LocalPlayer

if not DebugConfig.IsDebugUser(player) then
	return
end

local gui = UiTheme.screenGui("RicochetDebug", player:WaitForChild("PlayerGui"), 100)
local panel = UiTheme.panel("Panel", gui)
panel.Position = UDim2.new(0, 16, 0, 16)
panel.Size = UDim2.fromOffset(250, 220)
panel.BackgroundTransparency = 0.15
panel.Visible = false
UiTheme.padding(panel, 8)

local label = UiTheme.label("Stats", panel, "waiting for server...", UiConfig.Text.Small)
label.Size = UDim2.fromScale(1, 1)
label.TextYAlignment = Enum.TextYAlignment.Top
label.Font = Enum.Font.Code

local latest = nil
local frameTimes = table.create(60, 1 / 60)
local frameIndex = 0

RunService.RenderStepped:Connect(function(deltaTime)
	frameIndex = frameIndex % 60 + 1
	frameTimes[frameIndex] = deltaTime
end)

local function averageFps()
	local total = 0
	for _, sample in frameTimes do
		total += sample
	end
	return total > 0 and (#frameTimes / total) or 0
end

Remotes.Get("DebugStats").OnClientEvent:Connect(function(stats)
	if type(stats) == "table" then
		latest = stats
	end
end)

-- F3 toggles, matching the usual convention for a developer overlay.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.F3 then
		panel.Visible = not panel.Visible
	end
end)

RunService.Heartbeat:Connect(function()
	if not panel.Visible or not latest then
		return
	end
	label.Text = string.format(
		"Ricochet Depths %s\nfps        %5.1f\nstate      %s\nroom       %d / %d\nenemies    %d live (all arenas)\nprojectile %d active (all arenas)\nplayers    %d in this run\narenas     %d busy / %d built\ntelemetry  %d sent / %d dropped\ndata       %d saves / %d fail / %d retry\n\nF3 to hide",
		RunConfig.Version,
		averageFps(),
		tostring(latest.State),
		latest.RoomIndex,
		latest.RoomCount,
		latest.EnemiesActive,
		latest.ProjectilesActive,
		latest.Participants,
		latest.ArenasBusy or 0,
		latest.ArenaSlots or 0,
		latest.TelemetryEmitted,
		latest.TelemetryDropped,
		latest.DataSaves,
		latest.DataSaveFailures,
		latest.DataRetries
	)
end)
