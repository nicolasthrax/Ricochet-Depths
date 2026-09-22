-- Cosmetic hit bursts, driven by server-confirmed impacts. Parts are pooled, never created
-- at runtime, and exist only on this client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EffectConfig = require(ReplicatedStorage:WaitForChild("EffectConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local projectileImpact = Remotes.Get("ProjectileImpact")

local folder = Instance.new("Folder")
folder.Name = "ImpactEffects"
folder.Parent = workspace

local free = table.create(EffectConfig.PoolSize)
local active = {}

for index = 1, EffectConfig.PoolSize do
	local part = Instance.new("Part")
	part.Name = "Impact"
	part.Size = EffectConfig.StartSize
	part.Color = EffectConfig.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Position = EffectConfig.StoragePosition
	part.Parent = folder
	free[index] = part
end

local function spawnBurst(position, normal)
	local count = #free
	if count == 0 then
		return false -- pool dry: drop the burst rather than allocating
	end

	local part = free[count]
	free[count] = nil

	part.Size = EffectConfig.StartSize
	part.Transparency = 0
	part.CFrame = CFrame.lookAlong(position + normal * 0.1, normal)
	table.insert(active, { part = part, startedAt = os.clock() })
	return true
end

-- The server batches contacts, so one remote carries many impacts.
projectileImpact.OnClientEvent:Connect(function(positions, normals)
	if type(positions) ~= "table" or type(normals) ~= "table" then
		return
	end
	for index, position in positions do
		local normal = normals[index]
		if normal and not spawnBurst(position, normal) then
			break
		end
	end
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for index = #active, 1, -1 do
		local entry = active[index]
		local alpha = (now - entry.startedAt) / EffectConfig.Duration

		if alpha >= 1 then
			entry.part.Transparency = 1
			entry.part.Position = EffectConfig.StoragePosition
			free[#free + 1] = entry.part
			table.remove(active, index)
		else
			entry.part.Size = EffectConfig.StartSize:Lerp(EffectConfig.EndSize, alpha)
			entry.part.Transparency = alpha
		end
	end
end)
