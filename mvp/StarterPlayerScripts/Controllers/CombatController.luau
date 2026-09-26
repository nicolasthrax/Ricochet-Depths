--!strict
-- The player's hands in combat: moving along the rail, aiming, the aim guide, and firing.
--
-- Touch (the main target, design section 04): the left 40% of the screen is a move strip (drag
-- sideways, the avatar follows the thumb 1:1), the right side is a floating aim stick (put a
-- thumb down anywhere, drag towards where the shot should go, lift to fire). A drag shorter than
-- the dead zone fires nothing, so a stray tap never wastes a shot.
-- Mouse: the shot aims at the cursor; hold the button to keep firing.
-- Keyboard: A/D or the arrows move, Space fires at the current aim (straight up by default).
-- Gamepad: left stick moves, right stick aims, R2 (or A) fires while held.
--
-- The aim guide traces the shot's path with the shared Ricochet ray casts against the lane walls
-- and the targets this client can see: solid to the first bounce, dashed to the second, with a
-- ring where the first contact lands. The same math runs on the server, so the guide shows the
-- path the server will simulate.
--
-- The server owns every shot: this sends FireProjectile and announces the shot through `Fired`
-- so the renderer can show it at once. Nothing here touches targets or damage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local LaneGeometry = require(ReplicatedStorage.Source.Sim.LaneGeometry)
local Ricochet = require(ReplicatedStorage.Source.Sim.Ricochet)
local ShotStats = require(ReplicatedStorage.Source.Sim.ShotStats)
local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Modules.Signal)
local LaneCamera = require(script.Parent.LaneCamera)

local Rail = GameConfig.Rail
local Lane = GameConfig.Lane
local Palette = GameConfig.Palette
local AimPreview = GameConfig.Presentation.aimPreview

local MOVE_ZONE_FRACTION = 0.4
local AIM_DEADZONE_POINTS = 18
local STICK_DEADZONE = 0.2
local AIM_STICK_DEADZONE = 0.35
local GUIDE_HEIGHT = 0.08
local GUIDE_WIDTH = 0.16
local GUIDE_THICKNESS = 0.04
local DASH_LENGTH = 0.7
local DASH_GAP = 0.5
local MAX_DASHES = 48
local GUIDE_DISTANCE = Lane.length * 3
local RAIL_RESENDS_AT_REST = 3
local ACTION_LEFT = "LaneMoveLeft"
local ACTION_RIGHT = "LaneMoveRight"
local ACTION_FIRE = "LaneFire"
local ACTION_STICKS = "LaneSticks"

-- (sequence, muzzle x, muzzle y, dirX, dirY, speed, radius, tint)
export type FiredSignal = Signal.Signal<number, number, number, number, number, number, number, Types.ShotTint>

type TouchRole = "Move" | "Aim"

type TouchState = {
	role: TouchRole,
	start: Vector2,
	startRailX: number,
	aiming: boolean, -- the aim drag has passed the dead zone
}

type Guide = {
	folder: Folder,
	solid: Part,
	ring: Part,
	dashes: { Part },
}

local enabled = false
local origin: CFrame? = nil
local railX = 0
local railTarget = 0
local lastSentX: number? = nil
local restSends = 0
local sendAccumulator = 0
local railSequence = 0
local shotSequence = 0
local lastFireClock = -math.huge
local stats: ShotStats.ShotStats = ShotStats.compute({})
local obstacleProvider: () -> { Ricochet.Obstacle } = function()
	return {}
end

local touches: { [InputObject]: TouchState } = {}
local aimX, aimY = 0, 1
local aimActive = false -- a touch drag or gamepad stick is aiming right now
local keyAxis = { left = 0, right = 0 }
local stickMove = 0
local stickAim: Vector2? = nil
local mouseMode = false
local mouseAiming = false
local mouseHeld = false
local fireHeld = false -- keyboard / gamepad trigger
local guide: Guide? = nil
local connections: { RBXScriptConnection } = {}

local CombatController = {}

-- Fires once per shot this client sends, before the server confirms it.
CombatController.Fired = Signal.new() :: FiredSignal

---------------------------------------------------------------------------------------------
-- The aim guide
---------------------------------------------------------------------------------------------

local function guidePart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Palette.ShotCore
	part.Transparency = 1
	part.Size = Vector3.new(GUIDE_WIDTH, GUIDE_THICKNESS, 1)
	part.Parent = parent
	return part
end

