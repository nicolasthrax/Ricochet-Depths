-- Pooled client sound playback. Every cue gets a fixed set of Sound instances built up front
-- and reused round-robin, so a frantic fight never allocates. A cue whose asset id is still a
-- placeholder, or any cue while audio is switched off, is silently inert.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local SoundConfig = require(ReplicatedStorage:WaitForChild("SoundConfig"))

local SoundPlayer = {}
SoundPlayer.__index = SoundPlayer

-- The local player's Sound volume option (0..1), published as an attribute by ClientMain.
local function playerVolume()
	local Players = game:GetService("Players")
	local localPlayer = Players.LocalPlayer
	local value = localPlayer and localPlayer:GetAttribute("SfxVolume")
	return type(value) == "number" and math.clamp(value, 0, 1) or 1
end

-- options: cues (defaults to SoundConfig.Cues), enabled() -> bool, clock() -> seconds,
-- random (a Random), volumeScale() -> 0..1 (the player's volume option by default).
function SoundPlayer.new(parent, options)
	options = options or {}
	local self = setmetatable({}, SoundPlayer)
	self._cues = options.cues or SoundConfig.Cues
	self._enabled = options.enabled or function()
		return FeatureFlags.Audio
	end
	self._clock = options.clock or os.clock
	self._volumeScale = options.volumeScale or playerVolume
	self._random = options.random or Random.new()
	self._voices = {}
	self._next = {}
	self._lastPlayed = {}

	local folder = Instance.new("Folder")
	folder.Name = "RicochetSounds"
	folder.Parent = parent
	self.Folder = folder

	for name, cue in self._cues do
		local voices = {}
		if cue.SoundId ~= "" then
			for index = 1, cue.Voices do
				local sound = Instance.new("Sound")
				sound.Name = name .. index
				sound.SoundId = cue.SoundId
				sound.Volume = cue.Volume
				sound.PlaybackSpeed = cue.PlaybackSpeed
				sound.Parent = folder
				voices[index] = sound
			end
		end
		self._voices[name] = voices
		self._next[name] = 1
	end

	return self
end

function SoundPlayer:GetVoiceCount(cueName)
	local voices = self._voices[cueName]
	return voices and #voices or 0
end

-- params: pitch (multiplies the cue's playback speed), volume (multiplies its volume).
-- Returns the Sound that played, or nil when nothing did.
function SoundPlayer:Play(cueName, params)
	local cue = self._cues[cueName]
	local voices = self._voices[cueName]
	if not cue or not voices or #voices == 0 or not self._enabled() then
		return nil
	end

	local master = self._volumeScale()
	if master <= 0 then
		return nil
	end

	local now = self._clock()
	local last = self._lastPlayed[cueName]
	if last and now - last < (cue.MinInterval or 0) then
		return nil
	end
	self._lastPlayed[cueName] = now

	local index = self._next[cueName]
	self._next[cueName] = index % #voices + 1
	local sound = voices[index]

	local pitch = params and params.pitch or 1
	local volume = params and params.volume or 1
	local jitter = (cue.PitchJitter or 0) * (self._random:NextNumber() * 2 - 1)
	sound.PlaybackSpeed = cue.PlaybackSpeed * pitch * (1 + jitter)
	sound.Volume = cue.Volume * volume * master
	sound:Play()
	return sound
end

-- One player per client, shared by every script that makes noise.
local shared = nil
function SoundPlayer.Shared()
	if not shared then
		shared = SoundPlayer.new(game:GetService("SoundService"))
	end
	return shared
end

return SoundPlayer
