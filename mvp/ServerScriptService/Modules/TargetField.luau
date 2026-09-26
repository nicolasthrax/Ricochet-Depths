--!strict
-- The targets of one run: where they sit on the grid, their HP and status effects, and the
-- collision boxes the shot simulation sees. Server-only state; clients get snapshots.
--
-- Grid rules: a target covers `widthColumns` cells of one row, and no two targets share a cell.
-- Every pulse, blocks step one row towards the rail, nearest rows first, so a block that cannot
-- move (chilled, or the cell ahead is taken) holds up the blocks behind it. Elites hold their row.
-- A block stepping past the last grid row has crossed the danger line and is removed as breached.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local LaneGeometry = require(ReplicatedStorage.Source.Sim.LaneGeometry)
local Ricochet = require(ReplicatedStorage.Source.Sim.Ricochet)
local Network = require(ReplicatedStorage.Network)

local Grid = GameConfig.Lane.grid

export type Target = {
	id: number,
	kind: Types.TargetKind,
	column: number,
	row: number,
	widthColumns: number,
	hp: number,
	maxHp: number,
	skipSteps: number, -- pulses left to hold still (chill)
	burnDps: number,
	burnSecondsLeft: number,
	obstacle: Ricochet.Obstacle,
}

export type Move = Network.TargetMove

export type BurnTick = {
	targetId: number,
	amount: number,
}

type FieldData = {
	targets: { [number]: Target },
	cells: { [number]: number }, -- cell index -> target id
	nextId: number,
	count: number,
	obstacleCache: { Ricochet.Obstacle }?,
}

local TargetField = {}
TargetField.__index = TargetField

export type TargetField = typeof(setmetatable({} :: FieldData, TargetField))

local function cellIndex(column: number, row: number): number
	return (row - 1) * Grid.columns + column
end

local function makeObstacle(id: number, column: number, row: number, widthColumns: number): Ricochet.Obstacle
	local box = LaneGeometry.targetBox(column, row, widthColumns)
	return { id = id, minX = box.minX, minY = box.minY, maxX = box.maxX, maxY = box.maxY }
end

function TargetField.new(): TargetField
	local data: FieldData = {
		targets = {},
		cells = {},
		nextId = 0,
		count = 0,
		obstacleCache = nil,
	}
	return setmetatable(data, TargetField)
end

-- Marks the target's cells as taken by `id`, or frees them when `id` is nil.
local function occupy(self: TargetField, target: Target, id: number?)
	for offset = 0, target.widthColumns - 1 do
		local index = cellIndex(target.column + offset, target.row)
		if id == nil then
			self.cells[index] = nil
		else
			self.cells[index] = id
		end
	end
end

-- Whether a target of this width could stand at (column, row), ignoring `ignoreId`.
function TargetField.isFree(self: TargetField, column: number, row: number, widthColumns: number, ignoreId: number?): boolean
	if not LaneGeometry.fitsGrid(column, row, widthColumns) then
		return false
	end
	for offset = 0, widthColumns - 1 do
		local occupant = self.cells[cellIndex(column + offset, row)]
		if occupant ~= nil and occupant ~= ignoreId then
			return false
		end
	end
	return true
end

-- Adds a target; nil when it does not fit or overlaps another target.
function TargetField.add(
	self: TargetField,
	kind: Types.TargetKind,
	column: number,
	row: number,
	widthColumns: number,
	hp: number
): Target?
	assert(hp > 0, "a target needs HP")
	if not self:isFree(column, row, widthColumns) then
		return nil
	end
	self.nextId += 1
	local id = self.nextId
	local target: Target = {
		id = id,
		kind = kind,
		column = column,
		row = row,
		widthColumns = widthColumns,
		hp = hp,
		maxHp = hp,
		skipSteps = 0,
		burnDps = 0,
		burnSecondsLeft = 0,
		obstacle = makeObstacle(id, column, row, widthColumns),
	}
	self.targets[id] = target
	self.count += 1
	occupy(self, target, id)
	self.obstacleCache = nil
	return target
end

function TargetField.get(self: TargetField, id: number): Target?
	return self.targets[id]
end

function TargetField.size(self: TargetField): number
	return self.count
end

-- Every target, ordered by id (deterministic iteration).
function TargetField.all(self: TargetField): { Target }
	local list: { Target } = {}
	for _, target in self.targets do
		table.insert(list, target)
	end
	table.sort(list, function(a: Target, b: Target): boolean
		return a.id < b.id
	end)
	return list
end

function TargetField.remove(self: TargetField, id: number): Target?
	local target = self.targets[id]
	if target == nil then
		return nil
	end
	occupy(self, target, nil)
	self.targets[id] = nil
	self.count -= 1
	self.obstacleCache = nil
	return target
end

-- Deals damage. Returns the HP left and whether the target broke (a broken target is removed),
-- plus the target itself; nil when the target no longer exists.
function TargetField.damage(self: TargetField, id: number, amount: number): (number?, boolean, Target?)
	local target = self.targets[id]
	if target == nil then
		return nil, false, nil
	end
	target.hp = math.max(0, target.hp - amount)
	if target.hp <= 0 then
		self:remove(id)
		return 0, true, target
	end
	return target.hp, false, target
