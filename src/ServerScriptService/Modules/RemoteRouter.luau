-- The single boundary between client requests and run state. Every handler rate limits first,
-- validates types second, and only then hands off to MatchService, which validates again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteGuard = require(script.Parent.RemoteGuard)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local RemoteRouter = {}
RemoteRouter.__index = RemoteRouter

function RemoteRouter.new(match, persistence, onProfileChanged)
	return setmetatable({
		_match = match,
		_persistence = persistence,
		_onProfileChanged = onProfileChanged,
		_guard = RemoteGuard.new(RunConfig.RemoteRules),
		_connections = {},
	}, RemoteRouter)
end

function RemoteRouter:_connect(remoteName, action, handler)
	local remote = Remotes.Get(remoteName)
	local connection = remote.OnServerEvent:Connect(function(player, ...)
		local now = os.clock()
		if not self._guard:Check(player, action, now) then
			return
		end
		handler(player, now, ...)
	end)
	table.insert(self._connections, connection)
end

function RemoteRouter:Bind()
	self:_connect("FireProjectile", "Fire", function(player, now, direction, power)
		self._match:HandleFire(player, direction, power, now)
	end)

	self:_connect("ChooseUpgrade", "ChooseUpgrade", function(player, now, offerId, cardId)
		self._match:ChooseUpgrade(player, offerId, cardId, now)
	end)

	self:_connect("RequestStartRun", "RequestStartRun", function(player, now)
		self._match:RequestStart(player, now)
	end)

	self:_connect("RequestReturnToLobby", "RequestReturnToLobby", function(player, now)
		self._match:RequestReturnToLobby(player, now)
	end)

	self:_connect("UpdateSettings", "UpdateSettings", function(player, _now, settings)
		if not self._persistence or type(settings) ~= "table" then
			return
		end
		if self._persistence:ApplySettings(player, settings) and self._onProfileChanged then
			self._onProfileChanged(player)
		end
	end)
end

function RemoteRouter:ClearPlayer(player)
	self._guard:Clear(player)
end

function RemoteRouter:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._guard:ClearAll()
end

return RemoteRouter
