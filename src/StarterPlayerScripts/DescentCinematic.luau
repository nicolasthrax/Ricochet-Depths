-- The descent: when a run starts (and between rooms) the camera falls down a glowing shaft in the
-- next zone's colour, the screen fades to black as the room loads, and the room fades in under a
-- title card. Built once on this client, far from any arena. While it plays it sets the
-- "Cinematic" attribute, and CameraController stands aside.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DescentPlan = require(script.Parent.DescentPlan)
local UiConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("UiConfig"))

local DescentCinematic = {}
DescentCinematic.__index = DescentCinematic

local SHAFT_TOP = Vector3.new(-3000, 400, 0)
local DEPTH = 160
local RING_COUNT = 16
local RING_SEGMENTS = 10
local RING_RADIUS = 12
local MOTES = 40
local RENDER_STEP = "RicochetDescent"
local TITLE_SECONDS = 2.2

local ZONE_COLORS = {
	Ruins = Color3.fromRGB(150, 190, 255),
	Foundry = Color3.fromRGB(255, 150, 70),
	Abyss = Color3.fromRGB(190, 120, 255),
}

local player = Players.LocalPlayer

local function neon(parent, name, size, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

function DescentCinematic.new(playerGui)
	local self = setmetatable({ _glow = {}, _token = 0 }, DescentCinematic)

	-- The shaft: rings of glowing segments, and motes drifting in the dark between them.
	local shaft = Instance.new("Folder")
	shaft.Name = "DescentShaft"
	shaft.Parent = workspace
	local random = Random.new(7)
	for ring = 0, RING_COUNT - 1 do
		local y = SHAFT_TOP.Y - ring * (DEPTH / RING_COUNT) - 6
		for segment = 1, RING_SEGMENTS do
			local angle = segment * math.pi * 2 / RING_SEGMENTS + ring * 0.3
			local position = Vector3.new(SHAFT_TOP.X + math.cos(angle) * RING_RADIUS, y, SHAFT_TOP.Z + math.sin(angle) * RING_RADIUS)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			table.insert(self._glow, neon(shaft, "Ring", Vector3.new(0.6, 0.6, 7.2), CFrame.lookAlong(position, tangent)))
		end
	end
	for index = 1, MOTES do
		local angle = random:NextNumber() * math.pi * 2
		local radius = random:NextNumber() * (RING_RADIUS - 3)
		local position = Vector3.new(
			SHAFT_TOP.X + math.cos(angle) * radius,
			SHAFT_TOP.Y - random:NextNumber() * DEPTH,
			SHAFT_TOP.Z + math.sin(angle) * radius
		)
		local mote = neon(shaft, "Mote" .. index, Vector3.new(0.3, 0.3, 0.3), CFrame.new(position))
		mote.Shape = Enum.PartType.Ball
		table.insert(self._glow, mote)
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RicochetDescent"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Parent = playerGui

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Parent = gui
	self._fade = fade

	local function text(name, y, size, color)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.new(0.8, 0, 0, size)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.5
		label.TextTransparency = 1
		label.Text = ""
		label.Parent = gui
		return label
	end
	self._title = text("Title", 0.38, 46, UiConfig.Colors.Text)
	self._subtitle = text("Subtitle", 0.45, 26, UiConfig.Colors.Accent)
	return self
end

function DescentCinematic:_setZone(zone)
	local color = ZONE_COLORS[zone] or ZONE_COLORS.Ruins
	for _, part in self._glow do
		part.Color = color
	end
end

function DescentCinematic:_stopPlunge()
	RunService:UnbindFromRenderStep(RENDER_STEP)
end

function DescentCinematic:_plunge(action)
	self._token += 1
	self:_stopPlunge()
	self:_setZone(action.Zone)
	player:SetAttribute("Cinematic", true)
	self._title.Text = action.Text
	self._subtitle.Text = ""

	local camera = workspace.CurrentCamera
	local started = os.clock()
	local comfort = player:GetAttribute("ScreenShake")
	local rollScale = type(comfort) == "number" and comfort or 1
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 2, function()
		local t = os.clock() - started
		local shot = DescentPlan.CameraAt(t, action.Duration, SHAFT_TOP, DEPTH)
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAlong(shot.position, shot.look) * CFrame.Angles(0, 0, shot.roll * rollScale)
		end
		self._fade.BackgroundTransparency = 1 - shot.fade
		-- The caption shows through the middle of the fall.
		local captionAlpha = math.clamp(math.min(t / 0.4, (action.Duration - t) / 0.4), 0, 1)
		self._title.TextTransparency = 1 - captionAlpha
		if t >= action.Duration then
			-- Hold on black until the room arrives.
			self._fade.BackgroundTransparency = 0
			self._title.TextTransparency = 1
			self:_stopPlunge()
		end
	end)
end

function DescentCinematic:_arrive(action)
	self._token += 1
	local token = self._token
	self:_stopPlunge()
	player:SetAttribute("Cinematic", false)

	self._fade.BackgroundTransparency = 0
	TweenService:Create(self._fade, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
	self._title.Text = action.Title
	self._subtitle.Text = action.Subtitle
	self._title.TextTransparency = 0
	self._subtitle.TextTransparency = 0
	task.delay(TITLE_SECONDS, function()
		if self._token == token then
			local info = TweenInfo.new(0.6)
			TweenService:Create(self._title, info, { TextTransparency = 1 }):Play()
			TweenService:Create(self._subtitle, info, { TextTransparency = 1 }):Play()
		end
	end)
end

-- Clears everything: the run ended or was left mid-cinematic.
function DescentCinematic:Reset()
	self._token += 1
	self:_stopPlunge()
	player:SetAttribute("Cinematic", false)
	self._fade.BackgroundTransparency = 1
	self._title.TextTransparency = 1
	self._subtitle.TextTransparency = 1
end

-- Called with each run snapshot, and the state before it.
function DescentCinematic:OnRunState(previous, snapshot)
	local action = DescentPlan.For(previous, snapshot)
	if action and action.Kind == "Plunge" then
		self:_plunge(action)
	elseif action and action.Kind == "Arrive" then
		self:_arrive(action)
	elseif snapshot.State == "Lobby" or snapshot.State == "Results" then
		if player:GetAttribute("Cinematic") then
			self:Reset()
		end
	end
end

return DescentCinematic
