-- Drives a room's mechanics (layout.Mechanics), on the parts RoomBuilder made for them:
--   Sweeper    a reflector that swings about its resting heading; shots bounce off its live pose
--   LaserGate  a beam on a cycle (off, warning, on); it burns players inside while on
--   Breakable  cover with health; shots damage it, and at zero it is gone
--   AmpPad     a floor strip; a shot crossing it deals AmpBonus more damage from then on
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RoomGeometry = require(ReplicatedStorage:WaitForChild("RoomGeometry"))

local RoomMechanics = {}
RoomMechanics.__index = RoomMechanics

RoomMechanics.Kinds = { Sweeper = true, LaserGate = true, Breakable = true, AmpPad = true }

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

-- A shot struck `instance`. Returns nil when it is not a live breakable, otherwise "Damaged",
-- "Cracked" (at or below half health) or "Broken".
function RoomMechanics:HandleImpact(instance)
	local breakable = instance and self._breakables[instance]
	if not breakable or breakable.health <= 0 then
		return nil
	end
	breakable.health -= 1
	if breakable.health <= 0 then
		instance.Transparency = 1
		instance.CanQuery = false
		instance.CanCollide = false
		for _, trim in breakable.trims do
			trim.Transparency = 1
		end
		return "Broken"
	end
	if breakable.health <= breakable.maxHealth / 2 then
		instance:SetAttribute("Cracked", true)
		instance.Color = config.CrackedColor
		return "Cracked"
	end
	return "Damaged"
end

-- Called with each frame's travel of a shot; amps it the first time it crosses a pad.
function RoomMechanics:ApplySegment(entry, from, to)
	if entry.amped or #self._pads == 0 then
		return false
	end
	local ox, oz = self._origin.X, self._origin.Z
	local p, q = Vector2.new(from.X - ox, from.Z - oz), Vector2.new(to.X - ox, to.Z - oz)
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

return RoomMechanics
