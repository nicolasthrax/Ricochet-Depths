-- Audio and "juice": sound cue configuration and curves, the pooled client sound player,
-- camera shake, damage popups, and the richer impact payload that drives all three.
local CameraShake = __require("CameraShake")
local DamagePopups = __require("DamagePopups")
local EffectBroadcaster = __require("EffectBroadcaster")
local EffectConfig = __require("EffectConfig")
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local SoundConfig = __require("SoundConfig")
local SoundPlayer = __require("SoundPlayer")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3

describe("SoundConfig bounce pitch", function()
	it("starts at 1.0 and climbs 0.15 per bounce", function()
		expect(SoundConfig.BouncePitch(0)).toBeCloseTo(1.0)
		expect(SoundConfig.BouncePitch(1)).toBeCloseTo(1.15)
		expect(SoundConfig.BouncePitch(2)).toBeCloseTo(1.3)
		expect(SoundConfig.BouncePitch(4)).toBeCloseTo(1.6)
	end)

	it("caps at 2.0 however long the chain gets", function()
		expect(SoundConfig.BouncePitch(6)).toBeCloseTo(1.9)
		expect(SoundConfig.BouncePitch(7)).toBeCloseTo(2.0)
		expect(SoundConfig.BouncePitch(40)).toBeCloseTo(2.0)
	end)

	it("matches pitch = min(2.0, 1.0 + bounces * 0.15) at every count", function()
		for bounces = 0, 20 do
			expect(SoundConfig.BouncePitch(bounces)).toBeCloseTo(math.min(2.0, 1.0 + bounces * 0.15))
		end
	end)

	it("treats bad input as no bounces rather than erroring or going below 1", function()
		expect(SoundConfig.BouncePitch(-3)).toBeCloseTo(1.0)
		expect(SoundConfig.BouncePitch(nil)).toBeCloseTo(1.0)
		expect(SoundConfig.BouncePitch(0 / 0)).toBeCloseTo(1.0)
	end)
end)

describe("SoundConfig cues and volume curve", function()
	it("defines every cue the game plays, each with a placeholder id and sane levels", function()
		for _, name in { "Fire", "WallBounce", "EnemyHit", "ShieldBlock", "EnemyShatter", "CardSelect", "RoomClear" } do
			local cue = SoundConfig.Cues[name]
			if not cue then
				error("missing cue " .. name)
			end
			expect(type(cue.SoundId)).toBe("string")
			expect(cue.Volume).toBeGreaterThan(0)
			expect(cue.Volume).toBeLessThanOrEqual(1)
			expect(cue.PlaybackSpeed).toBeGreaterThan(0)
			expect(cue.Voices).toBeGreaterThanOrEqual(1)
			expect(type(cue.Brief)).toBe("string")
		end
	end)

	it("keeps nearby sounds at full volume and fades distant ones to a floor, never to silence", function()
		expect(SoundConfig.VolumeForDistance(0)).toBeCloseTo(1)
		expect(SoundConfig.VolumeForDistance(SoundConfig.FullVolumeRadius)).toBeCloseTo(1)
		local far = SoundConfig.VolumeForDistance(SoundConfig.FalloffRadius * 4)
		expect(far).toBeCloseTo(SoundConfig.MinVolumeScale)
		local mid = SoundConfig.VolumeForDistance((SoundConfig.FullVolumeRadius + SoundConfig.FalloffRadius) / 2)
		expect(mid).toBeLessThan(1)
		expect(mid).toBeGreaterThan(SoundConfig.MinVolumeScale)
	end)
end)

