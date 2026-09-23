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
local AimConfig = __require("AimConfig")

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

describe("every shielded enemy can be flanked", function()
	-- Rooms fielding shielded enemies (a Shield in EnemyConfig): their posts must leave most
	-- approach angles open and sit well away from the spawn, so a flanking ricochet exists.
	local function shieldedPosts(definition, layout)
		local markers = {}
		for _, assignment in RoomService.AssignSpawns(definition, layout) do
			local archetype = EnemyConfig.Get(assignment.archetype)
			if archetype and archetype.Shield and not archetype.IsElite then
				table.insert(markers, layout.EnemySpawns[assignment.marker])
			end
		end
		return markers
	end

	it("leaves at least half the approach angles open around every post", function()
		for _, definition in RunConfig.Rooms do
			local layout = RoomConfig.GetLayout(definition.Layout)
			local footprints = RoomGeometry.Footprints(layout, RoomConfig)
			local halfX, halfZ = layout.InteriorSize.X / 2 - 4, layout.InteriorSize.Y / 2 - 4
			for _, marker in shieldedPosts(definition, layout) do
				local open = 0
				for step = 0, 15 do
					local angle = step * 2 * math.pi / 16
					local point = Vector2.new(marker.X + math.cos(angle) * 16, marker.Y + math.sin(angle) * 16)
					local inside = math.abs(point.X) <= halfX and math.abs(point.Y) <= halfZ
					if inside and not RoomGeometry.SegmentBlocked(footprints, point, marker) then
						open += 1
					end
				end
				if open < 8 then
					error(("%s: shielded post (%d, %d) has only %d/16 open approaches"):format(
						definition.Id, marker.X, marker.Y, open))
				end
			end
		end
	end)

	it("posts shielded enemies at least 36 studs from the spawn", function()
		for _, definition in RunConfig.Rooms do
			local layout = RoomConfig.GetLayout(definition.Layout)
			for _, marker in shieldedPosts(definition, layout) do
				expect(marker.Magnitude).toBeGreaterThan(36)
			end
		end
	end)
end)

describe("room 3 flanking sightlines", function()
	local crossing = RunConfig.GetRoomById("Crossing")
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

-- Flicker guard. Two visible faces at (almost) the same height over the same floor area
-- z-fight in the engine: at the tactical camera's 60-100 stud range they shimmer as the
-- camera follows the player. Only top faces matter; everything is seen from above.
local Z_FIGHT_GAP = 0.05

local function footprint(part)
	local cframe = part.CFrame
	local right, up, look = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local size = part.Size
	local function extent(axis)
		return math.abs(right[axis]) * size.X / 2 + math.abs(up[axis]) * size.Y / 2 + math.abs(look[axis]) * size.Z / 2
	end
	local position = part.Position
	local hx, hy, hz = extent("X"), extent("Y"), extent("Z")
	return {
		minX = position.X - hx, maxX = position.X + hx,
		minZ = position.Z - hz, maxZ = position.Z + hz,
		top = position.Y + hy,
		rotated = math.abs(look.X) > 1e-3 and math.abs(look.Z) > 1e-3,
	}
end

local function overlapArea(a, b)
	local x = math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX)
	local z = math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ)
	return math.max(x, 0) * math.max(z, 0)
end

local function visibleParts(root)
	local out = {}
	local names = {}
	for _, part in root:GetDescendants() do
		names[part.Name] = true
	end
	for _, part in root:GetDescendants() do
		-- A solid's top face is hidden under its neon cap, which is what is actually seen.
		local capped = names[part.Name .. "Cap"] == true
		if part:IsA("BasePart") and part.Transparency < 1 and not capped then
			table.insert(out, { part = part, box = footprint(part) })
		end
	end
	return out
end

