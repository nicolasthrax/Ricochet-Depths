--!strict
-- Each player's run: their lane, the rooms and their targets, health, the haul, defeat and the
-- next run. Owns the SetPaused and FetchRunSnapshot remotes.
--
-- A run is solo for now: every player gets a lane slot of their own. The loop:
--   join -> lane built, avatar placed on the rail -> room 1 opens with rows of blocks ->
--   every pulse the blocks step towards the rail and a queued row enters at the back ->
--   a block crossing the danger line costs HP -> clearing every block clears the room ->
--   room 6 holds an elite with telegraphed attacks -> after room 6 the next depth begins.
-- At 0 HP the run ends (keeping part of the haul) and a new one starts after a short beat.
-- The world holds still while a card pick is open, while paused, and between rooms.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local LaneGeometry = require(ReplicatedStorage.Source.Sim.LaneGeometry)
local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Modules.Signal)
local TargetField = require(script.Parent.Parent.Modules.TargetField)
local WaveGenerator = require(script.Parent.Parent.Modules.WaveGenerator)
local LaneBuilder = require(script.Parent.Parent.Modules.LaneBuilder)
local CombatService = require(script.Parent.CombatService)
local UpgradeService = require(script.Parent.UpgradeService)

type Target = TargetField.Target

local RunConfig = GameConfig.Run
local Targets = GameConfig.Targets
local Elite = Targets.elite
local Grid = GameConfig.Lane.grid
local MAX_PIPS = GameConfig.Player.hpPips

type Telegraph = {
	column: number,
	widthColumns: number,
	secondsLeft: number,
}

type Run = {
	player: Player,
	slot: number,
	origin: CFrame,
	lane: Model,
	runId: number,
	rng: Random,
	depth: number,
	room: number,
	phase: Types.RunPhase,
	phaseTimer: number,
	hp: number,
	haul: number,
	field: TargetField.TargetField,
	queue: { WaveGenerator.Row },
	pulse: number,
	pulseTimer: number,
	eliteTimer: number,
	telegraph: Telegraph?,
	paused: boolean,
	picking: boolean,
	timeScale: number,
	breaksByShot: { [number]: number },
	bestCombo: number,
	characterConnection: RBXScriptConnection?,
}

local runs: { [Player]: Run } = {}
local slots: { [number]: Player } = {}
local connections: { RBXScriptConnection } = {}
local signalConnections: { Signal.Connection } = {}
local nextRunId = 0
local seeds = Random.new()

local RunDirector = {}

---------------------------------------------------------------------------------------------
-- State for clients
---------------------------------------------------------------------------------------------

local function reportedPhase(run: Run): Types.RunPhase
	if run.phase == "Combat" and run.picking then
		return "UpgradePick"
	end
	return run.phase
end

local function runState(run: Run): Network.RunState
	return {
		runId = run.runId,
		phase = reportedPhase(run),
		depth = run.depth,
		roomIndex = run.room,
		roomCount = RunConfig.roomsPerDepth,
		isFtue = false,
		timeScale = run.timeScale,
		paused = run.paused,
		partyUserIds = { run.player.UserId },
		serverTime = Workspace:GetServerTimeNow(),
		laneOrigin = run.origin,
	}
end

local function healthPayload(run: Run): Network.HealthChangedPayload
	return { userId = run.player.UserId, pips = run.hp, maxPips = MAX_PIPS, downed = run.hp <= 0 }
end

local function broadcastState(run: Run)
	Network.RunStateChanged:fireTo(run.player, runState(run))
end

-- The lane runs only in combat, unpaused, with no card pick open.
local function refreshTimeScale(run: Run)
	local scale = if run.phase == "Combat" and not run.paused and not run.picking then 1 else 0
	if scale ~= run.timeScale then
		run.timeScale = scale
		CombatService.setTimeScale(run.player, scale)
	end
	broadcastState(run)
end

---------------------------------------------------------------------------------------------
-- The avatar
---------------------------------------------------------------------------------------------

-- Puts the avatar on the rail, facing up the lane, with walking and jumping switched off (the
-- client slides it along the rail itself).
local function placeCharacter(run: Run)
	local character = run.player.Character
	if character == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil or runs[run.player] ~= run then
		return
	end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	local height = humanoid.HipHeight + root.Size.Y / 2
	root.CFrame = run.origin * CFrame.new(CombatService.getRailX(run.player), height, 0)
