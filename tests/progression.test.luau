-- Levels and experience, the invisible lobby spawn, and payouts that survive dying and Studio
-- restarts.
local CoinDrops = __require("CoinDrops")
local EnemyService = __require("EnemyService")
local GameBootstrap = __require("GameBootstrap")
local HudView = __require("HudView")
local Leaderstats = __require("Leaderstats")
local LobbyBuilder = __require("LobbyBuilder")
local MatchService = __require("MatchService")
local Nameplates = __require("Nameplates")
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")
local PlayerState = __require("PlayerState")
local ProgressionConfig = __require("ProgressionConfig")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3
local DT = 1 / 30

local function player(userId)
	return { Name = "P" .. userId, UserId = userId }
end

describe("level curve", function()
	it("starts everyone at level 1 and levels up exactly at each threshold", function()
		expect((ProgressionConfig.LevelFor(0))).toBe(1)
		local first = ProgressionConfig.XpToNext(1)
		expect((ProgressionConfig.LevelFor(first - 1))).toBe(1)
		expect((ProgressionConfig.LevelFor(first))).toBe(2)
		local level, into, need = ProgressionConfig.LevelFor(first + 7)
		expect(level).toBe(2)
		expect(into).toBe(7)
		expect(need).toBe(ProgressionConfig.XpToNext(2))
	end)

	it("never goes backwards and stops at the cap", function()
		local previous = 1
		for xp = 0, 200000, 997 do
			local level = ProgressionConfig.LevelFor(xp)
			expect(level >= previous).toBe(true)
			previous = level
		end
		local level, into, need = ProgressionConfig.LevelFor(10 ^ 9)
		expect(level).toBe(ProgressionConfig.MaxLevel)
		expect(into).toBe(0)
		expect(need).toBe(0)
	end)

	it("treats junk totals as no experience", function()
		for _, junk in { -5, 0 / 0, "12", nil } do
			expect((ProgressionConfig.LevelFor(junk))).toBe(1)
		end
	end)

	it("pays the coins for every level crossed, and nothing when none is", function()
		local toThree = ProgressionConfig.XpToNext(1) + ProgressionConfig.XpToNext(2)
		local coins, before, after = ProgressionConfig.RewardBetween(0, toThree)
		expect(before).toBe(1)
		expect(after).toBe(3)
		expect(coins).toBe(ProgressionConfig.LevelReward(2) + ProgressionConfig.LevelReward(3))
		expect((ProgressionConfig.RewardBetween(5, 6))).toBe(0)
	end)
end)

describe("run experience", function()
	local function stateWith(kills, rooms)
		local state = PlayerState.new(player(1))
		state.kills = kills
		state.roomsCleared = rooms
		return state
	end

	it("keeps kill and clear experience on every outcome, and adds extraction on a win", function()
		local rates = ProgressionConfig.Xp
		local base = 10 * rates.PerKill + 2 * rates.PerRoomCleared
		expect(RewardService.Experience(stateWith(10, 2), "Defeated", false)).toBe(base)
		expect(RewardService.Experience(stateWith(10, 2), "Extracted", true)).toBe(base + rates.EliteCleared + rates.Extracted)
	end)

	it("is not scaled by coin multipliers", function()
		local state = stateWith(10, 2)
		local plain = RewardService.Experience(state, "Defeated", false)
		state.stats.RewardMultiplier = 3
		state.stats.CoinMultiplier = 2
		expect(RewardService.Experience(state, "Defeated", false)).toBe(plain)
	end)
end)

