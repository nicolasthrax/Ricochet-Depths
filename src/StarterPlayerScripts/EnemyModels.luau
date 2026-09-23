-- Builds and poses the client-side enemy models described by EnemyVisualConfig. Pose maths is
-- pure (positions and look vectors) so the headless suite can cover it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage:WaitForChild("EnemyConfig"))
local EnemyVisualConfig = require(ReplicatedStorage:WaitForChild("EnemyVisualConfig"))

local EnemyModels = {}

local UP = Vector3.new(0, 1, 0)
local PARKED_BELOW = EnemyConfig.StoragePosition.Y / 2

local function makePart(spec, name, parent)
	local part = Instance.new(spec.Shape == "Wedge" and "WedgePart" or "Part")
	if spec.Shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	end
	part.Name = name
	part.Size = spec.Size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Role", spec.Role)
	if spec.Role == "Eye" or spec.Role == "Glow" then
		part.Material = Enum.Material.Neon
	elseif spec.Role == "Dark" then
		part.Material = Enum.Material.Metal
		part.Color = EnemyVisualConfig.DarkColor
	else
		part.Material = Enum.Material.SmoothPlastic
	end
	if spec.Role == "Eye" then
		part.Color = EnemyVisualConfig.EyeColor
	end
	part.Parent = parent
	return part
end

-- A folder of parts for one archetype, in the same order Pose returns poses.
function EnemyModels.Build(archetypeId, parent)
	local visual = EnemyVisualConfig.Archetypes[archetypeId]
	local model = Instance.new("Folder")
	model.Name = archetypeId
	model:SetAttribute("Archetype", archetypeId)
	local order = 0
	local function add(spec, name)
		order += 1
		local part = makePart(spec, name, model)
		part:SetAttribute("Order", order)
	end
	if visual then
		for _, spec in visual.Parts do
			add(spec, spec.Name)
		end
		for _, ring in visual.Rings or {} do
			for index = 1, ring.Count do
				add(ring, ring.Name .. index)
			end
		end
	end
	model.Parent = parent
	return model
end

-- Parts in Build order.
function EnemyModels.OrderedParts(model)
	local parts = model:GetChildren()
	table.sort(parts, function(a, b)
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)
	return parts
end

-- Poses every part for a body at `position` facing `facing` at time t. seed staggers the bob
-- so a room of the same enemy does not move in lockstep. Returns { position, look } per part.
function EnemyModels.Pose(visual, position, facing, t, seed)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local forward = flat.Magnitude > 1e-4 and flat.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local bob = (visual.Bob or 0) * math.sin((t * (visual.BobRate or 1) + (seed or 0) * 0.37) * math.pi * 2)
	local centre = position + Vector3.new(0, bob, 0)

	local function toWorld(offset)
		return centre + right * offset.X + UP * offset.Y - forward * offset.Z
	end

	local poses = {}
	for _, spec in visual.Parts do
		table.insert(poses, { position = toWorld(spec.Offset), look = forward })
	end
	for _, ring in visual.Rings or {} do
		local tilt = math.rad(ring.Tilt or 0)
		for index = 1, ring.Count do
			local angle = math.rad(ring.Speed * t + (index - 1) * 360 / ring.Count)
			local x, z = math.cos(angle) * ring.Radius, math.sin(angle) * ring.Radius
			-- Tilt the orbit about the enemy's X axis.
			local offset = Vector3.new(x, ring.Height - z * math.sin(tilt), z * math.cos(tilt))
			local tangent = Vector3.new(-math.sin(angle), -math.cos(angle) * math.sin(tilt), math.cos(angle) * math.cos(tilt))
			local look = right * tangent.X + UP * tangent.Y - forward * tangent.Z
			table.insert(poses, { position = toWorld(offset), look = look })
		end
	end
	return poses
end

-- Pooled bodies wait far below the arena; their models hide rather than follow them there.
function EnemyModels.IsParked(position)
	return position.Y < PARKED_BELOW
end

-- The colour a part of `role` takes when the hitbox shows `bodyColor`.
function EnemyModels.ColorFor(role, bodyColor)
	if role == "Body" then
		return bodyColor
	elseif role == "Glow" then
		return bodyColor:Lerp(Color3.new(1, 1, 1), EnemyVisualConfig.GlowWash)
	elseif role == "Eye" then
		return EnemyVisualConfig.EyeColor
	end
	return EnemyVisualConfig.DarkColor
end

return EnemyModels
