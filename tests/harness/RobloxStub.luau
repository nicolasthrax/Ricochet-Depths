-- Minimal Roblox API stub so production modules can run under the plain Luau CLI.
-- Only what the project actually touches is modelled; anything missing should be added here
-- rather than worked around in game code.

--// Virtual clock. The bundler rewrites os.clock() in game sources to __clock().
local clockValue = 0
function __clock()
	return clockValue
end

--// Signal ------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new(name)
	return setmetatable({ _name = name, _handlers = {} }, Signal)
end

function Signal:Connect(handler)
	local connection = { Connected = true, _handler = handler, _signal = self }
	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		local handlers = self._signal._handlers
		for index, candidate in handlers do
			if candidate == self then
				table.remove(handlers, index)
				break
			end
		end
	end
	connection.disconnect = connection.Disconnect
	table.insert(self._handlers, connection)
	return connection
end

Signal.Once = function(self, handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	local snapshot = table.clone(self._handlers)
	for _, connection in snapshot do
		if connection.Connected then
			connection._handler(...)
		end
	end
end

function Signal:CountHandlers()
	return #self._handlers
end

__Signal = Signal

--// Vector3 -----------------------------------------------------------------
local Vector3Mt = { __robloxType = "Vector3" }

local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, Vector3Mt)
end

Vector3Mt.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local magnitude = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if magnitude == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	elseif key == "Lerp" then
		return function(a, b, alpha)
			return v3(a.X + (b.X - a.X) * alpha, a.Y + (b.Y - a.Y) * alpha, a.Z + (b.Z - a.Z) * alpha)
		end
	elseif key == "Cross" then
		return function(a, b)
			return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
		end
	end
	return nil
end
Vector3Mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
Vector3Mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3Mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3Mt.__tostring = function(a)
	return string.format("Vector3(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z)
end

Vector3 = {
	new = function(x, y, z)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

--// Vector2 -----------------------------------------------------------------
local Vector2Mt = { __robloxType = "Vector2" }
local function v2(x, y)
	return setmetatable({ X = x, Y = y }, Vector2Mt)
end
Vector2Mt.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	elseif key == "Unit" then
		local magnitude = math.sqrt(self.X * self.X + self.Y * self.Y)
		return v2(self.X / magnitude, self.Y / magnitude)
	end
	return nil
end
Vector2Mt.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
Vector2Mt.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
Vector2Mt.__unm = function(a)
	return v2(-a.X, -a.Y)
end
Vector2Mt.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
Vector2Mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2 = {
	new = function(x, y)
		return v2(x or 0, y or 0)
	end,
	zero = v2(0, 0),
	one = v2(1, 1),
}

--// Color3 / UDim / UDim2 / CFrame ------------------------------------------
local Color3Mt = { __robloxType = "Color3" }
Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Mt)
	end,
}
Color3.fromRGB = function(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

local UDimMt = { __robloxType = "UDim" }
UDim = {
	new = function(scale, offset)
		return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDimMt)
	end,
}

local UDim2Mt = { __robloxType = "UDim2" }
UDim2 = {
	new = function(xs, xo, ys, yo)
		return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UDim2Mt)
	end,
}
UDim2.fromScale = function(x, y)
	return UDim2.new(x, 0, y, 0)
end
UDim2.fromOffset = function(x, y)
	return UDim2.new(0, x, 0, y)
end

local CFrameMt = { __robloxType = "CFrame" }
CFrameMt.__index = function(self, key)
	if key == "Position" or key == "p" then
		return rawget(self, "_position")
	elseif key == "LookVector" then
		return rawget(self, "_look")
	elseif key == "RightVector" then
		return rawget(self, "_right")
	elseif key == "UpVector" then
		return rawget(self, "_up")
	end
	return nil
end
local function makeCFrame(position, look, right, up)
	return setmetatable({
		_position = position,
		_look = look or v3(0, 0, -1),
		_right = right or v3(1, 0, 0),
		_up = up or v3(0, 1, 0),
	}, CFrameMt)
end
CFrame = {
	new = function(x, y, z)
		if typeof and type(x) == "table" then
			return makeCFrame(x)
		end
		return makeCFrame(v3(x or 0, y or 0, z or 0))
	end,
	identity = makeCFrame(v3(0, 0, 0)),
}
CFrame.lookAlong = function(position, direction)
	local look = direction.Magnitude > 0 and direction.Unit or v3(0, 0, -1)
	return makeCFrame(position, look)
