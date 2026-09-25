-- 3.0 launch economy beyond the catalogue: loadout presets (free slots plus pass slots), revive
-- tokens spent while down (once a run, with a grace window when everyone is down), rewarded
-- video (fixed bonus, daily cap, everything under pcall), and the private server owner check.
local CoinDrops = __require("CoinDrops")
local EnemyService = __require("EnemyService")
local GameBootstrap = __require("GameBootstrap")
local LoadoutService = __require("LoadoutService")
local MatchService = __require("MatchService")
local MetaConfig = __require("MetaConfig")
local PlayerDataService = __require("PlayerDataService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RewardedAds = __require("RewardedAds")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3
local DT = 1 / 30
local nextId = 9100

local function subject()
	nextId += 1
	return { Name = "E" .. nextId, UserId = nextId }
end

describe("loadout presets", function()
	local function setup(extra)
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = subject()
		persistence:Load(player)
		local worn = {}
		local loadout = LoadoutService.new(persistence, {
			extraPresets = function()
				return extra or 0
			end,
			ownsTrail = function(_, itemId)
				return itemId == "TrailEmber"
			end,
			wearTrail = function(who, itemId)
				worn[who] = itemId
				persistence:SetEquippedTrail(who, itemId)
			end,
		})
		return persistence, loadout, player, worn
	end

	it("gives two free slots, more with passes, never past the maximum", function()
		local _, free, player = setup(0)
		expect(free:PresetSlots(player)).toBe(MetaConfig.Presets.FreeSlots)
		local _, explorer, other = setup(1)
		expect(explorer:PresetSlots(other)).toBe(MetaConfig.Presets.FreeSlots + 1)
		local _, lots, third = setup(99)
		expect(lots:PresetSlots(third)).toBe(MetaConfig.Presets.MaxSlots)
	end)

	it("saves the rig, trail and Pact under a string slot key, and puts them back", function()
		local persistence, loadout, player, worn = setup(0)
		persistence:SetEquippedTrail(player, "TrailEmber")
		local saved = loadout:SavePreset(player, 2)
		expect(saved.Rig).toBe("Striker")
		expect(saved.Trail).toBe("TrailEmber")
		expect(persistence:GetPublicProfile(player).Presets["2"].Trail).toBe("TrailEmber")

		persistence:SetEquippedTrail(player, "")
		expect(loadout:ApplyPreset(player, 2).Trail).toBe("TrailEmber")
		expect(worn[player]).toBe("TrailEmber")
		expect(persistence:GetPublicProfile(player).EquippedTrail).toBe("TrailEmber")
	end)

	it("refuses slots past the player's count, empty slots and malformed slots", function()
		local _, loadout, player = setup(0)
		expect(select(2, loadout:SavePreset(player, 3))).toBe("no such slot")
		expect(select(2, loadout:SavePreset(player, 0))).toBe("no such slot")
		expect(select(2, loadout:SavePreset(player, 1.5))).toBe("no such slot")
		expect(select(2, loadout:SavePreset(player, "1"))).toBe("no such slot")
		expect(select(2, loadout:ApplyPreset(player, 1))).toBe("empty slot")
	end)

	it("never puts on a trail the player no longer owns", function()
		local persistence, loadout, player, worn = setup(0)
		persistence:SetEquippedTrail(player, "TrailVoid")
		loadout:SavePreset(player, 1)
		persistence:SetEquippedTrail(player, "")
		loadout:ApplyPreset(player, 1)
		expect(worn[player]).toBeNil()
		expect(persistence:GetPublicProfile(player).EquippedTrail).toBe("")
	end)

	it("saves presets in round trips through the store", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = subject()
		persistence:Load(player)
		LoadoutService.new(persistence):SavePreset(player, 1)
		persistence:Release(player, 1)
		local again = PlayerDataService.new(store)
		again:Load(player)
		expect(again:GetPublicProfile(player).Presets["1"].Rig).toBe("Striker")
	end)
end)

describe("revive tokens", function()
	local function build(persistence, canBuy)
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 3)
		local notes = {}
		local match = MatchService.new({
			rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(3)),
			enemies = enemies,
			upgrades = UpgradeService.new(3),
			projectiles = ProjectileService.new(arena, arena, PLANE_Y),
			rewards = RewardService.new(),
			coins = CoinDrops.new(arena, Random.new(3)),
			persistence = persistence,
			net = {
				Notify = {
					FireClient = function(_, who, payload)
						table.insert(notes, { who = who, payload = payload })
					end,
					FireAllClients = function() end,
				},
			},
			canBuyRevive = canBuy,
			planRun = function()
				return RunPlanner.Fixed({ "Atrium", "Cistern" })
			end,
		})
		return match, notes
	end

	local now = 0
	local function step(match, seconds)
		for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
			now += DT
			match:Step(DT, now)
		end
	end

	local function startAndFall(match, player)
		now = 0
		match:RegisterPlayer(player)
		match:RequestStart(player, now)
		step(match, RunConfig.StartCountdown + DT)
		local state = match:GetPlayerState(player)
		state.invulnerableUntil = 0
		state:ApplyDamage(10 ^ 6, now)
		return state
	end

	it("ends a solo run at once when nobody can revive", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = subject()
		persistence:Load(player)
		local match = build(persistence)
		startAndFall(match, player)
		step(match, DT)
		expect(match:GetState()).toBe(RunConfig.States.Results)
	end)

	it("holds the run while a downed player holds a token, and spends it to stand back up", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = subject()
		persistence:Load(player)
		persistence:GrantReward(player, "daily:5", 0, 0, { ReviveTokens = 1 })
		local match, notes = build(persistence)
		local state = startAndFall(match, player)
		step(match, DT)
		expect(match:GetState()).toBe(RunConfig.States.Combat)
		expect(notes[#notes].payload.Kind).toBe("ReviveOffer")
		expect(notes[#notes].payload.Tokens).toBe(1)

		expect((match:UseReviveToken(player, now))).toBe(true)
		expect(state.alive).toBe(true)
		expect(state.health).toBe(math.floor(state.maxHealth * RunConfig.Revive.HealthFraction))
		expect(persistence:GetBalance(player, "ReviveTokens")).toBe(0)
		persistence:Save(player, 1)
		expect(store:Peek("profile_" .. player.UserId).Currency.ReviveTokens).toBe(0)

		-- Once a run: down again, there is nothing to wait for.
		persistence:GrantReward(player, "daily:6", 0, 0, { ReviveTokens = 1 })
		state.invulnerableUntil = 0
		state:ApplyDamage(10 ^ 6, now)
		expect(select(2, match:UseReviveToken(player, now))).toBe("already revived")
		step(match, DT)
		expect(match:GetState()).toBe(RunConfig.States.Results)
	end)

	it("gives up once the grace runs out", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = subject()
		persistence:Load(player)
		persistence:GrantReward(player, "t", 0, 0, { ReviveTokens = 1 })
		local match = build(persistence)
		startAndFall(match, player)
		step(match, RunConfig.Revive.GraceSeconds - 1)
		expect(match:GetState()).toBe(RunConfig.States.Combat)
		step(match, 1.5)
		expect(match:GetState()).toBe(RunConfig.States.Results)
		expect(persistence:GetBalance(player, "ReviveTokens")).toBe(1) -- unspent, kept
	end)

	it("offers the paid Revive to a player with no token when it is switched on", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = subject()
		persistence:Load(player)
		local match, notes = build(persistence, function()
			return true
		end)
		startAndFall(match, player)
		step(match, DT)
		expect(match:GetState()).toBe(RunConfig.States.Combat)
		expect(notes[#notes].payload.Tokens).toBe(0)
		-- Without a token nothing is spent.
		expect(select(2, match:UseReviveToken(player, now))).toBe("insufficient revivetokens")
	end)

	it("refuses a revive for someone standing", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = subject()
		persistence:Load(player)
		persistence:GrantReward(player, "t", 0, 0, { ReviveTokens = 1 })
		local match = build(persistence)
		now = 0
		match:RegisterPlayer(player)
		match:RequestStart(player, now)
		step(match, RunConfig.StartCountdown + DT)
		expect(select(2, match:UseReviveToken(player, now))).toBe("not down")
		expect(persistence:GetBalance(player, "ReviveTokens")).toBe(1)
	end)
end)

describe("rewarded video", function()
	local FeatureFlags = __require("FeatureFlags")

	local function fakeAds(result)
		return {
			shown = 0,
			GetAdAvailabilityNowAsync = function()
				return Enum.AdAvailabilityResult.IsAvailable
			end,
			CreateAdRewardFromDevProductId = function(_, id)
				return { ProductId = id }
			end,
			ShowRewardedVideoAdAsync = function(self)
				self.shown += 1
				return result
			end,
		}
	end

	local function setup(result, config)
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = subject()
		persistence:Load(player)
		local day = 20400
		local ads = RewardedAds.new({
			ads = fakeAds(result or "done"),
			persistence = persistence,
			config = config or { RewardProductId = 77, MaxPerDay = 2, Coins = 40, Rerolls = 1 },
			wallClock = function()
				return day * MetaConfig.SecondsPerDay + 100
			end,
			completed = "done",
		})
		return ads, persistence, player
	end

	it("does nothing while switched off", function()
		local ads, persistence, player = setup()
		local previous = FeatureFlags.RewardedVideo
		FeatureFlags.RewardedVideo = false
		expect(select(2, ads:Watch(player))).toBe("ads disabled")
		FeatureFlags.RewardedVideo = previous
		expect(persistence:GetBalance(player)).toBe(0)
	end)

	it("pays a fixed bonus for a completed ad, up to the daily cap", function()
		local previous = FeatureFlags.RewardedVideo
		FeatureFlags.RewardedVideo = true
		local ads, persistence, player = setup()
		expect(ads:Watch(player)).toBe(40)
		expect(ads:Watch(player)).toBe(40)
		expect(select(2, ads:Watch(player))).toBe("daily limit")
		expect(persistence:GetBalance(player)).toBe(80)
		expect(persistence:GetBalance(player, "Rerolls")).toBe(2)
		expect(ads:WatchedToday(player)).toBe(2)
		FeatureFlags.RewardedVideo = previous
	end)

	it("pays nothing for an ad that was skipped or failed to show", function()
		local previous = FeatureFlags.RewardedVideo
		FeatureFlags.RewardedVideo = true
		local ads, persistence, player = setup("skipped")
		expect(select(2, ads:Watch(player))).toBe("not watched")
		expect(persistence:GetBalance(player)).toBe(0)
		local broken, _, other = setup()
		broken._ads.ShowRewardedVideoAdAsync = function()
			error("ads are not available in Studio")
		end
		expect(select(2, broken:Watch(other))).toBe("not watched")
		FeatureFlags.RewardedVideo = previous
	end)

	it("refuses with no reward product configured", function()
		local previous = FeatureFlags.RewardedVideo
		FeatureFlags.RewardedVideo = true
		local ads, _, player = setup(nil, { RewardProductId = 0, MaxPerDay = 2, Coins = 40 })
		expect(select(2, ads:CanWatch(player))).toBe("ads disabled")
		FeatureFlags.RewardedVideo = previous
	end)
end)

describe("private servers", function()
	it("recognises only the private server's owner", function()
		local owner = { UserId = 55 }
		local guest = { UserId = 56 }
		local private = { PrivateServerId = "abc", PrivateServerOwnerId = 55 }
		expect(GameBootstrap._ownsPrivateServer(private, owner)).toBe(true)
		expect(GameBootstrap._ownsPrivateServer(private, guest)).toBe(false)
		expect(GameBootstrap._ownsPrivateServer({ PrivateServerId = "", PrivateServerOwnerId = 0 }, owner)).toBe(false)
		-- A reserved server has an id but no owner.
		expect(GameBootstrap._ownsPrivateServer({ PrivateServerId = "r", PrivateServerOwnerId = 0 }, { UserId = 0 })).toBe(false)
	end)
end)
