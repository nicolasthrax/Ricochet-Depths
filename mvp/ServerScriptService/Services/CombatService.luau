--!strict
-- Server projectile authority. Owns the FireProjectile and RailInput remotes.
--
-- Shots are simulated here and only here, as 2D numbers in lane space (Source/Sim/Ricochet):
-- no parts, no Roblox physics, a fixed step on Heartbeat. Walls reflect along their surface normal
-- with the speed loss in GameConfig.Ricochet. When a shot touches a target, this service decides
-- what happens and deals the damage:
--   * the hit deals the shooter's shot damage (growing per bounce with Resonance);
--   * a hit that breaks its target lets the shot carry on through (overkill passes through);
--   * otherwise the shot pierces while it has pierces left (Drill, Auger), else bounces off;
--   * on-hit modifiers apply: burn and blast (Ember, Inferno), chill (Frostbite, Glacier), arcs
--     (Spark, Tempest); every bounce can split the shot into shards (Splitshot, Shatter).
-- Clients are told what happened in batches after every step: ShotsSpawned, ShotsBounced (each
-- change of course), DamageReport and ShotsEnded. They draw straight lines between bounces.
--
-- Room flow, health and rewards belong to RunDirector, which listens to TargetBroken.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local LaneGeometry = require(ReplicatedStorage.Source.Sim.LaneGeometry)
local Ricochet = require(ReplicatedStorage.Source.Sim.Ricochet)
local ShotStats = require(ReplicatedStorage.Source.Sim.ShotStats)
local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Modules.Signal)
local TargetField = require(script.Parent.Parent.Modules.TargetField)
local UpgradeService = require(script.Parent.UpgradeService)

type Stats = ShotStats.ShotStats
type Target = TargetField.Target

local Shot = GameConfig.Shot
local Rail = GameConfig.Rail
local Simulation = GameConfig.Simulation
local CELL_SIZE = GameConfig.Lane.grid.cellSize
local SURFACE_SKIN = GameConfig.Ricochet.surfaceSkin

-- A shot request inside this fraction of the cooldown is accepted, to absorb network jitter.
local COOLDOWN_TOLERANCE = 0.85
local SHARD_RADIUS_SCALE = 0.7
local SHARD_BOUNCES = 1
local SHARD_LIFETIME = 1.2

type ShotRecord = {
	id: number,
	shot: Ricochet.Shot,
	stats: Stats, -- the shooter's stats when fired; a pick made mid-flight does not change it
	damageScale: number, -- 1 for a shot, the split's shard damage scale for a shard
	generation: number, -- 0 for a shot, 1 for a shard (shards never split again)
	splits: number, -- how many bounces of this shot have split
	pierceLeft: number,
}

type Session = {
	player: Player,
	field: TargetField.TargetField,
	origin: CFrame,
	active: boolean,
	timeScale: number,
	accumulator: number,
	railX: number,
	railSequence: number,
	railStamp: number,
	lastFire: number,
	shots: { ShotRecord },
	pendingShards: { ShotRecord },
	stepStart: number, -- server time at the start of the step being simulated
	hits: { Network.DamageHit },
	spawned: { Network.ShotSnapshot },
	bounced: { Network.ShotBounce },
	ended: { Network.ShotEnd },
}

local sessions: { [Player]: Session } = {}
local connections: { RBXScriptConnection } = {}
local nextShotId = 0

local CombatService = {
	-- A target broke: (player, the target as it was, what broke it, the shot, if any).
	TargetBroken = Signal.new() :: Signal.Signal<Player, Target, Types.DamageSource, number?>,
}

---------------------------------------------------------------------------------------------
-- Batching
---------------------------------------------------------------------------------------------

local function flush(session: Session)
	local player = session.player
	if #session.spawned > 0 then
		Network.ShotsSpawned:fireTo(player, { shots = session.spawned })
		session.spawned = {}
	end
	if #session.bounced > 0 then
		Network.ShotsBounced:fireTo(player, { bounces = session.bounced })
		session.bounced = {}
	end
	if #session.hits > 0 then
		Network.DamageReport:fireTo(player, { hits = session.hits })
		session.hits = {}
	end
	if #session.ended > 0 then
		Network.ShotsEnded:fireTo(player, { ends = session.ended })
		session.ended = {}
	end