end
CFrame.lookAt = function(position, target)
	return CFrame.lookAlong(position, target - position)
end

--// Enum --------------------------------------------------------------------
local function makeEnumType(typeName)
	return setmetatable({}, {
		__index = function(self, itemName)
			local item = setmetatable(
				{ Name = itemName, Value = itemName, EnumType = typeName },
				{ __robloxType = "EnumItem", __tostring = function()
					return "Enum." .. typeName .. "." .. itemName
				end }
			)
			rawset(self, itemName, item)
			return item
		end,
	})
end

Enum = setmetatable({}, {
	__index = function(self, typeName)
		local enumType = makeEnumType(typeName)
		rawset(self, typeName, enumType)
		return enumType
	end,
})

--// Instance ----------------------------------------------------------------
local InstanceMethods = {}

local function detach(instance)
	local parent = rawget(instance, "Parent")
	if not parent then
		return
	end
	local siblings = rawget(parent, "_children")
	for index, child in siblings do
		if child == instance then
			table.remove(siblings, index)
			break
		end
	end
	rawget(parent, "_byName")[rawget(instance, "Name")] = nil
	for _, child in siblings do
		if rawget(child, "Name") == rawget(instance, "Name") then
			rawget(parent, "_byName")[rawget(child, "Name")] = child
			break
		end
	end
end

local function attach(instance, parent)
	rawset(instance, "Parent", parent)
	if not parent then
		return
	end
	table.insert(rawget(parent, "_children"), instance)
	local byName = rawget(parent, "_byName")
	local name = rawget(instance, "Name")
	if byName[name] == nil then
		byName[name] = instance
	end
	local waiters = rawget(parent, "_waiters")[name]
	if waiters then
		rawget(parent, "_waiters")[name] = nil
		for _, resolve in waiters do
			resolve(instance)
		end
	end
end

function InstanceMethods:FindFirstChild(name)
	return rawget(self, "_byName")[name]
end

function InstanceMethods:WaitForChild(name)
	local existing = rawget(self, "_byName")[name]
	if existing then
		return existing
	end
	error(("WaitForChild(%q) on %s would yield forever in tests; create it first")
		:format(name, tostring(rawget(self, "Name"))), 2)
end

function InstanceMethods:FindFirstChildOfClass(className)
	for _, child in rawget(self, "_children") do
		if rawget(child, "ClassName") == className then
			return child
		end
	end
	return nil
end

function InstanceMethods:FindFirstChildWhichIsA(className)
	return InstanceMethods.FindFirstChildOfClass(self, className)
end

function InstanceMethods:GetChildren()
	return table.clone(rawget(self, "_children"))
end

function InstanceMethods:GetDescendants()
	local out = {}
	for _, child in rawget(self, "_children") do
		table.insert(out, child)
		for _, nested in InstanceMethods.GetDescendants(child) do
			table.insert(out, nested)
		end
	end
	return out
end

function InstanceMethods:IsA(className)
	local own = rawget(self, "ClassName")
	if own == className then
		return true
	end
	local basePartClasses = { Part = true, SpawnLocation = true, MeshPart = true, WedgePart = true }
	if className == "BasePart" then
		return basePartClasses[own] == true
	end
	if className == "Instance" then
		return true
	end
	return false
end

function InstanceMethods:ClearAllChildren()
	for _, child in table.clone(rawget(self, "_children")) do
		InstanceMethods.Destroy(child)
	end
end

function InstanceMethods:Destroy()
	InstanceMethods.ClearAllChildren(self)
	detach(self)
	rawset(self, "Parent", nil)
	rawset(self, "_destroyed", true)
	__instanceCount -= 1
end

function InstanceMethods:GetAttribute(name)
	return rawget(self, "_attributes")[name]
end

function InstanceMethods:SetAttribute(name, value)
	rawget(self, "_attributes")[name] = value
end

function InstanceMethods:Clone()
	local copy = Instance.new(rawget(self, "ClassName"))
	for key, value in pairs(self) do
		if key:sub(1, 1) ~= "_" and key ~= "Parent" then
			rawset(copy, key, value)
		end
	end
	for _, child in rawget(self, "_children") do
		local childCopy = InstanceMethods.Clone(child)
		attach(childCopy, copy)
	end
	return copy
end

