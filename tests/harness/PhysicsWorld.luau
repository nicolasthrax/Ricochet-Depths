-- Box-accurate raycasting for the headless harness.
--
-- The earlier stub only modelled four infinite wall planes, which is why pillar and
-- moving-target cases could not be expressed. This models real axis-aligned boxes with the slab
-- method and reproduces three engine behaviours that matter to the ricochet code:
--
--   1. A ray whose origin is inside a box reports nothing. This is the exact quirk behind the
--      corner-leak bug, so the stub must have it or the regression test is meaningless.
--   2. Hits carry the face normal of the surface actually struck, not a per-object normal.
--   3. RaycastParams filtering (Include/Exclude by ancestry) and CanQuery are honoured.
--
-- Boxes may also be turned about the vertical axis (yaw), which is all the room geometry ever
-- uses: the ray is carried into the box's own frame, clipped there, and the struck face's
-- normal is turned back out. It is still a stub: no pitch or roll, no meshes, no continuous
-- collision between two moving bodies. Anything outside that list needs a real engine.

local PhysicsWorld = {}
PhysicsWorld.__index = PhysicsWorld

local EPSILON = 1e-9

function PhysicsWorld.new()
	return setmetatable({ _boxes = {}, _order = {} }, PhysicsWorld)
end

-- yawDegrees follows CFrame.Angles(0, yaw, 0); omitted means axis-aligned.
function PhysicsWorld:AddBox(instance, center, size, yawDegrees)
	if not self._boxes[instance] then
		table.insert(self._order, instance)
	end
	local yaw = math.rad(yawDegrees or 0)
	self._boxes[instance] = {
		instance = instance,
		center = center,
		half = size * 0.5,
		cos = math.cos(yaw),
		sin = math.sin(yaw),
		rotated = (yawDegrees or 0) % 360 ~= 0,
	}
	return instance
end

-- World vector to the box's own frame, and back. Local (x, z) lands at
-- (x cos + z sin, -x sin + z cos) in the world.
local function toBoxFrame(box, vector)
	return Vector3.new(vector.X * box.cos - vector.Z * box.sin, vector.Y, vector.X * box.sin + vector.Z * box.cos)
end

local function fromBoxFrame(box, vector)
	return Vector3.new(vector.X * box.cos + vector.Z * box.sin, vector.Y, -vector.X * box.sin + vector.Z * box.cos)
end

function PhysicsWorld:MoveBox(instance, center)
	local box = self._boxes[instance]
	if box then
		box.center = center
	end
end

function PhysicsWorld:RemoveBox(instance)
	if not self._boxes[instance] then
		return
	end
	self._boxes[instance] = nil
	for index, candidate in self._order do
		if candidate == instance then
			table.remove(self._order, index)
			break
		end
	end
end

function PhysicsWorld:Clear()
	table.clear(self._boxes)
	table.clear(self._order)
end

function PhysicsWorld:BoxCount()
	local count = 0
	for _ in self._boxes do
		count += 1
	end
	return count
end

local function isDescendantOf(instance, ancestor)
	local cursor = instance
	while cursor do
		if cursor == ancestor then
			return true
		end
		cursor = rawget(cursor, "Parent")
	end
	return false
end

local function passesFilter(instance, params)
	if rawget(instance, "CanQuery") == false then
		return false
	end
	if not params or not params.FilterDescendantsInstances or #params.FilterDescendantsInstances == 0 then
		return true
	end

	local matched = false
	for _, filterInstance in params.FilterDescendantsInstances do
		if isDescendantOf(instance, filterInstance) then
			matched = true
			break
		end
	end

	local filterType = params.FilterType
	local isExclude = filterType ~= nil and tostring(filterType):find("Exclude") ~= nil
	if isExclude then
		return not matched
	end
	return matched
end

-- Slab method, in the box's own frame. Returns entry distance, exit distance and the entry
-- face's axis and sign in that frame.
local function intersectBox(origin, direction, box)
	local tMin, tMax = -math.huge, math.huge
	local normalAxis, normalSign = nil, 0

	local center = Vector3.zero
	if box.rotated then
		origin = toBoxFrame(box, origin - box.center)
		direction = toBoxFrame(box, direction)
	else
		center = box.center
	end

	for _, axis in { "X", "Y", "Z" } do
		local originComponent = origin[axis]
		local directionComponent = direction[axis]
		local minimum = center[axis] - box.half[axis]
		local maximum = center[axis] + box.half[axis]

		if math.abs(directionComponent) < EPSILON then
			-- Parallel to this slab: a miss unless the origin already lies between its faces.
			if originComponent < minimum or originComponent > maximum then
				return nil
			end
		else
			local t1 = (minimum - originComponent) / directionComponent
			local t2 = (maximum - originComponent) / directionComponent
			local sign = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				sign = 1
			end
			if t1 > tMin then
				tMin = t1
				normalAxis = axis
				normalSign = sign
			end
			if t2 < tMax then
				tMax = t2
			end
			if tMin > tMax then
				return nil
			end
		end
	end

	return tMin, tMax, normalAxis, normalSign
