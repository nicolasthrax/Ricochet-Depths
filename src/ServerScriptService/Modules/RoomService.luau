-- Builds one room at a time and owns its enemy population. Clear detection is based on what
-- actually spawned, never on the configured count, so a failed spawn cannot soft-lock a run.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomBuilder = require(script.Parent.RoomBuilder)
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local RoomService = {}
RoomService.__index = RoomService

function RoomService.new(arenaFolder, enemyService, planeY, random)
	return setmetatable({
		_arena = arenaFolder,
		_enemies = enemyService,
		_planeY = planeY,
		_random = random or Random.new(1),
		_room = nil,
		_current = nil,
	}, RoomService)
end

function RoomService:GetCurrent()
	return self._current
end

function RoomService:Unload()
	if self._room then
		self._room:Destroy()
		self._room = nil
	end
	self._enemies:Clear()
	self._current = nil
end

-- Spawn markers are reused in order and jittered slightly so repeat rooms do not look identical.
function RoomService:_spawnPositionFor(layout, index)
	local markers = layout.EnemySpawns
	local marker = markers[((index - 1) % #markers) + 1]
	local jitter = 3
	return Vector3.new(
		marker.X + (self._random:NextNumber() * 2 - 1) * jitter,
		self._planeY,
		marker.Y + (self._random:NextNumber() * 2 - 1) * jitter
	)
end

function RoomService:Load(roomDefinition, now)
	self:Unload()

	local room, bounds, layout = RoomBuilder.Build(self._arena, roomDefinition.Layout)
	if not room then
		return nil, bounds -- bounds carries the error string on failure
	end

	self._room = room
	self._enemies:SetBounds(bounds.center, bounds.half)

	local spawned, failed, index = 0, 0, 0
	local elite = nil
	for _, group in roomDefinition.Spawns do
		for _ = 1, group.Count do
			index += 1
			local enemy = self._enemies:Spawn(group.Archetype, self:_spawnPositionFor(layout, index))
			if enemy then
				spawned += 1
				if enemy.archetype.IsElite then
					elite = enemy
				end
			else
				failed += 1
			end
		end
	end

	self._current = {
		definition = roomDefinition,
		bounds = bounds,
		layout = layout,
		spawned = spawned,
		failed = failed,
		elite = elite,
		startedAt = now,
		escortNextAt = now + ((roomDefinition.EscortRespawn and roomDefinition.EscortRespawn.Delay) or math.huge),
		forcedClear = false,
	}
	return self._current
end

function RoomService:GetRemaining()
	return self._enemies:GetActiveCount()
end

-- A room is clear when nothing is alive, when nothing ever spawned, or when it has run past
-- the time limit. The last two exist purely so a run can never get stuck.
function RoomService:IsCleared(now)
	local current = self._current
	if not current then
		return false
	end
	if current.forcedClear then
		return true
	end
	if current.spawned == 0 then
		return true
	end
	if self:GetRemaining() == 0 then
		return true
	end
	if now - current.startedAt >= RunConfig.RoomTimeLimit then
		current.forcedClear = true
		current.timedOut = true
		return true
	end
	return false
end

function RoomService:ForceClear()
	if self._current then
		self._current.forcedClear = true
	end
	self._enemies:Clear()
end

-- Elite rooms keep a small escort alive while the core lives, so the fight keeps pressure on.
function RoomService:Step(_deltaTime, now)
	local current = self._current
	if not current then
		return
	end

	local respawn = current.definition.EscortRespawn
	if not respawn or not current.elite or current.elite.dead then
		return
	end
	if now < current.escortNextAt then
		return
	end

	current.escortNextAt = now + respawn.Delay
	local escorts = 0
	for _, enemy in self._enemies:GetEnemies() do
		if enemy.archetypeId == respawn.Archetype then
			escorts += 1
		end
	end
	if escorts < respawn.MaxAlive then
		self._enemies:Spawn(respawn.Archetype, self:_spawnPositionFor(current.layout, escorts + 1))
	end
end

local SPAWN_HEIGHT = 4
local SPAWN_SEARCH_STEP = 6

-- A point on the floor clear of pillars. The room centre is preferred, but a layout with cover
-- there would otherwise teleport players inside solid geometry, so this spirals outward until
-- it finds somewhere clear.
function RoomService:GetSpawnPoint()
	local current = self._current
	local floorY = current and current.bounds.center.Y or 0
	local fallback = Vector3.new(0, floorY + SPAWN_HEIGHT, 0)
	if not current then
		return fallback
	end

	local obstacles = current.layout.Obstacles
	local clearance = RoomConfig.SpawnPadSize.X / 2 + 1
	local half = current.bounds.half

	local function isClear(x, z)
		if math.abs(x) > half.X or math.abs(z) > half.Y then
			return false
		end
		for _, obstacle in obstacles do
			if
				math.abs(x - obstacle.Offset.X) < obstacle.Size.X / 2 + clearance
				and math.abs(z - obstacle.Offset.Y) < obstacle.Size.Y / 2 + clearance
			then
				return false
			end
		end
		return true
	end

	if isClear(0, 0) then
		return fallback
	end

	local maxRadius = math.max(half.X, half.Y)
	for radius = SPAWN_SEARCH_STEP, maxRadius, SPAWN_SEARCH_STEP do
		for step = 0, 11 do
			local angle = step * math.pi / 6
			local x, z = math.cos(angle) * radius, math.sin(angle) * radius
			if isClear(x, z) then
				return Vector3.new(x, floorY + SPAWN_HEIGHT, z)
			end
		end
	end

	return fallback
end

function RoomService:Destroy()
	self:Unload()
	self._arena = nil
end

return RoomService
