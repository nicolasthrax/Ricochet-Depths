-- Runs several descents on one server at once. Each group (a gate's party, or one player through
-- the solo portal) gets an arena slot: its own folder, rooms, enemies, projectiles and
-- MatchService, built at its own origin far from the others. Slots are made when first needed
-- and reused when their run ends.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoinDrops = require(script.Parent.CoinDrops)
local EffectBroadcaster = require(script.Parent.EffectBroadcaster)
local EnemyService = require(script.Parent.EnemyService)
local MatchService = require(script.Parent.MatchService)
local ProjectileService = require(script.Parent.ProjectileService)
local RewardService = require(script.Parent.RewardService)
local RoomService = require(script.Parent.RoomService)
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local UpgradeService = require(script.Parent.UpgradeService)

local ArenaDirector = {}
ArenaDirector.__index = ArenaDirector

-- options: parent (where slot folders go), planeY, seed, maxSlots, shared (MatchService deps
-- every slot shares: net, world, persistence, telemetry, metaProvider, planRun, runKeyPrefix),
-- effectsRemote (optional), onReleased(players) called when a group is sent home.
function ArenaDirector.new(options)
	return setmetatable({
		_parent = options.parent,
		_planeY = options.planeY,
		_seed = options.seed or 1,
		_maxSlots = options.maxSlots or RunConfig.Arenas.MaxSlots,
		_shared = options.shared or {},
		_effectsRemote = options.effectsRemote,
		_onReleased = options.onReleased,
		_slots = {},
		_slotOf = {}, -- player -> slot
	}, ArenaDirector)
end

function ArenaDirector:_createSlot(index)
	local origin = Vector3.new(index * RunConfig.Arenas.Spacing, 0, 0)
	local folder = Instance.new("Folder")
	folder.Name = "Slot" .. index
	folder.Parent = self._parent

	-- Everything a projectile may collide with lives under Arena, so one filter covers it all.
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena:SetAttribute("IsArena", true)
	arena.Parent = folder

	local seed = self._seed + index * 7919
	local enemies = EnemyService.new(arena, self._planeY, seed)
	local projectiles = ProjectileService.new(folder, arena, self._planeY)
	-- Champion draws get their own stream, seeded per server and slot like everything else.
	local rooms = RoomService.new(arena, enemies, self._planeY, Random.new(seed), origin, Random.new(seed + 17))

	local slot = {
		index = index,
		origin = origin,
		folder = folder,
		arena = arena,
		enemies = enemies,
		projectiles = projectiles,
		rooms = rooms,
		members = {},
		busy = false,
	}

	local deps = table.clone(self._shared)
	deps.rooms = rooms
	deps.enemies = enemies
	deps.projectiles = projectiles
	deps.upgrades = UpgradeService.new(seed)
	deps.rewards = RewardService.new()
	deps.seed = seed -- crit rolls
	deps.coins = CoinDrops.new(arena, Random.new(seed))
	-- Run keys must be unique per slot as well as per server, or two arenas' first runs
	-- would share a payout key and the profile ledger would refuse the second.
	deps.runKeyPrefix = string.format("%s-a%d", self._shared.runKeyPrefix or "local", index)
	if self._effectsRemote then
		deps.effects = EffectBroadcaster.new(self._effectsRemote, function()
			return slot.members
		end)
	end
	slot.match = MatchService.new(deps)
	projectiles.OnImpact = function(result, entry)
		return slot.match:HandleImpact(result, entry, os.clock())
	end
	return slot
end

function ArenaDirector:_freeSlot()
	for _, slot in self._slots do
		if not slot.busy then
			return slot
		end
	end
	if #self._slots < self._maxSlots then
		local slot = self:_createSlot(#self._slots + 1)
		table.insert(self._slots, slot)
		return slot
	end
	return nil
end

-- Starts a descent for `players` in a free arena. Returns the slot, or nil and a reason.
function ArenaDirector:StartGroup(players, now)
	if #players == 0 then
		return nil, "no players"
	end
	for _, player in players do
		if self._slotOf[player] then
			return nil, "already in a run"
		end
	end
	local slot = self:_freeSlot()
	if not slot then
		return nil, "all arenas busy"
	end
	for _, player in players do
		slot.match:RegisterPlayer(player)
	end
	local ok, reason = slot.match:RequestStart(players[1], now)
	if not ok then
		for _, player in players do
			slot.match:UnregisterPlayer(player, now)
		end
		return nil, reason
	end
	slot.busy = true
	slot.members = table.clone(players)
	for _, player in players do
		self._slotOf[player] = slot
	end
	return slot
end

function ArenaDirector:SlotFor(player)
	return self._slotOf[player]
end

-- The match `player` is playing in, or nil while they are in the lobby.
function ArenaDirector:MatchFor(player)
	local slot = self._slotOf[player]
	return slot and slot.match
end

function ArenaDirector:GetSlots()
	return self._slots
end

-- A player left the server (or otherwise dropped out of their run).
function ArenaDirector:RemovePlayer(player, now)
	local slot = self._slotOf[player]
	if not slot then
		return
	end
	self._slotOf[player] = nil
	local index = table.find(slot.members, player)
	if index then
		table.remove(slot.members, index)
	end
	slot.match:UnregisterPlayer(player, now)
end

function ArenaDirector:_release(slot)
	local members = slot.members
	for _, player in members do
		self._slotOf[player] = nil
		slot.match:UnregisterPlayer(player)
	end
	slot.members = {}
	slot.busy = false
	if self._onReleased and #members > 0 then
		self._onReleased(members)
	end
end

function ArenaDirector:Step(deltaTime, now)
	for _, slot in self._slots do
		if slot.busy then
			slot.enemies:Step(deltaTime, now)
			slot.projectiles:Step(deltaTime)
			slot.match:Step(deltaTime, now)
			if slot.match._effects then
				slot.match._effects:Step(now)
			end
			-- Back in the lobby state: the run is over and its players were sent home.
			if slot.match:GetState() == RunConfig.States.Lobby then
				self:_release(slot)
			end
		end
	end
end

-- Totals across every slot, for the developer overlay.
function ArenaDirector:GetStats()
	local stats = { Slots = #self._slots, Busy = 0, ProjectilesActive = 0, EnemiesActive = 0, Players = 0 }
	for _, slot in self._slots do
		if slot.busy then
			stats.Busy += 1
			stats.Players += #slot.members
		end
		stats.ProjectilesActive += slot.projectiles:GetActiveCount()
		stats.EnemiesActive += slot.enemies:GetActiveCount()
	end
	return stats
end

return ArenaDirector
