--!strict
-- Lane space, the target grid, and the mapping to the world. See GameConfig for the axes: x runs
-- across the lane (0 is the centre), y runs up the lane from the rail (y = 0) to the back wall.
--
-- Sim modules work on plain numbers, never Vector2: Vector2 stores 32-bit floats, so a simulation
-- that round-trips through it would not match between server and client. Vector3 and CFrame
-- appear only in the world mapping at the bottom of this module.

local GameConfig = require(script.Parent.Parent.GameConfig)

local Lane = GameConfig.Lane
local Grid = Lane.grid
local Rail = GameConfig.Rail

-- An axis-aligned box in lane space.
export type Box = {
	minX: number,
	minY: number,
	maxX: number,
	maxY: number,
}

local LaneGeometry = {}

---------------------------------------------------------------------------------------------
-- Grid. Column 1 is the left edge; row 1 is against the back wall and rows count towards the
-- rail. Row Grid.rows is the last row above the danger line.
---------------------------------------------------------------------------------------------

-- Centre of a grid cell.
function LaneGeometry.cellCenter(column: number, row: number): (number, number)
	return -Lane.halfWidth + (column - 0.5) * Grid.cellSize, Lane.length - (row - 0.5) * Grid.cellSize
end

-- The collision box of a target covering `widthColumns` cells from `column`, in `row`. Boxes are
-- inset from their cells, so neighbouring targets never touch.
function LaneGeometry.targetBox(column: number, row: number, widthColumns: number): Box
	local left = -Lane.halfWidth + (column - 1) * Grid.cellSize
	local top = Lane.length - (row - 1) * Grid.cellSize
	return {
		minX = left + Grid.blockInset,
		maxX = left + widthColumns * Grid.cellSize - Grid.blockInset,
		minY = top - Grid.cellSize + Grid.blockInset,
		maxY = top - Grid.blockInset,
	}
end

-- The column under x, clamped to the grid.
function LaneGeometry.columnAt(x: number): number
	local column = math.floor((x + Lane.halfWidth) / Grid.cellSize) + 1
	return math.clamp(column, 1, Grid.columns)
end

-- The row at y. Not clamped at the rail end: a y below the danger line gives a row past Grid.rows.
function LaneGeometry.rowAt(y: number): number
	return math.max(1, math.floor((Lane.length - y) / Grid.cellSize) + 1)
end

-- Whether a target of this width fits the grid at this cell.
function LaneGeometry.fitsGrid(column: number, row: number, widthColumns: number): boolean
	return column >= 1
		and widthColumns >= 1
		and column + widthColumns - 1 <= Grid.columns
		and row >= 1
		and row <= Grid.rows
end

-- A target that has stepped into this row has crossed the danger line.
function LaneGeometry.isBreached(row: number): boolean
	return row > Grid.rows
end

---------------------------------------------------------------------------------------------
-- Rail
---------------------------------------------------------------------------------------------

function LaneGeometry.clampRailX(x: number): number
	return math.clamp(x, Rail.minX, Rail.maxX)
end

-- Where a shot fired from this rail position starts.
function LaneGeometry.muzzle(railX: number): (number, number)
	return LaneGeometry.clampRailX(railX), Rail.y + GameConfig.Shot.muzzleOffset
end

-- The aim rule, shared by the client's guide line and the server: a unit direction pointing up the
-- lane at least GameConfig.Shot.minAimY. Flatter aims are raised to that angle on the same side
-- (straight sideways goes right); a zero direction aims straight up the lane.
function LaneGeometry.clampAim(dx: number, dy: number): (number, number)
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1e-9 then
		return 0, 1
	end
	dx, dy = dx / length, dy / length
	local minY = GameConfig.Shot.minAimY
	if dy >= minY then
		return dx, dy
	end
	local side = if dx < 0 then -1 else 1
	return side * math.sqrt(1 - minY * minY), minY
end

---------------------------------------------------------------------------------------------
-- World mapping. `origin` is a pit's lane origin: its Position is the rail centre on the lane
-- floor, its LookVector points up the lane (+y) and its RightVector across it (+x).
---------------------------------------------------------------------------------------------

-- Written out per component: plain arithmetic, and the same result on every machine.
function LaneGeometry.toWorld(origin: CFrame, x: number, y: number, height: number?): Vector3
	local p, r, l, u = origin.Position, origin.RightVector, origin.LookVector, origin.UpVector
	local h = height or 0
	return Vector3.new(
		p.X + r.X * x + l.X * y + u.X * h,
		p.Y + r.Y * x + l.Y * y + u.Y * h,
		p.Z + r.Z * x + l.Z * y + u.Z * h
	)
end

function LaneGeometry.toLane(origin: CFrame, position: Vector3): (number, number)
	local p, r, l = origin.Position, origin.RightVector, origin.LookVector
	local dx, dy, dz = position.X - p.X, position.Y - p.Y, position.Z - p.Z
	return dx * r.X + dy * r.Y + dz * r.Z, dx * l.X + dy * l.Y + dz * l.Z
end

function LaneGeometry.directionToWorld(origin: CFrame, dx: number, dy: number): Vector3
	local r, l = origin.RightVector, origin.LookVector
	return Vector3.new(r.X * dx + l.X * dy, r.Y * dx + l.Y * dy, r.Z * dx + l.Z * dy)
end

table.freeze(LaneGeometry)
return LaneGeometry
