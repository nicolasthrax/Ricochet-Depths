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

local function spawnBurst(position, normal, kind)
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

	local scale = kind == "Blast" and EffectConfig.BlastScale or 1
	part.Size = EffectConfig.StartSize * scale
	part.Color = EffectConfig.KindColors[kind] or EffectConfig.Color
	part.Transparency = 1 - intensity
	part.CFrame = CFrame.lookAlong(position + normal * 0.1, normal)
	table.insert(active, { part = part, startedAt = os.clock(), intensity = intensity, scale = scale })
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

local CUE_FOR_KIND = { Wall = "WallBounce", Hit = "EnemyHit", Block = "ShieldBlock", Crit = "EnemyHit", Arc = "EnemyHit", Blast = "EnemyShatter" }
-- Crits ring higher; burn ticks are silent so a burning room does not buzz.
local PITCH_FOR_KIND = { Crit = 1.35, Arc = 1.6, Blast = 0.8 }

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
		local kind = kinds[index] or "Wall"
		spawnBurst(position, normal, kind)

		shake:Impulse(EffectConfig.ShakeImpulses[kind] or 0, now)

		if kind ~= "Wall" and type(damage[index]) == "number" then
			popups:Show(position, damage[index], kind, now)
		end

		-- Kills get their shatter from EnemyDefeated; everything else speaks here, up to a cap.
		local cue = CUE_FOR_KIND[kind]
		if cue and voiced < SoundConfig.MaxSoundsPerBatch then
			local pitch = kind == "Wall" and SoundConfig.BouncePitch(contacts[index]) or PITCH_FOR_KIND[kind] or 1
			if sounds:Play(cue, { pitch = pitch, volume = volumeAt(position) }) then
				voiced += 1
			end
		end
	end
end)

-- Shatter: a kill bursts into shards of the enemy's colour that tumble outwards and fall. A
-- fixed pool, animated here; when every shard is in flight the next burst is simply smaller.
local EnemyConfig = require(ReplicatedStorage:WaitForChild("EnemyConfig"))
local SHARD_POOL, SHARDS_PER_KILL, SHARD_LIFE, GRAVITY = 72, 7, 0.7, 60
local shardFree, shardsLive = {}, {}
for index = 1, SHARD_POOL do
	local part = Instance.new("Part")
	part.Name = "Shard"
	part.Size = Vector3.new(0.6, 0.6, 0.6)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Position = EffectConfig.StoragePosition
	part.Parent = folder
	shardFree[index] = part
end
local shardRandom = Random.new()

local function shatter(position, color, champion)
	local intensity = effectIntensity()
	if intensity <= 0 then
		return
	end
	local count = math.floor((champion and SHARDS_PER_KILL * 2 or SHARDS_PER_KILL) * intensity + 0.5)
	for _ = 1, count do
		local part = table.remove(shardFree)
		if not part then
			return
		end
		local angle = shardRandom:NextNumber() * math.pi * 2
		local speed = 10 + shardRandom:NextNumber() * 14
		part.Color = color
		part.Size = Vector3.one * (0.35 + shardRandom:NextNumber() * 0.55)
		part.Transparency = 0
		part.Position = position
		table.insert(shardsLive, {
			part = part,
			origin = position,
			velocity = Vector3.new(math.cos(angle) * speed, 12 + shardRandom:NextNumber() * 12, math.sin(angle) * speed),
			spin = shardRandom:NextNumber() * 10,
			startedAt = os.clock(),
		})
	end
end

local function stepShards(now)
	for index = #shardsLive, 1, -1 do
		local shard = shardsLive[index]
		local t = now - shard.startedAt
		if t >= SHARD_LIFE then
			shard.part.Transparency = 1
			shard.part.Position = EffectConfig.StoragePosition
			table.insert(shardFree, shard.part)
			table.remove(shardsLive, index)
		else
			local position = shard.origin + shard.velocity * t + Vector3.new(0, -0.5 * GRAVITY * t * t, 0)
			shard.part.CFrame = CFrame.new(position) * CFrame.Angles(t * shard.spin, t * shard.spin * 0.7, 0)
			shard.part.Transparency = (t / SHARD_LIFE) ^ 2
		end
	end
end

Remotes.Get("EnemyDefeated").OnClientEvent:Connect(function(position, archetypeId, _shooterId, _contacts, champion)
	if typeof(position) ~= "Vector3" then
		return
	end
	sounds:Play("EnemyShatter", { volume = volumeAt(position) })
	local archetype = type(archetypeId) == "string" and EnemyConfig.Get(archetypeId)
	shatter(position, archetype and archetype.Color or EffectConfig.Color, type(champion) == "string")
	if archetype and (archetype.IsBoss or archetype.IsMiniBoss or archetype.IsElite) then
		shake:Impulse(EffectConfig.ShakeImpulses.Blast, os.clock())
	end
end)

-- Floor orbs: yours glow and bob, teammates' are dimmed so you can tell whose is whose. The
-- circles announcing a wave pulse. Both are server parts; this only changes how they look here.
local function eachArenaPool(poolName, visit)
	local arenas = workspace:FindFirstChild("Arenas")
	for _, slot in arenas and arenas:GetChildren() or {} do
		local arena = slot:FindFirstChild("Arena")
		local pool = arena and arena:FindFirstChild(poolName)
		if pool then
			for _, part in pool:GetChildren() do
				visit(part)
			end
		end
	end
end

local function stepArenaCues(now)
	local pulse = 0.5 + 0.5 * math.sin(now * 10)
	eachArenaPool("OrbDropPool", function(orb)
		if orb.Transparency < 1 then
			local mine = orb:GetAttribute("Owner") == player.UserId
			orb.LocalTransparencyModifier = mine and 0 or 0.65
		end
	end)
	eachArenaPool("WaveMarkers", function(marker)
		if marker.Transparency < 1 then
			marker.LocalTransparencyModifier = 0.5 * pulse
		end
	end)
end

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
	stepShards(now)
	stepArenaCues(now)
	for index = #active, 1, -1 do
		local entry = active[index]
		local alpha = (now - entry.startedAt) / EffectConfig.Duration

		if alpha >= 1 then
			entry.part.Transparency = 1
			entry.part.Position = EffectConfig.StoragePosition
			free[#free + 1] = entry.part
			table.remove(active, index)
		else
			entry.part.Size = EffectConfig.StartSize:Lerp(EffectConfig.EndSize, alpha) * entry.scale
			entry.part.Transparency = 1 - entry.intensity * (1 - alpha)
		end
	end
end)