local instanceMt = {
	__robloxType = "Instance",
	__index = function(self, key)
		local method = InstanceMethods[key]
		if method then
			return method
		end
		local child = rawget(self, "_byName")[key]
		if child then
			return child
		end
		return nil
	end,
	__newindex = function(self, key, value)
		if key == "CFrame" then
			-- In the engine these are the same property; game code sets CFrame to move a part
			-- and other code reads Position back. Keeping them in step matters for teleports.
			rawset(self, "CFrame", value)
			local position = type(value) == "table" and rawget(value, "_position") or nil
			if position then
				rawset(self, "Position", position)
			end
			return
		elseif key == "Parent" then
			detach(self)
			attach(self, value)
			return
		elseif key == "Name" then
			local parent = rawget(self, "Parent")
			if parent then
				detach(self)
				rawset(self, "Name", value)
				attach(self, parent)
				return
			end
		end
		rawset(self, key, value)
	end,
	__tostring = function(self)
		return rawget(self, "Name") or rawget(self, "ClassName")
	end,
}

__instanceCount = 0

local remoteClasses = { RemoteEvent = true, UnreliableRemoteEvent = true, RemoteFunction = true }

Instance = {}
function Instance.new(className, parent)
	local instance = setmetatable({}, instanceMt)
	rawset(instance, "ClassName", className)
	rawset(instance, "Name", className)
	rawset(instance, "_children", {})
	rawset(instance, "_byName", {})
	rawset(instance, "_waiters", {})
	rawset(instance, "_attributes", {})
	rawset(instance, "Parent", nil)
	rawset(instance, "AncestryChanged", Signal.new("AncestryChanged"))
	rawset(instance, "ChildAdded", Signal.new("ChildAdded"))
	rawset(instance, "Destroying", Signal.new("Destroying"))

	if className == "Part" or className == "SpawnLocation" or className == "MeshPart" then
		rawset(instance, "Position", Vector3.zero)
		rawset(instance, "Size", Vector3.one)
		rawset(instance, "CFrame", CFrame.new(0, 0, 0))
		rawset(instance, "AssemblyLinearVelocity", Vector3.zero)
		rawset(instance, "Anchored", false)
		rawset(instance, "CanCollide", true)
		rawset(instance, "Transparency", 0)
		rawset(instance, "Touched", Signal.new("Touched"))
	elseif remoteClasses[className] then
		rawset(instance, "OnServerEvent", Signal.new("OnServerEvent"))
		rawset(instance, "OnClientEvent", Signal.new("OnClientEvent"))
		rawset(instance, "_fired", {})
		rawset(instance, "FireClient", function(self, player, ...)
			table.insert(rawget(self, "_fired"), { player = player, args = table.pack(...) })
		end)
		rawset(instance, "FireAllClients", function(self, ...)
			table.insert(rawget(self, "_fired"), { player = "all", args = table.pack(...) })
			rawget(self, "OnClientEvent"):Fire(...)
		end)
		rawset(instance, "FireServer", function(self, ...)
			rawget(self, "OnServerEvent"):Fire(__localPlayer, ...)
		end)
	end

	__instanceCount += 1
	if parent then
		instance.Parent = parent
	end
	return instance
end

--// typeof ------------------------------------------------------------------
local rawTypeof = typeof
function typeof(value)
	if type(value) == "table" then
		local mt = getmetatable(value)
		if mt and rawget(mt, "__robloxType") then
			return rawget(mt, "__robloxType")
		end
	end
	return rawTypeof(value)
end

--// Random ------------------------------------------------------------------
local RandomMt = { __robloxType = "Random" }
RandomMt.__index = RandomMt

function RandomMt:NextNumber(minimum, maximum)
	-- Deterministic LCG; only needs to be repeatable, not statistically strong.
	self._state = (1103515245 * self._state + 12345) % 2147483648
	local unit = self._state / 2147483648
	if minimum and maximum then
		return minimum + unit * (maximum - minimum)
	end
	return unit
end

function RandomMt:NextInteger(minimum, maximum)
	return math.floor(self:NextNumber() * (maximum - minimum + 1)) + minimum
end

function RandomMt:Clone()
	return setmetatable({ _state = self._state }, RandomMt)
end

Random = {
	new = function(seed)
		return setmetatable({ _state = (seed or 0) % 2147483648 }, RandomMt)
	end,
}

--// Raycasting --------------------------------------------------------------
RaycastParams = {}
function RaycastParams.new()
	return setmetatable({
		FilterType = nil,
		FilterDescendantsInstances = {},
		IgnoreWater = false,
		RespectCanCollide = false,
	}, { __robloxType = "RaycastParams" })
end

