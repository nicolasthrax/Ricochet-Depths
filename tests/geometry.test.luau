-- Room geometry integrity: angled bank-shot pieces, their placement, how RoomBuilder turns them
-- into parts, and that the collision model reflects off them correctly.
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")
local ProjectileService = __require("ProjectileService")
local RoomBuilder = __require("RoomBuilder")
local RoomConfig = __require("RoomConfig")
local RoomGeometry = __require("RoomGeometry")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")

local PLANE_Y = 3
local DT = 1 / 60
local SPAWN_JITTER = 3

local function solidsOfKind(layout, kind)
	local out = {}
	for _, solid in RoomGeometry.Solids(layout, RoomConfig) do
		if solid.Kind == kind then
			table.insert(out, solid)
		end
	end
	return out
end

local function largestEnemyHalf()
	local largest = 0
	for _, archetype in EnemyConfig.Archetypes do
		largest = math.max(largest, archetype.Size.X / 2, archetype.Size.Z / 2)
	end
	return largest
end

describe("RoomGeometry solids", function()
	it("describes walls, pillars, corner bevels and reflectors for every layout", function()
		for layoutId, layout in RoomConfig.Layouts do
			local walls = solidsOfKind(layout, "Wall")
			local obstacles = solidsOfKind(layout, "Obstacle")
			expect(#walls).toBe(4)
			expect(#obstacles).toBe(#layout.Obstacles)
			-- Every shipped room has all four corners bevelled and at least one diagonal reflector.
			expect(#solidsOfKind(layout, "Bevel")).toBe(4)
			expect(#solidsOfKind(layout, "Reflector")).toBeGreaterThan(0)
			expect(#layoutId).toBeGreaterThan(0)
		end
	end)

	it("sets every bevel and reflector at 45 degrees", function()
		for _, layout in RoomConfig.Layouts do
			for _, kind in { "Bevel", "Reflector" } do
				for _, solid in solidsOfKind(layout, kind) do
					expect(math.abs(solid.Yaw) % 90).toBe(45)
				end
			end
		end
	end)

	it("keeps pillars and reflectors fully inside the room", function()
		for _, layout in RoomConfig.Layouts do
			local halfX, halfZ = layout.InteriorSize.X / 2, layout.InteriorSize.Y / 2
			for _, solid in RoomGeometry.Footprints(layout, RoomConfig) do
				if solid.Kind ~= "Bevel" then
					for _, corner in RoomGeometry.Corners(solid) do
						expect(math.abs(corner.X)).toBeLessThanOrEqual(halfX + 1e-6)
						expect(math.abs(corner.Y)).toBeLessThanOrEqual(halfZ + 1e-6)
					end
				end
			end
		end
	end)

	it("cuts each corner with a face that meets both walls and stays inside the wall shell", function()
		for _, layout in RoomConfig.Layouts do
			local halfX, halfZ = layout.InteriorSize.X / 2, layout.InteriorSize.Y / 2
			local shell = RoomConfig.WallThickness
			for _, bevel in solidsOfKind(layout, "Bevel") do
				-- Nothing may poke out past the outer face of the walls.
				for _, corner in RoomGeometry.Corners(bevel) do
					expect(math.abs(corner.X)).toBeLessThanOrEqual(halfX + shell + 1e-6)
					expect(math.abs(corner.Y)).toBeLessThanOrEqual(halfZ + shell + 1e-6)
				end
				-- The exposed face touches both walls, so nothing can slip behind it.
				local a, b = RoomGeometry.FaceEndpoints(bevel)
				local touchesX = math.abs(math.abs(a.X) - halfX) < 1e-6 or math.abs(math.abs(b.X) - halfX) < 1e-6
				local touchesZ = math.abs(math.abs(a.Y) - halfZ) < 1e-6 or math.abs(math.abs(b.Y) - halfZ) < 1e-6
				expect(touchesX).toBe(true)
				expect(touchesZ).toBe(true)
			end
		end
	end)

	it("keeps the player spawn pad clear of every piece of cover", function()
		for _, layout in RoomConfig.Layouts do
			local padClearance = RoomConfig.SpawnPadSize.X / 2 + 1
			for _, solid in RoomGeometry.Footprints(layout, RoomConfig) do
				expect(RoomGeometry.Clearance(solid, 0, 0)).toBeGreaterThanOrEqual(padClearance)
			end
		end
	end)

	it("never places an enemy spawn marker inside or against cover, allowing for jitter", function()
		local margin = SPAWN_JITTER + largestEnemyHalf()
		for layoutId, layout in RoomConfig.Layouts do
			for index, marker in layout.EnemySpawns do
				for _, solid in RoomGeometry.Footprints(layout, RoomConfig) do
					local clearance = RoomGeometry.Clearance(solid, marker.X, marker.Y)
					if clearance < margin then
						error(("%s marker %d is %.1f studs from %s (needs %.1f)"):format(
							layoutId, index, clearance, solid.Name, margin
						))
					end
				end
			end
		end
	end)

	it("reports segments blocked by rotated cover and clear otherwise", function()
		local reflector = { Name = "R", Kind = "Reflector", Center = Vector2.new(0, 0), Size = Vector2.new(10, 2), Yaw = 45 }
		expect(RoomGeometry.SegmentBlocked({ reflector }, Vector2.new(-10, 0), Vector2.new(10, 0))).toBe(true)
		expect(RoomGeometry.SegmentBlocked({ reflector }, Vector2.new(-10, 20), Vector2.new(10, 20))).toBe(false)
		-- The slab runs along z = -x. A segment parallel to it, offset past its thickness: clear.
		expect(RoomGeometry.SegmentBlocked({ reflector }, Vector2.new(-6, 12), Vector2.new(6, 0))).toBe(false)
		-- Crossing it at right angles: blocked.
		expect(RoomGeometry.SegmentBlocked({ reflector }, Vector2.new(-6, -6), Vector2.new(6, 6))).toBe(true)
	end)
end)

describe("RoomBuilder angled geometry", function()
	it("builds a part for every solid with the solid's size, position and heading", function()
		for layoutId, layout in RoomConfig.Layouts do
			local room = RoomBuilder.Build(Instance.new("Folder"), layoutId)
			for _, solid in RoomGeometry.Solids(layout, RoomConfig) do
				local part = room:FindFirstChild(solid.Name)
				if not part then
					error(("%s: no part for %s"):format(layoutId, solid.Name))
				end
				expect(part.Size.X).toBeCloseTo(solid.Size.X)
				expect(part.Size.Z).toBeCloseTo(solid.Size.Y)
				expect(part.Size.Y).toBeCloseTo(RoomConfig.WallHeight)
				expect(part.CFrame.Position.X).toBeCloseTo(solid.Center.X)
				expect(part.CFrame.Position.Z).toBeCloseTo(solid.Center.Y)
				-- A yaw of theta turns the part's -Z look vector to (-sin theta, 0, -cos theta).
				local yaw = math.rad(solid.Yaw)
				expect(part.CFrame.LookVector.X).toBeCloseTo(-math.sin(yaw))
				expect(part.CFrame.LookVector.Z).toBeCloseTo(-math.cos(yaw))
				expect(part.Anchored).toBe(true)
				expect(part.CanCollide).toBe(true)
				expect(part.CanQuery).never().toBe(false)
			end
		end
	end)

	it("gives bank-shot pieces glowing hazard trim and the floor a two-tone pattern", function()
		local room = RoomBuilder.Build(Instance.new("Folder"), "Crossing")
		local decor = room:FindFirstChild("Decor")
		local hazard, tiles = 0, {}
		for _, part in decor:GetChildren() do
			if part.Name:find("^Reflector%d+Cap") or part.Name:find("^Bevel%d+Cap") then
				hazard += 1
				expect(part.Material).toBe(Enum.Material.Neon)
				expect(part.Color).toBe(RoomConfig.Decor.HazardColor)
			end
			if part.Name:find("^Tile") then
				tiles[part.Color] = true
			end
		end
		expect(hazard).toBe(#solidsOfKind(RoomConfig.Layouts.Crossing, "Reflector") + 4)
		local tones = 0
		for _ in tiles do
			tones += 1
		end
		expect(tones).toBe(2)
	end)
end)

describe("angled geometry in the collision model", function()
	it("turns a shot 90 degrees off a 45 degree reflector", function()
		local world = __PhysicsWorld.new()
		local arena = Instance.new("Folder")
		world:AddBareRoom(60, 60, arena)
		local reflector = Instance.new("Part")
		reflector.Parent = arena
		world:AddBox(reflector, Vector3.new(0, 7, 0), Vector3.new(16, 14, 2), 45)
		world:Install()

		local service = ProjectileService.new(arena, arena, PLANE_Y)
		local folder = arena:FindFirstChild("ProjectilePool")
		local contacts = {}
		service.OnImpact = function(result, entry)
			table.insert(contacts, { normal = result.Normal, incoming = entry.direction, instance = result.Instance })
			return false
		end
		Harness.setClock(0)
		service:Fire(nil, Vector3.new(-30, PLANE_Y, 0), Vector3.new(1, 0, 0), 1)
		for _ = 1, 30 do
			__integrateParts(folder, DT)
			Harness.setClock(Harness.now() + DT)
			service:Step(DT)
		end

		expect(#contacts).toBeGreaterThan(0)
		expect(contacts[1].instance).toBe(reflector)
		local outgoing = __reflect(contacts[1].incoming, contacts[1].normal)
		expect(math.abs(outgoing.X)).toBeCloseTo(0)
		expect(math.abs(outgoing.Z)).toBeCloseTo(1)
		world:Clear()
		__raycastHandler = nil
	end)

	it("keeps enemies out of the dead corner behind each bevel", function()
		local layout = RoomConfig.GetLayout("Atrium")
		local room, bounds = RoomBuilder.Build(Instance.new("Folder"), "Atrium")
		expect(room).toBeTruthy()
		local enemies = EnemyService.new(Instance.new("Folder"), PLANE_Y, 3)
		enemies:SetBounds(bounds.center, bounds.half, bounds.diagonal)
		local clamped = enemies:_clampToBounds(Vector3.new(layout.InteriorSize.X, PLANE_Y, layout.InteriorSize.Y))
		for _, bevel in solidsOfKind(layout, "Bevel") do
			expect(RoomGeometry.Clearance(bevel, clamped.X, clamped.Z)).toBeGreaterThan(0)
		end
	end)

	it("spawns players clear of rotated cover", function()
		local arena = Instance.new("Folder")
		local rooms = RoomService.new(arena, EnemyService.new(arena, PLANE_Y, 4), PLANE_Y, Random.new(4))
		for _, definition in RunConfig.Rooms do
			rooms:Load(definition, 0)
			local point = rooms:GetSpawnPoint()
			local layout = RoomConfig.GetLayout(definition.Layout)
			for _, solid in RoomGeometry.Footprints(layout, RoomConfig) do
				expect(RoomGeometry.Clearance(solid, point.X, point.Z)).toBeGreaterThan(0)
			end
		end
	end)
end)

describe("room 3 flanking sightlines", function()
	local crossing = RunConfig.Rooms[3]
	local layout = RoomConfig.GetLayout(crossing.Layout)

	-- The markers the room's Bulwarks actually take, from the same assignment RoomService uses.
	local function bulwarkMarkers()
		local markers = {}
		for _, assignment in RoomService.AssignSpawns(crossing, layout) do
			if assignment.archetype == "Bulwark" then
				table.insert(markers, layout.EnemySpawns[assignment.marker])
			end
		end
		return markers
	end

	it("pins every spawn group to markers the layout actually has", function()
		for _, definition in RunConfig.Rooms do
			local roomLayout = RoomConfig.GetLayout(definition.Layout)
			for _, group in definition.Spawns do
				for _, marker in group.Markers or {} do
					expect(roomLayout.EnemySpawns[marker]).toBeTruthy()
				end
			end
		end
	end)

	-- The audit: Bulwark lunges were ~100% of the damage taken here, and two at once was the
	-- wall. One remains, so the room still teaches the shield.
	it("fields a single Bulwark, still backed by Chasers", function()
		local chasers, bulwarks = 0, 0
		for _, group in crossing.Spawns do
			if group.Archetype == "Chaser" then
				chasers += group.Count
			elseif group.Archetype == "Bulwark" then
				bulwarks += group.Count
			end
		end
		expect(bulwarks).toBe(1)
		expect(chasers).toBeGreaterThan(0)
	end)

	it("leaves most approach angles around every bulwark open", function()
		local footprints = RoomGeometry.Footprints(layout, RoomConfig)
		local halfX, halfZ = layout.InteriorSize.X / 2 - 4, layout.InteriorSize.Y / 2 - 4
		local radius, samples = 16, 16
		for _, marker in bulwarkMarkers() do
			local open = 0
			for step = 0, samples - 1 do
				local angle = step * 2 * math.pi / samples
				local point = Vector2.new(marker.X + math.cos(angle) * radius, marker.Y + math.sin(angle) * radius)
				local inside = math.abs(point.X) <= halfX and math.abs(point.Y) <= halfZ
				if inside and not RoomGeometry.SegmentBlocked(footprints, point, marker) then
					open += 1
				end
			end
			expect(open / samples).toBeGreaterThanOrEqual(0.5)
		end
	end)

	it("posts the Bulwark well away from the spawn, leaving time to find its flank", function()
		for _, marker in bulwarkMarkers() do
			expect(marker.Magnitude).toBeGreaterThan(40)
		end
	end)

	it("does not box the player in at the spawn point", function()
		local footprints = RoomGeometry.Footprints(layout, RoomConfig)
		local open = 0
		for step = 0, 7 do
			local angle = step * math.pi / 4
			local target = Vector2.new(math.cos(angle) * 24, math.sin(angle) * 24)
			if not RoomGeometry.SegmentBlocked(footprints, Vector2.new(0, 0), target) then
				open += 1
			end
		end
		expect(open).toBeGreaterThanOrEqual(6)
	end)
end)
