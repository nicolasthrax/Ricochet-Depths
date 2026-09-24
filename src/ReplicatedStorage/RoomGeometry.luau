-- Pure room geometry: turns a RoomConfig layout into a list of solids that RoomBuilder builds,
-- RoomService searches for clear ground, and the headless collision model raycasts against.
-- One description, three consumers, so the room a test bounces shots around is the room a
-- player sees.
--
-- A solid is { Name, Kind, Center = Vector2 (XZ), Size = Vector2 (local X length, local Z
-- depth), Yaw = degrees about +Y }. Yaw follows Roblox's CFrame.Angles(0, yaw, 0): a local
-- point (x, z) lands at (x cos + z sin, -x sin + z cos) in the world.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))

local RoomGeometry = {}

local SQRT_HALF = math.sqrt(0.5)

local function toWorld(solid, x, z)
	local yaw = math.rad(solid.Yaw)
	local cosine, sine = math.cos(yaw), math.sin(yaw)
	return Vector2.new(solid.Center.X + x * cosine + z * sine, solid.Center.Y - x * sine + z * cosine)
end

local function toLocal(solid, x, z)
	local yaw = math.rad(solid.Yaw)
	local cosine, sine = math.cos(yaw), math.sin(yaw)
	local dx, dz = x - solid.Center.X, z - solid.Center.Y
	return dx * cosine - dz * sine, dx * sine + dz * cosine
end

-- The -Z look vector a part needs for CFrame.lookAt to give it this yaw.
function RoomGeometry.LookVector(yawDegrees)
	local yaw = math.rad(yawDegrees)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Cuts the corner at signs (sx, sz) with a slab whose exposed face runs from one wall to the
-- other, `leg` studs from the corner along each. The slab's back sits inside the wall shell.
local function bevelFor(name, leg, depth, halfX, halfZ, sx, sz)
	local first = Vector2.new(sx * (halfX - leg), sz * halfZ)
	local second = Vector2.new(sx * halfX, sz * (halfZ - leg))
	local towardCorner = Vector2.new(sx, sz) * SQRT_HALF
	local midpoint = (first + second) * 0.5
	return {
		Name = name,
		Kind = "Bevel",
		Center = midpoint + towardCorner * (depth / 2),
		Size = Vector2.new(leg / SQRT_HALF, depth),
		-- Local X runs along the face, from `first` towards `second`.
		Yaw = math.deg(math.atan2(sz, sx)),
		Face = { first, second },
	}
end

-- Every solid in the room: the four walls, then pillars, corner bevels and reflectors.
function RoomGeometry.Solids(layout, roomConfig)
	roomConfig = roomConfig or RoomConfig
	local interior = layout.InteriorSize
	local thickness = roomConfig.WallThickness
	local outerX = interior.X + thickness * 2
	local outerZ = interior.Y + thickness * 2
	local wallX = interior.X / 2 + thickness / 2
	local wallZ = interior.Y / 2 + thickness / 2

	local solids = {
		{ Name = "WallNorth", Kind = "Wall", Center = Vector2.new(0, wallZ), Size = Vector2.new(outerX, thickness), Yaw = 0 },
		{ Name = "WallSouth", Kind = "Wall", Center = Vector2.new(0, -wallZ), Size = Vector2.new(outerX, thickness), Yaw = 0 },
		{ Name = "WallEast", Kind = "Wall", Center = Vector2.new(wallX, 0), Size = Vector2.new(thickness, outerZ), Yaw = 0 },
		{ Name = "WallWest", Kind = "Wall", Center = Vector2.new(-wallX, 0), Size = Vector2.new(thickness, outerZ), Yaw = 0 },
	}

	for index, obstacle in layout.Obstacles or {} do
		table.insert(solids, {
			Name = "Obstacle" .. index,
			Kind = "Obstacle",
			Center = obstacle.Offset,
			Size = obstacle.Size,
			Yaw = obstacle.Yaw or 0,
		})
	end

	local leg = layout.CornerBevel
	if leg and leg > 0 then
		local halfX, halfZ = interior.X / 2, interior.Y / 2
		local depth = roomConfig.BevelDepth
		local corners = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
		for index, signs in corners do
			table.insert(solids, bevelFor("Bevel" .. index, leg, depth, halfX, halfZ, signs[1], signs[2]))
		end
	end

	for index, reflector in layout.Reflectors or {} do
		table.insert(solids, {
			Name = "Reflector" .. index,
			Kind = "Reflector",
			Center = reflector.Offset,
			Size = Vector2.new(reflector.Length, reflector.Thickness or roomConfig.ReflectorThickness),
			Yaw = reflector.Yaw,
		})
	end

	-- Mechanics that block shots are solids too: breakable cover, explosive barrels, and
	-- sweeping reflectors in their resting pose. Gates, pads and portals are not; they never
	-- stop a shot.
	local counts = {}
	for _, mechanic in layout.Mechanics or {} do
		if mechanic.Kind == "Breakable" or mechanic.Kind == "Sweeper" or mechanic.Kind == "Barrel" then
			counts[mechanic.Kind] = (counts[mechanic.Kind] or 0) + 1
			local sweeper = mechanic.Kind == "Sweeper"
			table.insert(solids, {
				Name = mechanic.Kind .. counts[mechanic.Kind],
				Kind = mechanic.Kind,
				Center = mechanic.Offset,
				Size = if sweeper
					then Vector2.new(mechanic.Length, roomConfig.ReflectorThickness)
					else mechanic.Size,
				Yaw = mechanic.Yaw or 0,
			})
		end
	end

	return solids
