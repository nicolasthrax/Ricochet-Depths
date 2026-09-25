--!strict
-- Draws the lane's moving parts on this client: target blocks (HP printed on their top faces),
-- the elite's telegraph lanes, and every shot. Everything here is client-local presentation; the
-- server owns the truth and this only mirrors its events.
--
-- Shots are drawn from server timestamps: each travels in a straight line from its last reported
-- position (ShotsSpawned, then every ShotsBounced) at its reported speed, so no collision runs on
-- the client. The local player's own shots appear the moment they are fired (predictShot) and are
-- handed over to the server's shot when it arrives. Parts come from ProjectilePool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local LaneGeometry = require(ReplicatedStorage.Source.Sim.LaneGeometry)
local Ricochet = require(ReplicatedStorage.Source.Sim.Ricochet)
local Network = require(ReplicatedStorage.Network)
local ProjectilePool = require(ReplicatedStorage.Modules.ProjectilePool)

local Lane = GameConfig.Lane
local World = GameConfig.World
local Palette = GameConfig.Palette

local FOLDER_NAME = "LaneView"
local SHOT_HEIGHT = 1
local ELITE_COLOR = Color3.fromRGB(116, 96, 196)
local HIT_FLASH = Color3.fromRGB(255, 255, 255)
local PREDICTION_TIMEOUT = 0.75
local INFERNO_VISUAL_SCALE = 1.35
local TINT_COLORS: { [string]: Color3 } = {
	Default = Palette.Wall,
	Ember = Color3.fromRGB(255, 150, 60),
	Inferno = Color3.fromRGB(255, 96, 32),
}
local STEP_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Linear)
local BREAK_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type TargetView = {
	id: number,
	kind: Types.TargetKind,
	column: number,
	row: number,
	widthColumns: number,
	hp: number,
	part: Part,
	label: TextLabel,
	ring: Part?,
	baseColor: Color3,
	obstacle: Ricochet.Obstacle,
}

type ShotView = {
	part: BasePart?,
	x: number,
	y: number,
	dirX: number,
	dirY: number,
	speed: number,
	radius: number,
	at: number,
}

type Prediction = {
	shot: ShotView,
	firedAt: number,
}

local folder: Folder? = nil
local origin: CFrame? = nil
local runId = 0
local frozenAt: number? = nil
local targets: { [number]: TargetView } = {}
local shots: { [number]: ShotView } = {}
local predictions: { [number]: Prediction } = {}
local obstacleCache: { Ricochet.Obstacle }? = nil

local LaneRenderer = {}

local function serverNow(): number
	return frozenAt or Workspace:GetServerTimeNow()
end

local function viewFolder(): Folder
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

local function laneCFrame(x: number, y: number, height: number): CFrame
	local laneOrigin = origin or CFrame.identity
	return laneOrigin * CFrame.new(x, height, -y)
end

---------------------------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------------------------

