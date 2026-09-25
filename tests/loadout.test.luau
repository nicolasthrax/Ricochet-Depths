-- Rigs, the Depth Pact, achievements and the Codex, co-op revives, and the lobby views that
-- show them: configs, LoadoutService's rules, schema v8, a Pact reaching a real run, and the
-- remote path end to end.
local AchievementConfig = __require("AchievementConfig")
local CombatConfig = __require("CombatConfig")
local EnemyService = __require("EnemyService")
local JournalView = __require("JournalView")
local LoadoutService = __require("LoadoutService")
local MatchService = __require("MatchService")
local MenuDock = __require("MenuDock")
local PactConfig = __require("PactConfig")
local PactView = __require("PactView")
local PlayerDataConfig = __require("PlayerDataConfig")
local PlayerDataService = __require("PlayerDataService")
local ProjectileService = __require("ProjectileService")
local RemoteRouter = __require("RemoteRouter")
local Remotes = __require("Remotes")
local RewardConfig = __require("RewardConfig")
local RewardService = __require("RewardService")
local RigConfig = __require("RigConfig")
local RigView = __require("RigView")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local TelemetryService = __require("TelemetryService")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local States = RunConfig.States
local PLANE_Y = 3
local DT = 1 / 30

local function player(userId)
	return { Name = "L" .. userId, UserId = userId }
end

local function loaded(userId, store)
	local persistence = PlayerDataService.new(store or __FakeDataStore.new())
	local subject = player(userId)
	persistence:Load(subject)
	return persistence, subject
end

local function extract(persistence, subject, extra)
	local summary = { Outcome = "Extracted", EnemiesDefeated = 0, BestChain = 0, RoomsCleared = 7, Reward = 0 }
	for key, value in extra or {} do
		summary[key] = value
	end
	persistence:RecordRunEnd(subject, summary)
end

describe("RigConfig", function()
	it("has a free default rig and unlocks the rest in rising level order", function()
		expect(RigConfig.Get(RigConfig.DefaultId).Level).toBe(1)
		local previous = 0
		for _, rig in RigConfig.Rigs do
			expect(rig.Level).toBeGreaterThanOrEqual(previous)
			previous = rig.Level
			for stat in rig.Stats do
				expect(UpgradeConfig.BaseStats[stat]).never().toBeNil()
			end
			expect(RigConfig.Summary(rig)).never().toBe("")
		end
	end)

	it("falls back to the default for an unknown or still-locked rig", function()
		expect(RigConfig.Resolve("Nope", 50).Id).toBe(RigConfig.DefaultId)
		expect(RigConfig.Resolve("Gambler", 1).Id).toBe(RigConfig.DefaultId)
		expect(RigConfig.Resolve("Gambler", 99).Id).toBe("Gambler")
	end)

	it("summarises what a rig changes in words", function()
		expect(RigConfig.Summary(RigConfig.Get("Scatter"))).toBe("+1 projectile, 20% slower fire")
	end)
end)

describe("PactConfig", function()
	it("sanitises anything to known conditions and legal ranks", function()
		local pact = PactConfig.Sanitise({ Hardened = 9, Frenzy = -3, Drought = 0.9, Bogus = 2, Narrow = "1" })
		expect(pact.Hardened).toBe(3)
		expect(pact.Frenzy).toBeNil()
		expect(pact.Drought).toBeNil()
		expect(pact.Bogus).toBeNil()
		expect(pact.Narrow).toBeNil()
		expect(next(PactConfig.Sanitise("junk"))).toBeNil()
	end)

	it("adds up Heat and turns it into rewards", function()
		expect(PactConfig.Heat({ Hardened = 2, Drought = 1 })).toBe(4)
		local effects = PactConfig.Effects({ Hardened = 2, Drought = 1, Narrow = 1, Frailty = 1 })
		expect(effects.Heat).toBe(7)
		expect(effects.EnemyHealth).toBeCloseTo(1.6, 1e-9)
		expect(effects.NoRegen).toBe(true)
		expect(effects.OfferCount).toBe(2)
		expect(effects.MaxHealthDelta).toBe(-20)
		expect(effects.RewardMultiplier).toBeCloseTo(1.7, 1e-9)
		expect(PactConfig.Effects({}).RewardMultiplier).toBe(1)
		expect(PactConfig.MaxHeat()).toBeGreaterThanOrEqual(10)
	end)

	it("runs a group at the lowest rank anyone chose", function()
		local merged = PactConfig.Merge({ { Hardened = 3, Brutal = 2 }, { Hardened = 1 }, { Hardened = 2, Brutal = 3 } })
		expect(merged.Hardened).toBe(1)
		expect(merged.Brutal).toBeNil()
		expect(next(PactConfig.Merge({}))).toBeNil()
	end)
end)

