-- Single access point for RemoteEvents. The server creates them, clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local REMOTE_NAMES = {
	-- client -> server (every one of these is validated and rate limited server-side)
	"FireProjectile", -- aim direction + power
	"ChooseUpgrade", -- offer id + card id
	"RequestStartRun",
	"RequestReturnToLobby",
	"UpdateSettings", -- accessibility options, sanitised server-side before storage
	"PurchaseShopItem", -- salvage shop item id; price and eligibility are decided server-side
	"EquipShopItem", -- an owned trail's item id, or "" to clear
	"DeepenArmory", -- reset a maxed Armory for the next Depth Rank; eligibility is decided server-side
	"ClaimDaily", -- claim today's login reward
	"ClaimQuest", -- quest id
	"RedeemCode", -- promo code text
	"RequestMeta", -- ask for a fresh MetaSync (opening the daily or quest panel)
	"SelectRig", -- rig id; unlock level checked server-side
	"SetPact", -- { [conditionId] = rank }; sanitised and unlock-checked server-side
	"ClaimAchievement", -- achievement id
	"Dash", -- the dash's heading; the client moves itself, the server grants i-frames and effects
	"ChooseSurge", -- surge offer id + perk id
	"ChooseDoor", -- door id, a vote for the next room

	-- server -> clients (display and cosmetics only)
	"ProjectileImpact", -- batched confirmed contacts
	"EnemyDefeated",
	"RunStateChanged",
	"PlayerStateChanged",
	"UpgradeOffer",
	"UpgradeResolved",
	"RunResults",
	"ProfileSync", -- currency, flags, settings and shop levels for this player
	"ShopResult", -- outcome of a shop request, or a purchase the store later refused
	"ShopOpen", -- the kiosk prompt was used: open the shop view
	"LobbyReadyState", -- ready pads: how many are ready and the start countdown
	"DebugStats", -- developer overlay only; sent to allowlisted users
	"MetaSync", -- daily streak and today's quests for this player
	"Notify", -- a toast: { Text, Kind = "Reward" | "Quest" | "Info" | "Error" }; "Callout" is a big centre call
	"SurgeOffer", -- three Surge perks to pick from mid-fight
	"SurgeResolved", -- which perk was taken
}

local Remotes = {}
local cachedFolder = nil

local function getFolder()
	if cachedFolder then
		return cachedFolder
	end

	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		for _, name in REMOTE_NAMES do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
		end
		cachedFolder = folder
	else
		cachedFolder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end

	return cachedFolder
end

function Remotes.Get(name)
	return getFolder():WaitForChild(name)
end

return Remotes
