-- End-to-end smoke test of GameBootstrap.Start: the real wiring between remotes, the kiosks,
-- the home base and its plots, the multiplayer gates, the solo portal and the arena director. Named to run last: Start
-- connects to Players, Heartbeat and every remote for the life of the process, and nothing tears
-- that down, so any test file after it would have a second game listening to its events.
local DebugConfig = __require("DebugConfig")
local GameBootstrap = __require("GameBootstrap")
local Remotes = __require("Remotes")
local RunConfig = __require("RunConfig")
local BaseConfig = __require("BaseConfig")

local DT = 1 / 30

describe("GameBootstrap wiring", function()
	DebugConfig.LogTelemetry = false
	-- Earlier files leave players behind; this game starts with an empty server.
	for _, leftover in game:GetService("Players"):GetPlayers() do
		Harness.removePlayer(leftover)
	end
	local store = __FakeDataStore.new()
	rawset(Harness.service("DataStoreService"), "GetDataStore", function()
		return store
	end)
	-- These players are veterans: the first descent has its own test below.
	local FeatureFlags = __require("FeatureFlags")
	FeatureFlags.FirstDescent = false
	-- Whatever today's modifier is would change the numbers below; it has its own tests.
	FeatureFlags.DailyModifiers = false
	local systems = GameBootstrap.Start()
	local lobby = workspace:FindFirstChild("Lobby")
	local spawnAt = RunConfig.LobbyReturnPosition

	local first, second, solo = Harness.addPlayer("GateA"), Harness.addPlayer("GateB"), Harness.addPlayer("Solo")
	for _, player in { first, second, solo } do
		Harness.giveCharacter(player, spawnAt)
	end
	local function root(player)
		return player.Character:FindFirstChild("HumanoidRootPart")
	end

	local function firedTo(player, remoteName)
		local out = {}
		for _, call in rawget(Remotes.Get(remoteName), "_fired") do
			if call.player == player then
				table.insert(out, call.args)
			end
		end
		return out
	end

	it("loads profiles, gives each player a plot and opens Cosmetics at its kiosk", function()
		expect(systems.persistence:IsLoaded(first)).toBe(true)
		for _, player in { first, second, solo } do
			expect(player:GetAttribute("PlotIndex")).toBeTruthy()
			expect(#firedTo(player, "BaseSync")).toBeGreaterThan(0)
		end
		lobby:FindFirstChild("CosmeticsKiosk"):FindFirstChild("OpenCosmeticsPrompt").Triggered:Fire(first)
		local opened = firedTo(first, "ShopOpen")
		expect(#opened).toBe(1)
		expect(opened[1][1]).toBe("Cosmetics")
	end)

	it("builds through the remote while in the lobby, and raises it on the plot", function()
		systems.persistence:GrantReward(first, "smoke-seed", 1000)
		Remotes.Get("UpgradeBuilding").OnServerEvent:Fire(first, "Infirmary", 3)
		expect(systems.persistence:GetMetaLevels(first).Infirmary).toBe(1)
		local synced = firedTo(first, "BaseSync")
		local latest = synced[#synced][1]
		expect(latest.Levels.Infirmary).toBe(1)
		expect(latest.Layout.Infirmary).toBe(3)
		local plot = systems.builder:PlotFor(first)
		expect(plot.buildings:FindFirstChild("Infirmary")).toBeTruthy()
		-- A refusal comes back as a toast, and nothing is spent.
		Remotes.Get("UpgradeBuilding").OnServerEvent:Fire(second, "Forge")
		local notes = firedTo(second, "Notify")
		expect(notes[#notes][1].Kind).toBe("Error")
	end)

	it("takes a player to their plot from the Outpost kiosk and back from the entry pad", function()
		lobby:FindFirstChild("OutpostKiosk"):FindFirstChild("OpenOutpostPrompt").Triggered:Fire(solo)
		local entry = systems.builder:EntryPosition(solo:GetAttribute("PlotIndex"))
		expect((root(solo).Position - entry).Magnitude).toBeLessThan(5)
		local plot = systems.builder:PlotFor(solo)
		plot.entry:FindFirstChild("ReturnPrompt").Triggered:Fire(solo)
		expect((root(solo).Position - spawnAt).Magnitude).toBeLessThan(5)
	end)

	it("cheers another player's base through the remote, once a day", function()
		local before = systems.persistence:GetBalance(first)
		Remotes.Get("CheerBase").OnServerEvent:Fire(solo, first.UserId)
		expect(systems.persistence:GetBalance(first)).toBe(before + BaseConfig.Visits.CheerCoins)
		Harness.advance(1)
		Remotes.Get("CheerBase").OnServerEvent:Fire(solo, first.UserId)
		expect(systems.persistence:GetBalance(first)).toBe(before + BaseConfig.Visits.CheerCoins)
	end)

	it("holds a gate with one player, then descends two together with building bonuses applied", function()
		local zone = lobby:FindFirstChild("Gates"):FindFirstChild("Gate1Zone")
		root(first).Position = zone.Position + Vector3.new(-2, 3, 0)
		Harness.step(DT, math.ceil((RunConfig.Lobby.GateCountdown + 1) / DT))
		expect(systems.director:MatchFor(first)).toBeNil()

		root(second).Position = zone.Position + Vector3.new(2, 3, 0)
		Harness.step(DT, math.ceil((RunConfig.Lobby.GateCountdown + 0.5) / DT))
		local match = systems.director:MatchFor(first)
		expect(match).toBeTruthy()
		expect(systems.director:MatchFor(second)).toBe(match)
		expect(#match:GetParticipants()).toBe(2)
		expect(systems.director:MatchFor(solo)).toBeNil()

		local state = match:GetPlayerState(first)
		expect(state.maxHealth).toBe(RunConfig.BaseHealth + BaseConfig.Get("Infirmary").Effect.PerLevel)
		-- Each gate member heard the countdown.
		expect(#firedTo(second, "LobbyReadyState")).toBeGreaterThan(0)
	end)

	it("sends the solo player into a separate arena through the portal", function()
		local prompt = lobby:FindFirstChild("DescentPedestal"):FindFirstChild("StartRunPrompt")
		prompt.Triggered:Fire(solo)
		local match = systems.director:MatchFor(solo)
		expect(match).toBeTruthy()
		expect(match).never().toBe(systems.director:MatchFor(first))
		expect(#match:GetParticipants()).toBe(1)
	end)

	it("drops a brand-new player straight into the first descent once they spawn", function()
		FeatureFlags.FirstDescent = true
		local rookie = Harness.addPlayer("Rookie")
		expect(systems.director:MatchFor(rookie)).toBeNil() -- no character yet
		Harness.giveCharacter(rookie, spawnAt)
		local match = systems.director:MatchFor(rookie)
		expect(match).toBeTruthy()
		expect(#match:GetParticipants()).toBe(1)
		expect(match._runOptions.firstDescent).toBe(true)
		FeatureFlags.FirstDescent = false
	end)

	it("closes the base to players in a run", function()
		Remotes.Get("UpgradeBuilding").OnServerEvent:Fire(first, "Bootworks")
		expect(systems.persistence:GetMetaLevels(first).Bootworks).toBeNil()
		local notes = firedTo(first, "Notify")
		expect(notes[#notes][1].Text).toBe("You can build between runs.")
	end)
end)

describe("place checks", function()
	local function place()
		local root = Instance.new("Folder")
		local lobby = Instance.new("Folder")
		lobby.Name = "Lobby"
		lobby.Parent = root
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Parent = lobby
		return root, lobby
	end

	it("is quiet for a clean place", function()
		local root, lobby = place()
		expect(#GameBootstrap._placeWarnings(root, lobby)).toBe(0)
	end)

	it("reports streaming, the template Baseplate and stray spawns without touching them", function()
		local root, lobby = place()
		root.StreamingEnabled = true
		local baseplate = Instance.new("Part")
		baseplate.Name = "Baseplate"
		baseplate.Parent = root
		local stray = Instance.new("SpawnLocation")
		stray.Name = "SpawnLocation"
		stray.Parent = root
		local warnings = GameBootstrap._placeWarnings(root, lobby)
		expect(#warnings).toBe(3)
		expect(table.concat(warnings, "\n"):find("StreamingEnabled")).toBeTruthy()
		expect(baseplate.Parent).toBe(root)
		expect(stray.Parent).toBe(root)
	end)
end)
