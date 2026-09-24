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
		-- options.meta (MetaService) and options.onMetaResult(player, kind, result, reason):
		-- daily rewards, quests and codes. Without them those remotes are never bound.
		_meta = options and options.meta,
		_onMetaResult = options and options.onMetaResult,
		-- options.loadout (LoadoutService) and options.onLoadoutResult(player, kind, result, reason):
		-- rigs, the Depth Pact and achievements. Without them those remotes are never bound.
		_loadout = options and options.loadout,
		_onLoadoutResult = options and options.onLoadoutResult,
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

	self:_connect("Dash", "Dash", function(player, now, direction)
		local match = self._matchFor(player)
		if match and match.HandleDash then
			match:HandleDash(player, typeof(direction) == "Vector3" and direction or nil, now)
		end
	end)

	self:_connect("ChooseSurge", "ChooseSurge", function(player, now, offerId, cardId)
		local match = self._matchFor(player)
		if match and match.ChooseSurge then
			match:ChooseSurge(player, offerId, cardId, now)
		end
	end)

	self:_connect("ChooseDoor", "ChooseDoor", function(player, now, doorId)
		local match = self._matchFor(player)
		if match and match.ChooseDoor then
			match:ChooseDoor(player, doorId, now)
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

	if self._meta and self._onMetaResult then
		self:_connect("ClaimDaily", "ClaimDaily", function(player)
			local result, reason = self._meta:ClaimDaily(player)
			self._onMetaResult(player, "Daily", result, reason)
		end)
		self:_connect("ClaimQuest", "ClaimQuest", function(player, _now, questId)
			local result, reason = self._meta:ClaimQuest(player, type(questId) == "string" and questId or nil)
			self._onMetaResult(player, "Quest", result, reason)
		end)
		self:_connect("RedeemCode", "RedeemCode", function(player, _now, code)
			local result, reason = self._meta:RedeemCode(player, type(code) == "string" and code or nil)
			self._onMetaResult(player, "Code", result, reason)
		end)
		self:_connect("RequestMeta", "RequestMeta", function(player)
			self._onMetaResult(player, "Sync", nil, nil)
		end)
	end

	if self._loadout and self._onLoadoutResult then
		self:_connect("SelectRig", "SelectRig", function(player, _now, rigId)
			local result, reason = self._loadout:SelectRig(player, type(rigId) == "string" and rigId or nil)
			self._onLoadoutResult(player, "Rig", result, reason)
		end)
		self:_connect("SetPact", "SetPact", function(player, _now, pact)
			local result, reason = self._loadout:SetPact(player, type(pact) == "table" and pact or nil)
			self._onLoadoutResult(player, "Pact", result, reason)
		end)
		self:_connect("ClaimAchievement", "ClaimAchievement", function(player, _now, achievementId)
			local id = type(achievementId) == "string" and achievementId or nil
			local result, reason = self._loadout:ClaimAchievement(player, id)
			self._onLoadoutResult(player, "Achievement", result, reason)
		end)
	end

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
