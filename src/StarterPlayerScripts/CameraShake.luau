-- Trauma-based camera shake. Impulses add trauma, trauma decays linearly over time, and the
-- offset grows with trauma squared, so small knocks barely register and big ones land hard.
-- The offset is a smooth pseudo-noise wobble, never a random jump, and is capped at MaxOffset.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectConfig = require(ReplicatedStorage:WaitForChild("EffectConfig"))

local CameraShake = {}
CameraShake.__index = CameraShake

function CameraShake.new(config)
	return setmetatable({
		_config = config or EffectConfig.Shake,
		_trauma = 0,
		_lastAt = nil,
	}, CameraShake)
end

function CameraShake:_decayTo(now)
	if self._lastAt then
		local elapsed = math.max(now - self._lastAt, 0)
		self._trauma = math.max(0, self._trauma - self._config.Decay * elapsed)
	end
	self._lastAt = now
end

function CameraShake:Impulse(amount, now)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	self:_decayTo(now)
	self._trauma = math.min(self._config.MaxTrauma, self._trauma + amount)
end

function CameraShake:GetTrauma()
	return self._trauma
end

-- scale is the player's screen-shake setting, 0..1. Returns a world-space offset to add to the
-- camera position this frame.
function CameraShake:Sample(now, scale)
	self:_decayTo(now)
	local strength = math.clamp(scale or 1, 0, 1)
	if self._trauma <= 0 or strength <= 0 then
		return Vector3.zero
	end

	local amount = self._trauma * self._trauma * self._config.MaxOffset * strength
	local phase = now * self._config.Frequency
	local wobble = Vector3.new(math.sin(phase + 0.3), 0.5 * math.sin(phase * 0.87 + 2.9), math.sin(phase * 1.31 + 1.7))
	if wobble.Magnitude > 1 then
		wobble = wobble.Unit
	end
	return wobble * amount
end

-- One shake per client: ImpactEffects kicks it, CameraController applies it.
local shared = nil
function CameraShake.Shared()
	if not shared then
		shared = CameraShake.new()
	end
	return shared
end

return CameraShake