end

---------------------------------------------------------------------------------------------
-- Health and defeat
---------------------------------------------------------------------------------------------

local function defeat(run: Run)
	local player = run.player
	run.phase = "Ended"
	run.phaseTimer = RunConfig.restartDelaySeconds
	run.telegraph = nil
	CombatService.clearShots(player)
	local summary = UpgradeService.runSummary(player)
	UpgradeService.endRun(player)
	local banked = math.floor(run.haul * RunConfig.defeatedHaulKept)
	Network.RunEnded:fireTo(player, {
		runId = run.runId,
		outcome = "Defeated",
		depth = run.depth,
		haulBanked = banked,
		haulLost = run.haul - banked,
		bestCombo = run.bestCombo,
		fusions = summary.fusions,
		discoveries = summary.discoveries,
		xpGained = summary.xpGained,
	})
	refreshTimeScale(run)
end

local function hurt(run: Run, amount: number)
	if run.phase ~= "Combat" or amount <= 0 then
		return
	end
	run.hp = math.max(0, run.hp - amount)
	Network.HealthChanged:fireTo(run.player, healthPayload(run))
	if run.hp <= 0 then
		defeat(run)
	end
end

---------------------------------------------------------------------------------------------
-- Rooms
---------------------------------------------------------------------------------------------

local function findElite(field: TargetField.TargetField): Target?
	for _, target in field:all() do
		if target.kind == "Elite" then
			return target
		end
	end
	return nil
end

-- Adds a row at the back wall if every one of its targets fits there now.
local function spawnQueuedRow(run: Run): { Network.TargetSnapshot }
	local row = run.queue[1]
	if row == nil then
		return {}
	end
	for _, spawn in row do
		if not run.field:isFree(spawn.column, 1, spawn.widthColumns) then
			return {}
		end
	end
	table.remove(run.queue, 1)
	local spawned: { Network.TargetSnapshot } = {}
	for _, spawn in row do
		local target = run.field:add(spawn.kind, spawn.column, 1, spawn.widthColumns, spawn.hp)
		if target then
			table.insert(spawned, run.field:snapshot(target))
		end
	end
	return spawned
end