end

---------------------------------------------------------------------------------------------
-- Shots
---------------------------------------------------------------------------------------------

type Launch = {
	x: number,
	y: number,
	dirX: number,
	dirY: number,
	speed: number,
	radius: number,
	bounces: number,
	lifetime: number,
	damageScale: number,
	generation: number,
	parentId: number?,
	sequence: number,
	at: number,
}

local function launch(session: Session, stats: Stats, spec: Launch): ShotRecord
	nextShotId += 1
	local shot = Ricochet.newShot({
		x = spec.x,
		y = spec.y,
		dirX = spec.dirX,
		dirY = spec.dirY,
		speed = spec.speed,
		radius = spec.radius,
		bounces = spec.bounces,
		lifetime = spec.lifetime,
	})
	local record: ShotRecord = {
		id = nextShotId,
		shot = shot,
		stats = stats,
		damageScale = spec.damageScale,
		generation = spec.generation,
		splits = 0,
		pierceLeft = if stats.pierce then stats.pierce.pierceCount else 0,
	}
	table.insert(session.spawned, {
		shotId = record.id,
		parentShotId = spec.parentId,
		ownerUserId = session.player.UserId,
		sequence = spec.sequence,
		x = shot.x,
		y = shot.y,
		dirX = shot.dirX,
		dirY = shot.dirY,
		speed = shot.speed,
		radius = shot.radius,
		tint = stats.tint,
		at = spec.at,
	})
	return record
end

local function spawnShards(session: Session, parent: ShotRecord, contact: Ricochet.Contact)
	local split = parent.stats.split
	if split == nil or parent.generation > 0 then
		return
	end
	if not split.everyBounce and parent.splits > 0 then
		return
	end
	parent.splits += 1
	local count = split.shardCount
	local spread = math.rad(split.spreadDegrees)
	for index = 1, count do
		if #session.shots + #session.pendingShards >= Simulation.maxShotsPerPit then
			return
		end
		local angle = if count == 1 then 0 else -spread / 2 + spread * (index - 1) / (count - 1)
		local c, s = math.cos(angle), math.sin(angle)
		local shard = launch(session, parent.stats, {
			x = contact.x + contact.normalX * SURFACE_SKIN,
			y = contact.y + contact.normalY * SURFACE_SKIN,
			dirX = contact.outDirX * c - contact.outDirY * s,
			dirY = contact.outDirX * s + contact.outDirY * c,
			speed = contact.outSpeed,
			radius = parent.shot.radius * SHARD_RADIUS_SCALE,
			bounces = SHARD_BOUNCES,
			lifetime = SHARD_LIFETIME,
			damageScale = split.shardDamageScale,
			generation = 1,
			parentId = parent.id,
			sequence = 0,
			at = session.stepStart + contact.time,
		})
		table.insert(session.pendingShards, shard)
	end
end

---------------------------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------------------------

-- Deals damage to one target and records it. Returns whether the target broke.
local function dealDamage(
	session: Session,
	targetId: number,
	amount: number,
	source: Types.DamageSource,
	shotId: number?,
	x: number,
	y: number
): boolean
	if amount <= 0 then
		return false
	end
	local hpAfter, broke, target = session.field:damage(targetId, amount)
	if hpAfter == nil or target == nil then
		return false
	end
	table.insert(session.hits, {
		shotId = shotId,
		targetId = targetId,
		amount = amount,
		hpAfter = hpAfter,
		source = source,
		x = x,
		y = y,
	})
	if broke then
		CombatService.TargetBroken:Fire(session.player, target, source, shotId)
	end
	return broke
end

