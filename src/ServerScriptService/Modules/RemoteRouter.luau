-- The single boundary between client requests and run state. Every handler rate limits first,
-- validates types second, and only then hands off to MatchService, which validates again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteGuard = require(script.Parent.RemoteGuard)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local RemoteRouter = {}
RemoteRouter.__index = RemoteRouter

-- `match` is either one MatchService or a function player -> MatchService (or nil while that
-- player is in the lobby), for servers running several arenas. shop is optional; without it the
-- shop remotes are never bound. options.onStartRequest(player, now), when given, handles a
-- client's start request instead of the match (the solo portal's server-side path).
function RemoteRouter.new(match, persistence, onProfileChanged, shop, options)
	local resolve = match
	if type(match) ~= "function" then
		resolve = function()
			return match
		end
	end
	return setmetatable({
		_matchFor = resolve,
		_onStartRequest = options and options.onStartRequest,
		_persistence = persistence,
		_onProfileChanged = onProfileChanged,
		_shop = shop,
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
		local match = self._matchFor(player)
		if match then
			match:HandleFire(player, direction, power, now)
		end
	end)

	self:_connect("ChooseUpgrade", "ChooseUpgrade", function(player, now, offerId, cardId)
		local match = self._matchFor(player)
		if match then
			match:ChooseUpgrade(player, offerId, cardId, now)
		end
	end)

	self:_connect("RequestStartRun", "RequestStartRun", function(player, now)
		if self._onStartRequest then
			self._onStartRequest(player, now)
			return
		end
		local match = self._matchFor(player)
		if match then
			match:RequestStart(player, now)
		end
	end)

	self:_connect("RequestReturnToLobby", "RequestReturnToLobby", function(player, now)
		local match = self._matchFor(player)
		if match then
			match:RequestReturnToLobby(player, now)
		end
	end)

	self:_connect("UpdateSettings", "UpdateSettings", function(player, _now, settings)
		if not self._persistence or type(settings) ~= "table" then
			return
		end
		if self._persistence:ApplySettings(player, settings) and self._onProfileChanged then
			self._onProfileChanged(player)
		end
	end)

	if self._shop then
		local shopResult = Remotes.Get("ShopResult")
		self:_connect("PurchaseShopItem", "PurchaseShopItem", function(player, now, itemId)
			local ok, result = self._shop:Purchase(player, itemId, now)
			shopResult:FireClient(player, {
				Ok = ok,
				Action = "Purchase",
				ItemId = type(itemId) == "string" and itemId or nil,
				Level = ok and result.Level or nil,
				Reason = not ok and result or nil,
			})
		end)
		self:_connect("EquipShopItem", "EquipShopItem", function(player, now, itemId)
			local ok, reason = self._shop:Equip(player, itemId, now)
			shopResult:FireClient(player, {
				Ok = ok,
				Action = "Equip",
				ItemId = type(itemId) == "string" and itemId or nil,
				Reason = reason,
			})
		end)
	end
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