describe("SoundPlayer", function()
	local cues = {
		Thump = { SoundId = "rbxassetid://1", Volume = 0.5, PlaybackSpeed = 0.9, PitchJitter = 0, Voices = 3, MinInterval = 0, Brief = "" },
		Silent = { SoundId = "", Volume = 0.5, PlaybackSpeed = 1, PitchJitter = 0, Voices = 2, MinInterval = 0, Brief = "" },
		Throttled = { SoundId = "rbxassetid://2", Volume = 1, PlaybackSpeed = 1, PitchJitter = 0, Voices = 4, MinInterval = 0.1, Brief = "" },
	}

	local function newPlayer(enabled)
		local clock = 0
		local player = SoundPlayer.new(Instance.new("Folder"), {
			cues = cues,
			enabled = function()
				return enabled ~= false
			end,
			clock = function()
				return clock
			end,
		})
		return player, function(value)
			clock = value
		end
	end

	it("pre-builds a fixed pool of voices and reuses them round-robin", function()
		local player = newPlayer()
		expect(player:GetVoiceCount("Thump")).toBe(3)
		local before = Harness.instanceCount()
		local first = player:Play("Thump")
		player:Play("Thump")
		player:Play("Thump")
		local fourth = player:Play("Thump")
		expect(fourth).toBe(first)
		expect(Harness.instanceCount()).toBe(before)
		expect(rawget(first, "_plays")).toBe(2)
	end)

	it("applies the pitch multiplier on top of the cue's base speed, and scales volume", function()
		local player = newPlayer()
		local sound = player:Play("Thump", { pitch = SoundConfig.BouncePitch(4), volume = 0.5 })
		expect(sound.PlaybackSpeed).toBeCloseTo(0.9 * 1.6)
		expect(sound.Volume).toBeCloseTo(0.25)
	end)

	it("is inert for a cue whose asset has not been set", function()
		local player = newPlayer()
		expect(player:GetVoiceCount("Silent")).toBe(0)
		expect(player:Play("Silent")).toBeNil()
	end)

	it("is inert while audio is switched off", function()
		local player = newPlayer(false)
		expect(player:Play("Thump")).toBeNil()
	end)

	it("drops a repeat inside the cue's minimum interval instead of stacking it", function()
		local player, setClock = newPlayer()
		setClock(1)
		expect(player:Play("Throttled")).toBeTruthy()
		setClock(1.05)
		expect(player:Play("Throttled")).toBeNil()
		setClock(1.2)
		expect(player:Play("Throttled")).toBeTruthy()
	end)

	it("ignores unknown cue names", function()
		local player = newPlayer()
		expect(player:Play("NoSuchCue")).toBeNil()
	end)
end)

describe("CameraShake", function()
	local config = { MaxTrauma = 1, Decay = 2, MaxOffset = 1, Frequency = 20 }

	it("is still until something happens", function()
		local shake = CameraShake.new(config)
		expect(shake:Sample(0, 1).Magnitude).toBe(0)
	end)

	it("kicks on an impulse and settles back to rest", function()
		local shake = CameraShake.new(config)
		shake:Impulse(0.8, 0)
		local peak = 0
		for frame = 1, 10 do
			peak = math.max(peak, shake:Sample(frame / 60, 1).Magnitude)
		end
		expect(peak).toBeGreaterThan(0)
		expect(peak).toBeLessThanOrEqual(config.MaxOffset)
		expect(shake:Sample(5, 1).Magnitude).toBe(0)
	end)

	it("never exceeds its ceiling however many impulses stack up", function()
		local shake = CameraShake.new(config)
		for _ = 1, 50 do
			shake:Impulse(1, 0)
		end
		expect(shake:GetTrauma()).toBe(config.MaxTrauma)
		for frame = 0, 30 do
			expect(shake:Sample(frame / 240, 1).Magnitude).toBeLessThanOrEqual(config.MaxOffset + 1e-9)
		end
	end)

	it("respects the player's screen shake setting, down to none at all", function()
		local shake = CameraShake.new(config)
		shake:Impulse(1, 0)
		expect(shake:Sample(0.01, 0).Magnitude).toBe(0)
	end)
end)

