-- Cosmetic feedback for server-confirmed impacts: hit bursts, sounds with a pitch that climbs
-- through a ricochet chain, floating damage numbers and camera shake. Everything is pooled,
-- never created at runtime, and exists only on this client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EffectConfig = require(ReplicatedStorage:WaitForChild("EffectConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local SoundConfig = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local CameraShake = require(script.Parent:WaitForChild("CameraShake"))
local DamagePopups = require(script.Parent:WaitForChild("DamagePopups"))
local SoundPlayer = require(script.Parent:WaitForChild("SoundPlayer"))

local projectileImpact = Remotes.Get("ProjectileImpact")
local player = Players.LocalPlayer
local sounds = SoundPlayer.Shared()
local shake = CameraShake.Shared()

-- Player-set comfort option, defaulting to full until the profile arrives.
local function effectIntensity()
	local value = player:GetAttribute("EffectIntensity")
	return type(value) == "number" and math.clamp(value, 0, 1) or 1
end

local folder = Instance.new("Folder")
folder.Name = "ImpactEffects"
folder.Parent = workspace

local popups = DamagePopups.new(workspace)

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
	local intensity = effectIntensity()
	if intensity <= 0 then
		return true -- effects disabled by the player; keep draining the batch
	end

	local count = #free
	if count == 0 then
		return false -- pool dry: drop the burst rather than allocating
	end

	local part = free[count]
	free[count] = nil

	part.Size = EffectConfig.StartSize
	part.Transparency = 1 - intensity
	part.CFrame = CFrame.lookAlong(position + normal * 0.1, normal)
	table.insert(active, { part = part, startedAt = os.clock(), intensity = intensity })
	return true
end

-- Positional cues are quieter the further they are from the player.
local function volumeAt(position)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return 1
	end
	return SoundConfig.VolumeForDistance((position - root.Position).Magnitude)
end

local CUE_FOR_KIND = { Wall = "WallBounce", Hit = "EnemyHit", Block = "ShieldBlock" }

-- The server batches contacts, so one remote carries many impacts. details is optional so an
-- older server's two-argument batch still draws its bursts.
projectileImpact.OnClientEvent:Connect(function(positions, normals, details)
	if type(positions) ~= "table" or type(normals) ~= "table" then
		return
	end
	local kinds = type(details) == "table" and type(details.Kinds) == "table" and details.Kinds or {}
	local contacts = type(details) == "table" and type(details.Contacts) == "table" and details.Contacts or {}
	local damage = type(details) == "table" and type(details.Damage) == "table" and details.Damage or {}

	local now = os.clock()
	local voiced = 0
	for index, position in positions do
		local normal = normals[index]
		if typeof(position) ~= "Vector3" or typeof(normal) ~= "Vector3" then
			continue
		end
		spawnBurst(position, normal)

		local kind = kinds[index] or "Wall"
		shake:Impulse(EffectConfig.ShakeImpulses[kind] or 0, now)

		if kind ~= "Wall" and type(damage[index]) == "number" then
			popups:Show(position, damage[index], kind, now)
		end

		-- Kills get their shatter from EnemyDefeated; everything else speaks here, up to a cap.
		local cue = CUE_FOR_KIND[kind]
		if cue and voiced < SoundConfig.MaxSoundsPerBatch then
			local pitch = kind == "Wall" and SoundConfig.BouncePitch(contacts[index]) or 1
			if sounds:Play(cue, { pitch = pitch, volume = volumeAt(position) }) then
				voiced += 1
			end
		end
	end
end)

Remotes.Get("EnemyDefeated").OnClientEvent:Connect(function(position)
	if typeof(position) ~= "Vector3" then
		return
	end
	sounds:Play("EnemyShatter", { volume = volumeAt(position) })
end)

-- Taking a hit shakes the camera hardest of all, so damage is felt even mid-aim.
local lastHealth = nil
Remotes.Get("PlayerStateChanged").OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.Health) ~= "number" then
		return
	end
	if lastHealth and snapshot.Health < lastHealth then
		shake:Impulse(EffectConfig.ShakeImpulses.PlayerHurt, os.clock())
	end
	lastHealth = snapshot.Health
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	popups:Step(now)
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
			entry.part.Transparency = 1 - entry.intensity * (1 - alpha)
		end
	end
end)