describe("AchievementConfig", function()
	it("has unique ids, positive targets and rewards", function()
		for _, achievement in AchievementConfig.Achievements do
			expect(achievement.Target).toBeGreaterThan(0)
			expect(achievement.Coins).toBeGreaterThan(0)
		end
		expect(AchievementConfig.Get("Naturalist").Target).toBe(#AchievementConfig.EnemyIds)
		expect(AchievementConfig.Get("Archivist").Target).toBe(#UpgradeConfig.MainCards())
	end)

	it("reads progress from stats, rigs and the Codex, ignoring ids that no longer exist", function()
		local profile = {
			Stats = { EnemiesDefeated = 300, RigsExtracted = { Striker = true, Carom = true, Gone = true } },
			Codex = { Cards = { SplitShot = true, Removed = true }, Enemies = { Drifter = 4, Chaser = 0 } },
		}
		expect(AchievementConfig.Progress(AchievementConfig.Get("Slayer"), profile)).toBe(300)
		expect(AchievementConfig.Progress(AchievementConfig.Get("Versatile"), profile)).toBe(2)
		expect(AchievementConfig.Progress(AchievementConfig.Get("Archivist"), profile)).toBe(1)
		expect(AchievementConfig.Progress(AchievementConfig.Get("Naturalist"), profile)).toBe(1)
		local described = AchievementConfig.Describe(profile)
		expect(described[1].Complete).toBe(true)
		expect(described[1].Progress).toBe(250) -- clamped to the target for display
	end)
end)

describe("schema v8", function()
	it("migrates a v7 profile to a Striker with no Pact, keeping everything else", function()
		local profile = PlayerDataService.Normalise({
			SchemaVersion = 7,
			Currency = { Salvage = 321 },
			Stats = { RunsExtracted = 4, EnemiesDefeated = 90 },
		})
		expect(profile.SchemaVersion).toBe(PlayerDataConfig.SchemaVersion)
		expect(profile.Currency.Salvage).toBe(321)
		expect(profile.Stats.RunsExtracted).toBe(4)
		expect(profile.SelectedRig).toBe("Striker")
		expect(next(profile.Pact)).toBeNil()
		expect(profile.Stats.BestHeat).toBe(0)
		expect(type(profile.Stats.RigsExtracted)).toBe("table")
		expect(type(profile.Codex.Cards)).toBe("table")
	end)

	it("records the Codex, champion and boss kills, and Heat and rig only when extracting", function()
		local persistence, subject = loaded(501)
		persistence:RecordRunEnd(subject, {
			Outcome = "Defeated", EnemiesDefeated = 5, BestChain = 2, RoomsCleared = 2, Reward = 10,
			Heat = 6, Rig = "Carom", ChampionsDefeated = 2, BossesDefeated = 0, RevivesGiven = 1,
			Upgrades = { { Id = "Ignite" } }, KillsByArchetype = { Drifter = 3, Chaser = 2 },
		})
		extract(persistence, subject, { Heat = 3, Rig = "Striker", KillsByArchetype = { Drifter = 1 } })
		local profile = persistence:GetPublicProfile(subject)
		expect(profile.Stats.ChampionsDefeated).toBe(2)
		expect(profile.Stats.Revives).toBe(1)
		expect(profile.Stats.BestHeat).toBe(3)
		expect(profile.Stats.RigsExtracted.Carom).toBeNil()
		expect(profile.Stats.RigsExtracted.Striker).toBe(true)
		expect(profile.Codex.Cards.Ignite).toBe(true)
		expect(profile.Codex.Enemies.Drifter).toBe(4)
		expect(profile.Codex.Enemies.Chaser).toBe(2)
	end)
end)

describe("LoadoutService", function()
	it("selects only unlocked rigs, and only in the lobby", function()
		local persistence, subject = loaded(601)
		local inRun = false
		local loadout = LoadoutService.new(persistence, {
			canChange = function()
				return not inRun
			end,
		})
		expect(select(2, loadout:SelectRig(subject, "Scatter"))).toBe("locked")
		expect(select(2, loadout:SelectRig(subject, "Nope"))).toBe("unknown rig")
		persistence:GrantReward(subject, "xp-boost", 0, 5000)
		expect(loadout:SelectRig(subject, "Scatter").Id).toBe("Scatter")
		expect(loadout:GetRig(subject).Id).toBe("Scatter")
		inRun = true
		expect(select(2, loadout:SelectRig(subject, "Striker"))).toBe("in a run")
	end)

	it("keeps the Pact closed until the first extraction", function()
		local persistence, subject = loaded(602)
		local loadout = LoadoutService.new(persistence)
		expect(select(2, loadout:SetPact(subject, { Hardened = 1 }))).toBe("locked")
		-- Clearing it is always allowed.
		expect(loadout:SetPact(subject, {})).toBeTruthy()
		extract(persistence, subject)
		local pact, heat = loadout:SetPact(subject, { Hardened = 2, Drought = 5 })
		expect(pact.Hardened).toBe(2)
		expect(pact.Drought).toBe(1)
		expect(heat).toBe(4)
		expect(loadout:GetPact(subject).Hardened).toBe(2)
	end)

	it("pays each completed achievement once, and refuses unfinished ones", function()
		local persistence, subject = loaded(603)
		local loadout = LoadoutService.new(persistence)
		expect(select(2, loadout:ClaimAchievement(subject, "OutAlive"))).toBe("not complete")
		expect(select(2, loadout:ClaimAchievement(subject, "Bogus"))).toBe("unknown achievement")
		extract(persistence, subject)
		expect(loadout:ClaimableCount(subject)).toBe(1)
		local before = persistence:GetBalance(subject)
		local result = loadout:ClaimAchievement(subject, "OutAlive")
		expect(result.Coins).toBe(AchievementConfig.Get("OutAlive").Coins)
		expect(persistence:GetBalance(subject)).toBeGreaterThanOrEqual(before + result.Coins)
		expect(select(2, loadout:ClaimAchievement(subject, "OutAlive"))).toBe("already claimed")
		expect(loadout:ClaimableCount(subject)).toBe(0)
	end)

	it("refuses everything for a read-only profile", function()
		local failing = {}
		function failing:UpdateAsync()
			error("down", 0)
		end
		local persistence = PlayerDataService.new(failing)
		local subject = player(604)
		persistence:Load(subject)
		local loadout = LoadoutService.new(persistence)
		expect(select(2, loadout:SelectRig(subject, "Striker"))).toBe("profile not loaded")
		expect(select(2, loadout:ClaimAchievement(subject, "OutAlive"))).toBe("profile not loaded")
		expect(loadout:GetRig(subject).Id).toBe(RigConfig.DefaultId)
		expect(next(loadout:GetPact(subject))).toBeNil()
	end)

	it("is reachable through the remote router", function()
		local persistence, subject = loaded(605)
		persistence:GrantReward(subject, "xp-boost", 0, 5000)
		local loadout = LoadoutService.new(persistence)
		local results = {}
		local router = RemoteRouter.new(function()
			return nil
		end, persistence, nil, nil, {
			loadout = loadout,
			onLoadoutResult = function(_player, kind, result, reason)
				table.insert(results, { kind = kind, result = result, reason = reason })
			end,
		})
		router:Bind()
		Remotes.Get("SelectRig").OnServerEvent:Fire(subject, "Carom")
		Remotes.Get("SetPact").OnServerEvent:Fire(subject, "not a table")
		expect(results[1].kind).toBe("Rig")
		expect(results[1].result.Id).toBe("Carom")
		expect(results[2].kind).toBe("Pact")
		router:Destroy()
	end)
end)

--// a Pact in a real run ------------------------------------------------------

local function buildMatch(pactFor)
	local arena = Instance.new("Folder")
	local enemies = EnemyService.new(arena, PLANE_Y, 2)
	local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(2))
	local upgrades = UpgradeService.new(2)
	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated", "Notify" } do
		local remote = { calls = {} }
		function remote:FireClient(target, ...)
			table.insert(self.calls, { player = target, args = table.pack(...) })
		end
		net[name] = remote
	end
	local positions = {}
	local match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = upgrades,
		projectiles = ProjectileService.new(arena, arena, PLANE_Y),
		rewards = RewardService.new(),
		telemetry = TelemetryService.new(nil),
		net = net,
		world = {
			GetPosition = function(who)
				return positions[who] or Vector3.new(0, PLANE_Y, 0)
			end,
			Teleport = function(who, position)
				positions[who] = position
			end,
			SetWalkSpeed = function() end,
		},
		pactProvider = pactFor,
		planRun = function()
			return RunPlanner.Fixed({ "Gallery", "Smelter" })
		end,
	})
	return { match = match, enemies = enemies, upgrades = upgrades, net = net, positions = positions }
