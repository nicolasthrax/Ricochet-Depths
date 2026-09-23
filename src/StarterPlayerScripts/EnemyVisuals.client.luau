-- Draws each live enemy as a multi-part model (EnemyVisualConfig) over its server hitbox, and
-- hides the hitbox box on this client. Models follow the hitbox every frame, face the way it
-- moves (or its shield), bob and spin, and take on its colour so telegraph flashes still show.
-- Cosmetic only: hits are still decided against the hitbox on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local EnemyVisualConfig = require(ReplicatedStorage:WaitForChild("EnemyVisualConfig"))
local EnemyModels = require(script.Parent:WaitForChild("EnemyModels"))

if not FeatureFlags.IsEnabled("EnemyModels") then
	return
end

-- How fast a model turns to its direction of travel (1/s).
local TURN_RATE = 10

local folder = Instance.new("Folder")
folder.Name = "EnemyModels"
folder.Parent = workspace

local entries = {} -- hitbox part -> { archetype, model, parts, visible, facing, lastPosition, color }

local function setVisible(entry, visible)
	if entry.visible == visible then
		return
	end
	entry.visible = visible
	for _, part in entry.parts do
		part.Transparency = visible and 0 or 1
	end
end

local function applyColor(entry, color)
	if entry.color == color then
		return
	end
	entry.color = color
	for _, part in entry.parts do
		part.Color = EnemyModels.ColorFor(part:GetAttribute("Role"), color)
	end
end

local function entryFor(body)
	local entry = entries[body]
	if entry and entry.archetype == body.Name then
		return entry
	end
	if entry then
		entry.model:Destroy()
	end
	if not EnemyVisualConfig.Archetypes[body.Name] then
		entries[body] = nil
		return nil
	end
	local model = EnemyModels.Build(body.Name, folder)
	entry = {
		archetype = body.Name,
		model = model,
		parts = EnemyModels.OrderedParts(model),
		visible = true,
		facing = Vector3.new(0, 0, -1),
		lastPosition = body.Position,
		seed = #folder:GetChildren(),
	}
	setVisible(entry, false)
	entries[body] = entry
	return entry
end

local function facingFor(body, entry, dt)
	local shield = body:FindFirstChild("Shield")
	if shield and shield.Transparency < 1 then
		local toShield = shield.Position - body.Position
		if toShield.Magnitude > 1e-3 then
			return toShield
		end
	end
	local moved = body.Position - entry.lastPosition
	moved = Vector3.new(moved.X, 0, moved.Z)
	if moved.Magnitude > 1e-3 then
		local alpha = 1 - math.exp(-TURN_RATE * dt)
		local blended = entry.facing:Lerp(moved.Unit, alpha)
		if blended.Magnitude > 1e-3 then
			return blended.Unit
		end
	end
	return entry.facing
end

local function update(dt)
	local arena = workspace:FindFirstChild("Arena")
	local pool = arena and arena:FindFirstChild("EnemyPool")
	if not pool then
		return
	end
	local now = os.clock()
	local moveParts, moveFrames = {}, {}
	for _, body in pool:GetChildren() do
		if body:IsA("BasePart") then
			local entry = entryFor(body)
			if entry then
				if EnemyModels.IsParked(body.Position) or body.Transparency >= 1 then
					setVisible(entry, false)
				else
					body.LocalTransparencyModifier = 1
					entry.facing = facingFor(body, entry, dt)
					applyColor(entry, body.Color)
					local visual = EnemyVisualConfig.Archetypes[entry.archetype]
					for index, pose in EnemyModels.Pose(visual, body.Position, entry.facing, now, entry.seed) do
						table.insert(moveParts, entry.parts[index])
						table.insert(moveFrames, CFrame.lookAlong(pose.position, pose.look))
					end
					setVisible(entry, true)
				end
				entry.lastPosition = body.Position
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

RunService.RenderStepped:Connect(update)