describe("experience persistence", function()
	it("stores experience with the run's coins and pays neither twice", function()
		local store = __FakeDataStore.new()
		local subject = player(301)
		local service = PlayerDataService.new(store)
		service:Load(subject)
		local coins, reason, xp = service:GrantReward(subject, "run-1", 50, 120)
		expect(coins).toBe(50)
		expect(reason).toBeNil()
		expect(xp).toBe(120)
		expect(service:GetXp(subject)).toBe(120)
		expect((service:Save(subject, 1))).toBe(true)
		expect(store.data["profile_301"].Progression.Xp).toBe(120)

		local again, why, noXp = service:GrantReward(subject, "run-1", 50, 120)
		expect(again).toBe(0)
		expect(why).toBe("already granted")
		expect(noXp).toBe(0)
		expect(service:GetXp(subject)).toBe(120)
	end)

	it("pays experience alone, with no coins", function()
		local service = PlayerDataService.new(__FakeDataStore.new())
		local subject = player(302)
		service:Load(subject)
		local coins, reason, xp = service:GrantReward(subject, "run-1", 0, 40)
		expect(coins).toBe(0)
		expect(reason).toBeNil()
		expect(xp).toBe(40)
	end)

	it("adds to experience another server already saved rather than overwriting it", function()
		local store = __FakeDataStore.new()
		local subject = player(303)
		local serverA, serverB = PlayerDataService.new(store), PlayerDataService.new(store)
		serverA:Load(subject)
		serverB:Load(subject)
		serverA:GrantReward(subject, "a-1", 0, 100)
		serverB:GrantReward(subject, "b-1", 0, 30)
		serverA:Save(subject, 1)
		serverB:Save(subject, 2)
		expect(store.data["profile_303"].Progression.Xp).toBe(130)
		expect(serverB:GetXp(subject)).toBe(130)
	end)

	it("refuses experience changes through Update", function()
		local service = PlayerDataService.new(__FakeDataStore.new())
		local subject = player(304)
		service:Load(subject)
		local ok = pcall(function()
			service:Update(subject, function(profile)
				profile.Progression.Xp = 999999
			end)
		end)
		expect(ok).toBe(false)
		expect(service:GetXp(subject)).toBe(0)
	end)

	it("migrates a v5 profile to level 1 with its coins intact", function()
		local profile = PlayerDataService.Normalise({ SchemaVersion = 5, Currency = { Salvage = 77 } })
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Progression.Xp).toBe(0)
		expect(profile.Currency.Salvage).toBe(77)
	end)

	it("shows the level in the public profile", function()
		local service = PlayerDataService.new(__FakeDataStore.new())
		local subject = player(305)
		service:Load(subject)
		service:GrantReward(subject, "run-1", 0, ProgressionConfig.XpToNext(1) + 5)
		local public = service:GetPublicProfile(subject)
		expect(public.Progression.Level).toBe(2)
		expect(public.Progression.XpIntoLevel).toBe(5)
	end)
end)

describe("payouts in a run", function()
	local function build(persistence, runKeyPrefix)
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, 11)
		local positions = {}
		local match = MatchService.new({
			rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(11)),
			enemies = enemies,
			upgrades = UpgradeService.new(11),
			projectiles = ProjectileService.new(arena, arena, PLANE_Y),
			rewards = RewardService.new(),
			coins = CoinDrops.new(arena, Random.new(11)),
			persistence = persistence,
			runKeyPrefix = runKeyPrefix,
			world = {
				GetPosition = function(who)
					return positions[who]
				end,
				Teleport = function(who, position)
					positions[who] = position
				end,
			},
			planRun = function()
				return RunPlanner.Fixed({ "Atrium", "Cistern" })
			end,
		})
		return match, positions
	end

	local function start(match, who)
		match:RegisterPlayer(who)
		match:RequestStart(who, 0)
		local now = 0
		for _ = 1, math.ceil((RunConfig.StartCountdown + 0.2) / DT) do
			now += DT
			match:Step(DT, now)
		end
		return now
	end

	local function die(match, who, now)
		local state = match:GetPlayerState(who)
		state.invulnerableUntil = 0
		state:ApplyDamage(10 ^ 6, now)
		now += DT
		match:Step(DT, now)
		return now
	end

	it("saves the coins and experience of a player who dies", function()
		local store = __FakeDataStore.new()
		local persistence = PlayerDataService.new(store)
		local match = build(persistence, "death")
		local subject = player(401)
		persistence:Load(subject)
		local now = start(match, subject)
		local state = match:GetPlayerState(subject)
		state.coins = 23
		state.kills = 5
		now = die(match, subject, now)

		expect(match:GetState()).toBe(RunConfig.States.Results)
		expect(persistence:GetBalance(subject)).toBeGreaterThan(22)
		expect(persistence:GetXp(subject)).toBe(5 * ProgressionConfig.Xp.PerKill)
		expect((persistence:Save(subject, now))).toBe(true)
		expect(store.data["profile_401"].Currency.Salvage).toBe(persistence:GetBalance(subject))
		expect(store.data["profile_401"].Progression.Xp).toBe(5 * ProgressionConfig.Xp.PerKill)
	end)

	it("banks coins still on the floor when the last player goes down", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local match, positions = build(persistence, "floor")
		local subject = player(402)
		persistence:Load(subject)
		local now = start(match, subject)
		-- Dropped out of the magnet's reach, so only the end-of-run sweep can collect it.
		local far = positions[subject] + Vector3.new(60, 0, 0)
		match._coins:Drop(far, 9)
		now = die(match, subject, now)
		expect(#match._coins:GetActive()).toBe(0)
		expect(persistence:GetBalance(subject)).toBeGreaterThan(8)
	end)

	it("pays every Studio session's runs, even though Studio has no JobId", function()
		-- The old fixed "studio" prefix gave every session's first run the same payout key, so
		-- the profile ledger refused every session after the first one.
		local store = __FakeDataStore.new()
		local subject = player(403)
		local balances = {}
		for session = 1, 2 do
			local persistence = PlayerDataService.new(store)
			persistence:Load(subject)
			local prefix = GameBootstrap._runKeyPrefix("", "guid-" .. session) .. "-a1"
			local match = build(persistence, prefix)
			local now = start(match, subject)
			match:GetPlayerState(subject).coins = 10
			now = die(match, subject, now)
			persistence:Release(subject, now)
			balances[session] = store.data["profile_403"].Currency.Salvage
		end
		expect(balances[1]).toBeGreaterThan(9)
		expect(balances[2]).toBeGreaterThan(balances[1] + 9)
	end)

	it("keeps a live server's JobId as the key prefix", function()
		expect(GameBootstrap._runKeyPrefix("job-123", "guid")).toBe("job-123")
		expect(GameBootstrap._runKeyPrefix("", "a")).never().toBe(GameBootstrap._runKeyPrefix("", "b"))
	end)

	it("pays experience to a player who leaves mid-run", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local match = build(persistence, "leaver")
		local subject = player(404)
		persistence:Load(subject)
		local now = start(match, subject)
		match:GetPlayerState(subject).kills = 3
		match:UnregisterPlayer(subject, now)
		match:UnregisterPlayer(subject, now)
		expect(persistence:GetXp(subject)).toBe(3 * ProgressionConfig.Xp.PerKill)
	end)
end)

