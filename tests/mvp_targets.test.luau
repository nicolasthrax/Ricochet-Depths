-- Lane game, server modules: the target field (grid, damage, statuses, advancing) and room plans.
__freshMvp()
local GameConfig = __require("GameConfig")
local LaneGeometry = __require("LaneGeometry")
local TargetField = __require("TargetField")
local WaveGenerator = __require("WaveGenerator")

local Grid = GameConfig.Lane.grid

describe("TargetField", function()
	it("places targets on free cells only", function()
		local field = TargetField.new()
		local a = field:add("Block", 4, 2, 2, 10)
		expect(a).toBeTruthy()
		expect(field:add("Block", 5, 2, 1, 10)).toBeNil() -- overlaps a's second cell
		expect(field:add("Block", 9, 2, 2, 10)).toBeNil() -- off the right edge
		expect(field:add("Block", 1, Grid.rows + 1, 1, 10)).toBeNil() -- past the danger line
		expect(field:add("Block", 6, 2, 1, 10)).toBeTruthy()
		expect(field:size()).toBe(2)
		local box = LaneGeometry.targetBox(4, 2, 2)
		expect(a.obstacle.minX).toBe(box.minX)
		expect(a.obstacle.maxX).toBe(box.maxX)
	end)

	it("keeps the obstacle list cached until the field changes", function()
		local field = TargetField.new()
		field:add("Block", 1, 1, 1, 5)
		local first = field:obstacles()
		expect(field:obstacles()).toBe(first)
		field:add("Block", 3, 1, 1, 5)
		local second = field:obstacles()
		expect(second).never().toBe(first)
		expect(#second).toBe(2)
	end)

	it("breaks and removes a target at 0 HP", function()
		local field = TargetField.new()
		local target = field:add("Block", 2, 3, 1, 5) :: any
		local hp, broke = field:damage(target.id, 2)
		expect(hp).toBe(3)
		expect(broke).toBe(false)
		hp, broke = field:damage(target.id, 10)
		expect(hp).toBe(0)
		expect(broke).toBe(true)
		expect(field:get(target.id)).toBeNil()
		expect(field:size()).toBe(0)
		expect(field:damage(target.id, 1)).toBeNil()
		expect(field:add("Block", 2, 3, 1, 5)).toBeTruthy() -- its cell is free again
	end)

	it("advances blocks nearest-first, holds chilled blocks and the blocks behind them", function()
		local field = TargetField.new()
		local front = field:add("Block", 5, 4, 1, 5) :: any
		local behind = field:add("Block", 5, 3, 1, 5) :: any
		local side = field:add("Block", 2, 3, 1, 5) :: any
		local elite = field:add("Elite", 7, 1, 2, 80) :: any

		local moves = field:advance()
		expect(#moves).toBe(3)
		expect(front.row).toBe(5)
		expect(behind.row).toBe(4) -- moved into the cell the front block just left
		expect(elite.row).toBe(1) -- elites hold

		field:chill(front.id, 1)
		moves = field:advance()
		expect(front.row).toBe(5)
		expect(behind.row).toBe(4) -- blocked by the chilled block
		expect(side.row).toBe(5)
		expect(#moves).toBe(1)

		field:advance()
		expect(front.row).toBe(6)
	end)

	it("removes blocks that step past the danger line as breached", function()
		local field = TargetField.new()
		local target = field:add("Block", 3, Grid.rows, 1, 5) :: any
		local moves, breached = field:advance()
		expect(#moves).toBe(0)
		expect(#breached).toBe(1)
		expect(breached[1].id).toBe(target.id)
		expect(field:size()).toBe(0)
	end)

	it("burns over time without stacking weaker burns", function()
		local field = TargetField.new()
		local target = field:add("Block", 1, 1, 1, 50) :: any
		field:applyBurn(target.id, 4, 1)
		field:applyBurn(target.id, 2, 0.5)
		local total = 0
		for _ = 1, 10 do
			for _, tick in field:tickBurns(0.25) do
				total += tick.amount
			end
		end
		expect(total).toBeCloseTo(4, 1e-9)
		expect(#field:tickBurns(0.25)).toBe(0)
	end)

	it("finds neighbours by distance and by blast radius", function()
		local field = TargetField.new()
		local center = field:add("Block", 5, 5, 1, 10) :: any
		local near = field:add("Block", 6, 5, 1, 10) :: any
		local far = field:add("Block", 9, 5, 1, 10) :: any
		local cx, cy = field:center(center)
		local found = field:nearest(cx, cy, 2 * Grid.cellSize, 3, center.id)
		expect(#found).toBe(1)
		expect(found[1].id).toBe(near.id)
		local blasted = field:within(cx, cy, 2, center.id)
		expect(#blasted).toBe(1)
		expect(blasted[1].id).toBe(near.id)
		expect(#field:inRow(5)).toBe(3)
		expect(far.row).toBe(5)
	end)
end)

describe("WaveGenerator", function()
	it("is deterministic for a seed", function()
		local a = WaveGenerator.plan(2, 3, Random.new(42))
		local b = WaveGenerator.plan(2, 3, Random.new(42))
		expect(#a.rows).toBe(#b.rows)
		for index, row in a.rows do
			expect(#row).toBe(#b.rows[index])
			for spawnIndex, spawn in row do
				expect(spawn.column).toBe(b.rows[index][spawnIndex].column)
				expect(spawn.hp).toBe(b.rows[index][spawnIndex].hp)
			end
		end
	end)

	it("builds non-empty rows that fit the grid without overlaps", function()
		local rng = Random.new(7)
		for room = 1, 5 do
			local plan = WaveGenerator.plan(1, room, rng)
			expect(plan.hasElite).toBe(false)
			expect(#plan.rows).toBe(GameConfig.Rooms.startRows + WaveGenerator.streamedRows(1, room))
			for _, row in plan.rows do
				expect(#row).toBeGreaterThan(0)
				local field = TargetField.new()
				for _, spawn in row do
					expect(spawn.hp).toBeGreaterThanOrEqual(1)
					expect(field:add(spawn.kind, spawn.column, 1, spawn.widthColumns, spawn.hp)).toBeTruthy()
				end
			end
		end
	end)

	it("puts the elite last, behind a screen of blocks, in the elite room", function()
		local plan = WaveGenerator.plan(1, GameConfig.Run.eliteRoom, Random.new(3))
		expect(plan.hasElite).toBe(true)
		local last = plan.rows[#plan.rows]
		expect(#last).toBe(1)
		expect(last[1].kind).toBe("Elite")
		expect(last[1].hp).toBe(GameConfig.Targets.elite.hp)
		expect(WaveGenerator.eliteHp(2)).toBeGreaterThan(GameConfig.Targets.elite.hp)
	end)

	it("makes blocks tougher deeper down", function()
		local shallow, deep = 0, 0
		local rng = Random.new(11)
		for _ = 1, 50 do
			shallow += WaveGenerator.blockHp(1, 1, rng)
			deep += WaveGenerator.blockHp(3, 1, rng)
		end
		expect(deep).toBeGreaterThan(shallow * 2)
	end)
end)
