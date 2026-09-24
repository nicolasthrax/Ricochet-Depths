-- Brings the lobby to life on this client: every part in Lobby.Ambience with a Spin attribute
-- (degrees per second) turns, and one with a Bob attribute (studs) floats up and down. Local and
-- cosmetic only; paused while this player is in a run, when the lobby is out of sight.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local lobby = workspace:WaitForChild("Lobby", 30)
local ambience = lobby and lobby:WaitForChild("Ambience", 10)
if not ambience then
	return
end

local movers = {}
for index, part in ambience:GetChildren() do
	if part:IsA("BasePart") and (part:GetAttribute("Spin") or part:GetAttribute("Bob")) then
		table.insert(movers, {
			part = part,
			base = part.CFrame,
			spin = math.rad(part:GetAttribute("Spin") or 0),
			bob = part:GetAttribute("Bob") or 0,
			phase = index * 0.7,
		})
	end
end

local elapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	local state = player:GetAttribute("RunState")
	if state ~= nil and state ~= "Lobby" then
		return
	end
	elapsed += deltaTime
	for _, mover in movers do
		local lift = math.sin(elapsed * 1.6 + mover.phase) * mover.bob
		mover.part.CFrame = mover.base * CFrame.new(0, lift, 0) * CFrame.Angles(0, elapsed * mover.spin, 0)
	end
end)