local function getGuide(): Guide
	local existing = guide
	if existing and existing.folder.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "AimGuide"
	local ring = guidePart("Ring", folder)
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = Palette.Wall
	local dashes: { Part } = {}
	for index = 1, MAX_DASHES do
		table.insert(dashes, guidePart(`Dash{index}`, folder))
	end
	local created: Guide = {
		folder = folder,
		solid = guidePart("Solid", folder),
		ring = ring,
		dashes = dashes,
	}
	folder.Parent = Workspace
	guide = created
	return created
end

local function hideGuide()
	local current = guide
	if current == nil then
		return
	end
	current.solid.Transparency = 1
	current.ring.Transparency = 1
	for _, dash in current.dashes do
		dash.Transparency = 1
	end
end

local function placeSegment(part: Part, laneOrigin: CFrame, x1: number, y1: number, x2: number, y2: number, transparency: number)
	local a = LaneGeometry.toWorld(laneOrigin, x1, y1, GUIDE_HEIGHT)
	local b = LaneGeometry.toWorld(laneOrigin, x2, y2, GUIDE_HEIGHT)
	local length = (b - a).Magnitude
	if length < 1e-3 then
		part.Transparency = 1
		return
	end
	part.Size = Vector3.new(GUIDE_WIDTH, GUIDE_THICKNESS, length)
	part.CFrame = CFrame.lookAt((a + b) / 2, b, laneOrigin.UpVector)
	part.Transparency = transparency
end

local function drawGuide(laneOrigin: CFrame, dirX: number, dirY: number)
	local current = getGuide()
	local mx, my = LaneGeometry.muzzle(railX)
	local contacts = AimPreview.solidBounces + AimPreview.dashedBounces
	local path = Ricochet.trace(mx, my, dirX, dirY, stats.radius, contacts, GUIDE_DISTANCE, obstacleProvider())

	-- Solid: muzzle to the first contact (or as far as the path goes).
	local first = path[2]
	if first then
		placeSegment(current.solid, laneOrigin, mx, my, first.x, first.y, 0.15)
	else
		current.solid.Transparency = 1
	end

	-- Ring at the first contact.
	if first and first.kind ~= nil then
		local diameter = stats.radius * 2 + 0.3
		current.ring.Size = Vector3.new(GUIDE_THICKNESS, diameter, diameter)
		current.ring.CFrame = CFrame.new(LaneGeometry.toWorld(laneOrigin, first.x, first.y, GUIDE_HEIGHT))
			* laneOrigin.Rotation
			* CFrame.Angles(0, 0, math.pi / 2)
		current.ring.Transparency = 0.35
	else
		current.ring.Transparency = 1
	end

	-- Dashed: first contact to the second.
	local used = 0
	local second = path[3]
	if first and second and first.kind ~= "Exit" then
		local dx, dy = second.x - first.x, second.y - first.y
		local length = math.sqrt(dx * dx + dy * dy)
		if length > 1e-6 then
			local ux, uy = dx / length, dy / length
			local along = 0
			while along < length and used < MAX_DASHES do
				local finish = math.min(along + DASH_LENGTH, length)
				used += 1
				placeSegment(
					current.dashes[used],
					laneOrigin,
					first.x + ux * along,
					first.y + uy * along,
					first.x + ux * finish,
					first.y + uy * finish,
					0.45
				)
				along = finish + DASH_GAP
			end
		end
	end
	for index = used + 1, MAX_DASHES do
		current.dashes[index].Transparency = 1
	end
end

---------------------------------------------------------------------------------------------
-- Rail movement
---------------------------------------------------------------------------------------------

local function moveAxis(): number
	local keys = keyAxis.right - keyAxis.left
	if keys ~= 0 then
		return keys
	end
	return stickMove
end

