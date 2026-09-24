-- Draws each live enemy as a multi-part model (EnemyVisualConfig) over its server hitbox, and
-- hides the hitbox box on this client. Models follow the hitbox every frame, face the way it
-- moves (or its shield), bob and spin, and take on its colour so telegraph flashes still show.
-- Cosmetic only: hits are still decided against the hitbox on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
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

-- 0 shown, 1 hidden; a blinking Phaser sits in between.
local function setVisibility(entry, transparency)
	if entry.transparency == transparency then
		return
	end
	entry.transparency = transparency
	for _, part in entry.parts do
		part.Transparency = transparency
	end
end

local function setVisible(entry, visible)
	setVisibility(entry, visible and 0 or 1)
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

local CHILL_COLOR = Color3.fromRGB(150, 220, 255)
local BURN_COLOR = Color3.fromRGB(255, 120, 40)

-- The glow and name tag a champion or a status gets. Built once per model and reused, since a
-- model follows whichever body its pool slot is given next.
local function buildMarkers(model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "StatusGlow"
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = model

	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local tag = Instance.new("BillboardGui")
	tag.Name = "ChampionTag"
	tag.Size = UDim2.fromOffset(140, 22)
	tag.StudsOffset = Vector3.new(0, 5, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Enabled = false
	tag.Adornee = anchor
	tag.Parent = model
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextStrokeTransparency = 0.2
	label.Parent = tag
	return highlight, tag, label
end

-- Chill shows over burning, and either over a champion's own glow.
local function updateMarkers(entry, body, shown)
	local championId = body:GetAttribute("Champion")
	local champion = type(championId) == "string" and CombatConfig.Champions[championId] or nil
	local color = body:GetAttribute("Chilled") and CHILL_COLOR
		or body:GetAttribute("Burning") and BURN_COLOR
		or champion and champion.Color
		or nil
	local key = shown and string.format("%s|%s", tostring(color), tostring(championId)) or "hidden"
	if entry.markerKey == key then
		return
	end
	entry.markerKey = key
	entry.highlight.Enabled = shown and color ~= nil
	if color then
		entry.highlight.FillColor = color
		entry.highlight.OutlineColor = color
	end
	entry.tag.Enabled = shown and champion ~= nil
	if champion then
		entry.tagLabel.Text = string.upper(champion.DisplayName)
		entry.tagLabel.TextColor3 = champion.Color
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
	local highlight, tag, tagLabel = buildMarkers(model)
	entry = {
		highlight = highlight,
		tag = tag,
		tagLabel = tagLabel,
		archetype = body.Name,
		model = model,
		parts = EnemyModels.OrderedParts(model),
		transparency = 0,
		facing = Vector3.new(0, 0, -1),
		lastPosition = body.Position,
		seed = #folder:GetChildren(),
	}
	setVisible(entry, false)
	entries[body] = entry
	return entry
end

local function facingFor(body, entry, dt)
	-- Turrets publish their heading, since they never move.
	local published = body:GetAttribute("Facing")
	if typeof(published) == "Vector3" and published.Magnitude > 1e-3 then
		return published
	end
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

-- Every arena slot's enemy pool. Runs happen side by side, one slot per group.
local function enemyPools()
	local pools = {}
	local arenas = workspace:FindFirstChild("Arenas")
	for _, slot in arenas and arenas:GetChildren() or {} do
		local arena = slot:FindFirstChild("Arena")
		local pool = arena and arena:FindFirstChild("EnemyPool")
		if pool then
			table.insert(pools, pool)
		end
	end
	return pools
end

-- Poses every live model in one pool, appending the moves to the frame's batch.
local function updatePool(pool, now, dt, moveParts, moveFrames)
	for _, body in pool:GetChildren() do
		if body:IsA("BasePart") then
			local entry = entryFor(body)
			if entry then
				local phasing = body:GetAttribute("Phasing") == true
				if EnemyModels.IsParked(body.Position) or (body.Transparency >= 1 and not phasing) then
					setVisible(entry, false)
					updateMarkers(entry, body, false)
				else
					updateMarkers(entry, body, not phasing)
					body.LocalTransparencyModifier = 1
					entry.facing = facingFor(body, entry, dt)
					applyColor(entry, body.Color)
					local visual = EnemyVisualConfig.Archetypes[entry.archetype]
					for index, pose in EnemyModels.Pose(visual, body.Position, entry.facing, now, entry.seed) do
						table.insert(moveParts, entry.parts[index])
						table.insert(moveFrames, CFrame.lookAlong(pose.position, pose.look))
					end
					setVisibility(entry, phasing and 0.75 or 0)
				end
				entry.lastPosition = body.Position
			end
		end
	end
end

local function update(dt)
	local now = os.clock()
	local moveParts, moveFrames = {}, {}
	for _, pool in enemyPools() do
		updatePool(pool, now, dt, moveParts, moveFrames)
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

RunService.RenderStepped:Connect(update)