local function blockPlacement(column: number, row: number, widthColumns: number): (CFrame, Vector3, Ricochet.Obstacle)
	local box = LaneGeometry.targetBox(column, row, widthColumns)
	local cx, cy = (box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2
	local size = Vector3.new(box.maxX - box.minX, World.blockHeight, box.maxY - box.minY)
	local obstacle: Ricochet.Obstacle = { id = 0, minX = box.minX, minY = box.minY, maxX = box.maxX, maxY = box.maxY }
	return laneCFrame(cx, cy, World.blockHeight / 2), size, obstacle
end

local function hpText(hp: number): string
	return tostring(math.max(1, math.ceil(hp - 1e-6)))
end

local function removeTarget(id: number, breached: boolean)
	local view = targets[id]
	if view == nil then
		return
	end
	targets[id] = nil
	obstacleCache = nil
	local part = view.part
	local ring = view.ring
	if ring then
		ring:Destroy()
	end
	if breached then
		part.Color = Palette.Harm
	end
	view.label.Text = ""
	local shrink = TweenService:Create(part, BREAK_TWEEN, {
		Size = part.Size * 0.2,
		Transparency = 1,
	})
	shrink.Completed:Connect(function()
		part:Destroy()
	end)
	shrink:Play()
end

local function addTarget(snapshot: Network.TargetSnapshot)
	if targets[snapshot.targetId] then
		removeTarget(snapshot.targetId, false)
	end
	local cframe, size, obstacle = blockPlacement(snapshot.column, snapshot.row, snapshot.widthColumns)
	obstacle.id = snapshot.targetId
	local isElite = snapshot.kind == "Elite"
	local baseColor = if isElite then ELITE_COLOR else Palette.Target

	local part = Instance.new("Part")
	part.Name = `Target_{snapshot.targetId}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Color = baseColor
	part.Size = size
	part.CFrame = cframe

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = hpText(snapshot.hp)
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.Parent = label

	local ring: Part? = nil
	if isElite then
		local halo = Instance.new("Part")
		halo.Name = "EliteRing"
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CanTouch = false
		halo.CastShadow = false
		halo.Material = Enum.Material.Neon
		halo.Color = Palette.Harm
		halo.Size = Vector3.new(size.X + 0.5, 0.12, size.Z + 0.5)
		halo.CFrame = cframe * CFrame.new(0, -World.blockHeight / 2 + 0.06, 0)
		halo.Parent = viewFolder()
		ring = halo
	end

	part.Parent = viewFolder()
	targets[snapshot.targetId] = {
		id = snapshot.targetId,
		kind = snapshot.kind,
		column = snapshot.column,
		row = snapshot.row,
		widthColumns = snapshot.widthColumns,
		hp = snapshot.hp,
		part = part,
		label = label,
		ring = ring,
		baseColor = baseColor,
		obstacle = obstacle,
	}
	obstacleCache = nil
end

local function moveTarget(id: number, row: number)
	local view = targets[id]
	if view == nil then
		return
	end
	view.row = row
	local cframe, _, obstacle = blockPlacement(view.column, row, view.widthColumns)
	obstacle.id = id
	view.obstacle = obstacle
	obstacleCache = nil
	TweenService:Create(view.part, STEP_TWEEN, { CFrame = cframe }):Play()
	local ring = view.ring
	if ring then
		TweenService:Create(ring, STEP_TWEEN, { CFrame = cframe * CFrame.new(0, -World.blockHeight / 2 + 0.06, 0) }):Play()
	end
end

local function damageTarget(hit: Network.DamageHit)
	local view = targets[hit.targetId]
	if view == nil then
		return
	end
	if hit.hpAfter <= 0 then
		removeTarget(hit.targetId, false)
		return
	end
	view.hp = hit.hpAfter
	view.label.Text = hpText(hit.hpAfter)
	view.part.Color = HIT_FLASH
	TweenService:Create(view.part, FLASH_TWEEN, { Color = view.baseColor }):Play()
end

local function clearTargets()
	for id in table.clone(targets) do
		local view = targets[id]
		view.part:Destroy()
		local ring = view.ring
		if ring then
			ring:Destroy()
		end
		targets[id] = nil
	end
	obstacleCache = nil
end

---------------------------------------------------------------------------------------------
-- Telegraphs
---------------------------------------------------------------------------------------------

local function showTelegraph(payload: Network.AttackTelegraphPayload)
	local attacker = targets[payload.attackerId]
	local left = -Lane.halfWidth + (payload.column - 1) * Lane.grid.cellSize
	local width = payload.widthColumns * Lane.grid.cellSize
	local top = if attacker then attacker.obstacle.minY else Lane.length
	local part = Instance.new("Part")
	part.Name = "Telegraph"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Palette.Harm
	part.Transparency = 0.75
	part.Size = Vector3.new(width, 0.08, top)
	part.CFrame = laneCFrame(left + width / 2, top / 2, 0.06)
	part.Parent = viewFolder()
	local windup = TweenService:Create(
		part,
		TweenInfo.new(payload.windupSeconds, Enum.EasingStyle.Linear),
		{ Transparency = 0.35 }
	)
	windup.Completed:Connect(function()
		part.Transparency = 0
		task.delay(0.15, function()
			part:Destroy()
		end)
	end)
	windup:Play()
end

---------------------------------------------------------------------------------------------
-- Shots
---------------------------------------------------------------------------------------------

local function releaseShot(view: ShotView)
	local part = view.part
	if part then
		ProjectilePool.Release(part)
		view.part = nil
	end
end

local function visualRadius(radius: number, tint: Types.ShotTint): number
	return if tint == "Inferno" then radius * INFERNO_VISUAL_SCALE else radius
end

local function acquirePart(x: number, y: number, radius: number, tint: Types.ShotTint): BasePart?
	return ProjectilePool.Get(laneCFrame(x, y, SHOT_HEIGHT), visualRadius(radius, tint), TINT_COLORS[tint])
end

local function spawnShot(snapshot: Network.ShotSnapshot)
	local localPlayer = Players.LocalPlayer
	local view: ShotView = {
		part = nil,
		x = snapshot.x,
		y = snapshot.y,
		dirX = snapshot.dirX,
		dirY = snapshot.dirY,
		speed = snapshot.speed,
		radius = snapshot.radius,
		at = snapshot.at,
	}
	local prediction = if localPlayer and snapshot.ownerUserId == localPlayer.UserId and snapshot.sequence > 0
		then predictions[snapshot.sequence]
		else nil
	if prediction then
		predictions[snapshot.sequence] = nil
		view.part = prediction.shot.part
	else
		view.part = acquirePart(view.x, view.y, view.radius, snapshot.tint)
	end
	local existing = shots[snapshot.shotId]
	if existing then
		releaseShot(existing)
	end
	shots[snapshot.shotId] = view
end

local function clearShots()
	for id, view in shots do
		releaseShot(view)
		shots[id] = nil
	end
	for sequence, prediction in predictions do
		releaseShot(prediction.shot)
		predictions[sequence] = nil
	end
	ProjectilePool.ReleaseAll()
end

local function shotPosition(view: ShotView, now: number): (number, number)
	local elapsed = math.max(0, now - view.at)
	local x = view.x + view.dirX * view.speed * elapsed
	local y = view.y + view.dirY * view.speed * elapsed
	-- A bounce report can land a frame late: never draw a shot through a wall while waiting.
	x = math.clamp(x, -Lane.halfWidth + view.radius, Lane.halfWidth - view.radius)
	y = math.min(y, Lane.length - view.radius)
	return x, y
end

local function renderShots()
	if origin == nil then
		return
	end
	local now = serverNow()
	local clock = os.clock()
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	for _, view in shots do
		local part = view.part
		if part then
			local x, y = shotPosition(view, now)
			table.insert(parts, part)
			table.insert(cframes, laneCFrame(x, y, SHOT_HEIGHT))
		end
	end
	for sequence, prediction in predictions do
		if clock - prediction.firedAt > PREDICTION_TIMEOUT then
			-- The server never confirmed it (a refused shot): drop the stand-in.
			releaseShot(prediction.shot)
			predictions[sequence] = nil
		else
			local part = prediction.shot.part
			if part then
				local x, y = shotPosition(prediction.shot, prediction.shot.at + (clock - prediction.firedAt))
				table.insert(parts, part)
				table.insert(cframes, laneCFrame(x, y, SHOT_HEIGHT))
			end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

function LaneRenderer.init()
	ProjectilePool.Prewarm(24)

	Network.TargetsSpawned:connect(function(payload: Network.TargetsSpawnedPayload)
		for _, snapshot in payload.targets do
			addTarget(snapshot)
		end
	end)
	Network.TargetsAdvanced:connect(function(payload: Network.TargetsAdvancedPayload)
		for _, move in payload.moves do
			moveTarget(move.targetId, move.row)
		end
		for _, id in payload.breached do
			removeTarget(id, true)
		end
	end)
	Network.DamageReport:connect(function(payload: Network.DamageReportPayload)
		for _, hit in payload.hits do
			damageTarget(hit)
		end
	end)
	Network.AttackTelegraph:connect(showTelegraph)

	Network.ShotsSpawned:connect(function(payload: Network.ShotsSpawnedPayload)
		for _, snapshot in payload.shots do
			spawnShot(snapshot)
		end
	end)
	Network.ShotsBounced:connect(function(payload: Network.ShotsBouncedPayload)
		for _, bounce in payload.bounces do
			local view = shots[bounce.shotId]
			if view then
				view.x, view.y = bounce.x, bounce.y
				view.dirX, view.dirY = bounce.dirX, bounce.dirY
				view.speed = bounce.speed
				view.at = bounce.at
			end
		end
	end)
	Network.ShotsEnded:connect(function(payload: Network.ShotsEndedPayload)
		for _, ending in payload.ends do
			local view = shots[ending.shotId]
			if view then
				releaseShot(view)
				shots[ending.shotId] = nil
			end
		end
	end)

	RunService.RenderStepped:Connect(renderShots)
end

-- Follows a run state: a new run clears the lane, a frozen lane stops the shots where they are.
function LaneRenderer.applyState(state: Network.RunState)
	origin = state.laneOrigin
	if state.runId ~= runId then
		runId = state.runId
		clearTargets()
		clearShots()
	end
	if state.timeScale <= 0 then
		frozenAt = frozenAt or Workspace:GetServerTimeNow()
	else
		local pausedAt = frozenAt
		if pausedAt then
			-- Carry every shot over the pause, so nothing jumps ahead before the server's
			-- resume bounces arrive.
			local pausedFor = Workspace:GetServerTimeNow() - pausedAt
			for _, view in shots do
				view.at += pausedFor
			end
		end
		frozenAt = nil
	end
end

-- Redraws the lane from a snapshot (join, respawn, script restart).
function LaneRenderer.applySnapshot(snapshot: Network.RunSnapshot)
	runId = -1
	LaneRenderer.applyState(snapshot.state)
	for _, target in snapshot.targets do
		addTarget(target)
	end
end

-- Shows the local player's shot the moment it is fired, before the server confirms it.
function LaneRenderer.predictShot(
	sequence: number,
	x: number,
	y: number,
	dirX: number,
	dirY: number,
	speed: number,
	radius: number,
	tint: Types.ShotTint
)
	if origin == nil then
		return
	end
	local part = acquirePart(x, y, radius, tint)
	if part == nil then
		return
	end
	predictions[sequence] = {
		shot = { part = part, x = x, y = y, dirX = dirX, dirY = dirY, speed = speed, radius = radius, at = 0 },
		firedAt = os.clock(),
	}
end

-- The client's view of the target boxes, for the aim guide.
function LaneRenderer.obstacles(): { Ricochet.Obstacle }
	local cached = obstacleCache
	if cached then
		return cached
	end
	local list: { Ricochet.Obstacle } = {}
	for _, view in targets do
		table.insert(list, view.obstacle)
	end
	table.sort(list, function(a: Ricochet.Obstacle, b: Ricochet.Obstacle): boolean
		return a.id < b.id
	end)
	obstacleCache = list
	return list
end

table.freeze(LaneRenderer)
return LaneRenderer