describe("DamagePopups", function()
	local config = { PoolSize = 3, Duration = 0.5, Rise = 3, StoragePosition = Vector3.new(0, -500, 0) }

	it("shows a number over a hit and recycles it when it fades", function()
		local popups = DamagePopups.new(Instance.new("Folder"), config)
		expect(popups:GetFreeCount()).toBe(3)
		expect(popups:Show(Vector3.new(4, 3, 4), 2, "Hit", 0)).toBe(true)
		expect(popups:GetFreeCount()).toBe(2)
		expect(popups:GetActiveText(1)).toBe("2")
		popups:Step(0.25)
		expect(popups:GetFreeCount()).toBe(2)
		popups:Step(0.6)
		expect(popups:GetFreeCount()).toBe(3)
	end)

	it("drops a popup rather than allocating when the pool is dry", function()
		local popups = DamagePopups.new(Instance.new("Folder"), config)
		local before = Harness.instanceCount()
		for _ = 1, 3 do
			expect(popups:Show(Vector3.zero, 1, "Hit", 0)).toBe(true)
		end
		expect(popups:Show(Vector3.zero, 1, "Hit", 0)).toBe(false)
		expect(Harness.instanceCount()).toBe(before)
	end)

	it("labels a shield block instead of showing a zero", function()
		local popups = DamagePopups.new(Instance.new("Folder"), config)
		popups:Show(Vector3.zero, 0, "Block", 0)
		expect(popups:GetActiveText(1)).toBe(EffectConfig.Popups.BlockedText)
	end)
end)

describe("impact payload detail", function()
	local function recordingRemote()
		local remote = { fired = {} }
		function remote:FireAllClients(...)
			table.insert(self.fired, table.pack(...))
		end
		function remote:FireClient() end
		return remote
	end

	it("carries kind, bounce count and damage alongside each impact", function()
		local remote = recordingRemote()
		local broadcaster = EffectBroadcaster.new(remote)
		broadcaster:Queue(Vector3.new(1, 3, 0), Vector3.new(1, 0, 0), "Wall", 2, 0)
		broadcaster:Queue(Vector3.new(2, 3, 0), Vector3.new(1, 0, 0), "Kill", 3, 1.5)
		broadcaster:Flush()
		local args = remote.fired[1]
		expect(#args[1]).toBe(2)
		local details = args[3]
		expect(details.Kinds[1]).toBe("Wall")
		expect(details.Kinds[2]).toBe("Kill")
		expect(details.Contacts[1]).toBe(2)
		expect(details.Damage[2]).toBe(1.5)
	end)

	it("defaults an impact queued the old way to a plain wall contact", function()
		local remote = recordingRemote()
		local broadcaster = EffectBroadcaster.new(remote)
		broadcaster:Queue(Vector3.zero, Vector3.new(0, 1, 0))
		broadcaster:Flush()
		local details = remote.fired[1][3]
		expect(details.Kinds[1]).toBe("Wall")
		expect(details.Contacts[1]).toBe(0)
		expect(details.Damage[1]).toBe(0)
	end)

	it("classifies what a projectile struck when the match reports it", function()
		local remote = recordingRemote()
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 1)
		local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
		local match = MatchService.new({
			rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(1)),
			enemies = enemies,
			upgrades = UpgradeService.new(1),
			projectiles = projectiles,
			rewards = RewardService.new(),
			effects = EffectBroadcaster.new(remote),
			net = { EnemyDefeated = recordingRemote() },
		})

		local wall = Instance.new("Part")
		-- Two health: the first hit lands, the second kills.
		local chaser = enemies:Spawn("Drifter", Vector3.new(10, PLANE_Y, 0))
		local entry = { damage = 1, damagePerBounce = 0, contacts = 1, direction = Vector3.new(1, 0, 0), shooter = nil }

		match:HandleImpact({ Instance = wall, Position = Vector3.zero, Normal = Vector3.new(1, 0, 0) }, entry, 0)
		match:HandleImpact({ Instance = chaser.part, Position = Vector3.zero, Normal = Vector3.new(1, 0, 0) }, entry, 0)
		entry.contacts = 2
		match:HandleImpact({ Instance = chaser.part, Position = Vector3.zero, Normal = Vector3.new(1, 0, 0) }, entry, 0)
		match._effects:Flush()

		local details = remote.fired[1][3]
		expect(details.Kinds[1]).toBe("Wall")
		expect(details.Kinds[2]).toBe("Hit")
		expect(details.Damage[2]).toBe(1)
		expect(details.Kinds[3]).toBe("Kill")
		expect(details.Contacts[3]).toBe(2)
	end)
end)
