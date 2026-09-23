-- HUD: what shows in the lobby versus a run, and the coin counter.
local HudView = __require("HudView")
local RunConfig = __require("RunConfig")

local function snapshot(state)
	return {
		State = state,
		RoomIndex = 1,
		RoomCount = 7,
		RoomName = "Collapsed Atrium",
		Zone = "Ruins",
		EnemiesRemaining = 3,
		Players = 1,
	}
end

describe("HudView", function()
	it("hides the upgrades panel in the lobby and shows the Store button there instead", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:UpdateRun(snapshot(RunConfig.States.Lobby))
		expect(hud.upgradePanel.Visible).toBe(false)
		expect(hud.storeButton.Visible).toBe(true)
		hud:UpdateRun(snapshot(RunConfig.States.Combat))
		expect(hud.upgradePanel.Visible).toBe(true)
		expect(hud.storeButton.Visible).toBe(false)
	end)

	it("clears last run's upgrades on the way back to the lobby", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:UpdatePlayer({ Health = 80, MaxHealth = 100, Alive = true, Coins = 0, Upgrades = { { Title = "Split Shot", Stacks = 1 } } })
		expect(#hud.upgradeEntries).toBe(2)
		hud:UpdateRun(snapshot(RunConfig.States.Lobby))
		expect(#hud.upgradeEntries).toBe(1)
	end)

	it("counts coins, with a +N as they arrive", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:UpdatePlayer({ Health = 100, MaxHealth = 100, Alive = true, Coins = 0, Upgrades = {} })
		expect(hud.coinLabel.Text).toBe("Coins 0")
		hud:UpdatePlayer({ Health = 100, MaxHealth = 100, Alive = true, Coins = 6, Upgrades = {} })
		expect(hud.coinLabel.Text).toBe("+6  Coins 6")
	end)

	it("tells a lobby player how to start, and a gate member how long is left", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:UpdateRun(snapshot(RunConfig.States.Lobby))
		hud:SetLobbyReady({ Active = true })
		expect(hud.objectiveLabel.Text:find("Solo Portal")).toBeTruthy()
		hud:SetLobbyReady({ Active = true, Gate = "GATE I", Count = 3, Capacity = 8, MinPlayers = 2, Countdown = 9 })
		expect(hud.objectiveLabel.Text).toBe("GATE I  3/8  -  descending in 9...")
	end)
end)
