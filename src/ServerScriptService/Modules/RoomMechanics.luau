-- Drives a room's mechanics (layout.Mechanics), on the parts RoomBuilder made for them:
--   Sweeper    a reflector that swings about its resting heading; shots bounce off its live pose
--   LaserGate  a beam on a cycle (off, warning, on); it burns players inside while on
--   Breakable  cover with health; shots damage it, and at zero it is gone
--   AmpPad     a floor strip; a shot crossing it deals AmpBonus more damage from then on
--   BoostPad   a floor strip; a shot crossing it speeds up and gains a bounce
--   Portal     paired floor discs; a shot entering one leaves the other on the same heading
--   Barrel     a low explosive prop; one shot sets it off, and it sets off its neighbours
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RoomGeometry = require(ReplicatedStorage:WaitForChild("RoomGeometry"))

local RoomMechanics = {}
RoomMechanics.__index = RoomMechanics

RoomMechanics.Kinds = {
	Sweeper = true,
	LaserGate = true,
	Breakable = true,
	AmpPad = true,
	BoostPad = true,
	Portal = true,
	Barrel = true,
}

local config = RoomConfig.Mechanics

-- Heading of a sweeper at time t: a sine swing of ±Swing degrees about its resting Yaw.
function RoomMechanics.SweeperYaw(spec, t)
	return spec.Yaw + spec.Swing * math.sin(2 * math.pi * t / spec.Period)
end

-- Where a gate is in its cycle at time t: "Off", "Warn" (the end of the off time) or "On".
function RoomMechanics.GatePhase(spec, t)
	local cycle = spec.OffTime + spec.OnTime
	local into = (t - (spec.Phase or 0)) % cycle
	if into >= spec.OffTime then
		return "On"
	elseif into >= spec.OffTime - config.GateWarnTime then
		return "Warn"
	end
	return "Off"
end

