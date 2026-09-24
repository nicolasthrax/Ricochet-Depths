-- Runs one room's objective (ObjectiveConfig): Crystals, Beacon or Gallery. Its parts are built
-- into the room's own folder, so they are raycast like the rest of the room and go when it goes.
-- Server-only; clients see the parts and read progress from the run snapshot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObjectiveConfig = require(ReplicatedStorage:WaitForChild("ObjectiveConfig"))

local RoomObjectives = {}
RoomObjectives.__index = RoomObjectives

local function makePart(parent, name, size, position, color, material, queryable)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = queryable == true
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- spec is the room's Objective; origin is the room centre and floorY its floor.
function RoomObjectives.new(roomFolder, spec, origin, floorY, now, random)
	local self = setmetatable({
		kind = spec.Kind,
		_spec = spec,
		_origin = origin,
		_floorY = floorY,
		_startedAt = now,
		_random = random or Random.new(1),
		_pieces = {}, -- part -> piece
		_complete = false,
	}, RoomObjectives)

	local folder = Instance.new("Folder")
	folder.Name = "Objective"
	folder.Parent = roomFolder
	self._folder = folder

	if spec.Kind == "Crystals" then
		local config = ObjectiveConfig.Crystals
		for index, spot in spec.Spots do
			local position = Vector3.new(origin.X + spot.X, floorY + config.Size.Y / 2, origin.Z + spot.Y)
			local part = makePart(folder, "Crystal" .. index, config.Size, position, config.Color, config.Material, true)
			self._pieces[part] = { kind = "Crystal", health = config.Health }
		end
		self._left = #spec.Spots
	elseif spec.Kind == "Beacon" then
		local config = ObjectiveConfig.Beacon
		local centre = Vector3.new(origin.X + spec.Spot.X, floorY + 0.35, origin.Z + spec.Spot.Y)
		self._beaconCentre = centre
		local ring = makePart(folder, "Beacon", Vector3.new(0.3, config.Radius * 2, config.Radius * 2), centre, config.IdleColor)
		ring.Shape = Enum.PartType.Cylinder
		ring.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Transparency = 0.45
		self._beacon = ring
		self._charge = 0
	elseif spec.Kind == "Gallery" then
		self._scores = {} -- shooter -> points
		self._free = table.clone(spec.Spots)
		self._respawns = {}
		-- A fixed set of targets, built once and moved between stands: nothing is made per hit.
		local config = ObjectiveConfig.Gallery
		for index = 1, math.min(config.LiveTargets, #self._free) do
			local part = makePart(folder, "Target" .. index, config.Size, Vector3.new(origin.X, floorY - 50, origin.Z),
				config.Color, Enum.Material.Neon, false)
			self:_raiseTarget(part)
		end
	end
	return self
end

-- Puts `part` up as a target on a free stand, chosen at random.
function RoomObjectives:_raiseTarget(part)
	if #self._free == 0 then
		return
	end
	local config = ObjectiveConfig.Gallery
	local spot = table.remove(self._free, self._random:NextInteger(1, #self._free))
	part.Position = Vector3.new(self._origin.X + spot.X, self._floorY + config.Size.Y / 2, self._origin.Z + spot.Y)
	part.Transparency = 0
	part.CanQuery = true
	self._pieces[part] = { kind = "Target", spot = spot }
end

-- A shot struck `instance`. Returns nil when it is not a live objective piece; otherwise what
-- happened ("Deflected", "Cracked", "Shattered" or "Target") and, for a target, the points.
function RoomObjectives:HandleImpact(instance, entry)
	local piece = instance and self._pieces[instance]
	if not piece then
		return nil
	end
	local bounces = entry and entry.wallBounces or 0
	if piece.kind == "Crystal" then
		if bounces < 1 then
			return "Deflected"
		end
		piece.health -= 1
		if piece.health > 0 then
			instance.Color = ObjectiveConfig.Crystals.CrackedColor
			return "Cracked"
		end
		self._pieces[instance] = nil
		instance.Transparency = 1
		instance.CanQuery = false
		self._left -= 1
		if self._left <= 0 then
			self._complete = true
		end
		return "Shattered"
	elseif piece.kind == "Target" then
		local config = ObjectiveConfig.Gallery
		local points = config.Points * config.BounceMultiplier ^ math.min(bounces, config.MaxBounces)
		local shooter = entry and entry.shooter
		if shooter then
			self._scores[shooter] = (self._scores[shooter] or 0) + points
		end
		self._pieces[instance] = nil
		instance.Transparency = 1
		instance.CanQuery = false
		table.insert(self._free, piece.spot)
		table.insert(self._respawns, { at = self._now or self._startedAt, part = instance })
		return "Target", points
	end
	return nil
end

-- positions: the live players' positions this step.
function RoomObjectives:Step(deltaTime, now, positions)
	self._now = now
	if self.kind == "Beacon" and not self._complete then
		local config = ObjectiveConfig.Beacon
		local occupied = false
		for _, position in positions or {} do
			local offset = Vector3.new(position.X - self._beaconCentre.X, 0, position.Z - self._beaconCentre.Z)
			if offset.Magnitude <= config.Radius then
				occupied = true
				break
			end
		end
		if occupied then
			self._charge = math.min(self._charge + deltaTime, config.Seconds)
		else
			self._charge = math.max(self._charge - config.DrainPerSecond * deltaTime, 0)
		end
		self._beacon.Color = occupied and config.Color or config.IdleColor
		self._beacon.Transparency = occupied and 0.25 or 0.45
		if self._charge >= config.Seconds then
			self._complete = true
		end
	elseif self.kind == "Gallery" then
		for index = #self._respawns, 1, -1 do
			local respawn = self._respawns[index]
			if now - respawn.at >= ObjectiveConfig.Gallery.RespawnDelay then
				table.remove(self._respawns, index)
				self:_raiseTarget(respawn.part)
			end
		end
		if now - self._startedAt >= ObjectiveConfig.Gallery.Duration then
			self._complete = true
		end
	end
end

function RoomObjectives:IsComplete()
	return self._complete
end

-- Waves stop once an objective is done; until then they keep coming.
function RoomObjectives:WantsWaves()
	return not self._complete and self.kind ~= "Gallery"
end

-- What the HUD shows.
function RoomObjectives:Snapshot(now)
	if self.kind == "Crystals" then
		local total = #self._spec.Spots
		return { Kind = "Crystals", Text = string.format("Shatter the crystals with bank shots  %d / %d", total - self._left, total),
			Progress = total - self._left, Target = total }
	elseif self.kind == "Beacon" then
		local seconds = ObjectiveConfig.Beacon.Seconds
		return { Kind = "Beacon", Text = string.format("Hold the beacon  %d%%", math.floor(self._charge / seconds * 100)),
			Progress = self._charge, Target = seconds }
	elseif self.kind == "Gallery" then
		local best = 0
		for _, points in self._scores do
			best += points
		end
		local left = math.max(ObjectiveConfig.Gallery.Duration - (now - self._startedAt), 0)
		return { Kind = "Gallery", Text = string.format("TRICK SHOT GALLERY  Score %d  -  %ds  (bounce for x2)", best, math.ceil(left)),
			Progress = best, Target = 0 }
	end
	return nil
end

-- Gallery points per shooter, for the payout.
function RoomObjectives:Scores()
	return self._scores or {}
end

-- Crystal positions still standing, for coins on the floor when they break.
function RoomObjectives:CrystalsLeft()
	return self._left or 0
end

return RoomObjectives