describe("level display", function()
	it("puts Level first in the player list", function()
		local subject = Instance.new("Folder")
		Leaderstats.Update(subject, 10, 2, 7)
		local stats = subject:FindFirstChild("leaderstats")
		expect(stats:GetChildren()[1].Name).toBe("Level")
		expect(stats:FindFirstChild("Level").Value).toBe(7)
		Leaderstats.Update(subject, 10, 2, 8)
		expect(stats:FindFirstChild("Level").Value).toBe(8)
		expect(#stats:GetChildren()).toBe(3)
	end)

	it("shows one level plate over the character's head and keeps it current", function()
		local subject = Instance.new("Folder")
		expect(Nameplates.Update(subject, 3)).toBe(false) -- no character yet
		local character = Instance.new("Model")
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = character
		subject.Character = character
		expect(Nameplates.Update(subject, 3)).toBe(true)
		Nameplates.Update(subject, 4)
		local plates = 0
		for _, child in head:GetChildren() do
			if child.Name == "LevelPlate" then
				plates += 1
				expect(child:FindFirstChild("Text").Text).toBe("Lv 4")
			end
		end
		expect(plates).toBe(1)
	end)

	it("draws the level bar and announces a level up once", function()
		local hud = HudView.new(Instance.new("Folder"))
		expect(hud:SetProgress(ProgressionConfig.Describe(30))).toBe(false) -- the first profile is not a level up
		expect(hud.levelLabel.Text).toBe("LEVEL 1")
		expect(hud.xpLabel.Text).toBe("30 / 100 XP")
		expect(hud:SetProgress(ProgressionConfig.Describe(130))).toBe(true)
		expect(hud.levelLabel.Text).toBe("LEVEL 2")
		expect(hud:SetProgress(ProgressionConfig.Describe(140))).toBe(false)
	end)

	it("shows the level in the lobby and keeps it out of the way in a run", function()
		local hud = HudView.new(Instance.new("Folder"))
		expect(hud.levelPanel.Visible).toBe(true)
		hud:UpdateRun({ State = RunConfig.States.Combat, RoomIndex = 1, RoomCount = 7, RoomName = "", EnemiesRemaining = 1 })
		expect(hud.levelPanel.Visible).toBe(false)
		hud:UpdateRun({ State = RunConfig.States.Lobby, RoomIndex = 0, RoomCount = 0, RoomName = "", EnemiesRemaining = 0 })
		expect(hud.levelPanel.Visible).toBe(true)
	end)

	it("warns only when progress is not being saved", function()
		local hud = HudView.new(Instance.new("Folder"))
		expect(hud.saveWarning.Visible).toBe(false)
		hud:SetReadOnly(true)
		expect(hud.saveWarning.Visible).toBe(true)
		hud:SetReadOnly(false)
		expect(hud.saveWarning.Visible).toBe(false)
	end)
end)

describe("lobby spawn", function()
	it("is invisible and cannot be walked into or shot", function()
		local lobby = LobbyBuilder.Build(Instance.new("Folder"))
		local spawn = lobby:FindFirstChild("LobbySpawn")
		expect(spawn).toBeTruthy()
		expect(spawn.Transparency).toBe(1)
		expect(spawn.CanCollide).toBe(false)
		expect(spawn.CanQuery).toBe(false)
		-- Still a working spawn: players appear over the hall floor.
		expect(spawn.Neutral).toBe(true)
		expect(lobby:FindFirstChild("LobbyFloor").CanCollide).toBe(true)
	end)
end)