-- Distance from point p to the segment a-b, all Vector2 in XZ.
function RoomMechanics.DistanceToSegment(p, a, b)
	local abX, abZ = b.X - a.X, b.Y - a.Y
	local lengthSquared = abX * abX + abZ * abZ
	local t = 0
	if lengthSquared > 0 then
		t = math.clamp(((p.X - a.X) * abX + (p.Y - a.Y) * abZ) / lengthSquared, 0, 1)
	end
	local dx, dz = p.X - (a.X + abX * t), p.Y - (a.Y + abZ * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Whether segment p-q crosses the axis-aligned rectangle (centre, size), in XZ.
local function segmentCrossesRect(p, q, centre, size)
	local enter, exit = 0, 1
	for _, axis in { { p.X - centre.X, q.X - p.X, size.X / 2 }, { p.Y - centre.Y, q.Y - p.Y, size.Y / 2 } } do
		local origin, delta, half = axis[1], axis[2], axis[3]
		if math.abs(delta) < 1e-9 then
			if math.abs(origin) > half then
				return false
			end
		else
			local t1, t2 = (-half - origin) / delta, (half - origin) / delta
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			enter, exit = math.max(enter, t1), math.min(exit, t2)
			if enter > exit then
				return false
			end
		end
	end
	return true
end

-- origin is where the room was built (RoomBuilder); specs are relative to it.
function RoomMechanics.new(room, layout, origin)
	local self = setmetatable({
		_origin = origin or Vector3.zero,
		_sweepers = {},
		_gates = {},
		_breakables = {}, -- part -> state
		_pads = {},
		_boosts = {},
		_portals = {}, -- pair letter -> { spec, ... }
		_barrels = {}, -- part -> { spec, live }
	}, RoomMechanics)
	local decor = room:FindFirstChild("Decor")
	local counts = {}
	for _, spec in layout.Mechanics or {} do
		counts[spec.Kind] = (counts[spec.Kind] or 0) + 1
		local index = counts[spec.Kind]
		if spec.Kind == "Sweeper" then
			local name = "Sweeper" .. index
			table.insert(self._sweepers, {
				spec = spec,
				part = room:FindFirstChild(name),
				cap = decor and decor:FindFirstChild(name .. "Cap"),
				base = decor and decor:FindFirstChild(name .. "Base"),
			})
		elseif spec.Kind == "LaserGate" then
			table.insert(self._gates, { spec = spec, part = room:FindFirstChild("Gate" .. index), phase = nil })
		elseif spec.Kind == "Breakable" then
			local name = "Breakable" .. index
			local part = room:FindFirstChild(name)
			if part then
				self._breakables[part] = {
					spec = spec,
					health = spec.Health or config.BreakableHealth,
					maxHealth = spec.Health or config.BreakableHealth,
					trims = { decor and decor:FindFirstChild(name .. "Cap"), decor and decor:FindFirstChild(name .. "Base") },
				}
			end
		elseif spec.Kind == "AmpPad" then
			table.insert(self._pads, { spec = spec, part = room:FindFirstChild("AmpPad" .. index) })
		elseif spec.Kind == "BoostPad" then
			table.insert(self._boosts, { spec = spec })
		elseif spec.Kind == "Portal" then
			local pair = self._portals[spec.Pair] or {}
			table.insert(pair, { spec = spec })
			self._portals[spec.Pair] = pair
		elseif spec.Kind == "Barrel" then
			local name = "Barrel" .. index
			local part = room:FindFirstChild(name)
			if part then
				self._barrels[part] = {
					spec = spec,
					live = true,
					trims = { decor and decor:FindFirstChild(name .. "Cap"), decor and decor:FindFirstChild(name .. "Base") },
				}
			end
		end
	end
	return self
end

local function pose(part, yaw)
	if part then
		local position = part.Position
		part.CFrame = CFrame.lookAt(position, position + RoomGeometry.LookVector(yaw))
	end
end

local GATE_LOOK = {
	Off = { color = "GateOffColor", transparency = "GateOffTransparency" },
	Warn = { color = "GateWarnColor", transparency = 0.4 },
	On = { color = "GateOnColor", transparency = 0.15 },
}

function RoomMechanics:Step(_deltaTime, now)
	for _, sweeper in self._sweepers do
		local yaw = RoomMechanics.SweeperYaw(sweeper.spec, now)
		pose(sweeper.part, yaw)
		pose(sweeper.cap, yaw)
		pose(sweeper.base, yaw)
	end
	for _, gate in self._gates do
		local phase = RoomMechanics.GatePhase(gate.spec, now)
		if phase ~= gate.phase then
			gate.phase = phase
		end
		if gate.part and gate.part:GetAttribute("Phase") ~= phase then
			gate.part:SetAttribute("Phase", phase)
			local look = GATE_LOOK[phase]
			gate.part.Color = config[look.color]
			gate.part.Transparency = if type(look.transparency) == "string"
				then config[look.transparency]
				else look.transparency
		end
	end
end

-- The state gate `index` was last stepped into.
function RoomMechanics:GateState(index)
	local gate = self._gates[index]
	return gate and gate.phase
end

-- Damage a player at `position` takes from hazards right now (0 if none). The caller spaces
-- repeated burns out by GateTick.
function RoomMechanics:HazardAt(position, now)
	local point = Vector2.new(position.X - self._origin.X, position.Z - self._origin.Z)
	for _, gate in self._gates do
		if RoomMechanics.GatePhase(gate.spec, now) == "On" then
			if RoomMechanics.DistanceToSegment(point, gate.spec.From, gate.spec.To) <= config.GateHitHalfWidth then
				return config.GateDamage
			end
		end
	end
	return 0
end

local function hide(part, trims)
	part.Transparency = 1
	part.CanQuery = false
	part.CanCollide = false
	for _, trim in trims do
		trim.Transparency = 1
	end
end

-- Sets off the barrel `part`: returns { position, radius, damage }, or nil if it is not a live
-- barrel.
function RoomMechanics:_detonate(part)
	local barrel = self._barrels[part]
	if not barrel or not barrel.live then
		return nil
	end
	barrel.live = false
	hide(part, barrel.trims)
	return { position = part.Position, radius = config.BarrelRadius, damage = config.BarrelDamage }
end

-- Every live barrel within `radius` of `position` goes off too. Returns their blasts.
function RoomMechanics:DetonateNear(position, radius)
	local blasts = {}
	for part, barrel in self._barrels do
		if barrel.live then
			local offset = Vector3.new(part.Position.X - position.X, 0, part.Position.Z - position.Z)
			if offset.Magnitude <= radius then
				table.insert(blasts, self:_detonate(part))
			end
		end
	end
	return blasts
end

-- A shot struck `instance`. Returns nil when it is not a live breakable or barrel, otherwise
-- "Damaged", "Cracked" (at or below half health), "Broken" or "Exploded", and for a break or a
-- blast the details: { position, loot } or { position, radius, damage }.
function RoomMechanics:HandleImpact(instance, _entry)
	local blast = instance and self:_detonate(instance)
	if blast then
		return "Exploded", blast
	end
	local breakable = instance and self._breakables[instance]
	if not breakable or breakable.health <= 0 then
		return nil
	end
	breakable.health -= 1
	if breakable.health <= 0 then
		hide(instance, breakable.trims)
		return "Broken", { position = instance.Position, loot = breakable.spec.Loot }
	end
	if breakable.health <= breakable.maxHealth / 2 then
		instance:SetAttribute("Cracked", true)
		instance.Color = config.CrackedColor
		return "Cracked"
	end
	return "Damaged"
end

-- Called with each frame's travel of a shot: boost pads, portals, then amp pads.
function RoomMechanics:ApplySegment(entry, from, to)
	local ox, oz = self._origin.X, self._origin.Z
	local p, q = Vector2.new(from.X - ox, from.Z - oz), Vector2.new(to.X - ox, to.Z - oz)
	self:_applyBoosts(entry, p, q)
	self:_applyPortals(entry, p, q, to.Y)
	if entry.amped or #self._pads == 0 then
		return false
	end
	for _, pad in self._pads do
		if segmentCrossesRect(p, q, pad.spec.Offset, pad.spec.Size) then
			entry.amped = true
			entry.damage += config.AmpBonus
			if entry.part then
				entry.part.Color = config.AmpColor
			end
			return true
		end
	end
	return false
end

-- A shot crossing a boost pad speeds up and gains a bounce, once per pad.
function RoomMechanics:_applyBoosts(entry, p, q)
	for index, boost in self._boosts do
		entry.boosted = entry.boosted or {}
		if not entry.boosted[index] and segmentCrossesRect(p, q, boost.spec.Offset, boost.spec.Size) then
			entry.boosted[index] = true
			entry.speed = (entry.speed or 0) * config.BoostSpeed
			entry.bouncesLeft = (entry.bouncesLeft or 0) + config.BoostBounces
			if entry.part then
				entry.part.Color = config.BoostColor
			end
		end
	end
end

-- A shot entering a portal leaves its partner, just past the far side, on the same heading.
function RoomMechanics:_applyPortals(entry, p, q, planeY)
	if (entry.portalUntil or 0) > (entry.travelled or 0) then
		entry.travelled = (entry.travelled or 0) + (q - p).Magnitude
		return
	end
	entry.travelled = (entry.travelled or 0) + (q - p).Magnitude
	for _, pair in self._portals do
		if #pair == 2 then
			for index, portal in pair do
				if segmentCrossesRect(p, q, portal.spec.Offset, portal.spec.Size) then
					local exit = pair[3 - index].spec
					local heading = entry.direction or Vector3.new(0, 0, 1)
					local push = math.max(exit.Size.X, exit.Size.Y) / 2 + 1
					entry.teleportTo = Vector3.new(
						self._origin.X + exit.Offset.X + heading.X * push,
						planeY,
						self._origin.Z + exit.Offset.Y + heading.Z * push
					)
					-- Not again until it has flown clear of the exit.
					entry.portalUntil = entry.travelled + push + 2
					return
				end
			end
		end
	end
end

return RoomMechanics
