-- Onboarding funnel and economy analytics: each step once ever per player (remembered in the
-- profile across servers), sent to telemetry and to Roblox's AnalyticsService under pcall; every
-- grant and spend reported as a source or a sink; and the run loop reporting its steps.
local EnemyService = __require("EnemyService")
local FunnelService = __require("FunnelService")
local MatchService = __require("MatchService")
local PlayerDataService = __require("PlayerDataService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local TelemetryService = __require("TelemetryService")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local nextId = 9300
local function subject()
	nextId += 1
	return { Name = "F" .. nextId, UserId = nextId }
end

local function fakeAnalytics()
	local analytics = { steps = {}, economy = {} }
	function analytics:LogOnboardingFunnelStepEvent(player, index, name)
		table.insert(self.steps, { player = player, index = index, name = name })
	end
	function analytics:LogEconomyEvent(player, flow, currency, amount, balance, transaction, sku)
		table.insert(self.economy, {
			player = player, flow = flow, currency = currency, amount = amount, balance = balance,
			transaction = transaction, sku = sku,
		})
	end
	return analytics
end

local function telemetry()
	local events = {}
	return TelemetryService.new(function(name, payload)
		table.insert(events, { name = name, payload = payload })
	end), events
end

describe("funnel steps", function()
	it("lists the seven onboarding steps in order", function()
		expect(FunnelService.Steps).toEqual({
			"Join", "FirstInput", "FirstHit", "FirstUpgrade", "FirstFusion", "FirstRunEnd", "FirstBaseUpgrade",
		})
	end)

	it("reports a step once ever, to telemetry and to AnalyticsService", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local player = subject()
		persistence:Load(player)
		local analytics = fakeAnalytics()
		local sink, events = telemetry()
		local funnel = FunnelService.new({ persistence = persistence, telemetry = sink, analytics = analytics })

		expect(funnel:Step(player, "Join")).toBe(true)
		expect(funnel:Step(player, "Join")).toBe(false)
		expect(funnel:Step(player, "FirstHit")).toBe(true)
		expect(#analytics.steps).toBe(2)
		expect(analytics.steps[1].index).toBe(1)
		expect(analytics.steps[1].name).toBe("Join")
		expect(analytics.steps[2].index).toBe(3)
		expect(events[1].name).toBe("FunnelStep")
		expect(persistence:GetSession(player).profile.Flags.Funnel.Join).toBe(true)

		-- Another server, later: the profile remembers, so nothing repeats.
		persistence:Release(player, 1)
		local again = PlayerDataService.new(store)
		again:Load(player)
		local second = fakeAnalytics()
		local funnel2 = FunnelService.new({ persistence = again, analytics = second })
		expect(funnel2:Step(player, "Join")).toBe(false)
		expect(funnel2:Step(player, "FirstInput")).toBe(true)
		expect(#second.steps).toBe(1)
	end)

	it("reports nothing for a read-only session, and ignores unknown steps", function()
		local store = __FakeDataStore.new()
		store.alwaysFail = true
		local persistence = PlayerDataService.new(store)
		local player = subject()
		persistence:Load(player)
		local analytics = fakeAnalytics()
		local funnel = FunnelService.new({ persistence = persistence, analytics = analytics })
		expect(funnel:Step(player, "Join")).toBe(false)
		expect(funnel:Step(player, "Bogus")).toBe(false)
		expect(#analytics.steps).toBe(0)
	end)

	it("never lets a failing AnalyticsService break the game", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local player = subject()
		persistence:Load(player)
		local funnel = FunnelService.new({
			persistence = persistence,
			analytics = {
				LogOnboardingFunnelStepEvent = function()
					error("analytics down")
				end,
				LogEconomyEvent = function()
					error("analytics down")
				end,
			},
		})
		expect(funnel:Step(player, "Join")).toBe(true)
		funnel:Economy(player, "Source", "Salvage", 10, 10, "daily:1")
	end)
end)

describe("economy events", function()
	it("reports every grant as a source and every spend as a sink", function()
		local analytics = fakeAnalytics()
		local funnel
		local persistence = PlayerDataService.new(__FakeDataStore.new(), {
			onEconomy = function(...)
				funnel:Economy(...)
			end,
		})
		funnel = FunnelService.new({ persistence = persistence, analytics = analytics })
		local player = subject()
		persistence:Load(player)

		persistence:GrantReward(player, "daily:20000", 50, 0, { ReviveTokens = 1 })
		persistence:SpendOnUpgrade(player, "Forge", 1, 30)
		persistence:SpendOnUpgrade(player, "ReviveUse", 1, 1, "ReviveTokens")

		expect(#analytics.economy).toBe(4)
		local coins = analytics.economy[1]
		expect(coins.flow).toBe(Enum.AnalyticsEconomyFlowType.Source)
		expect(coins.currency).toBe("Coins")
		expect(coins.amount).toBe(50)
		expect(coins.balance).toBe(50)
		expect(coins.transaction).toBe("TimedReward")
		expect(analytics.economy[2].currency).toBe("ReviveTokens")
		local build = analytics.economy[3]
		expect(build.flow).toBe(Enum.AnalyticsEconomyFlowType.Sink)
		expect(build.amount).toBe(30)
		expect(build.balance).toBe(20)
		expect(build.transaction).toBe("Shop")
		expect(build.sku).toBe("Forge")
		expect(analytics.economy[4].transaction).toBe("Gameplay")
	end)

	it("names where coins came from by the grant's key", function()
		expect(FunnelService.SourceType("daily:5")).toBe("TimedReward")
		expect(FunnelService.SourceType("offline:123")).toBe("TimedReward")
		expect(FunnelService.SourceType("receipt:abc")).toBe("IAP")
		expect(FunnelService.SourceType("job-a1-4")).toBe("Gameplay")
		expect(FunnelService.SourceType(nil)).toBe("Gameplay")
	end)
end)

describe("funnel steps in a run", function()
	it("reports the first shot, hit, card, fusion and run end", function()
		local steps = {}
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, 3, 6)
		local rooms = RoomService.new(arena, enemies, 3, Random.new(6))
		local upgrades = UpgradeService.new(6)
		local match = MatchService.new({
			rooms = rooms,
			enemies = enemies,
			upgrades = upgrades,
			projectiles = ProjectileService.new(arena, arena, 3),
			rewards = RewardService.new(),
			world = {
				GetPosition = function()
					return Vector3.new(0, 3, 0)
				end,
				Teleport = function() end,
			},
			onFunnel = function(player, step)
				table.insert(steps, step)
			end,
			planRun = function()
				return RunPlanner.Fixed({ "Atrium", "Cistern" })
			end,
		})
		local player = { Name = "Rookie", UserId = 9399 }
		local real = Harness.addPlayer("RookieReal")
		player.Character = Harness.giveCharacter(real, Vector3.new(0, 3, 0))
		match:RegisterPlayer(player)
		match:RequestStart(player, 0)
		local now = 0
		for _ = 1, math.ceil((RunConfig.StartCountdown + 0.1) * 30) do
			now += 1 / 30
			match:Step(1 / 30, now)
		end
		Harness.setClock(2000)
		expect((match:HandleFire(player, Vector3.new(0, 0, 1), 1, now))).toBe(true)
		local enemy = enemies:GetEnemies()[1]
		match:HandleImpact({ Position = enemy.position, Normal = Vector3.new(0, 0, -1), Instance = enemy.part },
			{ direction = Vector3.new(0, 0, 1), damage = 0.5, damagePerBounce = 0, contacts = 1, shooter = player, wallBounces = 1 }, now)
		match._state = RunConfig.States.UpgradeChoice
		local offer = upgrades:_open(player, match:GetPlayerState(player), { UpgradeConfig.Get("Fusillade") }, now)
		match:GetPlayerState(player):AddUpgrade(UpgradeConfig.Get("SplitShot"))
		match:GetPlayerState(player):AddUpgrade(UpgradeConfig.Get("SplitShot"))
		match:ChooseUpgrade(player, offer.id, "Fusillade", now)
		match:_finish("Defeated", now)
		for _, expected in { "FirstInput", "FirstHit", "FirstUpgrade", "FirstFusion", "FirstRunEnd" } do
			expect(table.find(steps, expected)).toBeTruthy()
		end
		Harness.removePlayer(real)
	end)
end)