local function startRoom(run: Run)
	local plan = WaveGenerator.plan(run.depth, run.room, run.rng)
	local startRows = math.min(GameConfig.Rooms.startRows, #plan.rows)
	local spawned: { Network.TargetSnapshot } = {}
	run.queue = {}
	for index, row in plan.rows do
		if index <= startRows then
			-- The first row to arrive sits nearest the rail.
			local gridRow = startRows - index + 1
			for _, spawn in row do
				local target = run.field:add(spawn.kind, spawn.column, gridRow, spawn.widthColumns, spawn.hp)
				if target then
					table.insert(spawned, run.field:snapshot(target))
				end
			end
		else
			table.insert(run.queue, row)
		end
	end
	run.pulse = 0
	run.pulseTimer = Targets.pulseIntervalSeconds
	run.eliteTimer = Elite.attackIntervalSeconds
	run.telegraph = nil
	table.clear(run.breaksByShot)
	run.phase = "Combat"
	refreshTimeScale(run)
	Network.TargetsSpawned:fireTo(run.player, { targets = spawned })
end

local function clearRoom(run: Run)
	run.phase = "RoomClear"
	run.phaseTimer = GameConfig.Rooms.clearDelaySeconds
	run.telegraph = nil
	CombatService.clearShots(run.player)
	refreshTimeScale(run)
end

local function nextRoom(run: Run)
	run.room += 1
	if run.room > RunConfig.roomsPerDepth then
		run.room = 1
		run.depth += 1
	end
	startRoom(run)
end

local function pulse(run: Run)
	run.pulse += 1
	local moves, breached = run.field:advance()
	local spawned = spawnQueuedRow(run)
	local breachedIds: { number } = {}
	local damage = 0
	for _, target in breached do
		table.insert(breachedIds, target.id)
		damage += if target.kind == "Elite" then Targets.breachDamage.Elite else Targets.breachDamage.Block
	end
	Network.TargetsAdvanced:fireTo(run.player, { pulse = run.pulse, moves = moves, breached = breachedIds })
	if #spawned > 0 then
		Network.TargetsSpawned:fireTo(run.player, { targets = spawned })
	end
	hurt(run, damage)
end

-- Lane-space x range covered by a span of columns.
local function columnSpan(column: number, widthColumns: number): (number, number)
	local left = -GameConfig.Lane.halfWidth + (column - 1) * Grid.cellSize
	return left, left + widthColumns * Grid.cellSize
end

local function updateElite(run: Run, dt: number)
	local elite = findElite(run.field)
	if elite == nil then
		run.telegraph = nil
		return
	end
	local railX = CombatService.getRailX(run.player)
	local telegraph = run.telegraph
	if telegraph then
		telegraph.secondsLeft -= dt
		if telegraph.secondsLeft <= 0 then
			run.telegraph = nil
			local left, right = columnSpan(telegraph.column, telegraph.widthColumns)
			-- The avatar is hit if any part of it stands in the telegraphed lane.
			local nearest = math.clamp(railX, left, right)
			if math.abs(railX - nearest) < GameConfig.Rail.avatarRadius then
				hurt(run, Elite.attackDamage)
			end
		end
		return
	end
	run.eliteTimer -= dt
	if run.eliteTimer > 0 then
		return
	end
	run.eliteTimer = Elite.attackIntervalSeconds
	local width = Elite.widthColumns
	local column = math.clamp(LaneGeometry.columnAt(railX) - math.floor((width - 1) / 2), 1, Grid.columns - width + 1)
	run.telegraph = { column = column, widthColumns = width, secondsLeft = Elite.telegraphSeconds }
	Network.AttackTelegraph:fireTo(run.player, {
		attackerId = elite.id,
		column = column,
		widthColumns = width,
		windupSeconds = Elite.telegraphSeconds,
		startsAt = Workspace:GetServerTimeNow(),
	})
end

---------------------------------------------------------------------------------------------
-- Runs
---------------------------------------------------------------------------------------------

local function startRun(run: Run)
	local player = run.player
	nextRunId += 1
	local seed = seeds:NextInteger(1, 2 ^ 30)
	run.runId = nextRunId
	run.rng = Random.new(seed)
	run.depth = 1
	run.room = 1
	run.hp = MAX_PIPS
	run.haul = 0
	run.bestCombo = 0
	table.clear(run.breaksByShot)
	run.field = TargetField.new()
	run.queue = {}
	run.paused = false
	run.picking = false
	run.timeScale = 1
	run.telegraph = nil

	CombatService.beginLane(player, run.field, run.origin)
	UpgradeService.beginRun(player, seed)
	Network.HealthChanged:fireTo(player, healthPayload(run))
	Network.HaulChanged:fireTo(player, { haul = 0, delta = 0, fromTargetId = nil })
	task.spawn(placeCharacter, run)
	startRoom(run)
end

local function update(run: Run, dt: number)
	if run.phase == "Combat" then
		if run.timeScale <= 0 then
			return
		end
		local scaled = dt * run.timeScale
		run.pulseTimer -= scaled
		if run.pulseTimer <= 0 then
			run.pulseTimer += Targets.pulseIntervalSeconds
			pulse(run)
		end
		if run.phase == "Combat" then
			updateElite(run, scaled)
		end
		if run.phase == "Combat" and run.field:size() == 0 and #run.queue == 0 then
			clearRoom(run)
		end
	elseif run.phase == "RoomClear" then
		if run.paused then
			return
		end
		run.phaseTimer -= dt
		if run.phaseTimer <= 0 then
			nextRoom(run)
		end
	elseif run.phase == "Ended" then
		run.phaseTimer -= dt
		if run.phaseTimer <= 0 then
			startRun(run)
		end
	end
end

local function onTargetBroken(player: Player, target: Target, _source: Types.DamageSource, shotId: number?)
	local run = runs[player]
	if run == nil or run.phase ~= "Combat" then
		return
	end
	local rate = GameConfig.Gems.perBlockHp * (if target.kind == "Elite" then GameConfig.Gems.eliteMultiplier else 1)
	local gems = math.max(1, math.ceil(target.maxHp * rate))
	run.haul += gems
	Network.HaulChanged:fireTo(player, { haul = run.haul, delta = gems, fromTargetId = target.id })
	if shotId then
		local breaks = (run.breaksByShot[shotId] or 0) + 1
		run.breaksByShot[shotId] = breaks
		run.bestCombo = math.max(run.bestCombo, breaks)
	end
	UpgradeService.addXp(player, target.maxHp * GameConfig.Xp.perBlockHp)
end

local function claimSlot(player: Player): number
	local slot = 1
	while slots[slot] do
		slot += 1
	end
	slots[slot] = player
	return slot
end

local function setup(player: Player)
	if runs[player] then
		return
	end
	local slot = claimSlot(player)
	local origin = LaneBuilder.originForSlot(slot)
	local run: Run = {
		player = player,
		slot = slot,
		origin = origin,
		lane = LaneBuilder.build(origin, `Lane_{player.UserId}`),
		runId = 0,
		rng = Random.new(0),
		depth = 1,
		room = 1,
		phase = "Intro",
		phaseTimer = 0,
		hp = MAX_PIPS,
		haul = 0,
		field = TargetField.new(),
		queue = {},
		pulse = 0,
		pulseTimer = 0,
		eliteTimer = 0,
		telegraph = nil,
		paused = false,
		picking = false,
		timeScale = 0,
		breaksByShot = {},
		bestCombo = 0,
		characterConnection = nil,
	}
	runs[player] = run
	run.characterConnection = player.CharacterAdded:Connect(function()
		task.spawn(placeCharacter, run)
	end)
	startRun(run)
end

local function teardown(player: Player)
	local run = runs[player]
	if run == nil then
		return
	end
	runs[player] = nil
	if slots[run.slot] == player then
		slots[run.slot] = nil
	end
	local connection = run.characterConnection
	if connection then
		connection:Disconnect()
	end
	CombatService.endLane(player)
	UpgradeService.endRun(player)
	run.lane:Destroy()
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

function RunDirector.init()
	table.insert(connections, Players.PlayerAdded:Connect(setup))
	table.insert(connections, Players.PlayerRemoving:Connect(teardown))
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		for _, run in runs do
			update(run, dt)
		end
	end))
	table.insert(signalConnections, CombatService.TargetBroken:Connect(onTargetBroken))
	table.insert(signalConnections, UpgradeService.OfferOpened:Connect(function(player: Player)
		local run = runs[player]
		if run then
			run.picking = true
			refreshTimeScale(run)
		end
	end))
	table.insert(signalConnections, UpgradeService.OfferClosed:Connect(function(player: Player)
		local run = runs[player]
		if run then
			run.picking = false
			refreshTimeScale(run)
		end
	end))
	table.insert(connections, Network.SetPaused:connect(function(player: Player, payload: Network.SetPausedPayload)
		local run = runs[player]
		if run and run.paused ~= payload.paused then
			run.paused = payload.paused
			refreshTimeScale(run)
		end
	end))
	Network.FetchRunSnapshot:setHandler(function(player: Player, _request: Network.NoPayload): Network.RunSnapshot?
		local run = runs[player]
		if run == nil then
			return nil
		end
		-- A client asking for a snapshot has (re)built its UI, so it needs the open offer again.
		task.defer(UpgradeService.resendOffer, player)
		return {
			state = runState(run),
			targets = run.field:snapshots(),
			health = healthPayload(run),
			haul = run.haul,
			xp = UpgradeService.getXp(player),
			loadout = UpgradeService.getLoadout(player),
		}
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(setup, player)
	end
end

-- Disconnects everything init() connected and tears every run down.
function RunDirector.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, connection in signalConnections do
		connection:Disconnect()
	end
	table.clear(signalConnections)
	for player in table.clone(runs) do
		teardown(player)
	end
end

-- Read-only views for tooling and tests.
export type RunView = {
	runId: number,
	phase: Types.RunPhase,
	depth: number,
	room: number,
	hp: number,
	haul: number,
	timeScale: number,
	targets: number,
	queuedRows: number,
	origin: CFrame,
}

function RunDirector.getRun(player: Player): RunView?
	local run = runs[player]
	if run == nil then
		return nil
	end
	return {
		runId = run.runId,
		phase = reportedPhase(run),
		depth = run.depth,
		room = run.room,
		hp = run.hp,
		haul = run.haul,
		timeScale = run.timeScale,
		targets = run.field:size(),
		queuedRows = #run.queue,
		origin = run.origin,
	}
end

-- The live target field of a player's run (tests and debugging tools).
function RunDirector.getField(player: Player): TargetField.TargetField?
	local run = runs[player]
	return if run then run.field else nil
end

return RunDirector
