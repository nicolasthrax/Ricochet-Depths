-- Lane-game shared simulation (mvp/ReplicatedStorage/Source/Sim): lane geometry, ricochet, shot
-- stats. Exact cases first, then invariants over randomised shots.
local GameConfig = __require("GameConfig")
local LaneGeometry = __require("LaneGeometry")
local Ricochet = __require("Ricochet")
local ShotStats = __require("ShotStats")

local Lane = GameConfig.Lane
local Tuning = GameConfig.Ricochet
local RADIUS = GameConfig.Shot.radius

local function shot(x, y, dirX, dirY, overrides)
	local params = {
		x = x,
		y = y,
		dirX = dirX,
		dirY = dirY,
		speed = 70,
		radius = RADIUS,
		bounces = 10,
		lifetime = 100,
	}
	for key, value in overrides or {} do
		params[key] = value
	end
	return Ricochet.newShot(params)
end

local function obstacle(id, column, row, width)
	local box = LaneGeometry.targetBox(column, row, width or 1)
	return { id = id, minX = box.minX, minY = box.minY, maxX = box.maxX, maxY = box.maxY }
end

describe("LaneGeometry", function()
	it("maps grid cells to lane space", function()
		local x, y = LaneGeometry.cellCenter(1, 1)
		expect(x).toBeCloseTo(-12, 1e-9)
		expect(y).toBeCloseTo(40.5, 1e-9)
		x, y = LaneGeometry.cellCenter(9, 12)
		expect(x).toBeCloseTo(12, 1e-9)
		expect(y).toBeCloseTo(7.5, 1e-9)
		expect(LaneGeometry.columnAt(0)).toBe(5)
		expect(LaneGeometry.columnAt(-100)).toBe(1)
		expect(LaneGeometry.columnAt(100)).toBe(9)
		expect(LaneGeometry.rowAt(40.5)).toBe(1)
		expect(LaneGeometry.rowAt(7.5)).toBe(12)
		expect(LaneGeometry.rowAt(Lane.dangerLineY - 1)).toBe(13)
	end)

	it("insets target boxes inside their cells", function()
		local box = LaneGeometry.targetBox(4, 2, 2)
		expect(box.minX).toBeCloseTo(-4.3, 1e-9)
		expect(box.maxX).toBeCloseTo(1.3, 1e-9)
		expect(box.minY).toBeCloseTo(36.2, 1e-9)
		expect(box.maxY).toBeCloseTo(38.8, 1e-9)
	end)

	it("knows what fits the grid and what has breached", function()
		expect(LaneGeometry.fitsGrid(8, 1, 2)).toBe(true)
		expect(LaneGeometry.fitsGrid(9, 1, 2)).toBe(false)
		expect(LaneGeometry.fitsGrid(1, 13, 1)).toBe(false)
		expect(LaneGeometry.isBreached(12)).toBe(false)
		expect(LaneGeometry.isBreached(13)).toBe(true)
	end)

	it("clamps the rail and places the muzzle", function()
		expect(LaneGeometry.clampRailX(100)).toBe(GameConfig.Rail.maxX)
		local x, y = LaneGeometry.muzzle(-100)
		expect(x).toBe(GameConfig.Rail.minX)
		expect(y).toBeCloseTo(GameConfig.Rail.y + GameConfig.Shot.muzzleOffset, 1e-9)
	end)

	it("maps lane space to the world and back through a rotated origin", function()
		local flat = LaneGeometry.toWorld(CFrame.new(0, 0, 0), 0, 10)
		expect(flat.Z).toBeCloseTo(-10, 1e-9) -- up the lane is the origin's LookVector
		local origin = CFrame.new(10, 5, -20) * CFrame.Angles(0, math.rad(30), 0)
		local world = LaneGeometry.toWorld(origin, 3, 7, 2)
		local x, y = LaneGeometry.toLane(origin, world)
		expect(x).toBeCloseTo(3, 1e-9)
		expect(y).toBeCloseTo(7, 1e-9)
		expect(world.Y).toBeCloseTo(7, 1e-9)
	end)
end)