-- A shot touched a target: its damage and on-hit effects. Returns whether the target broke.
local function resolveHit(session: Session, record: ShotRecord, target: Target, contact: Ricochet.Contact): boolean
	local field = session.field
	local stats = record.stats
	local amount = ShotStats.hitDamage(stats, contact.bouncesTaken) * record.damageScale
	local source: Types.DamageSource = if record.generation > 0 then "Shard" else "Direct"
	local targetId = target.id
	local row = target.row
	local centerX, centerY = field:center(target)

	local broke = dealDamage(session, targetId, amount, source, record.id, contact.x, contact.y)

	local burn = stats.burn
	if burn then
		if not broke then
			field:applyBurn(targetId, burn.damagePerSecond, burn.durationSeconds)
		end
		if burn.blastRadius > 0 then
			for _, other in field:within(contact.x, contact.y, burn.blastRadius, targetId) do
				local x, y = field:center(other)
				dealDamage(session, other.id, amount * burn.blastDamageScale, "Blast", record.id, x, y)
			end
		end
	end

	local chill = stats.chill
	if chill then
		if chill.wholeRow then
			for _, other in field:inRow(row) do
				field:chill(other.id, chill.skipSteps)
			end
		elseif not broke then
			field:chill(targetId, chill.skipSteps)
		end
	end

	local arc = stats.arc
	if arc then
		local range = arc.arcRangeCells * CELL_SIZE
		for _, other in field:nearest(centerX, centerY, range, arc.arcCount, targetId) do
			local x, y = field:center(other)
			dealDamage(session, other.id, amount * arc.arcDamageScale, "Arc", record.id, x, y)
		end
	end

	return broke
end

local function respond(session: Session, record: ShotRecord, contact: Ricochet.Contact): Ricochet.ContactResponse
	local targetId = contact.targetId
	if targetId == nil then
		return "Reflect"
	end
	local target = session.field:get(targetId)
	if target == nil then
		-- Broken earlier in this step: its box is still in this step's obstacle list.
		return "Pierce"
	end
	if resolveHit(session, record, target, contact) then
		return "Pierce"
	end
	if record.pierceLeft > 0 then
		record.pierceLeft -= 1
		return "Pierce"
	end
	return "Reflect"
end

---------------------------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------------------------

local function stepSession(session: Session, dt: number)
	local field = session.field
	local index = 1
	while index <= #session.shots do
		local record = session.shots[index]
		local contacts = Ricochet.step(record.shot, dt, field:obstacles(), function(contact: Ricochet.Contact): Ricochet.ContactResponse
			return respond(session, record, contact)
		end)
		for _, contact in contacts do
			if contact.reflected then
				table.insert(session.bounced, {
					shotId = record.id,
					x = contact.x,
					y = contact.y,
					dirX = contact.outDirX,
					dirY = contact.outDirY,
					speed = contact.outSpeed,
					at = session.stepStart + contact.time,
				})
				spawnShards(session, record, contact)
			end
		end
		if record.shot.alive then
			index += 1
		else
			table.insert(session.ended, { shotId = record.id, x = record.shot.x, y = record.shot.y })
			table.remove(session.shots, index)
		end
	end

	for _, shard in session.pendingShards do
		table.insert(session.shots, shard)
	end
	table.clear(session.pendingShards)

	for _, tick in field:tickBurns(dt) do
		local target = field:get(tick.targetId)
		if target then
			local x, y = field:center(target)
			dealDamage(session, target.id, tick.amount, "Burn", nil, x, y)
		end
	end

	flush(session)
end

local function onHeartbeat(dt: number)
	local step = Simulation.fixedStep
	local maxBacklog = step * Simulation.maxStepsPerFrame
	for _, session in sessions do
		if session.active and session.timeScale > 0 then
			session.accumulator = math.min(session.accumulator + dt * session.timeScale, maxBacklog)
			local steps = math.floor(session.accumulator / step + 1e-9)
			local now = Workspace:GetServerTimeNow()
			for stepIndex = 1, steps do
				-- A handler (a pick opening, a defeat) can stop the session mid-frame.
				if not session.active or session.timeScale <= 0 then
					break
				end
				session.accumulator -= step
				session.stepStart = now - (steps - stepIndex + 1) * step
				stepSession(session, step)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------------------------

