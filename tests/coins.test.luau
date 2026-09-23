-- Coins: dropped by kills as pickups, collected by walking over them (with a magnet pull),
-- swept to the nearest player when a room clears, and paid out at the end of the run.
local CoinConfig = __require("CoinConfig")
local CoinDrops = __require("CoinDrops")
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local PlayerState = __require("PlayerState")
local ProjectileService = __require("ProjectileService")
local RewardConfig = __require("RewardConfig")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3
local DT = 1 / 30

local function total(coins)
	local sum = 0
	for _, coin in coins:GetActive() do
		sum += coin.value
	end
	return sum
end

describe("CoinDrops", function()
	it("scatters a kill's value over a few pickups near where it fell", function()
		local coins = CoinDrops.new(Instance.new("Folder"), Random.new(1))
		coins:Drop(Vector3.new(10, PLANE_Y, 10), 7)
		local active = coins:GetActive()
		expect(#active).toBeGreaterThan(0)
		expect(#active).toBeLessThanOrEqual(CoinConfig.MaxPickupsPerDrop)
		expect(total(coins)).toBe(7)
		for _, coin in active do
			expect((coin.position - Vector3.new(10, coin.position.Y, 10)).Magnitude).toBeLessThanOrEqual(CoinConfig.ScatterRadius + 0.01)
			expect(coin.part.CanQuery).toBe(false)
			expect(coin.part.CanCollide).toBe(false)
		end
	end)

	it("pulls coins in from the magnet radius and credits whoever collects them", function()
		local coins = CoinDrops.new(Instance.new("Folder"), Random.new(2))
		coins:Drop(Vector3.new(0, PLANE_Y, 0), 3)
		-- Inside the magnet radius from every coin, wherever the scatter put it.
		local near = { player = "Near", position = Vector3.new(CoinConfig.MagnetRadius - CoinConfig.ScatterRadius - 0.5, PLANE_Y, 0), magnet = 0 }
		local credited = {}
		local now = 0
		for _ = 1, 60 do
			now += DT
			for _, event in coins:Step(DT, now, { near }) do
				credited[event.player] = (credited[event.player] or 0) + event.value
			end
		end
		expect(credited.Near).toBe(3)
		expect(#coins:GetActive()).toBe(0)
	end)

	it("leaves coins alone for anyone out of reach", function()
		local coins = CoinDrops.new(Instance.new("Folder"), Random.new(3))
		coins:Drop(Vector3.new(0, PLANE_Y, 0), 4)
		local far = { player = "Far", position = Vector3.new(40, PLANE_Y, 0), magnet = 0 }
		local now = 0
		for _ = 1, 60 do
			now += DT
			expect(#coins:Step(DT, now, { far })).toBe(0)
		end
		expect(total(coins)).toBe(4)
	end)

	it("widens the pull with the Coin Magnet bonus", function()
		local function tryFrom(magnet)
			local coins = CoinDrops.new(Instance.new("Folder"), Random.new(4))
			coins:Drop(Vector3.new(0, PLANE_Y, 0), 1)
			local coin = coins:GetActive()[1].position
			-- Just beyond the plain magnet radius from where the coin actually landed.
			local collector = { player = "Magnet", position = Vector3.new(coin.X + CoinConfig.MagnetRadius + 2, PLANE_Y, coin.Z), magnet = magnet }
			local got, now = 0, 0
			for _ = 1, 90 do
				now += DT
				for _, event in coins:Step(DT, now, { collector }) do
					got += event.value
				end
			end
			return got
		end
		expect(tryFrom(0)).toBe(0)
		expect(tryFrom(4)).toBe(1)
	end)

	it("sweeps every leftover coin to the nearest player", function()
		local coins = CoinDrops.new(Instance.new("Folder"), Random.new(5))
		coins:Drop(Vector3.new(0, PLANE_Y, 0), 5)
		coins:Drop(Vector3.new(50, PLANE_Y, 0), 6)
		local left = { player = "Left", position = Vector3.new(-30, PLANE_Y, 0), magnet = 0 }
		local right = { player = "Right", position = Vector3.new(80, PLANE_Y, 0), magnet = 0 }
		local credited = {}
		for _, event in coins:Sweep({ left, right }) do
			credited[event.player] = (credited[event.player] or 0) + event.value
		end
		expect(credited.Left).toBe(5)
		expect(credited.Right).toBe(6)
		expect(#coins:GetActive()).toBe(0)
	end)

	it("never loses value when the pool runs dry", function()
		local coins = CoinDrops.new(Instance.new("Folder"), Random.new(6))
		for _ = 1, CoinConfig.PoolSize do
			coins:Drop(Vector3.new(0, PLANE_Y, 0), 1)
		end
		coins:Drop(Vector3.new(5, PLANE_Y, 5), 9)
		local collector = { player = "Only", position = Vector3.new(100, PLANE_Y, 0), magnet = 0 }
		local swept = 0
		for _, event in coins:Sweep({ collector }) do
			swept += event.value
		end
		expect(swept).toBe(CoinConfig.PoolSize + 9)
	end)
end)

describe("coins in a run", function()
	local function build(planRun, persistence)
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 7)
		local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
		local positions = {}
		local match = MatchService.new({
			rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(7)),
			enemies = enemies,
			upgrades = UpgradeService.new(7),
			projectiles = projectiles,
			rewards = RewardService.new(),
			coins = CoinDrops.new(arena, Random.new(7)),
			persistence = persistence,
			world = {
				GetPosition = function(player)
					return positions[player]
				end,
				Teleport = function(player, position)
					positions[player] = position
				end,
			},
			planRun = planRun,
		})
		return match, enemies, positions
	end

	local function start(match, player)
		match:RegisterPlayer(player)
		match:RequestStart(player, 0)
		local now = 0
		for _ = 1, math.ceil((RunConfig.StartCountdown + 0.2) / DT) do
			now += DT
			match:Step(DT, now)
		end
		return now
	end

	it("drops each archetype's coins where it dies, and credits the player who walks over them", function()
		local match, enemies, positions = build(function()
			return RunPlanner.Fixed({ "Atrium" })
		end)
		local player = { Name = "Collector", UserId = 41 }
		local now = start(match, player)
		local victim = enemies:GetEnemies()[1]
		local value = EnemyConfig.Archetypes[victim.archetypeId].Coins
		expect(value).toBeGreaterThan(0)
		local entry = { damage = 99, damagePerBounce = 0, contacts = 1, direction = Vector3.new(1, 0, 0), shooter = player }
		match:HandleImpact({ Instance = victim.part, Position = victim.position, Normal = Vector3.new(1, 0, 0) }, entry, now)

		positions[player] = victim.position
		for _ = 1, 30 do
			now += DT
			match:Step(DT, now)
		end
		expect(match:GetPlayerState(player).coins).toBe(value)
		expect(match:GetPlayerState(player):ToSnapshot().Coins).toBe(value)
	end)

	it("gives every archetype a coin value", function()
		for id, archetype in EnemyConfig.Archetypes do
			if type(archetype.Coins) ~= "number" or archetype.Coins <= 0 then
				error(id .. " drops no coins")
			end
		end
		expect(EnemyConfig.Archetypes.WardenPrime.Coins).toBeGreaterThan(EnemyConfig.Archetypes.Drifter.Coins)
	end)

	it("pays a player who leaves mid-run for the coins they collected, exactly once", function()
		local grants = {}
		local persistence = {
			GrantReward = function(_, who, key, amount)
				table.insert(grants, { who = who, key = key, amount = amount })
				return amount
			end,
			RecordRunEnd = function() end,
			SaveInBackground = function() end,
		}
		local match = build(function()
			return RunPlanner.Fixed({ "Atrium", "Cistern" })
		end, persistence)
		local player = { Name = "Leaver", UserId = 42 }
		local now = start(match, player)
		match:GetPlayerState(player).coins = 17
		match:UnregisterPlayer(player, now)
		match:UnregisterPlayer(player, now)
		expect(#grants).toBe(1)
		expect(grants[1].amount).toBe(17)
		expect(grants[1].who).toBe(player)
	end)
end)

describe("run payout", function()
	local function stateWith(coins, rooms)
		local state = PlayerState.new({ Name = "Payee", UserId = 43 })
		state.coins = coins
		state.roomsCleared = rooms
		return state
	end

	it("pays the coins collected plus a clear bonus", function()
		local state = stateWith(40, 3)
		local expected = 40 + 3 * RewardConfig.PerRoomCleared + RewardConfig.EliteBonus + RewardConfig.ExtractionBonus
		expect(RewardService.Compute(state, "Extracted", true)).toBe(expected)
	end)

	it("keeps every collected coin on defeat and only trims the bonus", function()
		local state = stateWith(40, 3)
		local bonus = 3 * RewardConfig.PerRoomCleared
		expect(RewardService.Compute(state, "Defeated", false)).toBe(40 + math.floor(bonus * RewardConfig.DefeatMultiplier))
		expect(RewardService.Compute(stateWith(40, 0), "Defeated", false)).toBe(40)
	end)

	it("doubles with 2x Coins and grows with Fortune, within the cap", function()
		local state = stateWith(50, 0)
		local plain = RewardService.Compute(state, "Defeated", false)
		state.stats.CoinMultiplier = 2
		expect(RewardService.Compute(state, "Defeated", false)).toBe(plain * 2)
		state.stats.RewardMultiplier = 1.3
		expect(RewardService.Compute(state, "Defeated", false)).toBe(math.floor(plain * 2 * 1.3))
		state.coins = 10 ^ 9
		expect(RewardService.Compute(state, "Defeated", false)).toBe(RewardConfig.MaxPerRun)
	end)
end)

describe("leaderboard", function()
	it("shows each player's coin balance and best depth in the player list", function()
		local Leaderstats = __require("Leaderstats")
		local player = Instance.new("Folder")
		Leaderstats.Update(player, 120, 4)
		local stats = player:FindFirstChild("leaderstats")
		expect(stats).toBeTruthy()
		expect(stats:FindFirstChild("Coins").Value).toBe(120)
		expect(stats:FindFirstChild("Best Depth").Value).toBe(4)
		Leaderstats.Update(player, 135, 4)
		expect(stats:FindFirstChild("Coins").Value).toBe(135)
		expect(#stats:GetChildren()).toBe(2)
	end)
end)
