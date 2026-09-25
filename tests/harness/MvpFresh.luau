-- Isolation between lane-game test files (mvp_*.test.luau), which share one bundle and one stub
-- DataModel. Call __freshMvp() at the top of each file: every module is re-required fresh, the
-- runtime remotes, built lanes and players from earlier files are removed, and handlers that an
-- earlier file's services left on engine signals are dropped.
function __freshMvp()
	local replicated = game:GetService("ReplicatedStorage")
	local remotes = replicated:FindFirstChild("NetworkRemotes")
	if remotes then
		remotes:Destroy()
	end
	local lanes = workspace:FindFirstChild("Lanes")
	if lanes then
		lanes:Destroy()
	end
	local runService = game:GetService("RunService")
	local players = game:GetService("Players")
	for _, signal in { runService.Heartbeat, players.PlayerAdded, players.PlayerRemoving } do
		table.clear(signal._handlers)
	end
	for _, player in players:GetPlayers() do
		player:Destroy()
	end
	__resetModules()
end
