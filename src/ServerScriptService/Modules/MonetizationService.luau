-- Game passes and developer products. Pass ownership is read when a player joins (and updated
-- when they buy one in-game) and turns into entitlements: presets, offline hours, cosmetics, a
-- nameplate and a chat tag, never run power. Products are paid through the profile's grant
-- ledger keyed by the receipt's PurchaseId, and only confirmed to Roblox once saved, so a
-- receipt pays exactly once however often Roblox delivers it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local MonetizationService = {}
MonetizationService.__index = MonetizationService

local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet

-- options: marketplace (MarketplaceService or a stand-in), persistence, config (default
-- MonetizationConfig), getPlayer(userId), onChanged(player), onRevive(player) -> bool (spend a
-- just-bought revive now, if the buyer is down in a run), productEnabled(product) -> bool
-- (whether a product may be offered; the paid revive waits for FeatureFlags.PaidRevive).
function MonetizationService.new(options)
	return setmetatable({
		_marketplace = options.marketplace,
		_persistence = options.persistence,
		_config = options.config or MonetizationConfig,
		_getPlayer = options.getPlayer,
		_onChanged = options.onChanged,
		_onRevive = options.onRevive,
		_productEnabled = options.productEnabled or function()
			return true
		end,
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
		if configured(product) and self._productEnabled(product) then
			table.insert(products, { Key = product.Key, Id = product.Id, Title = product.Title, Description = product.Description })
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

-- The sum of a numeric perk over every pass the player owns.
function MonetizationService:_sum(player, perk)
	local total = 0
	for key in self._owned[player] or {} do
		local pass = self._config.Passes[key]
		total += pass and tonumber(pass[perk]) or 0
	end
	return total
end

-- Offline storage hours passes add to the Salvage Yard's cap.
function MonetizationService:GetExtraCapHours(player)
	return self:_sum(player, "ExtraCapHours")
end

-- Loadout preset slots passes add to the free ones.
function MonetizationService:GetPresetSlots(player)
	return self:_sum(player, "PresetSlots")
end

-- The first owned pass's value for a text perk (Nameplate, ChatTag), or nil. Passes are checked
-- in a fixed order so the result never depends on table order.
function MonetizationService:GetPerk(player, perk)
	local keys = {}
	for key in self._owned[player] or {} do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local pass = self._config.Passes[key]
		if pass and type(pass[perk]) == "string" then
			return pass[perk]
		end
	end
	return nil
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
	-- A rewarded video's product: AdService already paid the bonus when the ad completed.
	local ads = self._config.Ads
	if ads and configured({ Id = ads.RewardProductId }) and receipt.ProductId == ads.RewardProductId then
		return GRANTED
	end
	local product = self:_productFor(receipt.ProductId)
	if not product then
		return NOT_YET
	end
	local player = self._getPlayer(receipt.PlayerId)
	if not player or not self._persistence:IsLoaded(player) then
		return NOT_YET
	end
	local _, reason = self._persistence:GrantReward(player, "receipt:" .. tostring(receipt.PurchaseId), 0, 0, product.Extras)
	if reason and reason ~= "already granted" then
		return NOT_YET
	end
	-- Confirmed only once the coins are in the store.
	local saved = self._persistence:Save(player, now)
	if not saved then
		return NOT_YET
	end
	-- A revive bought while down is spent straight away (once a run); otherwise the token waits.
	if product.Kind == "Revive" and reason == nil and self._onRevive then
		self._onRevive(player)
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
