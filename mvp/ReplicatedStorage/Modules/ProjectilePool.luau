--!strict
-- Recycles projectile visuals instead of creating and destroying a part for every shot.
--
-- Shots are simulated on the server as numbers (Source/Sim/Ricochet); these parts are what a
-- client draws for them, so the pool is used on the client. Parts are never destroyed: a released
-- part is hidden and parked far below the map, and its trail is switched off so parking never
-- draws a streak across the screen.
--
-- At most GameConfig.Presentation.maxVisibleShots parts are out at once. Past that, Get returns
-- nil and the caller skips drawing that shot: a crowded screen reads the same, and frame time
-- stays flat on phones.

local Workspace = game:GetService("Workspace")

local GameConfig = require(script.Parent.Parent.Source.GameConfig)

local FOLDER_NAME = "ProjectilePool"
local PARK_CFRAME = CFrame.new(0, -10000, 0)
local CAPACITY = GameConfig.Presentation.maxVisibleShots
local DEFAULT_RADIUS = GameConfig.Shot.radius
local TRAIL_LIFETIME = 0.16

type Pooled = {
	part: BasePart,
	trail: Trail,
	top: Attachment,
	bottom: Attachment,
}

local folder: Folder? = nil
local free: { Pooled } = {}
local byPart: { [BasePart]: Pooled } = {}
local active: { [BasePart]: boolean } = {}
local activeCount = 0

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
	return created
end

local function setRadius(pooled: Pooled, radius: number)
	pooled.part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	pooled.top.Position = Vector3.new(0, radius * 0.7, 0)
	pooled.bottom.Position = Vector3.new(0, -radius * 0.7, 0)
end

local function build(): Pooled
	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = GameConfig.Palette.ShotCore
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.CFrame = PARK_CFRAME

	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = TRAIL_LIFETIME
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Enabled = false
	trail.Parent = part

	local pooled: Pooled = { part = part, trail = trail, top = top, bottom = bottom }
	setRadius(pooled, DEFAULT_RADIUS)
	part.Parent = getFolder()
	byPart[part] = pooled
	return pooled
end

local ProjectilePool = {}

-- Builds parts ahead of time so the first shots of a fight never allocate.
function ProjectilePool.Prewarm(count: number)
	for _ = #free + activeCount + 1, math.min(count, CAPACITY) do
		table.insert(free, build())
	end
end

-- A visible projectile at `cf`, or nil when the visible cap is reached. `radius` and
-- `trailColor` restyle the recycled part (defaults: the base shot radius, the shot core colour).
function ProjectilePool.Get(cf: CFrame, radius: number?, trailColor: Color3?): BasePart?
	if activeCount >= CAPACITY then
		return nil
	end
	local pooled = table.remove(free) or build()
	local part = pooled.part
	setRadius(pooled, radius or DEFAULT_RADIUS)
	pooled.trail.Color = ColorSequence.new(trailColor or GameConfig.Palette.ShotCore)
	part.CFrame = cf
	part.Transparency = 0
	-- Clear after moving, so the trail starts here and not at the parking spot.
	pooled.trail:Clear()
	pooled.trail.Enabled = true
	active[part] = true
	activeCount += 1
	return part
end

-- Returns a projectile to the pool. Releasing a part twice, or a part the pool does not own,
-- does nothing.
function ProjectilePool.Release(projectile: Instance)
	if not projectile:IsA("BasePart") then
		return
	end
	local part = projectile :: BasePart
	local pooled = byPart[part]
	if pooled == nil or not active[part] then
		return
	end
	active[part] = nil
	activeCount -= 1
	pooled.trail.Enabled = false
	part.Transparency = 1
	part.CFrame = PARK_CFRAME
	table.insert(free, pooled)
end

-- Releases every projectile that is out (a new run, a room change).
function ProjectilePool.ReleaseAll()
	for part in table.clone(active) do
		ProjectilePool.Release(part)
	end
end

function ProjectilePool.ActiveCount(): number
	return activeCount
end

function ProjectilePool.Capacity(): number
	return CAPACITY
end

table.freeze(ProjectilePool)
return ProjectilePool