end

local AXIS_VECTORS = {
	X = Vector3.new(1, 0, 0),
	Y = Vector3.new(0, 1, 0),
	Z = Vector3.new(0, 0, 1),
}

-- Signature matches workspace:Raycast(origin, direction, params); direction carries the length.
function PhysicsWorld:Raycast(origin, delta, params)
	local length = delta.Magnitude
	if length <= EPSILON then
		return nil
	end
	local direction = delta.Unit

	local bestDistance, bestBox, bestAxis, bestSign
	for _, instance in self._order do
		local box = self._boxes[instance]
		if box and passesFilter(instance, params) then
			local tMin, tMax, axis, sign = intersectBox(origin, direction, box)
			if tMin then
				-- Origin inside the box: the engine reports nothing here, so neither do we.
				local inside = tMin < 0 and tMax > 0
				if not inside and tMin >= 0 and tMin <= length then
					if not bestDistance or tMin < bestDistance then
						bestDistance, bestBox, bestAxis, bestSign = tMin, box, axis, sign
					end
				end
			end
		end
	end

	if not bestDistance then
		return nil
	end

	local normal = AXIS_VECTORS[bestAxis] * bestSign
	if bestBox.rotated then
		normal = fromBoxFrame(bestBox, normal)
	end
	return {
		Position = origin + direction * bestDistance,
		Normal = normal,
		Instance = bestBox.instance,
		Distance = bestDistance,
	}
end

-- Makes this world the one the stubbed workspace:Raycast consults.
function PhysicsWorld:Install()
	__raycastHandler = function(origin, delta, params)
		return self:Raycast(origin, delta, params)
	end
	return self
end

-- Builds every solid of a RoomConfig layout (walls, pillars, bevels and reflectors, from the
-- same RoomGeometry RoomBuilder uses) as real boxes, parented under `parent` so raycast filters
-- behave exactly as they do in the game.
function PhysicsWorld:AddRoomLayout(layout, roomConfig, parent)
	local interior = layout.InteriorSize
	local height = roomConfig.WallHeight
	local wallY = roomConfig.FloorY + height / 2

	for _, solid in __require("RoomGeometry").Solids(layout, roomConfig) do
		local part = Instance.new("Part")
		part.Name = solid.Name
		part.Size = Vector3.new(solid.Size.X, height, solid.Size.Y)
		part.Position = Vector3.new(solid.Center.X, wallY, solid.Center.Y)
		part.Parent = parent
		self:AddBox(part, part.Position, part.Size, solid.Yaw)
	end

	return {
		halfX = interior.X / 2,
		halfZ = interior.Y / 2,
	}
end

__PhysicsWorld = PhysicsWorld

-- A plain walled rectangle with no pillars, for tests that need a clear firing lane.
function PhysicsWorld:AddBareRoom(halfX, halfZ, parent, floorY, height, thickness)
	floorY, height, thickness = floorY or 0, height or 14, thickness or 2
	local wallY = floorY + height / 2

	local function addPart(name, size, position)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Position = position
		part.Parent = parent
		self:AddBox(part, position, size)
	end

	local spanX = halfX * 2 + thickness * 2
	local spanZ = halfZ * 2 + thickness * 2
	addPart("WallNorth", Vector3.new(spanX, height, thickness), Vector3.new(0, wallY, halfZ + thickness / 2))
	addPart("WallSouth", Vector3.new(spanX, height, thickness), Vector3.new(0, wallY, -halfZ - thickness / 2))
	addPart("WallEast", Vector3.new(thickness, height, spanZ), Vector3.new(halfX + thickness / 2, wallY, 0))
	addPart("WallWest", Vector3.new(thickness, height, spanZ), Vector3.new(-halfX - thickness / 2, wallY, 0))

	return { halfX = halfX, halfZ = halfZ }
end

-- Integrates unanchored pooled parts exactly as the engine would between Heartbeats:
-- physics moves the part, then game logic runs.
function __integrateParts(folder, deltaTime)
	for _, part in folder:GetChildren() do
		if part.Anchored == false then
			part.Position = part.Position + part.AssemblyLinearVelocity * deltaTime
		end
	end
end

-- r = d - 2(d.n)n, the same law ProjectileService applies.
function __reflect(direction, normal)
	return direction - 2 * direction:Dot(normal) * normal
end

function __flatUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return flat.Magnitude > 0 and flat.Unit or flat
end

function __angleBetween(a, b)
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end