local function placeAvatar(laneOrigin: CFrame)
	local character = Players.LocalPlayer.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		return
	end
	local height = humanoid.HipHeight + root.Size.Y / 2
	root.CFrame = laneOrigin * CFrame.new(railX, height, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function sendRail(dt: number)
	sendAccumulator += dt
	local interval = 1 / Rail.sendRateHz
	if sendAccumulator < interval then
		return
	end
	sendAccumulator = 0
	if lastSentX ~= nil and math.abs(railX - lastSentX) < 1e-3 then
		-- At rest: repeat the last position a few times (the remote is unreliable), then stop.
		if restSends >= RAIL_RESENDS_AT_REST then
			return
		end
		restSends += 1
	else
		restSends = 0
	end
	lastSentX = railX
	railSequence += 1
	Network.RailInput:fire({ x = railX, sequence = railSequence })
end

local function updateRail(dt: number, laneOrigin: CFrame)
	local axis = moveAxis()
	if axis ~= 0 then
		railTarget = LaneGeometry.clampRailX(railTarget + axis * Rail.maxSpeed * dt)
	end
	railTarget = LaneGeometry.clampRailX(railTarget)
	local step = Rail.maxSpeed * dt
	railX = LaneGeometry.clampRailX(railX + math.clamp(railTarget - railX, -step, step))
	placeAvatar(laneOrigin)
	sendRail(dt)
end

---------------------------------------------------------------------------------------------
-- Firing
---------------------------------------------------------------------------------------------

local function tryFire(dirX: number, dirY: number): boolean
	if not enabled or origin == nil then
		return false
	end
	local now = os.clock()
	if now - lastFireClock < stats.cooldownSeconds then
		return false
	end
	lastFireClock = now
	local dx, dy = LaneGeometry.clampAim(dirX, dirY)
	local mx, my = LaneGeometry.muzzle(railX)
	shotSequence += 1
	Network.FireProjectile:fire({
		originX = LaneGeometry.clampRailX(railX),
		direction = Vector2.new(dx, dy),
		sequence = shotSequence,
	})
	CombatController.Fired:Fire(shotSequence, mx, my, dx, dy, stats.speed, stats.radius, stats.tint)
	return true
end

-- Aim direction in lane space from a screen-space drag (screen up is up the lane).
local function dragToAim(delta: Vector2): (number, number)
	return LaneGeometry.clampAim(delta.X, -delta.Y)
end

-- Whether the mouse is the pointer in use. Keyboard input keeps the current mode, so moving with
-- A/D does not hide the mouse aim; touch or gamepad input switches it off.
local function updateMouseMode(inputType: Enum.UserInputType)
	if
		inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseWheel
	then
		mouseMode = true
	elseif inputType == Enum.UserInputType.Touch or string.sub(inputType.Name, 1, 7) == "Gamepad" then
		mouseMode = false
	end
end

local function updateMouseAim()
	mouseAiming = false
	if not mouseMode then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	-- GetMouseLocation includes the top bar inset; ScreenPointToRay wants GUI coordinates.
	local inset = GuiService:GetGuiInset()
	local laneX, laneY = LaneCamera.screenToLane(mouse - inset)
	if laneX == nil or laneY == nil then
		return
	end
	local mx, my = LaneGeometry.muzzle(railX)
	local dx, dy = laneX - mx, laneY - my
	if dx * dx + dy * dy < 0.25 then
		return
	end
	aimX, aimY = LaneGeometry.clampAim(dx, dy)
	mouseAiming = true
end

local function update(dt: number)
	local laneOrigin = origin
	if laneOrigin == nil then
		hideGuide()
		return
	end
	if enabled then
		updateRail(dt, laneOrigin)
	else
		placeAvatar(laneOrigin)
	end

	local stick = stickAim
	if stick then
		aimX, aimY = LaneGeometry.clampAim(stick.X, stick.Y)
	end
	updateMouseAim()

	local showing = enabled and (aimActive or stick ~= nil or mouseAiming)
	if showing then
		drawGuide(laneOrigin, aimX, aimY)
	else
		hideGuide()
	end

	if enabled and ((mouseHeld and mouseAiming) or fireHeld) then
		tryFire(aimX, aimY)
	end
end

---------------------------------------------------------------------------------------------
-- Touch
---------------------------------------------------------------------------------------------

local function viewportWidth(): number
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize.X else 1
end

local function onTouchStarted(input: InputObject, processed: boolean)
	if processed or not enabled then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local role: TouchRole = if position.X < viewportWidth() * MOVE_ZONE_FRACTION then "Move" else "Aim"
	for _, other in touches do
		if other.role == role then
			-- One thumb per zone; a second finger in the same zone is ignored.
			return
		end
	end
	touches[input] = { role = role, start = position, startRailX = railTarget, aiming = false }
end

local function onTouchMoved(input: InputObject)
	local touch = touches[input]
	if touch == nil then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local delta = position - touch.start
	if touch.role == "Move" then
		railTarget = LaneGeometry.clampRailX(touch.startRailX + delta.X / LaneCamera.railPixelsPerStud())
	elseif delta.Magnitude >= AIM_DEADZONE_POINTS then
		touch.aiming = true
		aimActive = true
		aimX, aimY = dragToAim(delta)
	elseif touch.aiming then
		-- Dragged back inside the dead zone: releasing here cancels the shot.
		touch.aiming = false
		aimActive = false
	end
end

local function onTouchEnded(input: InputObject)
	local touch = touches[input]
	if touch == nil then
		return
	end
	touches[input] = nil
	if touch.role == "Aim" then
		aimActive = false
		if touch.aiming then
			tryFire(aimX, aimY)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Keyboard, mouse and gamepad
---------------------------------------------------------------------------------------------

local function onMoveAction(actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	local value = if inputState == Enum.UserInputState.Begin then 1 else 0
	if inputState == Enum.UserInputState.Change then
		return Enum.ContextActionResult.Pass
	end
	if actionName == ACTION_LEFT then
		keyAxis.left = value
	else
		keyAxis.right = value
	end
	if value == 0 then
		-- Stop where the avatar is instead of sliding on to the last target.
		railTarget = railX
	end
	return Enum.ContextActionResult.Sink
end

local function onFireAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		fireHeld = true
		tryFire(aimX, aimY)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		fireHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local function onSticks(_actionName: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local released = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		local x = if released then 0 else position.X
		local previous = stickMove
		stickMove = if math.abs(x) >= STICK_DEADZONE then x else 0
		if previous ~= 0 and stickMove == 0 then
			railTarget = railX
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stickAim = if not released and position.Magnitude >= AIM_STICK_DEADZONE then position else nil
	end
	return Enum.ContextActionResult.Sink
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = true
		updateMouseAim()
		if mouseAiming then
			tryFire(aimX, aimY)
		end
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
	end
end

-- Combat bindings exist only while combat is enabled, so the card pick gets the gamepad's A
-- button and the keyboard back.
local function bindActions()
	local priority = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority(ACTION_LEFT, onMoveAction, false, priority, Enum.KeyCode.A, Enum.KeyCode.Left)
	ContextActionService:BindActionAtPriority(ACTION_RIGHT, onMoveAction, false, priority, Enum.KeyCode.D, Enum.KeyCode.Right)
	ContextActionService:BindActionAtPriority(ACTION_FIRE, onFireAction, false, priority, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority(ACTION_STICKS, onSticks, false, priority, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2)
end

local function unbindActions()
	ContextActionService:UnbindAction(ACTION_LEFT)
	ContextActionService:UnbindAction(ACTION_RIGHT)
	ContextActionService:UnbindAction(ACTION_FIRE)
	ContextActionService:UnbindAction(ACTION_STICKS)
end

local function clearInput()
	table.clear(touches)
	aimActive = false
	mouseHeld = false
	fireHeld = false
	keyAxis.left, keyAxis.right = 0, 0
	stickMove = 0
	stickAim = nil
	railTarget = railX
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

function CombatController.init()
	-- The default thumbstick and jump button would sit on top of the move and aim zones.
	GuiService.TouchControlsEnabled = false

	table.insert(connections, UserInputService.TouchStarted:Connect(onTouchStarted))
	table.insert(connections, UserInputService.TouchMoved:Connect(function(input: InputObject, _processed: boolean)
		onTouchMoved(input)
	end))
	table.insert(connections, UserInputService.TouchEnded:Connect(function(input: InputObject, _processed: boolean)
		onTouchEnded(input)
	end))
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, RunService.RenderStepped:Connect(update))
	updateMouseMode(UserInputService:GetLastInputType())
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(updateMouseMode))

	table.insert(connections, Network.LoadoutChanged:connect(function(payload: Network.LoadoutChangedPayload)
		if payload.userId == Players.LocalPlayer.UserId then
			CombatController.setLoadout(payload.modifiers)
		end
	end))
end

-- Turns aiming and firing on or off (off during card picks, pauses and between rooms). The
-- avatar stays pinned to the rail either way.
function CombatController.setEnabled(value: boolean)
	if enabled == value then
		return
	end
	enabled = value
	clearInput()
	if value then
		bindActions()
	else
		unbindActions()
		hideGuide()
	end
end

function CombatController.isEnabled(): boolean
	return enabled
end

-- The lane this player stands in. A new lane (new run) puts the avatar back at the centre.
function CombatController.setLane(laneOrigin: CFrame, resetRail: boolean)
	origin = laneOrigin
	if resetRail then
		railX, railTarget = 0, 0
		lastSentX = nil
		restSends = 0
		clearInput()
	end
end

-- The loadout sets the cooldown, shot size and tint the guide and prediction use.
function CombatController.setLoadout(modifiers: { Network.LoadoutEntry })
	local entries: { ShotStats.LoadoutEntry } = {}
	for _, entry in modifiers do
		table.insert(entries, { id = entry.id, stacks = entry.stacks })
	end
	stats = ShotStats.compute(entries)
end

-- Where the aim guide gets the targets it traces against.
function CombatController.setObstacleProvider(provider: () -> { Ricochet.Obstacle })
	obstacleProvider = provider
end

function CombatController.getRailX(): number
	return railX
end

table.freeze(CombatController)
return CombatController
