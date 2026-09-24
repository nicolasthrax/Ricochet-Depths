-- Orbs on the floor for one arena. A thrown orb that has spent its bounces lands here; its owner
-- picks it up by walking over it, and after a short rest it rolls home by itself, so an orb is
-- never lost and a run can never stall for want of one. Parts are pooled and block nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArsenalConfig = require(ReplicatedStorage:WaitForChild("ArsenalConfig"))
local PartPool = require(script.Parent.PartPool)

local config = ArsenalConfig.Orbs

local OrbDrops = {}
OrbDrops.__index = OrbDrops

local function createOrb()
	local part = Instance.new("Part")
	part.Name = "Orb"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * config.Size
	part.Color = config.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Position = config.StoragePosition
	return part
end

function OrbDrops.new(parent)
	return setmetatable({
		_pool = PartPool.new("OrbDropPool", parent, config.PoolSize, createOrb),
		_active = {},
	}, OrbDrops)
end

-- An orb of `owner` lands at `position` (on the shot plane). Returns false when the pool is
-- dry, in which case the caller hands the orb straight back instead.
function OrbDrops:Drop(owner, position, floorY, now)
	local part = self._pool:Acquire()
	if not part then
		return false
	end
	local spot = Vector3.new(position.X, (floorY or position.Y) + config.Height, position.Z)
	part.Position = spot
	part.Transparency = 0
	local ok, userId = pcall(function()
		return owner.UserId
	end)
	part:SetAttribute("Owner", ok and userId or 0)
	table.insert(self._active, { owner = owner, part = part, position = spot, droppedAt = now, recalled = false })
	return true
end

function OrbDrops:_release(index)
	local orb = table.remove(self._active, index)
	orb.part.Transparency = 1
	orb.part.Position = config.StoragePosition
	orb.part:SetAttribute("Owner", nil)
	self._pool:Release(orb.part)
	return orb
end

-- Every orb `owner` has on the floor flies home at recall speed.
function OrbDrops:Recall(owner)
	local count = 0
	for _, orb in self._active do
		if orb.owner == owner then
			orb.recalled = true
			count += 1
		end
	end
	return count
end

-- How many of `owner`'s orbs are on the floor.
function OrbDrops:CountFor(owner)
	local count = 0
	for _, orb in self._active do
		if orb.owner == owner then
			count += 1
		end
	end
	return count
end

-- carriers: owner -> { position, returnMultiplier }, for the players who can pick orbs up now.
-- Returns the owners whose orbs were collected this step, one entry per orb.
function OrbDrops:Step(deltaTime, now, carriers)
	local collected = {}
	for index = #self._active, 1, -1 do
		local orb = self._active[index]
		local carrier = carriers[orb.owner]
		if carrier then
			local offset = Vector3.new(carrier.position.X - orb.position.X, 0, carrier.position.Z - orb.position.Z)
			local distance = offset.Magnitude
			if distance <= config.PickupRadius then
				self:_release(index)
				table.insert(collected, orb.owner)
			elseif orb.recalled or now - orb.droppedAt >= config.ReturnDelay then
				local speed = orb.recalled and config.RecallSpeed or config.ReturnSpeed * (carrier.returnMultiplier or 1)
				local travel = math.min(speed * deltaTime, distance)
				orb.position += offset.Unit * travel
				orb.part.Position = orb.position
			end
		end
	end
	return collected
end

-- Takes every orb off the floor (a room ended). Returns the owners, one entry per orb.
function OrbDrops:Collect(owner)
	local owners = {}
	for index = #self._active, 1, -1 do
		if owner == nil or self._active[index].owner == owner then
			table.insert(owners, self:_release(index).owner)
		end
	end
	return owners
end

-- Where `owner`'s orbs lie, nearest first to `position` (for tools and bots).
function OrbDrops:PositionsFor(owner, position)
	local list = {}
	for _, orb in self._active do
		if orb.owner == owner then
			table.insert(list, orb.position)
		end
	end
	if position then
		table.sort(list, function(a, b)
			return (a - position).Magnitude < (b - position).Magnitude
		end)
	end
	return list
end

function OrbDrops:GetActiveCount()
	return #self._active
end

function OrbDrops:GetFreeCount()
	return self._pool:GetFreeCount()
end

function OrbDrops:Clear()
	self:Collect(nil)
end

function OrbDrops:Destroy()
	self:Clear()
	self._pool:Destroy()
end

return OrbDrops