describe("floor layers never z-fight", function()
	it("keeps every pair of overlapping visible top faces apart in every layout", function()
		for layoutId in RoomConfig.Layouts do
			local parts = visibleParts(RoomBuilder.Build(Instance.new("Folder"), layoutId))
			for i = 1, #parts do
				for j = i + 1, #parts do
					local a, b = parts[i], parts[j]
					-- Rotated boxes are bounded loosely; a real overlap needs some area.
					local minArea = (a.box.rotated or b.box.rotated) and 1 or 0.01
					-- Coincident faces of the same colour and material render identically either way.
					local lookAlike = a.part.Color == b.part.Color and a.part.Material == b.part.Material
					if not lookAlike and overlapArea(a.box, b.box) > minArea and math.abs(a.box.top - b.box.top) < Z_FIGHT_GAP then
						error(("%s: %s and %s share a top face at y=%.3f"):format(
							layoutId, a.part.Name, b.part.Name, a.box.top))
					end
				end
			end
		end
	end)

	it("floats the aim ground cues clear of every floor layer and the spawn pad", function()
		local cueBottom = AimConfig.GroundCueHeight - AimConfig.GroundCueThickness / 2
		for layoutId in RoomConfig.Layouts do
			local room = RoomBuilder.Build(Instance.new("Folder"), layoutId)
			for _, entry in visibleParts(room) do
				local top = entry.box.top
				-- Floor-level decor (tiles, grid, border, foot trims, the spawn pad) sits below.
				-- Dressing is left out: it stays outside the play space (see RoomDressing).
				if top < 1 and entry.part.Parent.Name ~= "Dressing" then
					expect(cueBottom - top).toBeGreaterThanOrEqual(Z_FIGHT_GAP)
				end
			end
		end
	end)

	it("builds the spawn pad as a low plinth with a glowing ring that casts no shadow", function()
		local room = RoomBuilder.Build(Instance.new("Folder"), "Atrium")
		local pad = room:FindFirstChild("PlayerSpawn")
		expect(pad.Size.Y).toBeLessThan(0.6)
		expect(pad.CastShadow).toBe(false)
		local rings = 0
		for _, part in room:FindFirstChild("Decor"):GetChildren() do
			if part.Name:find("^SpawnRing") then
				rings += 1
				expect(part.Material).toBe(Enum.Material.Neon)
			end
		end
		expect(rings).toBe(4)
	end)
end)

describe("rooms built in an arena slot away from the origin", function()
	local offset = Vector3.new(500, 0, 0)

	local function partsByPath(root)
		local out = {}
		for _, part in root:GetDescendants() do
			if part:IsA("BasePart") then
				out[part.Parent.Name .. "/" .. part.Name] = part
			end
		end
		return out
	end

	it("moves every part by the slot's origin and keeps its heading", function()
		for _, layoutId in { "Crossing", "Hollow", "Forgeworks" } do
			local home = partsByPath(RoomBuilder.Build(Instance.new("Folder"), layoutId))
			local away, bounds = RoomBuilder.Build(Instance.new("Folder"), layoutId, offset)
			for path, part in partsByPath(away) do
				local original = home[path]
				expect((part.Position - original.Position - offset).Magnitude).toBeCloseTo(0)
				expect(part.CFrame.LookVector:Dot(original.CFrame.LookVector)).toBeCloseTo(1)
			end
			expect(bounds.center.X).toBe(offset.X)
		end
	end)

	it("spawns players and enemies, and places hazards and cover, around the slot's origin", function()
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 5)
		local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(5), offset)
		local current = rooms:Load(RunConfig.GetRoomById("Conveyor"), 0)
		local point = rooms:GetSpawnPoint()
		expect(math.abs(point.X - offset.X)).toBeLessThan(20)
		for _, enemy in enemies:GetEnemies() do
			expect(math.abs(enemy.position.X - offset.X)).toBeLessThan(80)
		end
		-- The first gate burns at its offset position while on, not at the world origin.
		local gate = RoomConfig.GetLayout("Conveyor").Mechanics[1]
		local onAt = (gate.Phase or 0) + gate.OffTime + 0.1
		local middle = Vector3.new((gate.From.X + gate.To.X) / 2, PLANE_Y, gate.From.Y)
		expect(current.mechanics:HazardAt(middle + offset, onAt)).toBeGreaterThan(0)
		expect(current.mechanics:HazardAt(middle, onAt)).toBe(0)
		-- Orbs meet the cover where it actually stands.
		for _, solid in enemies:GetObstacles() do
			expect(math.abs(solid.Center.X - offset.X)).toBeLessThan(80)
		end
	end)
end)