describe("Ricochet", function()
	it("reflects with the angle out equal to the angle in", function()
		local s = math.sqrt(0.5)
		local rx, ry = Ricochet.reflect(s, -s, 0, 1)
		expect(rx).toBeCloseTo(s, 1e-12)
		expect(ry).toBeCloseTo(s, 1e-12)
	end)

	it("bounces off a side wall, loses speed and keeps the remaining time", function()
		local s = shot(0, 10, 1, 0)
		local contacts = Ricochet.step(s, 0.25, {})
		expect(#contacts).toBe(1)
		local wallX = Lane.halfWidth - RADIUS
		expect(contacts[1].kind).toBe("Wall")
		expect(contacts[1].x).toBeCloseTo(wallX, 1e-9)
		expect(contacts[1].normalX).toBe(-1)
		expect(contacts[1].time).toBeCloseTo(wallX / 70, 1e-12)
		expect(s.dirX).toBeCloseTo(-1, 1e-12)
		expect(s.speed).toBeCloseTo(70 * Tuning.wallSpeedRetention, 1e-9)
		expect(s.bouncesLeft).toBe(9)
		expect(s.bouncesTaken).toBe(1)
		local expectedX = wallX - Tuning.surfaceSkin - (0.25 - wallX / 70) * s.speed
		expect(s.x).toBeCloseTo(expectedX, 1e-9)
	end)

	it("exits past the open rail edge", function()
		local s = shot(0, 5, 0, -1)
		local contacts = Ricochet.step(s, 1, {})
		expect(contacts[1].kind).toBe("Exit")
		expect(contacts[1].y).toBeCloseTo(-RADIUS, 1e-9)
		expect(s.alive).toBe(false)
		expect(s.endReason).toBe("Exit")
	end)

	it("bounces off a target face", function()
		local target = obstacle(7, 5, 1)
		local s = shot(0, 30, 0, 1)
		local contacts = Ricochet.step(s, 0.2, { target })
		expect(contacts[1].kind).toBe("Target")
		expect(contacts[1].targetId).toBe(7)
		expect(contacts[1].y).toBeCloseTo(target.minY - RADIUS, 1e-9)
		expect(contacts[1].normalY).toBe(-1)
		expect(s.dirY).toBeCloseTo(-1, 1e-12)
		expect(s.speed).toBeCloseTo(70 * Tuning.targetSpeedRetention, 1e-9)
	end)

	it("bounces off a rounded corner along the true normal", function()
		-- Aimed straight at the corner: a flat face would deflect sideways, a round corner sends it back.
		local corner = { id = 1, minX = 0, maxX = 2, minY = 20, maxY = 22 }
		local s = shot(-3, 17, 1, 1)
		local contacts = Ricochet.step(s, 0.2, { corner })
		expect(contacts[1].kind).toBe("Target")
		expect(contacts[1].normalX).toBeCloseTo(-math.sqrt(0.5), 1e-9)
		expect(contacts[1].normalY).toBeCloseTo(-math.sqrt(0.5), 1e-9)
		expect(s.dirX).toBeCloseTo(-math.sqrt(0.5), 1e-9)
		expect(s.dirY).toBeCloseTo(-math.sqrt(0.5), 1e-9)
		expect(contacts[1].time * 70).toBeCloseTo(math.sqrt(18) - RADIUS, 1e-9)
	end)

	it("ends shots that are spent, slow, expired or stopped", function()
		local spent = shot(0, 10, 1, 0, { bounces = 0 })
		expect(#Ricochet.step(spent, 1, {})).toBe(1) -- the contact still counts
		expect(spent.endReason).toBe("Spent")

		local slow = shot(0, 10, 1, 0, { speed = Tuning.minSpeed + 0.5 })
		Ricochet.step(slow, 1, {})
		expect(slow.endReason).toBe("Slow")

		local old = shot(0, 10, 0, 1, { speed = 10, lifetime = 0.5 })
		Ricochet.step(old, 0.25, {})
		expect(old.alive).toBe(true)
		Ricochet.step(old, 0.25, {})
		expect(old.endReason).toBe("Expired")
		expect(old.y).toBeCloseTo(15, 1e-9)

		local stopped = shot(0, 30, 0, 1)
		Ricochet.step(stopped, 1, { obstacle(1, 5, 1) }, function()
			return "Stop"
		end)
		expect(stopped.endReason).toBe("Stopped")
		expect(#Ricochet.step(stopped, 1, {})).toBe(0)
	end)

	it("pierces a target once, then can hit it again after bouncing", function()
		local target = obstacle(3, 5, 5)
		local s = shot(0, 10, 0, 1)
		local asked = 0
		local contacts = Ricochet.step(s, 1, { target }, function()
			asked += 1
			return "Pierce"
		end)
		expect(#contacts).toBe(3)
		expect(contacts[1].kind).toBe("Target")
		expect(contacts[1].normalY).toBe(-1)
		expect(contacts[2].kind).toBe("Wall")
		expect(contacts[3].kind).toBe("Target")
		expect(contacts[3].normalY).toBe(1)
		expect(asked).toBe(2)
		expect(s.bouncesTaken).toBe(1)
	end)

	it("caps contacts per step", function()
		local s = shot(0, 10, 1, 0)
		local contacts = Ricochet.step(s, 2, {})
		expect(#contacts).toBe(Tuning.maxBouncesPerStep)
		expect(s.alive).toBe(true)
	end)

	it("previews exactly the path the simulation takes", function()
		local field = { obstacle(1, 7, 3), obstacle(2, 2, 6, 2), obstacle(3, 5, 1, 3) }
		local path = Ricochet.trace(0, 1.2, 0.6, 1, RADIUS, 3, 500, field)
		local s = shot(0, 1.2, 0.6, 1, { speed = 45 })
		local contacts = {}
		for _ = 1, 400 do
			for _, contact in Ricochet.step(s, 1 / 60, field) do
				table.insert(contacts, contact)
			end
			if #contacts >= 3 or not s.alive then
				break
			end
		end
		expect(#path).toBeGreaterThanOrEqual(4)
		for index = 1, 3 do
			expect(path[index + 1].x).toBeCloseTo(contacts[index].x, 1e-9)
			expect(path[index + 1].y).toBeCloseTo(contacts[index].y, 1e-9)
			expect(path[index + 1].kind).toBe(contacts[index].kind)
		end
	end)

	it("is deterministic", function()
		local field = { obstacle(1, 3, 2), obstacle(2, 6, 4, 2), obstacle(3, 1, 7) }
		local function run()
			local s = shot(1.7, 1.2, -0.35, 1, { bounces = 30 })
			for _ = 1, 240 do
				Ricochet.step(s, 1 / 60, field)
			end
			return s.x, s.y, s.bouncesTaken
		end
		local x1, y1, b1 = run()
		local x2, y2, b2 = run()
		expect(x1).toBe(x2)
		expect(y1).toBe(y2)
		expect(b1).toBe(b2)
		expect(b1).toBeGreaterThan(0)
	end)

	it("never leaves the lane or ends a step inside a target (randomised)", function()
		math.randomseed(1234)
		local tolerance = 1e-6
		local stepsChecked = 0
		for _ = 1, 300 do
			local field = {}
			for id = 1, math.random(0, 18) do
				local width = math.random(1, 2)
				table.insert(field, obstacle(id, math.random(1, 9 - width + 1), math.random(1, 10), width))
			end
			local angle = math.rad(math.random(10, 170))
			local s = shot((math.random() - 0.5) * 24, 1.2, math.cos(angle), math.sin(angle), {
				bounces = 40,
				speed = math.random(40, 140),
			})
			while s.alive do
				Ricochet.step(s, 1 / 60, field)
				stepsChecked += 1
				if s.alive then
					expect(s.x).toBeGreaterThanOrEqual(-Lane.halfWidth + s.radius - tolerance)
					expect(s.x).toBeLessThanOrEqual(Lane.halfWidth - s.radius + tolerance)
					expect(s.y).toBeLessThanOrEqual(Lane.length - s.radius + tolerance)
					for _, box in field do
						local dx = math.max(box.minX - s.x, 0, s.x - box.maxX)
						local dy = math.max(box.minY - s.y, 0, s.y - box.maxY)
						expect(math.sqrt(dx * dx + dy * dy)).toBeGreaterThanOrEqual(s.radius - tolerance)
					end
				end
			end
			expect(s.endReason).never().toBeNil()
		end
		expect(stepsChecked).toBeGreaterThan(1000)
	end)
end)

describe("ShotStats", function()
	it("starts from the config", function()
		local stats = ShotStats.compute({})
		expect(stats.damage).toBe(GameConfig.Shot.baseDamage)
		expect(stats.radius).toBe(GameConfig.Shot.radius)
		expect(stats.bounces).toBe(GameConfig.Shot.baseBounces)
		expect(stats.cooldownSeconds).toBe(GameConfig.Shot.cooldownSeconds)
		expect(stats.tint).toBe("Default")
		expect(stats.burn).toBeNil()
	end)

	it("stacks size, fire rate and bounces", function()
		local big = ShotStats.compute({ { id = "Bigshot", stacks = 1 } })
		expect(big.radius).toBeCloseTo(GameConfig.Shot.radius * 1.35, 1e-12)
		expect(big.damage).toBe(GameConfig.Shot.baseDamage + 1)

		local quick = ShotStats.compute({ { id = "Quickdraw", stacks = 2 } })
		expect(quick.cooldownSeconds).toBeCloseTo(GameConfig.Shot.cooldownSeconds * 0.64, 1e-12)

		local capped = ShotStats.compute({ { id = "Gatling", stacks = 1 }, { id = "Quickdraw", stacks = 2 } })
		expect(capped.cooldownSeconds).toBe(GameConfig.Shot.minCooldownSeconds)

		local resonance = ShotStats.compute({ { id = "Resonance", stacks = 1 }, { id = "Echo", stacks = 1 } })
		expect(resonance.bounces).toBe(GameConfig.Shot.baseBounces + 3)
		expect(ShotStats.hitDamage(resonance, 2)).toBeCloseTo(GameConfig.Shot.baseDamage * 1.3, 1e-12)
	end)

	it("applies one on-hit effect per kind, fused beating base in any order", function()
		local a = ShotStats.compute({ { id = "Inferno", stacks = 1 }, { id = "Ember", stacks = 1 } })
		local b = ShotStats.compute({ { id = "Ember", stacks = 1 }, { id = "Inferno", stacks = 1 } })
		expect(a.burn.damagePerSecond).toBe(4)
		expect(b.burn.damagePerSecond).toBe(4)
		expect(a.tint).toBe("Inferno")

		local twoEmbers = ShotStats.compute({ { id = "Ember", stacks = 2 } })
		expect(twoEmbers.burn.damagePerSecond).toBe(2)
		expect(twoEmbers.tint).toBe("Ember")

		local drill = ShotStats.compute({ { id = "Drill", stacks = 1 } })
		expect(drill.damage).toBeCloseTo(GameConfig.Shot.baseDamage * 0.9, 1e-12)
		expect(drill.pierce.pierceCount).toBe(1)
	end)

	it("rejects bad stack counts", function()
		expect(function()
			ShotStats.compute({ { id = "Ember", stacks = 0 } })
		end).toThrow()
		expect(function()
			ShotStats.compute({ { id = "Ember", stacks = 1.5 } })
		end).toThrow()
	end)
end)
