-- Coin pickups for one arena: dropped where enemies die, pulled towards and collected by nearby
-- players, and swept to the nearest player when the room clears. Parts are pooled and never
-- block shots, movement or touches.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoinConfig = require(ReplicatedStorage:WaitForChild("CoinConfig"))
local PartPool = require(script.Parent.PartPool)

local CoinDrops = {}
CoinDrops.__index = CoinDrops

local function createCoin()
	local part = Instance.new("Part")
	part.Name = "Coin"
	part.Shape = Enum.PartType.Cylinder
	part.Size = CoinConfig.Size
	part.Color = CoinConfig.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Position = CoinConfig.StoragePosition
	return part
end

function CoinDrops.new(parent, random)
	return setmetatable({
		_pool = PartPool.new("CoinPool", parent, CoinConfig.PoolSize, createCoin),
		_random = random or Random.new(1),
		_active = {},
		-- Value dropped while the pool was dry. Never lost: it goes out with the sweep.
		_pot = 0,
	}, CoinDrops)
end

function CoinDrops:GetActive()
	return table.clone(self._active)
end

-- Scatters `value` coins over a few pickups around `position`.
function CoinDrops:Drop(position, value)
	value = math.floor(value)
	if value <= 0 then
		return
	end
	local count = math.clamp(math.ceil(value / 2), 1, CoinConfig.MaxPickupsPerDrop)
	local share, remainder = value // count, value % count
	for index = 1, count do
		local amount = share + (index <= remainder and 1 or 0)
		local part = self._pool:Acquire()
		if not part then
			self._pot += amount
		else
			local angle = self._random:NextNumber() * math.pi * 2
			local radius = CoinConfig.ScatterRadius * math.sqrt(self._random:NextNumber())
			local spot = Vector3.new(
				position.X + math.cos(angle) * radius,
				position.Y - CoinConfig.HeightBelowPlane,
				position.Z + math.sin(angle) * radius
			)
			part.Position = spot
			part.Transparency = 0
			table.insert(self._active, { part = part, position = spot, value = amount })
		end
	end
end

local function nearest(collectors, position)
	local best, bestDistance
	for _, collector in collectors do
		local offset = Vector3.new(collector.position.X - position.X, 0, collector.position.Z - position.Z)
		local distance = offset.Magnitude
		if not bestDistance or distance < bestDistance then
			best, bestDistance = collector, distance
		end
	end
	return best, bestDistance
end

function CoinDrops:_release(index)
	local coin = table.remove(self._active, index)
	coin.part.Transparency = 1
	coin.part.Position = CoinConfig.StoragePosition
	self._pool:Release(coin.part)
	return coin
end

-- collectors: { { player, position, magnet (extra studs of pull) } }, the live players.
-- Returns the pickups collected this step as { { player, value } }.
function CoinDrops:Step(deltaTime, _now, collectors)
	local events = {}
	if #collectors == 0 then
		return events
	end
	for index = #self._active, 1, -1 do
		local coin = self._active[index]
		local collector, distance = nearest(collectors, coin.position)
		if distance <= CoinConfig.CollectRadius then
			self:_release(index)
			table.insert(events, { player = collector.player, value = coin.value })
		elseif distance <= CoinConfig.MagnetRadius + (collector.magnet or 0) then
			local toward = Vector3.new(collector.position.X - coin.position.X, 0, collector.position.Z - coin.position.Z)
			local stepLength = math.min(CoinConfig.MagnetSpeed * deltaTime, toward.Magnitude)
			coin.position += toward.Unit * stepLength
			coin.part.Position = coin.position
		end
	end
	return events
end

-- Every coin still out, and anything held back, goes to the nearest collector. With nobody to
-- collect, the coins are simply gone.
function CoinDrops:Sweep(collectors)
	local events = {}
	for index = #self._active, 1, -1 do
		local coin = self:_release(index)
		local collector = nearest(collectors, coin.position)
		if collector then
			table.insert(events, { player = collector.player, value = coin.value })
		end
	end
	if self._pot > 0 and collectors[1] then
		table.insert(events, { player = collectors[1].player, value = self._pot })
	end
	self._pot = 0
	return events
end

function CoinDrops:Clear()
	for index = #self._active, 1, -1 do
		self:_release(index)
	end
	self._pot = 0
end

function CoinDrops:Destroy()
	self:Clear()
	self._pool:Destroy()
end

return CoinDrops
