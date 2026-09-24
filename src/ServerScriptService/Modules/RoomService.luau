-- Builds one room at a time and owns its enemy population. Clear detection is based on what
-- actually spawned, never on the configured count, so a failed spawn cannot soft-lock a run.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local ObjectiveConfig = require(ReplicatedStorage:WaitForChild("ObjectiveConfig"))
local PartPool = require(script.Parent.PartPool)
local RoomBuilder = require(script.Parent.RoomBuilder)
local RoomObjectives = require(script.Parent.RoomObjectives)
local RoomMechanics = require(script.Parent.RoomMechanics)
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RoomGeometry = require(ReplicatedStorage:WaitForChild("RoomGeometry"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local RoomService = {}
RoomService.__index = RoomService

-- Waves: a later wave is announced by glowing circles on the floor for TelegraphTime seconds
-- before its enemies arrive, so nothing ever spawns on top of a player unannounced.
RoomService.WaveTelegraph = 1.4
RoomService.MarkerPoolSize = 16
local MARKER_STORAGE = Vector3.new(0, -500, 0)

local function createMarker()
	local part = Instance.new("Part")
	part.Name = "WaveMarker"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.2, 5, 5)
	part.Color = Color3.fromRGB(255, 70, 90)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Position = MARKER_STORAGE
	part:SetAttribute("WaveMarker", true)
	return part
end

-- origin (default the world origin) is where this service's rooms are centred: each arena slot
-- builds its rooms at its own origin, so several runs can share a server.
-- championRandom decides which enemies spawn as champions. It is separate from `random`, which
-- jitters spawn points, so adding champions never moved a seeded layout.
function RoomService.new(arenaFolder, enemyService, planeY, random, origin, championRandom)
	return setmetatable({
		_championRandom = championRandom or Random.new(7),
		-- Added to every zone's champion chance for this run (the Depth Pact's Champions).
		_championBonus = 0,
		_origin = origin or Vector3.zero,
		_arena = arenaFolder,
		_enemies = enemyService,
		_planeY = planeY,
		_random = random or Random.new(1),
		_room = nil,
		_current = nil,
	}, RoomService)
end

-- Random room events (Treasure Runners). Off unless a match asks for them, so seeded rooms in
-- tests hold exactly the enemies their definitions list.
function RoomService:SetEvents(events)
	self._events = type(events) == "table" and events or nil
end

function RoomService:_markers()
	if not self._markerPool then
		self._markerPool = PartPool.new("WaveMarkers", self._arena, RoomService.MarkerPoolSize, createMarker)
	end
	return self._markerPool
end

function RoomService:SetChampionBonus(bonus)
	self._championBonus = math.max(tonumber(bonus) or 0, 0)
end