end

-- Everything standing inside the room: the solids that are not walls. A sweeper counts as the
-- square its swing can reach, so nothing is placed where it will pass.
function RoomGeometry.Footprints(layout, roomConfig)
	local out = {}
	for _, solid in RoomGeometry.Solids(layout, roomConfig) do
		if solid.Kind == "Sweeper" then
			local reach = solid.Size.X
			table.insert(out, { Name = solid.Name, Kind = solid.Kind, Center = solid.Center, Size = Vector2.new(reach, reach), Yaw = 0 })
		elseif solid.Kind ~= "Wall" then
			table.insert(out, solid)
		end
	end
	return out
end

-- A copy of `solids` moved by `offset` (Vector2, XZ): a room's solids in its arena slot.
function RoomGeometry.Translate(solids, offset)
	if offset.X == 0 and offset.Y == 0 then
		return solids
	end
	local out = table.create(#solids)
	for index, solid in solids do
		local moved = table.clone(solid)
		moved.Center = Vector2.new(solid.Center.X + offset.X, solid.Center.Y + offset.Y)
		out[index] = moved
	end
	return out
end

function RoomGeometry.Corners(solid)
	local halfX, halfZ = solid.Size.X / 2, solid.Size.Y / 2
	return {
		toWorld(solid, -halfX, -halfZ),
		toWorld(solid, halfX, -halfZ),
		toWorld(solid, halfX, halfZ),
		toWorld(solid, -halfX, halfZ),
	}
end

-- A bevel's exposed face, wall to wall.
function RoomGeometry.FaceEndpoints(solid)
	if solid.Face then
		return solid.Face[1], solid.Face[2]
	end
	local corners = RoomGeometry.Corners(solid)
	return corners[1], corners[2]
end

-- How far (x, z) sits outside the solid, measured in its own frame. Negative means inside, so
-- larger is always better, and a fully covered room still has a least-bad answer.
function RoomGeometry.Clearance(solid, x, z)
	local localX, localZ = toLocal(solid, x, z)
	return math.max(math.abs(localX) - solid.Size.X / 2, math.abs(localZ) - solid.Size.Y / 2)
end

-- Whether the segment from a to b (Vector2, XZ) passes through any of the solids.
function RoomGeometry.SegmentBlocked(solids, a, b)
	for _, solid in solids do
		local ax, az = toLocal(solid, a.X, a.Y)
		local bx, bz = toLocal(solid, b.X, b.Y)
		local halfX, halfZ = solid.Size.X / 2, solid.Size.Y / 2

		-- Slab clipping of the segment against the solid's own axis-aligned box.
		local enter, exit = 0, 1
		local blocked = true
		for _, axis in { { ax, bx - ax, halfX }, { az, bz - az, halfZ } } do
			local origin, delta, half = axis[1], axis[2], axis[3]
			if math.abs(delta) < 1e-9 then
				if math.abs(origin) >= half then
					blocked = false
					break
				end
			else
				local t1, t2 = (-half - origin) / delta, (half - origin) / delta
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				enter, exit = math.max(enter, t1), math.min(exit, t2)
				if enter >= exit then
					blocked = false
					break
				end
			end
		end
		if blocked then
			return true
		end
	end
	return false
end

-- The largest |x| + |z| an enemy centre may reach, keeping it in front of every corner bevel.
-- nil when the layout has no bevels.
function RoomGeometry.DiagonalLimit(layout, roomConfig)
	roomConfig = roomConfig or RoomConfig
	local leg = layout.CornerBevel
	if not leg or leg <= 0 then
		return nil
	end
	local interior = layout.InteriorSize
	return interior.X / 2 + interior.Y / 2 - leg - roomConfig.BevelEnemyClearance
end

return RoomGeometry
