-- Batches cosmetic impact notifications so a busy frame costs one remote call, not one per hit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectConfig = require(ReplicatedStorage:WaitForChild("EffectConfig"))

local EffectBroadcaster = {}
EffectBroadcaster.__index = EffectBroadcaster

-- recipients, when given, returns the players who should see these effects (one arena's
-- players); without it every client does.
function EffectBroadcaster.new(remote, recipients)
	return setmetatable({
		_remote = remote,
		_recipients = recipients,
		_positions = {},
		_normals = {},
		_kinds = {},
		_contacts = {},
		_damage = {},
		_count = 0,
		_dropped = 0,
		_nextFlush = 0,
	}, EffectBroadcaster)
end

-- kind is what was struck: "Wall", "Hit", "Block" (a shield took it) or "Kill". contacts is
-- the projectile's contact count so far, which drives the rising bounce pitch; damage is what
-- landed, for the popup. All three are cosmetic and default to a plain wall contact.
function EffectBroadcaster:Queue(position, normal, kind, contacts, damage)
	if self._count >= EffectConfig.MaxImpactsPerBatch then
		self._dropped += 1
		return false
	end
	self._count += 1
	self._positions[self._count] = position
	self._normals[self._count] = normal
	self._kinds[self._count] = kind or "Wall"
	self._contacts[self._count] = contacts or 0
	self._damage[self._count] = damage or 0
	return true
end

function EffectBroadcaster:Flush()
	if self._count == 0 then
		return 0
	end

	local count = self._count
	local function take(list)
		return table.move(list, 1, count, 1, table.create(count))
	end
	local positions, normals = take(self._positions), take(self._normals)
	-- Parallel arrays of plain values: they survive remote serialisation unchanged.
	local details = { Kinds = take(self._kinds), Contacts = take(self._contacts), Damage = take(self._damage) }

	self._count = 0
	if self._recipients then
		for _, player in self._recipients() do
			self._remote:FireClient(player, positions, normals, details)
		end
	else
		self._remote:FireAllClients(positions, normals, details)
	end
	return count
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
