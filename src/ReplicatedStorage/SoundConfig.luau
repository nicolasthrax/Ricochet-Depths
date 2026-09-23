-- Sound cues and the curves that shape them. Client-side only; nothing here is authoritative.
--
-- Every SoundId is a placeholder until real assets are uploaded. An empty id makes that cue
-- inert (no Sound instance is built, nothing plays, nothing warns), so the hooks can ship and
-- be exercised long before the audio does. Fill in an id and turn on FeatureFlags.Audio.
local SoundConfig = {}

-- Wall bounce pitch climbs with every ricochet in a chain, so a long bank shot audibly builds.
SoundConfig.BouncePitchStep = 0.15
SoundConfig.MaxBouncePitch = 2.0

-- Distance falloff for positional cues, measured from the camera's focus (the player).
SoundConfig.FullVolumeRadius = 30
SoundConfig.FalloffRadius = 120
-- Never fully silent: a kill across the room should still be heard.
SoundConfig.MinVolumeScale = 0.25

-- A busy impact batch can carry two dozen contacts; only this many make a sound.
SoundConfig.MaxSoundsPerBatch = 6

-- Brief: what the asset should sound like, for whoever authors it.
-- Voices: pooled Sound instances, so overlapping plays never allocate.
-- MinInterval: a repeat inside this many seconds is dropped instead of stacking.
-- PitchJitter: +/- random spread on playback speed so repeats do not sound machine-gunned.
SoundConfig.Cues = {
	Fire = {
		Brief = "Weapon fire: punchy bass thump with a short metallic snap, under 150ms.",
		SoundId = "",
		Volume = 0.55,
		PlaybackSpeed = 0.9,
		PitchJitter = 0.04,
		Voices = 6,
		MinInterval = 0.03,
	},
	WallBounce = {
		Brief = "Ricochet off stone: bright ping. Pitch is raised per bounce by BouncePitch.",
		SoundId = "",
		Volume = 0.4,
		PlaybackSpeed = 1,
		PitchJitter = 0.02,
		Voices = 8,
		MinInterval = 0.02,
	},
	EnemyHit = {
		Brief = "Enemy hit: dull crunch with a little glassy crack.",
		SoundId = "",
		Volume = 0.5,
		PlaybackSpeed = 1,
		PitchJitter = 0.06,
		Voices = 6,
		MinInterval = 0.03,
	},
	ShieldBlock = {
		Brief = "Shot deflected by a shield: hard metallic clank, clearly 'no damage'.",
		SoundId = "",
		Volume = 0.5,
		PlaybackSpeed = 1,
		PitchJitter = 0.03,
		Voices = 4,
		MinInterval = 0.05,
	},
	EnemyShatter = {
		Brief = "Enemy destroyed: glass shatter over a low boom, the most satisfying sound in the game.",
		SoundId = "",
		Volume = 0.7,
		PlaybackSpeed = 1,
		PitchJitter = 0.08,
		Voices = 6,
		MinInterval = 0.02,
	},
	CardSelect = {
		Brief = "Upgrade card picked: rising two-note chime.",
		SoundId = "",
		Volume = 0.6,
		PlaybackSpeed = 1,
		PitchJitter = 0,
		Voices = 2,
		MinInterval = 0.1,
	},
	RoomClear = {
		Brief = "Room clear fanfare: short triumphant brass-and-synth stab, about one second.",
		SoundId = "",
		Volume = 0.7,
		PlaybackSpeed = 1,
		PitchJitter = 0,
		Voices = 1,
		MinInterval = 1,
	},
}

local function isNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- pitch = min(2.0, 1.0 + bounceCount * 0.15). Missing or negative counts are no bounces.
function SoundConfig.BouncePitch(bounceCount)
	local bounces = isNumber(bounceCount) and math.max(bounceCount, 0) or 0
	return math.min(SoundConfig.MaxBouncePitch, 1.0 + bounces * SoundConfig.BouncePitchStep)
end

-- Full volume up close, a straight fade out to the floor, then the floor beyond.
function SoundConfig.VolumeForDistance(distance)
	if not isNumber(distance) or distance <= SoundConfig.FullVolumeRadius then
		return 1
	end
	local span = SoundConfig.FalloffRadius - SoundConfig.FullVolumeRadius
	local alpha = math.clamp((distance - SoundConfig.FullVolumeRadius) / span, 0, 1)
	return 1 - alpha * (1 - SoundConfig.MinVolumeScale)
end

return SoundConfig
