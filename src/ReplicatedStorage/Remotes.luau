-- Single access point for RemoteEvents. The server creates them, clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local REMOTE_NAMES = {
	-- client -> server (every one of these is validated and rate limited server-side)
	"FireProjectile", -- aim direction + power
	"ChooseUpgrade", -- offer id + card id
	"RequestStartRun",
	"RequestReturnToLobby",
	"UpdateSettings", -- accessibility options, sanitised server-side before storage

	-- server -> clients (display and cosmetics only)
	"ProjectileImpact", -- batched confirmed contacts
	"EnemyDefeated",
	"RunStateChanged",
	"PlayerStateChanged",
	"UpgradeOffer",
	"UpgradeResolved",
	"RunResults",
	"ProfileSync", -- currency, flags and settings for this player
	"DebugStats", -- developer overlay only; sent to allowlisted users
}

local Remotes = {}
local cachedFolder = nil

local function getFolder()
	if cachedFolder then
		return cachedFolder
	end

	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		for _, name in REMOTE_NAMES do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
		end
		cachedFolder = folder
	else
		cachedFolder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end

	return cachedFolder
end

function Remotes.Get(name)
	return getFolder():WaitForChild(name)
end

return Remotes