local function onFire(player: Player, payload: Network.FireProjectilePayload)
	local session = sessions[player]
	if session == nil or not session.active or session.timeScale <= 0 then
		return
	end
	local stats = UpgradeService.getShotStats(player)
	local now = os.clock()
	if now - session.lastFire < stats.cooldownSeconds * COOLDOWN_TOLERANCE then
		return
	end
	local mainShots = 0
	for _, record in session.shots do
		if record.generation == 0 then
			mainShots += 1
		end
	end
	if mainShots >= Shot.maxActivePerPlayer or #session.shots >= Simulation.maxShotsPerPit then
		return
	end

	-- The client fires from where it sees itself, as long as that agrees with the server.
	local originX = if math.abs(payload.originX - session.railX) <= Rail.fireOriginTolerance
		then payload.originX
		else session.railX
	local x, y = LaneGeometry.muzzle(originX)
	local dirX, dirY = LaneGeometry.clampAim(payload.direction.X, payload.direction.Y)

	session.lastFire = now
	local record = launch(session, stats, {
		x = x,
		y = y,
		dirX = dirX,
		dirY = dirY,
		speed = stats.speed,
		radius = stats.radius,
		bounces = stats.bounces,
		lifetime = stats.lifetimeSeconds,
		damageScale = 1,
		generation = 0,
		parentId = nil,
		sequence = payload.sequence,
		at = Workspace:GetServerTimeNow(),
	})
	table.insert(session.shots, record)
	flush(session)
end

local function onRail(player: Player, payload: Network.RailInputPayload)
	local session = sessions[player]
	if session == nil or not session.active or payload.sequence <= session.railSequence then
		return
	end
	local now = os.clock()
	local elapsed = math.min(now - session.railStamp, Rail.maxGapSeconds)
	local allowed = Rail.maxSpeed * Rail.speedTolerance * elapsed
	local desired = LaneGeometry.clampRailX(payload.x)
	session.railX += math.clamp(desired - session.railX, -allowed, allowed)
	session.railSequence = payload.sequence
	session.railStamp = now
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

function CombatService.init()
	table.insert(connections, Network.FireProjectile:connect(onFire))
	table.insert(connections, Network.RailInput:connect(onRail))
	table.insert(connections, RunService.Heartbeat:Connect(onHeartbeat))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end))
end

-- Disconnects everything init() connected and drops every session.
function CombatService.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(sessions)
end

-- Starts simulating a player's lane against `field`. Replaces any lane the player had.
function CombatService.beginLane(player: Player, field: TargetField.TargetField, origin: CFrame)
	local previous = sessions[player]
	if previous then
		previous.active = false
	end
	sessions[player] = {
		player = player,
		field = field,
		origin = origin,
		active = true,
		timeScale = 1,
		accumulator = 0,
		railX = 0,
		railSequence = -1,
		railStamp = os.clock(),
		lastFire = -math.huge,
		shots = {},
		pendingShards = {},
		stepStart = Workspace:GetServerTimeNow(),
		hits = {},
		spawned = {},
		bounced = {},
		ended = {},
	}
end

function CombatService.endLane(player: Player)
	local session = sessions[player]
	if session then
		session.active = false
		sessions[player] = nil
	end
end

-- 1 runs the lane, 0 freezes it (a card pick, a pause, between rooms). Resuming re-sends every
-- live shot's position, because clients draw shots from timestamps.
function CombatService.setTimeScale(player: Player, scale: number)
	local session = sessions[player]
	if session == nil then
		return
	end
	local wasFrozen = session.timeScale <= 0
	session.timeScale = math.max(0, scale)
	if wasFrozen and session.timeScale > 0 then
		local now = Workspace:GetServerTimeNow()
		for _, record in session.shots do
			local shot = record.shot
			table.insert(session.bounced, {
				shotId = record.id,
				x = shot.x,
				y = shot.y,
				dirX = shot.dirX,
				dirY = shot.dirY,
				speed = shot.speed,
				at = now,
			})
		end
		flush(session)
	end
end

-- Ends every shot in flight (a room cleared, a run lost).
function CombatService.clearShots(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	for _, record in session.shots do
		table.insert(session.ended, { shotId = record.id, x = record.shot.x, y = record.shot.y })
	end
	table.clear(session.shots)
	table.clear(session.pendingShards)
	flush(session)
end

-- The server's view of the player's rail position.
function CombatService.getRailX(player: Player): number
	local session = sessions[player]
	return if session then session.railX else 0
end

function CombatService.activeShotCount(player: Player): number
	local session = sessions[player]
	return if session then #session.shots else 0
end

return CombatService
