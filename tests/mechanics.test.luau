-- Room mechanics: sweeping reflectors, laser gates, breakable cover and amp pads. Built from
-- layout config like everything else, and driven by RoomMechanics on the server.
local ProjectileService = __require("ProjectileService")
local RoomBuilder = __require("RoomBuilder")
local RoomConfig = __require("RoomConfig")
local RoomGeometry = __require("RoomGeometry")
local RoomMechanics = __require("RoomMechanics")

local PLANE_Y = 3

local function mechanicsOf(layout, kind)
	local out = {}
	for _, mechanic in layout.Mechanics or {} do
		if mechanic.Kind == kind then
			table.insert(out, mechanic)
		end
	end
	return out
end

local function build(layoutId)
	local room, _, layout = RoomBuilder.Build(Instance.new("Folder"), layoutId)
	return RoomMechanics.new(room, layout), room, layout
end

-- A layout id that has at least one mechanic of `kind`.
local function layoutWith(kind)
	for layoutId, layout in RoomConfig.Layouts do
		if #mechanicsOf(layout, kind) > 0 then
			return layoutId, layout
		end
	end
	error("no layout uses " .. kind)
end

describe("mechanic placement", function()
	it("gives every Foundry and Abyss room a mechanic, and keeps the Ruins plain", function()
		for layoutId, layout in RoomConfig.Layouts do
			local count = #(layout.Mechanics or {})
			if layout.Zone == "Ruins" then
				expect(count).toBe(0)
			elseif count == 0 then
				error(layoutId .. " has no room mechanic")
			end
			for _, mechanic in layout.Mechanics or {} do
				expect(RoomMechanics.Kinds[mechanic.Kind]).toBe(true)
			end
		end
	end)

	it("uses every kind of mechanic somewhere", function()
		for kind in RoomMechanics.Kinds do
			layoutWith(kind)
		end
	end)

	it("counts breakable cover and sweepers as footprints, so spawns and markers avoid them", function()
		local layoutId, layout = layoutWith("Breakable")
		local names = {}
		for _, solid in RoomGeometry.Footprints(layout, RoomConfig) do
			names[solid.Name] = solid
		end
		expect(names.Breakable1).toBeTruthy()
		local sweeperLayout = select(2, layoutWith("Sweeper"))
		local sweeper = mechanicsOf(sweeperLayout, "Sweeper")[1]
		local found
		for _, solid in RoomGeometry.Footprints(sweeperLayout, RoomConfig) do
			if solid.Name == "Sweeper1" then
				found = solid
			end
		end
		-- The footprint covers the whole sweep, not just the resting pose.
		expect(found.Size.X).toBeGreaterThanOrEqual(sweeper.Length)
		expect(found.Size.Y).toBeGreaterThanOrEqual(sweeper.Length)
		expect(layoutId).toBeTruthy()
	end)

	it("keeps laser gates away from the spawn and off every enemy marker", function()
		for layoutId, layout in RoomConfig.Layouts do
			for index, gate in mechanicsOf(layout, "LaserGate") do
				local toSpawn = RoomMechanics.DistanceToSegment(Vector2.zero, gate.From, gate.To)
				if toSpawn < 12 then
					error(("%s gate %d is %.1f studs from the spawn"):format(layoutId, index, toSpawn))
				end
				for markerIndex, marker in layout.EnemySpawns do
					local distance = RoomMechanics.DistanceToSegment(marker, gate.From, gate.To)
					if distance < 7 then
						error(("%s gate %d crosses marker %d"):format(layoutId, index, markerIndex))
					end
				end
			end
		end
	end)
end)

describe("sweeping reflectors", function()
	it("swing about their resting heading and carry their trims with them", function()
		local mechanics, room, layout = build((layoutWith("Sweeper")))
		local spec = mechanicsOf(layout, "Sweeper")[1]
		local part = room:FindFirstChild("Sweeper1")
		local cap = room:FindFirstChild("Decor"):FindFirstChild("Sweeper1Cap")
		mechanics:Step(0, spec.Period / 4)
		local expected = RoomGeometry.LookVector(spec.Yaw + spec.Swing)
		expect(part.CFrame.LookVector.X).toBeCloseTo(expected.X)
		expect(part.CFrame.LookVector.Z).toBeCloseTo(expected.Z)
		expect(cap.CFrame.LookVector.X).toBeCloseTo(expected.X)
		expect(part.CFrame.Position.X).toBeCloseTo(spec.Offset.X)
		mechanics:Step(0, spec.Period * 3 / 4)
		expected = RoomGeometry.LookVector(spec.Yaw - spec.Swing)
		expect(part.CFrame.LookVector.Z).toBeCloseTo(expected.Z)
	end)

	it("reflect a shot off their current face", function()
		local world = __PhysicsWorld.new():Install()
		local spec = { Offset = Vector2.new(0, 0), Length = 14, Yaw = 45, Swing = 30, Period = 4 }
		local part = Instance.new("Part")
		part.Size = Vector3.new(spec.Length, 14, 2)
		local function poseAt(t)
			local yaw = RoomMechanics.SweeperYaw(spec, t)
			world:AddBox(part, Vector3.new(0, 7, 0), part.Size, yaw)
			return yaw
		end
		local params = RaycastParams.new()
		poseAt(0)
		local rest = world:Raycast(Vector3.new(-20, PLANE_Y, 0), Vector3.new(40, 0, 0), params)
		poseAt(1)
		local swung = world:Raycast(Vector3.new(-20, PLANE_Y, 0), Vector3.new(40, 0, 0), params)
		expect(rest).toBeTruthy()
		expect(swung).toBeTruthy()
		-- Different heading, different face normal.
		expect(math.abs(rest.Normal:Dot(swung.Normal))).toBeLessThan(0.99)
	end)
end)