--// Services ----------------------------------------------------------------
local services = {}
local function makeService(className)
	local service = Instance.new(className)
	rawset(service, "Name", className)
	services[className] = service
	return service
end

local runServiceStub = makeService("RunService")
rawset(runServiceStub, "Heartbeat", Signal.new("Heartbeat"))
rawset(runServiceStub, "RenderStepped", Signal.new("RenderStepped"))
rawset(runServiceStub, "Stepped", Signal.new("Stepped"))
rawset(runServiceStub, "PostSimulation", Signal.new("PostSimulation"))
rawset(runServiceStub, "IsServer", function()
	return __isServer ~= false
end)
rawset(runServiceStub, "IsClient", function()
	return __isServer == false
end)
rawset(runServiceStub, "IsStudio", function()
	return true
end)
__isServer = true

local playersStub = makeService("Players")
rawset(playersStub, "PlayerAdded", Signal.new("PlayerAdded"))
rawset(playersStub, "PlayerRemoving", Signal.new("PlayerRemoving"))
rawset(playersStub, "GetPlayers", function(self)
	local out = {}
	for _, child in rawget(self, "_children") do
		if rawget(child, "ClassName") == "Player" then
			table.insert(out, child)
		end
	end
	return out
end)

makeService("ReplicatedStorage")
makeService("ServerScriptService")
makeService("ServerStorage")
makeService("StarterPlayer")
makeService("Lighting")
makeService("TweenService")
makeService("HttpService")
makeService("DataStoreService")
makeService("MessagingService")
makeService("TextService")
makeService("UserInputService")
makeService("ContextActionService")
makeService("SoundService")
makeService("CollectionService")
makeService("AnalyticsService")
makeService("MemStorageService")

local workspaceStub = makeService("Workspace")
rawset(workspaceStub, "Gravity", 196.2)
rawset(workspaceStub, "CurrentCamera", Instance.new("Camera"))
-- Tests install a world model here: function(origin, direction, params) -> result | nil
__raycastHandler = nil
rawset(workspaceStub, "Raycast", function(self, origin, direction, params)
	if __raycastHandler then
		return __raycastHandler(origin, direction, params)
	end
	return nil
end)
workspace = workspaceStub

game = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, className)
				local service = services[className]
				if not service then
					service = makeService(className)
				end
				return service
			end
		elseif key == "BindToClose" then
			return function(_, callback)
				table.insert(__bindToClose, callback)
			end
		elseif key == "PlaceId" then
			return 0
		elseif key == "JobId" then
			return "test-job"
		end
		return services[key]
	end,
})
__bindToClose = {}
__services = services

--// task ----------------------------------------------------------------------
-- A deterministic cooperative scheduler, so code that yields actually yields.
--
-- The earlier stub ran task.spawn synchronously and made task.wait return at once, so no two
-- threads could ever interleave. Any bug that needs one thread to be suspended while another
-- runs, such as a save still waiting on the DataStore when the next change arrives, was
-- invisible. Here:
--
--   * task.spawn resumes the new thread immediately and returns when it first yields, as in
--     the engine.
--   * task.wait inside a spawned thread suspends it until the virtual clock reaches its wake
--     time. On the main test thread, which cannot yield, it lets the time pass instead and runs
--     every thread that falls due meanwhile, which is what the engine does for other threads
--     while one is blocked.
--   * Threads wake in (time, then scheduling order) order, so every run is reproducible.
--   * An error in a spawned thread is recorded, and fails the test that caused it.

local queue = {}
local sequence = 0
local taskErrors = {}

local function enqueue(at, thread, ...)
	sequence += 1
	table.insert(queue, { at = at, seq = sequence, thread = thread, args = table.pack(...) })
end