end

-- The collision boxes for the shot simulation. Rebuilt only when the field changes.
function TargetField.obstacles(self: TargetField): { Ricochet.Obstacle }
	local cached = self.obstacleCache
	if cached then
		return cached
	end
	local list: { Ricochet.Obstacle } = {}
	for _, target in self:all() do
		table.insert(list, target.obstacle)
	end
	self.obstacleCache = list
	return list
end

-- Centre of a target in lane space.
function TargetField.center(_self: TargetField, target: Target): (number, number)
	local box = target.obstacle
	return (box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2
end

-- Sets a target burning. A new burn never weakens or shortens a stronger one already running.
function TargetField.applyBurn(self: TargetField, id: number, damagePerSecond: number, seconds: number)
	local target = self.targets[id]
	if target then
		target.burnDps = math.max(target.burnDps, damagePerSecond)
		target.burnSecondsLeft = math.max(target.burnSecondsLeft, seconds)
	end
end

-- Chills a target: it holds still for the next `steps` pulses.
function TargetField.chill(self: TargetField, id: number, steps: number)
	local target = self.targets[id]
	if target then
		target.skipSteps = math.max(target.skipSteps, steps)
	end
end

-- Burn damage owed for `dt` seconds, per burning target (not applied: the caller deals it, so
-- burn breaks go through the same path as every other break).
function TargetField.tickBurns(self: TargetField, dt: number): { BurnTick }
	local ticks: { BurnTick } = {}
	for _, target in self:all() do
		if target.burnSecondsLeft > 0 then
			local seconds = math.min(dt, target.burnSecondsLeft)
			table.insert(ticks, { targetId = target.id, amount = target.burnDps * seconds })
			target.burnSecondsLeft -= seconds
			if target.burnSecondsLeft <= 0 then
				target.burnDps = 0
			end
		end
	end
	return ticks
end

-- Targets in a row, by id.
function TargetField.inRow(self: TargetField, row: number): { Target }
	local list: { Target } = {}
	for _, target in self:all() do
		if target.row == row then
			table.insert(list, target)
		end
	end
	return list
end

-- Up to `count` targets whose centres are within `range` of (x, y), nearest first (ties by id),
-- skipping `excludeId`.
function TargetField.nearest(self: TargetField, x: number, y: number, range: number, count: number, excludeId: number?): { Target }
	type Candidate = { target: Target, distance: number }
	local candidates: { Candidate } = {}
	for _, target in self:all() do
		if target.id ~= excludeId then
			local cx, cy = self:center(target)
			local distance = math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
			if distance <= range then
				table.insert(candidates, { target = target, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.target.id < b.target.id
	end)
	local result: { Target } = {}
	for index = 1, math.min(count, #candidates) do
		table.insert(result, candidates[index].target)
	end
	return result
end

-- Targets whose boxes come within `radius` of (x, y), skipping `excludeId` (blast damage).
function TargetField.within(self: TargetField, x: number, y: number, radius: number, excludeId: number?): { Target }
	local result: { Target } = {}
	for _, target in self:all() do
		if target.id ~= excludeId then
			local box = target.obstacle
			local dx = math.max(box.minX - x, 0, x - box.maxX)
			local dy = math.max(box.minY - y, 0, y - box.maxY)
			if dx * dx + dy * dy <= radius * radius then
				table.insert(result, target)
			end
		end
	end
	return result
end

-- One pulse: blocks step a row towards the rail. Returns the moves and the breached targets
-- (already removed from the field).
function TargetField.advance(self: TargetField): ({ Move }, { Target })
	local order = self:all()
	-- Nearest the rail first, so each block sees whether the cell ahead was just vacated.
	table.sort(order, function(a: Target, b: Target): boolean
		if a.row ~= b.row then
			return a.row > b.row
		end
		return a.id < b.id
	end)

	local moves: { Move } = {}
	local breached: { Target } = {}
	for _, target in order do
		if target.kind == "Elite" then
			continue
		end
		if target.skipSteps > 0 then
			target.skipSteps -= 1
			continue
		end
		local nextRow = target.row + 1
		if LaneGeometry.isBreached(nextRow) then
			self:remove(target.id)
			table.insert(breached, target)
		elseif self:isFree(target.column, nextRow, target.widthColumns, target.id) then
			occupy(self, target, nil)
			target.row = nextRow
			target.obstacle = makeObstacle(target.id, target.column, nextRow, target.widthColumns)
			occupy(self, target, target.id)
			self.obstacleCache = nil
			table.insert(moves, { targetId = target.id, row = nextRow })
		end
	end
	return moves, breached
end

function TargetField.snapshot(_self: TargetField, target: Target): Network.TargetSnapshot
	return {
		targetId = target.id,
		kind = target.kind,
		column = target.column,
		row = target.row,
		widthColumns = target.widthColumns,
		hp = target.hp,
		maxHp = target.maxHp,
	}
end

function TargetField.snapshots(self: TargetField): { Network.TargetSnapshot }
	local list: { Network.TargetSnapshot } = {}
	for _, target in self:all() do
		table.insert(list, self:snapshot(target))
	end
	return list
end

return TargetField