describe("laser gates", function()
	it("warn, then burn only while on, and only inside the beam", function()
		local mechanics, _, layout = build((layoutWith("LaserGate")))
		local spec = mechanicsOf(layout, "LaserGate")[1]
		local middle = Vector2.new((spec.From.X + spec.To.X) / 2, (spec.From.Y + spec.To.Y) / 2)
		local inside = Vector3.new(middle.X, PLANE_Y, middle.Y)
		local outside = Vector3.new(middle.X + 30, PLANE_Y, middle.Y + 30)
		local phase = spec.Phase or 0

		local offAt = phase + 0.05
		local warnAt = phase + spec.OffTime - RoomConfig.Mechanics.GateWarnTime + 0.05
		local onAt = phase + spec.OffTime + 0.05

		mechanics:Step(0, offAt)
		expect(mechanics:GateState(1)).toBe("Off")
		expect(mechanics:HazardAt(inside, offAt)).toBe(0)
		mechanics:Step(0, warnAt)
		expect(mechanics:GateState(1)).toBe("Warn")
		expect(mechanics:HazardAt(inside, warnAt)).toBe(0)
		mechanics:Step(0, onAt)
		expect(mechanics:GateState(1)).toBe("On")
		expect(mechanics:HazardAt(inside, onAt)).toBe(RoomConfig.Mechanics.GateDamage)
		expect(mechanics:HazardAt(outside, onAt)).toBe(0)
	end)

	it("never blocks a shot", function()
		local _, room = build((layoutWith("LaserGate")))
		local beam = room:FindFirstChild("Gate1")
		expect(beam.CanQuery).toBe(false)
		expect(beam.CanCollide).toBe(false)
	end)
end)

describe("breakable cover", function()
	it("cracks at half health and falls away at zero, letting shots through", function()
		local mechanics, room, layout = build((layoutWith("Breakable")))
		local spec = mechanicsOf(layout, "Breakable")[1]
		local part = room:FindFirstChild("Breakable1")
		local world = __PhysicsWorld.new():Install()
		world:AddBox(part, part.Position, part.Size)
		local params = RaycastParams.new()
		local from = part.Position + Vector3.new(-spec.Size.X, PLANE_Y - part.Position.Y, 0)
		expect(world:Raycast(from, Vector3.new(spec.Size.X * 2, 0, 0), params)).toBeTruthy()

		local health = spec.Health or RoomConfig.Mechanics.BreakableHealth
		for hit = 1, health - 1 do
			expect(mechanics:HandleImpact(part)).toBe(hit >= health / 2 and "Cracked" or "Damaged")
		end
		expect(part:GetAttribute("Cracked")).toBe(true)
		expect(mechanics:HandleImpact(part)).toBe("Broken")
		expect(part.CanQuery).toBe(false)
		expect(part.CanCollide).toBe(false)
		expect(part.Transparency).toBe(1)
		expect(world:Raycast(from, Vector3.new(spec.Size.X * 2, 0, 0), params)).toBeNil()
		-- A broken piece takes no further hits, and ordinary geometry is not a mechanic.
		expect(mechanics:HandleImpact(part)).toBeNil()
		expect(mechanics:HandleImpact(room:FindFirstChild("WallNorth"))).toBeNil()
	end)
end)

describe("amp pads", function()
	it("add damage once to a shot that crosses them", function()
		local mechanics, _, layout = build((layoutWith("AmpPad")))
		local pad = mechanicsOf(layout, "AmpPad")[1]
		local entry = { damage = 1 }
		local before = Vector3.new(pad.Offset.X - pad.Size.X, PLANE_Y, pad.Offset.Y)
		local after = Vector3.new(pad.Offset.X + pad.Size.X, PLANE_Y, pad.Offset.Y)
		mechanics:ApplySegment(entry, before, after)
		expect(entry.damage).toBe(1 + RoomConfig.Mechanics.AmpBonus)
		mechanics:ApplySegment(entry, after, before)
		expect(entry.damage).toBe(1 + RoomConfig.Mechanics.AmpBonus)

		local miss = { damage = 1 }
		local far = Vector3.new(pad.Offset.X, PLANE_Y, pad.Offset.Y + 40)
		mechanics:ApplySegment(miss, far, far + Vector3.new(5, 0, 0))
		expect(miss.damage).toBe(1)
	end)

	it("are consulted by the projectile step along each frame's travel", function()
		local world = __PhysicsWorld.new():Install()
		local arena = Instance.new("Folder")
		world:AddBareRoom(60, 60, arena)
		local service = ProjectileService.new(arena, arena, PLANE_Y)
		local seen = 0
		service.SegmentHook = function(entry, from, to)
			seen += 1
			expect(entry.damage).toBeTruthy()
			expect((to - from).Magnitude).toBeGreaterThan(0)
		end
		Harness.setClock(0)
		service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(1, 0, 0), 1)
		local pool = arena:FindFirstChild("ProjectilePool")
		for _ = 1, 10 do
			__integrateParts(pool, 1 / 60)
			Harness.setClock(Harness.now() + 1 / 60)
			service:Step(1 / 60)
		end
		expect(seen).toBeGreaterThan(0)
	end)
end)
