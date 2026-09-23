-- End-to-end smoke test of GameBootstrap.Start: the real wiring between remotes, the shop, the
-- lobby ready pads and the run loop. Named to run last: Start connects to Players, Heartbeat
-- and every remote for the life of the process, and nothing tears that down, so any test file
-- after it would have a second game listening to its events.
local DebugConfig = __require("DebugConfig")
local GameBootstrap = __require("GameBootstrap")
local Remotes = __require("Remotes")
local RunConfig = __require("RunConfig")
local ShopConfig = __require("ShopConfig")

local DT = 1 / 30

describe("GameBootstrap wiring", function()
	DebugConfig.LogTelemetry = false
	-- Earlier files leave players behind. They would count as lobby players who are not on a
	-- pad, which (correctly) holds the ready countdown, so this game starts with an empty server.
	for _, leftover in game:GetService("Players"):GetPlayers() do
		Harness.removePlayer(leftover)
	end
	local store = __FakeDataStore.new()
	rawset(Harness.service("DataStoreService"), "GetDataStore", function()
		return store
	end)
	local systems = GameBootstrap.Start()
	local lobby = workspace:FindFirstChild("Lobby")
	local player = Harness.addPlayer("Smoke")
	Harness.giveCharacter(player, RunConfig.LobbyPosition + Vector3.new(0, 3, 8))
	local root = player.Character:FindFirstChild("HumanoidRootPart")

	local function firedTo(remoteName)
		local out = {}
		for _, call in rawget(Remotes.Get(remoteName), "_fired") do
			if call.player == player then
				table.insert(out, call.args)
			end
		end
		return out
	end

	it("loads the profile and opens the shop from the kiosk", function()
		expect(systems.persistence:IsLoaded(player)).toBe(true)
		local prompt = lobby:FindFirstChild("ShopKiosk"):FindFirstChild("OpenShopPrompt")
		prompt.Triggered:Fire(player)
		expect(#firedTo("ShopOpen")).toBe(1)
	end)

	it("sells an upgrade through the remote while in the lobby", function()
		systems.persistence:GrantReward(player, "smoke-seed", 1000)
		Remotes.Get("PurchaseShopItem").OnServerEvent:Fire(player, "Vitality")
		expect(systems.persistence:GetMetaLevels(player).Vitality).toBe(1)
		local results = firedTo("ShopResult")
		expect(results[#results][1].Ok).toBe(true)
	end)

	it("starts a descent once the only player stands on a ready pad, with shop bonuses applied", function()
		local pad = lobby:FindFirstChild("ReadyZone"):FindFirstChild("ReadyPad1")
		root.Position = pad.Position + Vector3.new(0, 3, 0)
		Harness.step(DT, math.ceil((RunConfig.Lobby.ReadyCountdown + 0.5) / DT))
		expect(systems.match:GetState()).never().toBe(RunConfig.States.Lobby)

		local state = systems.match:GetPlayerState(player)
		expect(state.maxHealth).toBe(RunConfig.BaseHealth + ShopConfig.Get("Vitality").Effect.PerLevel)
		-- The countdown was broadcast to the lobby while it ran.
		expect(#rawget(Remotes.Get("LobbyReadyState"), "_fired")).toBeGreaterThan(0)
	end)

	it("closes the shop once the run is under way", function()
		Remotes.Get("PurchaseShopItem").OnServerEvent:Fire(player, "Velocity")
		expect(systems.persistence:GetMetaLevels(player).Velocity).toBeNil()
		local results = firedTo("ShopResult")
		expect(results[#results][1].Reason).toBe("shop closed")
	end)
end)
