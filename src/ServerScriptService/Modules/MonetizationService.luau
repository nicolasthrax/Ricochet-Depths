-- Game passes and coin packs. Pass ownership is read when a player joins (and updated when they
-- buy one in-game) and turns into run bonuses. Coin packs are paid through the profile's grant
-- ledger keyed by the receipt's PurchaseId, and only confirmed to Roblox once saved, so a
-- receipt pays exactly once however often Roblox delivers it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local MonetizationService = {}
MonetizationService.__index = MonetizationService

local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet

-- options: marketplace (MarketplaceService or a stand-in), persistence, config (default
-- MonetizationConfig), getPlayer(userId), onChanged(player).
function MonetizationService.new(options)
	return setmetatable({
		_marketplace = options.marketplace,
		_persistence = options.persistence,
		_config = options.config or MonetizationConfig,
		_getPlayer = options.getPlayer,
		_onChanged = options.onChanged,
		_owned = {}, -- player -> { [passKey] = true }
	}, MonetizationService)
end

local function configured(entry)
	return type(entry.Id) == "number" and entry.Id > 0
end

-- What the Store tab offers: only passes and products with real ids.
function MonetizationService:Catalogue()
	local passes, products = {}, {}
	for key, pass in self._config.Passes do
		if configured(pass) then
			table.insert(passes, { Key = key, Id = pass.Id, Title = pass.Title, Description = pass.Description })
		end
	end
	table.sort(passes, function(a, b)
		return a.Key < b.Key
	end)
	for _, product in self._config.Products do
		if configured(product) then
			table.insert(products, { Key = product.Key, Id = product.Id, Title = product.Title, Coins = product.Coins })
		end
	end
	return { Passes = passes, Products = products }
end

-- Reads pass ownership. A marketplace outage counts as not owned; the next refresh fixes it.
function MonetizationService:RefreshOwnership(player)
	local owned = {}
	for key, pass in self._config.Passes do
		if configured(pass) then
			local ok, result = pcall(self._marketplace.UserOwnsGamePassAsync, self._marketplace, player.UserId, pass.Id)
			owned[key] = ok and result == true or nil
		end
	end
	self._owned[player] = owned
	return owned
end

function MonetizationService:MarkOwned(player, passKey)
	self._owned[player] = self._owned[player] or {}
	self._owned[player][passKey] = true
	if self._onChanged then
		self._onChanged(player)
	end
end

function MonetizationService:OwnsPass(player, passKey)
	local owned = self._owned[player]
	return owned ~= nil and owned[passKey] == true
end

function MonetizationService:OwnedList(player)
	local list = {}
	for key in self._owned[player] or {} do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- Stat deltas passes add to every run: { CoinMultiplier = total bonus }.
function MonetizationService:GetRunBonuses(player)
	local bonus = 0
	for key in self._owned[player] or {} do
		local pass = self._config.Passes[key]
		bonus += pass and pass.CoinBonus or 0
	end
	return { CoinMultiplier = bonus }
end

-- Offline storage hours passes add to the Salvage Yard's cap.
function MonetizationService:GetExtraCapHours(player)
	local hours = 0
	for key in self._owned[player] or {} do
		local pass = self._config.Passes[key]
		hours += pass and pass.ExtraCapHours or 0
	end
	return hours
end

function MonetizationService:_productFor(productId)
	for _, product in self._config.Products do
		if configured(product) and product.Id == productId then
			return product
		end
	end
	return nil
end

-- MarketplaceService.ProcessReceipt. Anything that cannot be granted and saved right now is
-- left for Roblox to deliver again.
function MonetizationService:ProcessReceipt(receipt, now)
	local product = self:_productFor(receipt.ProductId)
	if not product then
		return NOT_YET
	end
	local player = self._getPlayer(receipt.PlayerId)
	if not player or not self._persistence:IsLoaded(player) then
		return NOT_YET
	end
	local granted, reason = self._persistence:GrantReward(player, "receipt:" .. tostring(receipt.PurchaseId), product.Coins)
	if granted <= 0 and reason ~= "already granted" then
		return NOT_YET
	end
	-- Confirmed only once the coins are in the store.
	local saved = self._persistence:Save(player, now)
	if not saved then
		return NOT_YET
	end
	if self._onChanged then
		self._onChanged(player)
	end
	return GRANTED
end

function MonetizationService:ClearPlayer(player)
	self._owned[player] = nil
end

-- Hooks the real MarketplaceService: receipts, and passes bought while in the server.
function MonetizationService:Bind()
	local marketplace = self._marketplace
	marketplace.ProcessReceipt = function(receipt)
		return self:ProcessReceipt(receipt, os.clock())
	end
	local finished = marketplace.PromptGamePassPurchaseFinished
	if finished then
		finished:Connect(function(player, passId, purchased)
			if not purchased then
				return
			end
			for key, pass in self._config.Passes do
				if configured(pass) and pass.Id == passId then
					self:MarkOwned(player, key)
				end
			end
		end)
	end
end

return MonetizationService
