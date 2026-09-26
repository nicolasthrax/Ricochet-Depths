--!strict
-- Room layouts: which targets a room holds, row by row. Deterministic for a given Random, so a
-- run can be replayed from its seed.
--
-- A plan's rows are in arrival order: rows[1] arrives first and so sits nearest the rail. The first
-- GameConfig.Rooms.startRows rows are on the grid when the room opens; the rest stream in at the
-- back wall, one per pulse. The elite room (GameConfig.Run.eliteRoom) ends with the elite, so it
-- opens at the back of the lane behind a screen of blocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)

local Rooms = GameConfig.Rooms
local Grid = GameConfig.Lane.grid
local Elite = GameConfig.Targets.elite

export type Spawn = {
	kind: Types.TargetKind,
	column: number,
	widthColumns: number,
	hp: number,
}

export type Row = { Spawn }

export type RoomPlan = {
	rows: { Row },
	hasElite: boolean,
}

local WaveGenerator = {}

-- A block's HP for this room: grows with room and depth, jittered, never below 1.
function WaveGenerator.blockHp(depth: number, room: number, rng: Random): number
	local hp = Rooms.blockHp
	local base = hp.base + hp.perRoom * (room - 1) + hp.perDepth * (depth - 1)
	local jitter = 1 + rng:NextNumber(-hp.jitter, hp.jitter)
	return math.max(1, math.round(base * jitter))
end

function WaveGenerator.eliteHp(depth: number): number
	return math.round(Elite.hp * (1 + Rooms.eliteHpPerDepth * (depth - 1)))
end

-- One row of blocks. Never empty: a row that rolled no blocks gets one in a random column.
function WaveGenerator.row(depth: number, room: number, rng: Random): Row
	local row: Row = {}
	local column = 1
	while column <= Grid.columns do
		if rng:NextNumber() < Rooms.rowFill then
			local wide = column < Grid.columns and rng:NextNumber() < Rooms.wideBlockChance
			local width = if wide then 2 else 1
			local spawn: Spawn = {
				kind = "Block",
				column = column,
				widthColumns = width,
				hp = WaveGenerator.blockHp(depth, room, rng) * width,
			}
			table.insert(row, spawn)
			column += width
		else
			column += 1
		end
	end
	if #row == 0 then
		local spawn: Spawn = {
			kind = "Block",
			column = rng:NextInteger(1, Grid.columns),
			widthColumns = 1,
			hp = WaveGenerator.blockHp(depth, room, rng),
		}
		table.insert(row, spawn)
	end
	return row
end

-- How many rows stream in after the room opens.
function WaveGenerator.streamedRows(depth: number, room: number): number
	return math.floor(Rooms.streamRowsBase + Rooms.streamRowsPerRoom * room + (depth - 1))
end

function WaveGenerator.plan(depth: number, room: number, rng: Random): RoomPlan
	local rows: { Row } = {}
	if room == GameConfig.Run.eliteRoom then
		-- A screen of blocks, then the elite centred against the back wall.
		for _ = 1, Rooms.startRows - 1 do
			table.insert(rows, WaveGenerator.row(depth, room, rng))
		end
		local width = Elite.widthColumns
		local elite: Spawn = {
			kind = "Elite",
			column = math.floor((Grid.columns - width) / 2) + 1,
			widthColumns = width,
			hp = WaveGenerator.eliteHp(depth),
		}
		local eliteRow: Row = { elite }
		table.insert(rows, eliteRow)
		return { rows = rows, hasElite = true }
	end

	for _ = 1, Rooms.startRows + WaveGenerator.streamedRows(depth, room) do
		table.insert(rows, WaveGenerator.row(depth, room, rng))
	end
	return { rows = rows, hasElite = false }
end

table.freeze(WaveGenerator)
return WaveGenerator