local function resumeThread(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(taskErrors, tostring(err))
	end
end

local function popDue(limit)
	local bestIndex
	for index, entry in queue do
		if entry.at <= limit then
			local best = bestIndex and queue[bestIndex]
			if not best or entry.at < best.at or (entry.at == best.at and entry.seq < best.seq) then
				bestIndex = index
			end
		end
	end
	return bestIndex and table.remove(queue, bestIndex) or nil
end

-- Wakes every thread due at or before limit, moving the clock to each wake time in turn.
local function runUntil(limit)
	while true do
		local entry = popDue(limit)
		if not entry then
			break
		end
		if entry.at > clockValue then
			clockValue = entry.at
		end
		resumeThread(entry.thread, table.unpack(entry.args, 1, entry.args.n))
	end
	if limit > clockValue then
		clockValue = limit
	end
end

-- The engine's frame length, used when task.wait is called with no duration.
local FRAME = 1 / 60

-- The CLI runs the test script itself inside a coroutine, so isyieldable() is true even on the
-- main test thread. Yielding it would suspend the whole run, so it is identified explicitly.
local mainThread = coroutine.running()

local function canSuspend()
	return coroutine.running() ~= mainThread and coroutine.isyieldable()
end

-- task.* accepts either a function or an existing thread.
local function asThread(target)
	if type(target) == "thread" then
		return target
	end
	return coroutine.create(target :: any)
end

task = {
	spawn = function(target, ...)
		local thread = asThread(target)
		resumeThread(thread, ...)
		return thread
	end,
	defer = function(target, ...)
		local thread = asThread(target)
		enqueue(clockValue, thread, ...)
		return thread
	end,
	delay = function(seconds, target, ...)
		local thread = asThread(target)
		enqueue(clockValue + (seconds or 0), thread, ...)
		return thread
	end,
	wait = function(seconds)
		local duration = seconds or FRAME
		local startedAt = clockValue
		if canSuspend() then
			enqueue(clockValue + duration, coroutine.running())
			coroutine.yield()
		else
			runUntil(clockValue + duration)
		end
		return clockValue - startedAt
	end,
	cancel = function(thread)
		for index = #queue, 1, -1 do
			if queue[index].thread == thread then
				table.remove(queue, index)
			end
		end
	end,
}
wait = task.wait

--// Harness driver ----------------------------------------------------------
Harness = {}

function Harness.now()
	return clockValue
end

-- Jumps the clock without waking anything. Tests that manage time by hand use this.
function Harness.setClock(value)
	clockValue = value
end

-- Lets `seconds` of virtual time pass, waking every thread that falls due.
function Harness.advance(seconds)
	runUntil(clockValue + seconds)
end

-- Runs until no thread is waiting, or maxSeconds of virtual time have passed. Stops at the
-- last wake time rather than jumping to the limit.
function Harness.settle(maxSeconds)
	local limit = clockValue + (maxSeconds or 120)
	while #queue > 0 do
		local nextAt = math.huge
		for _, entry in queue do
			nextAt = math.min(nextAt, entry.at)
		end
		if nextAt > limit then
			break
		end
		runUntil(nextAt)
	end
	return #queue
end

function Harness.pendingThreads()
	return #queue
end

-- Errors raised inside spawned threads since the last call. The runner fails a test that
-- leaves any behind; a test that expects one can take it here first.
function Harness.takeTaskErrors()
	local errors = taskErrors
	taskErrors = {}
	return errors
end

-- Called by the runner before each test so one test's sleeping threads cannot wake in another.
function Harness.resetScheduler()
	table.clear(queue)
	taskErrors = {}
end

-- Advances the virtual clock and fires Heartbeat exactly as Roblox would.
function Harness.step(deltaTime, steps)
	for _ = 1, steps or 1 do
		runUntil(clockValue + deltaTime)
		runServiceStub.Heartbeat:Fire(deltaTime)
	end
end

function Harness.stepSeconds(seconds, deltaTime)
	local dt = deltaTime or 1 / 60
	Harness.step(dt, math.max(1, math.floor(seconds / dt + 0.5)))
end

function Harness.service(name)
	return services[name] or game:GetService(name)
end

function Harness.instanceCount()
	return __instanceCount
end

local playerCounter = 0
function Harness.addPlayer(name)
	playerCounter += 1
	local player = Instance.new("Player")
	rawset(player, "Name", name or ("Tester" .. playerCounter))
	rawset(player, "UserId", 1000 + playerCounter)
	rawset(player, "CharacterAdded", Signal.new("CharacterAdded"))
	rawset(player, "CharacterRemoving", Signal.new("CharacterRemoving"))
	rawset(player, "Kick", function() end)
	player.Parent = playersStub
	playersStub.PlayerAdded:Fire(player)
	return player
end

function Harness.removePlayer(player)
	playersStub.PlayerRemoving:Fire(player)
	player:Destroy()
end

-- Builds a character model with the parts the server validates against.
function Harness.giveCharacter(player, position)
	local character = Instance.new("Model")
	character.Name = rawget(player, "Name")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = position or Vector3.new(0, 3, 0)
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	humanoid.Parent = character
	character.Parent = workspace
	rawset(player, "Character", character)
	rawget(player, "CharacterAdded"):Fire(character)
	return character
end
