-- The retention layer: daily login rewards, daily quests, promo codes, badges, global
-- leaderboards, and the lobby menus and toasts that show them.
local CalloutView = __require("CalloutView")
local CodesView = __require("CodesView")
local DailyView = __require("DailyView")
local LeaderboardService = __require("LeaderboardService")
local LobbyBuilder = __require("LobbyBuilder")
local MenuDock = __require("MenuDock")
local MetaConfig = __require("MetaConfig")
local MetaService = __require("MetaService")
local NotificationView = __require("NotificationView")
local PlayerDataService = __require("PlayerDataService")
local ProgressionConfig = __require("ProgressionConfig")
local QuestsView = __require("QuestsView")
local RemoteRouter = __require("RemoteRouter")
local Remotes = __require("Remotes")
local StatsView = __require("StatsView")

local DAY = MetaConfig.SecondsPerDay
local START = 20000 * DAY + 3600 -- an arbitrary day, one hour in

local function player(userId)
	return { Name = "M" .. userId, UserId = userId }
end

-- A loaded profile and a MetaService whose clock the test controls.
local function setup(userId, store)
	local clock = { now = START }
	local persistence = PlayerDataService.new(store or __FakeDataStore.new())
	local subject = player(userId)
	persistence:Load(subject)
	local badges = {}
	local meta = MetaService.new(persistence, {
		wallClock = function()
			return clock.now
		end,
		awardBadge = function(who, badgeId)
			table.insert(badges, { who = who, id = badgeId })
		end,
	})
	return meta, persistence, subject, clock, badges
end