end

local function run(ctx, seconds, now)
	for _ = 1, math.floor(seconds / DT + 0.5) do
		now += DT
		ctx.match:Step(DT, now)
	end
	return now
end

describe("a Pact in a run", function()
	it("toughens enemies, narrows offers, stops regen and pays more", function()
		local hero = player(700)
		local ctx = buildMatch(function()
			return { Hardened = 3, Narrow = 1, Drought = 1 }
		end)
		ctx.match:RegisterPlayer(hero)
		ctx.match:RequestStart(hero, 0)
		local now = run(ctx, RunConfig.StartCountdown + DT, 0)
		expect(ctx.match:GetState()).toBe(States.Combat)
		expect(ctx.match:GetRunSnapshot().Heat).toBe(7)
		for _, enemy in ctx.enemies:GetEnemies() do
			expect(enemy.maxHealth).toBe(math.ceil(enemy.archetype.Health * 1.9 - 1e-6))
		end

		local state = ctx.match:GetPlayerState(hero)
		state.health = 40
		now = run(ctx, RunConfig.Regen.Delay + 2, now)
		expect(state.health).toBe(40) -- Drought

		local function clear()
			__clearRoom(ctx.match._rooms, function()
				for _, enemy in ctx.enemies:GetEnemies() do
					ctx.enemies:ApplyHit(enemy.part, 999, nil, hero)
				end
			end, function(seconds)
				now = run(ctx, seconds, now)
			end)
		end
		clear()
		now = run(ctx, DT, now)
		expect(ctx.match:GetState()).toBe(States.UpgradeChoice)
		expect(#ctx.upgrades:GetOffer(hero).cards).toBe(2)

		local _, heat = ctx.match:GetPact()
		expect(heat).toBe(7)
		local offer = ctx.upgrades:GetOffer(hero)
		ctx.match:ChooseUpgrade(hero, offer.id, offer.cards[1].Id, now)
		now = run(ctx, RunConfig.TransitionDuration + 2 * DT, now)
		expect(ctx.match:GetState()).toBe(States.Combat)
		clear()
		now = run(ctx, DT, now)
		expect(ctx.match:GetState()).toBe(States.Results)
		local results = ctx.net.RunResults
		local summary = results.calls[#results.calls].args[1]
		expect(summary.Outcome).toBe("Extracted")
		expect(summary.Heat).toBe(7)
		now = run(ctx, RunConfig.ResultsDuration + 2 * DT, now)
		-- Back in the lobby, the arena forgets the Pact.
		expect(ctx.enemies:GetModifiers().Health).toBe(1)
	end)

	it("runs a group at the gentlest shared Pact", function()
		local a, b = player(701), player(702)
		local pacts = { [a] = { Hardened = 3 }, [b] = { Hardened = 1, Brutal = 2 } }
		local ctx = buildMatch(function(who)
			return pacts[who]
		end)
		ctx.match:RegisterPlayer(a)
		ctx.match:RegisterPlayer(b)
		ctx.match:RequestStart(a, 0)
		local pact, heat = ctx.match:GetPact()
		expect(pact.Hardened).toBe(1)
		expect(pact.Brutal).toBeNil()
		expect(heat).toBe(1)
	end)

	it("scales run rewards and experience by Heat", function()
		local state = { coins = 100, roomsCleared = 0, kills = 10, championKills = 1, stats = { RewardMultiplier = 1, CoinMultiplier = 1 } }
		expect(RewardService.Compute(state, "Defeated", false, 1.5)).toBe(math.floor(100 * RewardConfig.DefeatHaulShare * 1.5))
		local plain = RewardService.Experience(state, "Defeated", false)
		expect(RewardService.Experience(state, "Defeated", false, 2)).toBe(plain * 2)
		expect(plain).toBe(10 * 4 + CombatConfig.ChampionXp)
	end)
end)

describe("co-op revives", function()
	local function downedPair()
		local a, b = player(801), player(802)
		local ctx = buildMatch(nil)
		ctx.match:RegisterPlayer(a)
		ctx.match:RegisterPlayer(b)
		ctx.match:RequestStart(a, 0)
		local now = run(ctx, RunConfig.StartCountdown + DT, 0)
		local downed = ctx.match:GetPlayerState(b)
		downed.invulnerableUntil = 0
		ctx.match:HandlePlayerContact(b, 9999, nil, now)
		expect(downed.alive).toBe(false)
		return ctx, a, b, now
	end

	it("brings a downed teammate back when someone stands close, and credits the helper", function()
		local ctx, a, b, now = downedPair()
		ctx.positions[a] = Vector3.new(0, PLANE_Y, 0)
		ctx.positions[b] = Vector3.new(3, PLANE_Y, 0)
		expect(ctx.match:GetRunSnapshot().Downed[1].UserId).toBe(b.UserId)
		now = run(ctx, CombatConfig.Revive.Seconds + 0.2, now)
		local revived = ctx.match:GetPlayerState(b)
		expect(revived.alive).toBe(true)
		expect(revived.health).toBe(math.floor(revived.maxHealth * CombatConfig.Revive.HealthFraction))
		expect(ctx.match:GetPlayerState(a).revivesGiven).toBe(1)
		expect(ctx.match:GetRunSnapshot().Downed).toBeNil()
		local _ = now
	end)

	it("makes no progress while nobody is close, and drains what was made", function()
		local ctx, a, b, now = downedPair()
		ctx.positions[a] = Vector3.new(0, PLANE_Y, 0)
		ctx.positions[b] = Vector3.new(3, PLANE_Y, 0)
		now = run(ctx, 1, now)
		local state = ctx.match:GetPlayerState(b)
		local partway = state.reviveProgress
		expect(partway).toBeGreaterThan(0)
		ctx.positions[a] = Vector3.new(40, PLANE_Y, 0)
		now = run(ctx, 1, now)
		expect(state.reviveProgress).toBeLessThan(partway)
		expect(state.alive).toBe(false)
	end)

	it("never runs in a solo run", function()
		local hero = player(803)
		local ctx = buildMatch(nil)
		ctx.match:RegisterPlayer(hero)
		ctx.match:RequestStart(hero, 0)
		run(ctx, RunConfig.StartCountdown + DT, 0)
		expect(ctx.match:GetRunSnapshot().Downed).toBeNil()
	end)
end)

describe("lobby views", function()
	local profile = {
		Progression = { Level = 6 },
		SelectedRig = "Carom",
		Pact = { Hardened = 2 },
		Stats = { RunsExtracted = 1, EnemiesDefeated = 300 },
		Achievements = { Slayer = true },
		Codex = { Cards = { SplitShot = true }, Enemies = { Drifter = 3 } },
	}

	it("RigView marks the selected rig and locks the ones above your level", function()
		local picked
		local view = RigView.new(Instance.new("Folder"), function(id)
			picked = id
		end)
		view:SetProfile(profile)
		expect(view:GetSelected()).toBe("Carom")
		expect(view.rows.Carom.button.Text).toBe("SELECTED")
		expect(view.rows.Scatter.button.Text).toBe("SELECT")
		expect(view.rows.Gambler.button.Text).toBe("LEVEL 16")
		view.rows.Gambler.button.Activated:Fire()
		expect(picked).toBeNil()
		view.rows.Scatter.button.Activated:Fire()
		expect(picked).toBe("Scatter")
	end)

	it("PactView shows Heat and rewards, and stays locked before the first extraction", function()
		local view = PactView.new(Instance.new("Folder"), function() end)
		view:SetProfile(profile)
		expect(view.heatLabel.Text).toBe("Heat 2  -  +20% coins and XP")
		expect(view.rows.Hardened.rank.Text).toBe("2 / 3")
		view:SetProfile({ Stats = { RunsExtracted = 0 }, Pact = {} })
		expect(string.find(view.heatLabel.Text, "Locked", 1, true)).toBeTruthy()
		expect(view.rows.Hardened.plus.Visible).toBe(false)
	end)

	it("JournalView lists achievements with claim state and hides undiscovered Codex entries", function()
		local claimed
		local view = JournalView.new(Instance.new("Folder"), function(id)
			claimed = id
		end)
		view:SetProfile(profile)
		local slayer = view.achievementRows[1]
		expect(slayer.button.Text).toBe("DONE")
		local cards, cardTotal, enemies = JournalView.CodexCounts(profile)
		expect(cards).toBe(1)
		expect(cardTotal).toBe(#UpgradeConfig.MainCards())
		expect(enemies).toBe(1)
		view:ShowTab("Codex")
		expect(view.codexList.Visible).toBe(true)
		expect(view.achievementList.Visible).toBe(false)
		-- OutAlive is complete (one extraction) and unclaimed.
		for _, row in view.achievementRows do
			if row.id == "OutAlive" then
				expect(row.button.Text).toBe("CLAIM")
				row.button.Activated:Fire()
			end
		end
		expect(claimed).toBe("OutAlive")
	end)

	it("MenuDock keeps a short rail and tucks the rest behind MORE", function()
		local opened
		local dock = MenuDock.new(Instance.new("Folder"), {
			Journal = function()
				opened = "Journal"
			end,
		})
		for _, id in { "Rigs", "Pact", "Daily", "Quests" } do
			expect(dock.buttons[id].Parent).toBe(dock.dock)
		end
		for _, id in { "Journal", "Codes", "Invite" } do
			expect(dock.buttons[id].Parent).toBe(dock.more)
		end
		expect(dock:IsMoreOpen()).toBe(false)
		dock.moreButton.Activated:Fire()
		expect(dock:IsMoreOpen()).toBe(true)
		expect(dock.moreButton.Text).toBe("CLOSE")
		-- Choosing something closes the pop-out.
		dock.buttons.Journal.Activated:Fire()
		expect(opened).toBe("Journal")
		expect(dock:IsMoreOpen()).toBe(false)
		-- Hiding the dock (a run starting) closes it too.
		dock.moreButton.Activated:Fire()
		dock:SetVisible(false)
		expect(dock:IsMoreOpen()).toBe(false)
	end)

	it("MenuDock shows a dot on MORE when the Journal behind it has something to claim", function()
		local dock = MenuDock.new(Instance.new("Folder"), {})
		expect(dock.moreDot.Visible).toBe(false)
		dock:SetJournalClaimable(true)
		expect(dock.dots.Journal.Visible).toBe(true)
		expect(dock.moreDot.Visible).toBe(true)
		dock:SetClaimable(true, false)
		expect(dock.moreDot.Visible).toBe(true)
		dock:SetJournalClaimable(false)
		expect(dock.moreDot.Visible).toBe(false)
	end)
end)

describe("HUD for the new systems", function()
	local HudView = __require("HudView")
	local DamagePopups = __require("DamagePopups")

	local function combat(extra)
		local snapshot = { State = States.Combat, RoomIndex = 2, RoomCount = 7, RoomName = "Cold Smelter", Zone = "Foundry", EnemiesRemaining = 4 }
		for key, value in extra or {} do
			snapshot[key] = value
		end
		return snapshot
	end

	it("shows Heat in the room line and a downed teammate over the target count", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:SetUserId(1)
		hud:UpdateRun(combat({ Heat = 5 }))
		expect(string.find(hud.roomLabel.Text, "Heat 5", 1, true)).toBeTruthy()
		expect(hud.objectiveLabel.Text).toBe("4 targets left")
		hud:UpdateRun(combat({ Downed = { { UserId = 2, Name = "Pal", Progress = 0.5 } } }))
		expect(hud.objectiveLabel.Text).toBe("Pal is down! Stand next to them to revive (50%)")
		-- Never asks you to revive yourself.
		hud:UpdateRun(combat({ Downed = { { UserId = 1, Name = "Me", Progress = 0 } } }))
		expect(hud.objectiveLabel.Text).toBe("4 targets left")
	end)

	it("shows revive progress when down and Second Wind when ready", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:UpdatePlayer({ Health = 50, MaxHealth = 100, Alive = true, Coins = 0, Upgrades = {}, ExtraLivesLeft = 1 })
		expect(string.find(hud.healthLabel.Text, "Second Wind", 1, true)).toBeTruthy()
		hud:UpdatePlayer({ Health = 0, MaxHealth = 100, Alive = false, Coins = 0, Upgrades = {}, ReviveProgress = 0.25 })
		expect(hud.healthLabel.Text).toBe("DOWN  -  being revived 25%")
	end)

	it("shows the lobby loadout line", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:SetLoadout("Carom", { Hardened = 2 })
		expect(hud.loadoutLabel.Text).toBe("Rig: Carom   -   Heat 2")
		hud:SetLoadout("Nope", {})
		expect(hud.loadoutLabel.Text).toBe("Rig: Striker")
	end)

	it("marks crits with an exclamation and colours element damage", function()
		local popups = DamagePopups.new(Instance.new("Folder"))
		popups:Show(Vector3.zero, 4, "Crit", 0)
		popups:Show(Vector3.zero, 1.5, "Burn", 0)
		expect(popups:GetActiveText(1)).toBe("4!")
		expect(popups:GetActiveText(2)).toBe("1.5")
	end)
end)
