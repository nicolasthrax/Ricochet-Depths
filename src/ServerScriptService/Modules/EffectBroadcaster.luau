-- Batches cosmetic impact notifications so a busy frame costs one remote call, not one per hit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectConfig = require(ReplicatedStorage:WaitForChild("EffectConfig"))

local EffectBroadcaster = {}
EffectBroadcaster.__index = EffectBroadcaster

function EffectBroadcaster.new(remote)
	return setmetatable({
		_remote = remote,
		_positions = {},
		_normals = {},
		_count = 0,
		_dropped = 0,
		_nextFlush = 0,
	}, EffectBroadcaster)
end

function EffectBroadcaster:Queue(position, normal)
	if self._count >= EffectConfig.MaxImpactsPerBatch then
		self._dropped += 1
		return false
	end
	self._count += 1
	self._positions[self._count] = position
	self._normals[self._count] = normal
	return true
end

function EffectBroadcaster:Flush()
	if self._count == 0 then
		return 0
	end

	local positions = table.move(self._positions, 1, self._count, 1, table.create(self._count))
	local normals = table.move(self._normals, 1, self._count, 1, table.create(self._count))
	local sent = self._count

	self._count = 0
	self._remote:FireAllClients(positions, normals)
	return sent
end

function EffectBroadcaster:Step(now)
	if now < self._nextFlush then
		return 0
	end
	self._nextFlush = now + EffectConfig.BatchInterval
	return self:Flush()
end

function EffectBroadcaster:GetDroppedCount()
	return self._dropped
end

return EffectBroadcaster