describe("MetaConfig", function()
	it("cycles the seven daily rewards and grows them through the week", function()
		expect(MetaConfig.DailyRewardFor(1).Coins).toBe(MetaConfig.DailyRewards[1].Coins)
		expect(MetaConfig.DailyRewardFor(7).Coins).toBeGreaterThan(MetaConfig.DailyRewardFor(1).Coins)
		expect(MetaConfig.DailyRewardFor(8)).toBe(MetaConfig.DailyRewards[1])
		expect(MetaConfig.DailyRewardFor(0)).toBe(MetaConfig.DailyRewards[1])
	end)

	it("draws the same three distinct quests for a player all day, and new ones tomorrow", function()
		local today = MetaConfig.QuestsFor(20000, 55)
		expect(#today).toBe(MetaConfig.QuestsPerDay)
		local stats = {}
		for _, id in today do
			local quest = MetaConfig.QuestById[id]
			expect(quest).toBeTruthy()
			expect(stats[quest.Stat]).toBeNil()
			stats[quest.Stat] = true
		end
		expect(table.concat(MetaConfig.QuestsFor(20000, 55), ",")).toBe(table.concat(today, ","))
		local differs = false
		for day = 20001, 20010 do
			if table.concat(MetaConfig.QuestsFor(day, 55), ",") ~= table.concat(today, ",") then
				differs = true
			end
		end
		expect(differs).toBe(true)
	end)

	it("normalises codes and rejects junk", function()
		expect(MetaConfig.NormaliseCode(" ricochet ")).toBe("RICOCHET")
		expect(MetaConfig.NormaliseCode("bank-shot")).toBe("BANKSHOT")
		expect(MetaConfig.NormaliseCode("")).toBeNil()
		expect(MetaConfig.NormaliseCode(42)).toBeNil()
		expect(MetaConfig.NormaliseCode(string.rep("A", 100))).toBeNil()
		expect(MetaConfig.NormaliseCode("!!!")).toBeNil()
	end)

	it("counts the reset down to midnight UTC", function()
		expect(MetaConfig.SecondsUntilReset(START)).toBe(DAY - 3600)
	end)
end)

describe("daily login reward", function()
	it("pays once a day and builds a streak on consecutive days", function()
		local meta, persistence, subject, clock = setup(501)
		expect(meta:GetState(subject).Daily.CanClaim).toBe(true)
		local first = meta:ClaimDaily(subject)
		expect(first.Streak).toBe(1)
		expect(first.Coins).toBe(MetaConfig.DailyRewards[1].Coins)
		expect(persistence:GetBalance(subject)).toBe(first.Coins)

		local again, reason = meta:ClaimDaily(subject)
		expect(again).toBeNil()
		expect(reason).toBe("already claimed")
		expect(meta:GetState(subject).Daily.CanClaim).toBe(false)

		clock.now += DAY
		expect(meta:GetState(subject).Daily.Streak).toBe(1)
		expect(meta:GetState(subject).Daily.DayIndex).toBe(2)
		local second = meta:ClaimDaily(subject)
		expect(second.Streak).toBe(2)
		expect(second.Coins).toBe(MetaConfig.DailyRewards[2].Coins)
	end)

	it("starts the streak again after a missed day", function()
		local meta, _, subject, clock = setup(502)
		meta:ClaimDaily(subject)
		clock.now += DAY
		meta:ClaimDaily(subject)
		clock.now += 2 * DAY
		expect(meta:GetState(subject).Daily.Streak).toBe(0)
		expect(meta:ClaimDaily(subject).Streak).toBe(1)
	end)

	it("cannot be claimed twice across a rejoin on the same day", function()
		local store = __FakeDataStore.new()
		local meta, persistence, subject = setup(503, store)
		meta:ClaimDaily(subject)
		persistence:Release(subject, 1)

		local meta2, persistence2, subject2 = setup(503, store)
		local result, reason = meta2:ClaimDaily(subject2)
		expect(result).toBeNil()
		expect(reason).toBe("already claimed")
		expect(persistence2:GetBalance(subject2)).toBe(MetaConfig.DailyRewards[1].Coins)
	end)

	it("levels players up with its experience like any other payout", function()
		local meta, persistence, subject, clock = setup(504)
		for _ = 1, 5 do
			meta:ClaimDaily(subject)
			clock.now += DAY
		end
		local xp = 0
		for index = 1, 5 do
			xp += MetaConfig.DailyRewards[index].Xp or 0
		end
		expect(persistence:GetXp(subject)).toBe(xp)
		expect((ProgressionConfig.LevelFor(xp))).toBeGreaterThan(1)
	end)

	it("pays nothing to a read-only profile", function()
		local failing = {}
		function failing:UpdateAsync()
			error("down", 0)
		end
		local meta, _, subject = setup(505, failing)
		expect(meta:GetState(subject)).toBeNil()
		local result, reason = meta:ClaimDaily(subject)
		expect(result).toBeNil()
		expect(reason).toBe("profile not loaded")
	end)
end)

describe("daily quests", function()
	local function runSummary(overrides)
		local summary = { Outcome = "Defeated", EnemiesDefeated = 0, RoomsCleared = 0, BestChain = 0, Reward = 0 }
		for key, value in overrides or {} do
			summary[key] = value
		end
		return summary
	end

	it("tracks progress from runs and pays a completed quest exactly once", function()
		local meta, persistence, subject = setup(601)
		local quests = meta:GetState(subject).Quests
		expect(#quests).toBe(3)
		local quest = MetaConfig.QuestById[quests[1].Id]

		local notYet, reason = meta:ClaimQuest(subject, quest.Id)
		expect(notYet).toBeNil()
		expect(reason).toBe("not complete")

		-- A run big enough to finish any quest.
		local completed = meta:OnRunEnd(subject, runSummary({
			Outcome = "Extracted", EnemiesDefeated = 500, RoomsCleared = 50, BestChain = 20, Reward = 5000,
		}))
		expect(#completed).toBe(3)
		for _, entry in meta:GetState(subject).Quests do
			expect(entry.Complete).toBe(true)
			expect(entry.Progress).toBe(entry.Target)
		end

		local before = persistence:GetBalance(subject)
		local paid = meta:ClaimQuest(subject, quest.Id)
		expect(paid.Coins).toBe(quest.Coins)
		expect(persistence:GetBalance(subject) - before).toBeGreaterThan(quest.Coins - 1)
		local twice, why = meta:ClaimQuest(subject, quest.Id)
		expect(twice).toBeNil()
		expect(why).toBe("already claimed")
	end)

	it("adds runs together, but keeps only the best chain", function()
		local meta, _, subject = setup(602)
		meta:GetState(subject)
		meta:OnRunEnd(subject, runSummary({ EnemiesDefeated = 3, BestChain = 2 }))
		meta:OnRunEnd(subject, runSummary({ EnemiesDefeated = 4, BestChain = 5 }))
		meta:OnRunEnd(subject, runSummary({ EnemiesDefeated = 1, BestChain = 1 }))
		for _, entry in meta:GetState(subject).Quests do
			local quest = MetaConfig.QuestById[entry.Id]
			if quest.Stat == "Kills" then
				expect(entry.Progress).toBe(8)
			elseif quest.Stat == "BestChain" then
				expect(entry.Progress).toBe(math.min(5, quest.Target))
			elseif quest.Stat == "Runs" then
				expect(entry.Progress).toBe(3)
			end
		end
	end)

	it("refuses quests that are not today's", function()
		local meta, _, subject = setup(603)
		local result, reason = meta:ClaimQuest(subject, "NoSuchQuest")
		expect(result).toBeNil()
		expect(reason).toBe("unknown quest")
	end)

	it("draws fresh quests with no progress the next day", function()
		local meta, _, subject, clock = setup(604)
		meta:OnRunEnd(subject, runSummary({ EnemiesDefeated = 500, RoomsCleared = 50, Outcome = "Extracted", BestChain = 20, Reward = 900 }))
		clock.now += DAY
		for _, entry in meta:GetState(subject).Quests do
			expect(entry.Progress).toBe(0)
			expect(entry.Claimed).toBe(false)
		end
	end)
end)

describe("promo codes", function()
	it("redeems a code once per account, in any case", function()
		local meta, persistence, subject = setup(701)
		local result = meta:RedeemCode(subject, "ricochet")
		expect(result.Code).toBe("RICOCHET")
		expect(persistence:GetBalance(subject)).toBe(MetaConfig.Codes.RICOCHET.Coins)
		local again, reason = meta:RedeemCode(subject, "RICOCHET")
		expect(again).toBeNil()
		expect(reason).toBe("already redeemed")
		expect(persistence:GetBalance(subject)).toBe(MetaConfig.Codes.RICOCHET.Coins)
	end)

	it("rejects unknown and expired codes", function()
		local meta, _, subject, clock = setup(702)
		expect(select(2, meta:RedeemCode(subject, "NOPE"))).toBe("invalid code")
		expect(select(2, meta:RedeemCode(subject, nil))).toBe("invalid code")
		MetaConfig.Codes.OLDCODE = { Coins = 10, Expires = clock.now - 1 }
		expect(select(2, meta:RedeemCode(subject, "oldcode"))).toBe("expired")
		MetaConfig.Codes.OLDCODE = nil
	end)
end)

describe("badges", function()
	it("awards configured badges once per session and skips ones without an id", function()
		local meta, _, subject, _, badges = setup(801)
		meta:OnRunEnd(subject, { Outcome = "Extracted", EnemiesDefeated = 1, RoomsCleared = 1, BestChain = 1, Reward = 1 })
		expect(#badges).toBe(0) -- every shipped id is 0

		MetaConfig.Badges.FirstDescent.Id = 12345
		meta:OnRunEnd(subject, { Outcome = "Defeated", EnemiesDefeated = 1, RoomsCleared = 0, BestChain = 1, Reward = 1 })
		meta:OnRunEnd(subject, { Outcome = "Defeated", EnemiesDefeated = 1, RoomsCleared = 0, BestChain = 1, Reward = 1 })
		MetaConfig.Badges.FirstDescent.Id = 0
		expect(#badges).toBe(1)
		expect(badges[1].id).toBe(12345)
	end)

	it("earns the extraction, chain and level badges from the right runs", function()
		local earned = MetaConfig.BadgesForRun({ Outcome = "Extracted", BestChain = 9 }, 26)
		for _, key in { "FirstDescent", "FirstExtraction", "Chain8", "Level10", "Level25" } do
			expect(table.find(earned, key) ~= nil).toBe(true)
		end
		expect(table.find(earned, "Level50")).toBeNil()
	end)
end)

describe("meta remotes", function()
	it("routes claims through the rate limiter to the meta service", function()
		local persistence = PlayerDataService.new(__FakeDataStore.new())
		local subject = Harness.addPlayer("Claimer")
		persistence:Load(subject)
		local meta = MetaService.new(persistence, { wallClock = function()
			return START
		end })
		local results = {}
		local router = RemoteRouter.new({ HandleFire = function() end }, persistence, nil, nil, {
			meta = meta,
			onMetaResult = function(who, kind, result, reason)
				table.insert(results, { who = who, kind = kind, result = result, reason = reason })
			end,
		})
		router:Bind()
		Remotes.Get("ClaimDaily").OnServerEvent:Fire(subject)
		Remotes.Get("RedeemCode").OnServerEvent:Fire(subject, { "not a string" })
		Remotes.Get("RequestMeta").OnServerEvent:Fire(subject)
		expect(results[1].kind).toBe("Daily")
		expect(results[1].result.Streak).toBe(1)
		expect(results[2].kind).toBe("Code")
		expect(results[2].reason).toBe("invalid code")
		expect(results[3].kind).toBe("Sync")
		router:Destroy()
		Harness.removePlayer(subject)
	end)
end)

describe("leaderboards", function()
	local function orderedStore()
		local store = { data = {}, sets = 0 }
		function store:SetAsync(key, value)
			self.sets += 1
			self.data[key] = value
		end
		function store:GetSortedAsync(ascending, pageSize)
			local rows = {}
			for key, value in self.data do
				table.insert(rows, { key = key, value = value })
			end
			table.sort(rows, function(a, b)
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end)
			while #rows > pageSize do
				table.remove(rows)
			end
			return { GetCurrentPage = function()
				return rows
			end }
		end
		return store
	end

	local function boardText(board)
		return board:FindFirstChildOfClass("SurfaceGui"):FindFirstChild("Text").Text
	end

	it("writes players' values and prints the top rows on each board", function()
		local _, _, parts = LobbyBuilder.Build(Instance.new("Folder"))
		local stores = {}
		local service = LeaderboardService.new({
			boards = parts.leaderboards,
			getStore = function(name)
				stores[name] = stores[name] or orderedStore()
				return stores[name]
			end,
			getName = function(userId)
				return "User" .. userId
			end,
			spawn = function(work)
				work()
			end,
		})
		service:Submit({ Name = "Ace", DisplayName = "Ace", UserId = 1 }, { Level = 5000, Kills = 300, Extractions = 9 })
		service:Submit({ Name = "Bo", DisplayName = "Bo", UserId = 2 }, { Level = 100, Kills = 900, Extractions = 0 })
		service:Step(0)
		expect(stores.LB_Xp_v1.data["1"]).toBe(5000)
		expect(stores.LB_Extractions_v1.data["2"]).toBeNil() -- zero is not worth a row
		local levels = boardText(parts.leaderboards.Level)
		expect(levels:find("1.  Ace", 1, true)).toBeTruthy()
		expect(levels:find("Lv " .. (ProgressionConfig.LevelFor(5000)), 1, true)).toBeTruthy()
		expect(boardText(parts.leaderboards.Kills):find("1.  Bo", 1, true)).toBeTruthy()

		-- Not due again until the intervals pass.
		local sets = stores.LB_Xp_v1.sets
		service:Submit({ Name = "Ace", DisplayName = "Ace", UserId = 1 }, { Level = 6000 })
		service:Step(1)
		expect(stores.LB_Xp_v1.sets).toBe(sets)
		service:Step(LeaderboardService.FlushInterval + 1)
		expect(stores.LB_Xp_v1.data["1"]).toBe(6000)
	end)

	it("says it is offline when the store cannot be reached", function()
		local _, _, parts = LobbyBuilder.Build(Instance.new("Folder"))
		local service = LeaderboardService.new({
			boards = parts.leaderboards,
			getStore = function()
				error("no API access")
			end,
			getName = function()
				return "x"
			end,
			spawn = function(work)
				work()
			end,
		})
		service:Submit({ Name = "A", UserId = 1 }, { Level = 10 })
		service:Step(0)
		expect(boardText(parts.leaderboards.Level)).toBe(LeaderboardService.OfflineText)
	end)
end)

describe("lobby landmarks", function()
	local lobby, _, parts = LobbyBuilder.Build(Instance.new("Folder"))

	it("has the title marquee, three leaderboards and lit braziers", function()
		local title = false
		for _, gui in lobby:GetDescendants() do
			if gui.ClassName == "TextLabel" and gui.Text == "RICOCHET DEPTHS" then
				title = true
			end
		end
		expect(title).toBe(true)
		for _, id in { "Level", "Kills", "Extractions" } do
			expect(parts.leaderboards[id]).toBeTruthy()
		end
		local fires = 0
		for _, child in lobby:GetDescendants() do
			if child.ClassName == "Fire" then
				fires += 1
			end
		end
		expect(fires).toBeGreaterThanOrEqual(4)
	end)

	it("animates crystals that nobody can bump into or shoot", function()
		local ambience = lobby:FindFirstChild("Ambience")
		local spinning = 0
		for _, part in ambience:GetChildren() do
			if part:IsA("BasePart") then
				expect(part.CanCollide).toBe(false)
				expect(part.CanQuery).toBe(false)
				if part:GetAttribute("Spin") then
					spinning += 1
				end
			end
		end
		expect(spinning).toBeGreaterThanOrEqual(3)
	end)
end)

describe("menus and toasts", function()
	local function state(canClaim, streak, dayIndex, quests)
		return {
			Daily = { CanClaim = canClaim, Streak = streak, DayIndex = dayIndex },
			Quests = quests or {},
			ResetsIn = 3 * 3600 + 120,
		}
	end

	it("shows a claim dot on Daily and Quests only when something is waiting", function()
		local pressed = {}
		local dock = MenuDock.new(Instance.new("Folder"), {
			Daily = function()
				table.insert(pressed, "Daily")
			end,
		})
		dock:SetClaimable(true, false)
		expect(dock.dots.Daily.Visible).toBe(true)
		expect(dock.dots.Quests.Visible).toBe(false)
		dock.buttons.Daily.Activated:Fire()
		expect(pressed[1]).toBe("Daily")
		dock:SetVisible(false)
		expect(dock.dock.Visible).toBe(false)
	end)

	it("marks the week's tiles as claimed, today, or still to come", function()
		local claims = 0
		local view = DailyView.new(Instance.new("Folder"), function()
			claims += 1
		end)
		view:SetState(state(true, 2, 3).Daily, 100)
		expect(view.tiles[1].state.Text).toBe("CLAIMED")
		expect(view.tiles[3].state.Text).toBe("TODAY")
		expect(view.tiles[4].state.Text).toBe("")
		view.claimButton.Activated:Fire()
		expect(claims).toBe(1)
		view:SetState(state(false, 3, 3).Daily, 3 * 3600 + 120)
		expect(view.tiles[3].state.Text).toBe("CLAIMED")
		expect(view.resetLabel.Text).toBe("Next reward in 3h 2m")
		view.claimButton.Activated:Fire()
		expect(claims).toBe(1) -- nothing to claim
	end)

	it("lists quests with progress and only lets finished ones be claimed", function()
		local claimed = {}
		local view = QuestsView.new(Instance.new("Folder"), function(id)
			table.insert(claimed, id)
		end)
		view:SetState({
			{ Id = "A", Title = "Defeat 40 enemies", Target = 40, Progress = 10, Coins = 100, Xp = 80, Claimed = false, Complete = false },
			{ Id = "B", Title = "Play 3 descents", Target = 3, Progress = 3, Coins = 90, Xp = 70, Claimed = false, Complete = true },
		}, 60)
		expect(view.rows[1].count.Text).toBe("10 / 40")
		expect(view.rows[1].button.Text).toBe("IN PROGRESS")
		view.rows[1].button.Activated:Fire()
		view.rows[2].button.Activated:Fire()
		expect(#claimed).toBe(1)
		expect(claimed[1]).toBe("B")
	end)

	it("sends a typed code and clears the box", function()
		local sent = {}
		local view = CodesView.new(Instance.new("Folder"), function(code)
			table.insert(sent, code)
		end)
		view.redeemButton.Activated:Fire()
		expect(#sent).toBe(0)
		view.box.Text = "launch"
		view.redeemButton.Activated:Fire()
		expect(sent[1]).toBe("launch")
		expect(view.box.Text).toBe("")
	end)

	it("fills the profile card from the saved stats", function()
		local view = StatsView.new(Instance.new("Folder"), "TESTER")
		view:SetProfile({ Progression = ProgressionConfig.Describe(150), Stats = { RunsStarted = 4, EnemiesDefeated = 77 } })
		expect(view.levelLabel.Text).toBe("LEVEL 2")
		expect(view.values.RunsStarted.Text).toBe("4")
		expect(view.values.EnemiesDefeated.Text).toBe("77")
		expect(view.values.CoinsEarned.Text).toBe("0")
	end)

	it("keeps at most a few toasts on screen", function()
		local view = NotificationView.new(Instance.new("Folder"))
		for index = 1, 7 do
			view:Show("Toast " .. index, "Info")
		end
		expect(view:Count()).toBe(NotificationView.MaxShown)
		expect(view:Show("", "Info")).toBeNil()
	end)

	it("calls out kill streaks and long ricochets", function()
		expect((CalloutView.TextFor(1, 1))).toBeNil()
		expect((CalloutView.TextFor(1, 4))).toBe("RICOCHET x4")
		expect((CalloutView.TextFor(2, 1))).toBe("DOUBLE KILL")
		expect((CalloutView.TextFor(6, 1))).toBe("RAMPAGE x6")
		local now = 0
		local view = CalloutView.new(Instance.new("Folder"), function()
			return now
		end)
		expect(view:OnKill(1)).toBeNil()
		now += 1
		expect(view:OnKill(1)).toBe("DOUBLE KILL")
		now += 5
		expect(view:OnKill(1)).toBeNil() -- the streak lapsed
	end)
end)
