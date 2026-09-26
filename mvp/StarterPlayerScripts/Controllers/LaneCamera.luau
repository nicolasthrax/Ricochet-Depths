--!strict
-- The locked tabletop camera (design section 01): Scriptable, pitched 62 degrees down, 32 degree
-- vertical FOV, looking up the lane from behind the rail. No camera input: zoom and rotate are
-- off, so a bounce angle looks the same on every shot. The distance is solved from the viewport
-- every frame, so the whole lane stays in view from 4:3 to 20:9 and through rotations.
--
-- Also maps between the screen and lane space for aiming.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local LaneGeometry = require(ReplicatedStorage.Source.Sim.LaneGeometry)

local CameraConfig = GameConfig.Camera
local Lane = GameConfig.Lane
local World = GameConfig.World

local RENDER_STEP_NAME = "LaneCamera"
-- The lane's length may fill at most this share of the screen height.
local LENGTH_FILL = 0.9
-- The camera looks at this point up the lane (between the apron and the back wall).
local FOCUS_Y = (Lane.length - World.apronDepth * 0.5) / 2

local origin: CFrame? = nil
local pitchDegrees = CameraConfig.pitchDegrees
local easeFrom = CameraConfig.pitchDegrees
local easeElapsed = math.huge
local bound = false

local LaneCamera = {}

-- Camera distance that fits the lane in a viewport of this size at this pitch. The lane's width
-- fills at most GameConfig.Camera.laneScreenWidthFraction of the screen, and its whole length
-- (apron to back wall) always fits.
function LaneCamera.solveDistance(viewport: Vector2, pitch: number): number
	local tanHalfV = math.tan(math.rad(CameraConfig.fovDegrees) / 2)
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local tanHalfH = tanHalfV * aspect
	local width = Lane.halfWidth * 2 + World.wallThickness * 2
	local byWidth = width / (CameraConfig.laneScreenWidthFraction * 2 * tanHalfH)
	local depth = Lane.length + World.apronDepth
	local byLength = depth * math.sin(math.rad(pitch)) / (2 * tanHalfV * LENGTH_FILL)
	return math.max(byWidth, byLength)
end

-- The camera CFrame for a lane origin at this pitch and distance.
function LaneCamera.cframeFor(laneOrigin: CFrame, pitch: number, distance: number): CFrame
	local focus = LaneGeometry.toWorld(laneOrigin, 0, FOCUS_Y, 0)
	local look = laneOrigin.LookVector
	local up = laneOrigin.UpVector
	local radians = math.rad(pitch)
	local viewDirection = look * math.cos(radians) - up * math.sin(radians)
	return CFrame.lookAt(focus - viewDirection * distance, focus, up)
end

local function update(dt: number)
	local laneOrigin = origin
	local camera = Workspace.CurrentCamera
	if laneOrigin == nil or camera == nil then
		return
	end
	if easeElapsed < CameraConfig.introEaseSeconds then
		easeElapsed = math.min(easeElapsed + dt, CameraConfig.introEaseSeconds)
		local alpha = easeElapsed / CameraConfig.introEaseSeconds
		local eased = 1 - (1 - alpha) ^ 3
		pitchDegrees = easeFrom + (CameraConfig.pitchDegrees - easeFrom) * eased
	else
		pitchDegrees = CameraConfig.pitchDegrees
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CameraConfig.fovDegrees
	camera.CFrame = LaneCamera.cframeFor(laneOrigin, pitchDegrees, LaneCamera.solveDistance(camera.ViewportSize, pitchDegrees))
end

-- Locks the camera on a lane. `intro` eases the pitch in from the intro angle, so the pit
-- "opens up" on spawn.
function LaneCamera.setLane(laneOrigin: CFrame, intro: boolean)
	origin = laneOrigin
	if intro then
		easeFrom = CameraConfig.introPitchDegrees
		easeElapsed = 0
	end
	if not bound then
		bound = true
		RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, update)
	end
end

-- Hands the camera back to the default follow camera.
function LaneCamera.release()
	origin = nil
	if bound then
		bound = false
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function LaneCamera.getLane(): CFrame?
	return origin
end

-- The lane-space point on the lane floor under a screen position (GUI coordinates, as
-- InputObject.Position reports them), or nil when the ray misses the floor.
function LaneCamera.screenToLane(screenPosition: Vector2): (number?, number?)
	local laneOrigin = origin
	local camera = Workspace.CurrentCamera
	if laneOrigin == nil or camera == nil then
		return nil, nil
	end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local up = laneOrigin.UpVector
	local denominator = ray.Direction:Dot(up)
	if math.abs(denominator) < 1e-6 then
		return nil, nil
	end
	local distance = (laneOrigin.Position - ray.Origin):Dot(up) / denominator
	if distance < 0 then
		return nil, nil
	end
	return LaneGeometry.toLane(laneOrigin, ray.Origin + ray.Direction * distance)
end

-- Screen pixels per stud across the lane at the rail, for the move strip.
function LaneCamera.railPixelsPerStud(): number
	local laneOrigin = origin
	local camera = Workspace.CurrentCamera
	if laneOrigin == nil or camera == nil then
		return 10
	end
	local left = camera:WorldToScreenPoint(LaneGeometry.toWorld(laneOrigin, -Lane.halfWidth, 0, 0))
	local right = camera:WorldToScreenPoint(LaneGeometry.toWorld(laneOrigin, Lane.halfWidth, 0, 0))
	local pixels = math.abs(right.X - left.X)
	return math.max(pixels / (Lane.halfWidth * 2), 1)
end

table.freeze(LaneCamera)
return LaneCamera
