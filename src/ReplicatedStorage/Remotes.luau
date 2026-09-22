-- Single access point for RemoteEvents. The server creates them, clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local REMOTE_NAMES = {
	"FireProjectile", -- client -> server: aim direction + power
	"ProjectileImpact", -- server -> clients: confirmed hit, cosmetic only
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