-- The champion affix for one enemy of this room, or nil. Elites, bosses and anything summoned
-- later never roll; neither does any room whose zone chance and bonus are both zero.
function RoomService:_rollChampion(definition, archetypeId)
	local chance = (CombatConfig.ChampionChance[definition.Zone] or 0) + self._championBonus
	if chance <= 0 or definition.Kind ~= "Normal" then
		return nil
	end
	if self._championRandom:NextNumber() >= chance then
		return nil
	end
	local order = CombatConfig.ChampionOrder
	return order[self._championRandom:NextInteger(1, #order)]
end

-- The loaded room's objective (RoomObjectives), or nil.
function RoomService:GetObjective()
	return self._current and self._current.objective
end

function RoomService:GetCurrent()
	return self._current
end

-- The loaded room's mechanics, or nil between rooms.
function RoomService:GetMechanics()
	return self._current and self._current.mechanics
end

function RoomService:Unload()
	self:_hideMarkers()
	if self._room then
		self._room:Destroy()
		self._room = nil
	end
	self._enemies:Clear()
	self._current = nil
end

function RoomService:_hideMarkers()
	local current = self._current
	local telegraph = current and current.waveTelegraph
	if telegraph then
		for _, marker in telegraph.markers do
			marker.Transparency = 1
			marker.Position = MARKER_STORAGE
			self._markerPool:Release(marker)
		end
		current.waveTelegraph = nil
	end
end

-- Which marker each enemy in a room definition takes, as { archetype, marker } in spawn order.
-- A group may pin its enemies to specific markers with `Markers`; otherwise enemies take
-- markers in order. Pure, so tests can see exactly where a room puts its enemies.
function RoomService.AssignSpawns(definition, layout)
	local assignments = {}
	local markerCount = #layout.EnemySpawns
	local index = 0
	for _, group in definition.Spawns do
		for member = 1, group.Count do
			index += 1
			local marker = group.Markers and group.Markers[((member - 1) % #group.Markers) + 1] or index
			table.insert(assignments, {
				archetype = group.Archetype,
				marker = ((marker - 1) % markerCount) + 1,
			})
		end
	end
	return assignments
end

-- Spawn markers are jittered slightly so repeat rooms do not look identical.
function RoomService:_spawnPositionFor(layout, index)
	local markers = layout.EnemySpawns
	local marker = markers[((index - 1) % #markers) + 1]
	local jitter = 3
	return Vector3.new(
		self._origin.X + marker.X + (self._random:NextNumber() * 2 - 1) * jitter,
		self._planeY,
		self._origin.Z + marker.Y + (self._random:NextNumber() * 2 - 1) * jitter
	)
end

function RoomService:Load(roomDefinition, now)
	self:Unload()

	local room, bounds, layout = RoomBuilder.Build(self._arena, roomDefinition.Layout, self._origin)
	if not room then
		return nil, bounds -- bounds carries the error string on failure
	end

	self._room = room
	self._enemies:SetBounds(bounds.center, bounds.half, bounds.diagonal)
	self._enemies:SetObstacles(RoomGeometry.Translate(
		RoomGeometry.Footprints(layout, RoomConfig),
		Vector2.new(self._origin.X, self._origin.Z)
	))

	self._current = {
		mechanics = RoomMechanics.new(room, layout, self._origin),
		definition = roomDefinition,
		bounds = bounds,
		layout = layout,
		startedAt = now,
		escortNextAt = now + ((roomDefinition.EscortRespawn and roomDefinition.EscortRespawn.Delay) or math.huge),
		forcedClear = false,
		spawned = 0,
		failed = 0,
		-- Later waves (roomDefinition.Waves); the first is Spawns, placed below.
		waves = roomDefinition.Waves or {},
		nextWave = 1,
		waveStartedAt = now,
		waveTelegraph = nil,
	}
	local current = self._current
	self:_spawnGroup(roomDefinition.Spawns, layout, roomDefinition)
	if roomDefinition.Objective then
		current.objective = RoomObjectives.new(room, roomDefinition.Objective, self._origin, bounds.center.Y, now, self._championRandom)
	end
	self:_maybeRunner(roomDefinition, layout)
	return current
end

-- Spawns one group of enemies (a room's Spawns, or one wave's), at its assigned markers or at
-- `positions` when a wave already announced them.
function RoomService:_spawnGroup(spawns, layout, definition, positions)
	local current = self._current
	for index, assignment in RoomService.AssignSpawns({ Spawns = spawns or {} }, layout) do
		local champion = self:_rollChampion(definition, assignment.archetype)
		local position = positions and positions[index] or self:_spawnPositionFor(layout, assignment.marker)
		local enemy = self._enemies:Spawn(assignment.archetype, position, champion and { champion = champion } or nil)
		if enemy then
			current.spawned += 1
			if enemy.archetype.IsElite then
				current.elite = current.elite or enemy
			end
			if enemy.archetype.IsBoss then
				current.boss = enemy
			end
			if enemy.archetype.IsMiniBoss then
				current.miniBoss = enemy
			end
		else
			current.failed += 1
		end
	end
end

-- A Treasure Runner, sometimes, when events are on.
function RoomService:_maybeRunner(definition, layout)
	if not self._events or not self._events.runners or definition.Kind ~= "Normal" or definition.Objective then
		return
	end
	local chance = ObjectiveConfig.RunnerChance[definition.Zone] or 0
	if self._championRandom:NextNumber() >= chance then
		return
	end
	local marker = self._championRandom:NextInteger(1, #layout.EnemySpawns)
	local runner = self._enemies:Spawn("TreasureRunner", self:_spawnPositionFor(layout, marker))
	if runner then
		self._current.runner = runner
	end
end

-- Whether another wave is still to come (or looping, while an objective wants more).
function RoomService:_waveDue()
	local current = self._current
	if #current.waves == 0 then
		return false
	end
	if current.objective then
		return current.objective:WantsWaves()
	end
	return current.nextWave <= #current.waves
end

-- Announces the next wave: circles on the floor where it will arrive.
function RoomService:_announceWave(now)
	local current = self._current
	local index = ((current.nextWave - 1) % #current.waves) + 1
	local wave = current.waves[index]
	current.nextWave += 1
	local positions, markers = {}, {}
	local pool = self:_markers()
	for slot, assignment in RoomService.AssignSpawns({ Spawns = wave.Spawns }, current.layout) do
		local position = self:_spawnPositionFor(current.layout, assignment.marker)
		positions[slot] = position
		local marker = pool:Acquire()
		if marker then
			marker.CFrame = CFrame.new(position.X, current.bounds.center.Y + 0.4, position.Z) * CFrame.Angles(0, 0, math.pi / 2)
			marker.Transparency = 0.25
			table.insert(markers, marker)
		end
	end
	current.waveTelegraph = { at = now + RoomService.WaveTelegraph, wave = wave, positions = positions, markers = markers }
end

function RoomService:_stepWaves(now)
	local current = self._current
	local telegraph = current.waveTelegraph
	if telegraph then
		if now >= telegraph.at then
			local wave, positions = telegraph.wave, telegraph.positions
			self:_hideMarkers()
			self:_spawnGroup(wave.Spawns, current.layout, current.definition, positions)
			current.waveStartedAt = now
		end
		return
	end
	if not self:_waveDue() then
		return
	end
	local wave = current.waves[((current.nextWave - 1) % #current.waves) + 1]
	if self:GetRemaining() <= (wave.WhenRemaining or 1) or now - current.waveStartedAt >= (wave.After or 14) then
		self:_announceWave(now)
	end
end

-- Whether more enemies are on the way: a wave announced, or one still to come.
function RoomService:HasPendingWaves()
	local current = self._current
	return current ~= nil and (current.waveTelegraph ~= nil or self:_waveDue())
end

-- Wave progress for the HUD: this wave and how many there are (nil for a single-wave room).
function RoomService:GetWaveInfo()
	local current = self._current
	if not current or #current.waves == 0 or current.objective then
		return nil
	end
	local arrived = current.nextWave - (current.waveTelegraph and 1 or 0)
	return { Wave = math.min(arrived, #current.waves + 1), Waves = #current.waves + 1, Incoming = current.waveTelegraph ~= nil }
end

function RoomService:GetRemaining()
	if self._enemies.GetRequiredCount then
		return self._enemies:GetRequiredCount()
	end
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
	local objective = current.objective
	if objective then
		if objective:IsComplete() then
			-- The job is done: whatever is left flees.
			self:_hideMarkers()
			self._enemies:Clear()
			return true
		end
	else
		local wavesDone = not current.waveTelegraph and not self:_waveDue()
		if current.spawned == 0 and wavesDone then
			return true
		end
		if self:GetRemaining() == 0 and wavesDone then
			return true
		end
	end
	local limit = current.boss and RunConfig.BossRoomTimeLimit or RunConfig.RoomTimeLimit
	if now - current.startedAt >= limit then
		current.forcedClear = true
		current.timedOut = true
		return true
	end
	return false
end

-- Mechanics, waves and the objective move on; elite rooms keep a small escort alive while the
-- core lives, so the fight keeps pressure on. positions are the live players' (for objectives).
function RoomService:Step(deltaTime, now, positions)
	local current = self._current
	if not current then
		return
	end
	current.mechanics:Step(deltaTime, now)
	if current.objective then
		current.objective:Step(deltaTime, now, positions)
	end
	self:_stepWaves(now)

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

-- A point on the floor clear of cover, rotated pieces included. The room centre is preferred,
-- but a layout with cover there would otherwise teleport players inside solid geometry, so this
-- spirals outward until it finds somewhere clear.
function RoomService:GetSpawnPoint()
	local current = self._current
	local origin = self._origin
	local floorY = current and current.bounds.center.Y or origin.Y
	local fallback = Vector3.new(origin.X, floorY + SPAWN_HEIGHT, origin.Z)
	if not current then
		return fallback
	end

	local footprints = RoomGeometry.Footprints(current.layout, RoomConfig)
	local clearance = RoomConfig.SpawnPadSize.X / 2 + 1
	local half = current.bounds.half

	-- How far this point sits outside the nearest padded obstacle footprint. Negative means
	-- inside one, and larger is better, so a fully blocked room still has a least-bad answer.
	local function clearanceAt(x, z)
		if math.abs(x) > half.X or math.abs(z) > half.Y then
			return -math.huge
		end
		local worst = math.huge
		for _, solid in footprints do
			-- A point escapes a box as soon as it is outside on either of the box's own axes.
			worst = math.min(worst, RoomGeometry.Clearance(solid, x, z) - clearance)
		end
		return worst
	end

	local bestX, bestZ = 0, 0
	local bestClearance = clearanceAt(0, 0)
	if bestClearance >= 0 then
		return fallback
	end

	local maxRadius = math.max(half.X, half.Y)
	for radius = SPAWN_SEARCH_STEP, maxRadius, SPAWN_SEARCH_STEP do
		for step = 0, 11 do
			local angle = step * math.pi / 6
			local x, z = math.cos(angle) * radius, math.sin(angle) * radius
			local score = clearanceAt(x, z)
			if score >= 0 then
				return Vector3.new(origin.X + x, floorY + SPAWN_HEIGHT, origin.Z + z)
			end
			if score > bestClearance then
				bestX, bestZ, bestClearance = x, z, score
			end
		end
	end

	-- Nothing is fully clear. Take the least-bad point rather than the centre, which is the one
	-- place already known to be blocked.
	return Vector3.new(origin.X + bestX, floorY + SPAWN_HEIGHT, origin.Z + bestZ)
end

function RoomService:GetOrigin()
	return self._origin
end

function RoomService:Destroy()
	self:Unload()
	self._arena = nil
end

return RoomService
