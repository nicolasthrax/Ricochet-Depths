-- End-to-end smoke test of GameBootstrap.Start: the real wiring between remotes, the shop
-- kiosks, the multiplayer gates, the solo portal and the arena director. Named to run last: Start
-- connects to Players, Heartbeat and every remote for the life of the process, and nothing tears
-- that down, so any test file after it would have a second game listening to its events.
local DebugConfig = __require("DebugConfig")
local GameBootstrap = __require("GameBootstrap")
local Remotes = __require("Remotes")
local RunConfig = __require("RunConfig")
local ShopConfig = __require("ShopConfig")

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

	it("loads profiles and opens the shop on the kiosk's tab", function()
		expect(systems.persistence:IsLoaded(first)).toBe(true)
		lobby:FindFirstChild("ArmoryKiosk"):FindFirstChild("OpenArmoryPrompt").Triggered:Fire(first)
		local opened = firedTo(first, "ShopOpen")
		expect(#opened).toBe(1)
		expect(opened[1][1]).toBe("Armory")
		lobby:FindFirstChild("CosmeticsKiosk"):FindFirstChild("OpenCosmeticsPrompt").Triggered:Fire(first)
		opened = firedTo(first, "ShopOpen")
		expect(opened[2][1]).toBe("Cosmetics")
	end)

	it("sells an upgrade through the remote while in the lobby", function()
		systems.persistence:GrantReward(first, "smoke-seed", 1000)
		Remotes.Get("PurchaseShopItem").OnServerEvent:Fire(first, "Vitality")
		expect(systems.persistence:GetMetaLevels(first).Vitality).toBe(1)
		local results = firedTo(first, "ShopResult")
		expect(results[#results][1].Ok).toBe(true)
	end)

	it("holds a gate with one player, then descends two together with shop bonuses applied", function()
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
		expect(state.maxHealth).toBe(RunConfig.BaseHealth + ShopConfig.Get("Vitality").Effect.PerLevel)
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

	it("closes the shop to players in a run", function()
		Remotes.Get("PurchaseShopItem").OnServerEvent:Fire(first, "Velocity")
		expect(systems.persistence:GetMetaLevels(first).Velocity).toBeNil()
		local results = firedTo(first, "ShopResult")
		expect(results[#results][1].Reason).toBe("shop closed")
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
