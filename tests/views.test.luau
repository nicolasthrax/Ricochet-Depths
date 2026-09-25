-- 3.0 client views, headless: the base panel (grid, tap-to-build/move, claim, visits), the card
-- picker's labels / RECOMMENDED / reroll / respec / Bank loot door, the results screen's haul
-- and calls to action, the shop's cosmetic tabs, the HUD's BASE button, modifier chip and
-- revive button, the menu's BASE entry, presets in the rig view, the base preview camera and
-- the daily tiles' extras. Views only ever ask the server; these check what they ask and show.
local BaseConfig = __require("BaseConfig")
local BasePreview = __require("BasePreview")
local BaseView = __require("BaseView")
local CardPickerView = __require("CardPickerView")
local DailyView = __require("DailyView")
local HudView = __require("HudView")
local MenuDock = __require("MenuDock")
local MetaConfig = __require("MetaConfig")
local ResultsView = __require("ResultsView")
local RigView = __require("RigView")
local RunConfig = __require("RunConfig")
local ShopConfig = __require("ShopConfig")
local ShopView = __require("ShopView")
local UiConfig = __require("UiConfig")

-- A BaseSync payload for a fresh base with some coins.
local function baseState(overrides)
	local levels = {}
	for _, building in BaseConfig.Buildings do
		levels[building.Id] = building.StartLevel
	end
	local state = {
		Levels = levels,
		Layout = { Hearth = 6 },
		Hearth = 1,
		Balance = 500,
		Offline = { Coins = 0, Fill = 0, PerHour = 0, CapHours = 8 },
		NextBuild = { Id = "SalvageYard", Title = "Salvage Yard", Level = 1, Cost = 60 },
	}
	for key, value in overrides or {} do
		state[key] = value
	end
	return state
end

local function find(root, name)
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name then
			return descendant
		end
	end
	return nil
end

describe("BaseView", function()
	local function view()
		local calls = { upgrade = {}, move = {}, claim = 0, visit = {}, cheer = {} }
		local panel = BaseView.new(Instance.new("Folder"), {
			upgrade = function(id, tile)
				table.insert(calls.upgrade, { id, tile })
			end,
			move = function(id, tile)
				table.insert(calls.move, { id, tile })
			end,
			claim = function()
				calls.claim += 1
			end,
			visit = function(userId)
				table.insert(calls.visit, userId or "own")
			end,
			cheer = function(userId)
				table.insert(calls.cheer, userId)
			end,
		})
		return panel, calls
	end

	it("draws the 4x4 grid and a card for each of the twelve buildings", function()
		local panel = view()
		panel:SetState(baseState())
		expect(#panel.tiles).toBe(16)
		local cards = 0
		for _ in panel.cards do
			cards += 1
		end
		expect(cards).toBe(12)
		expect(panel.tiles[6].Text).toBe("Camp Hearth\n1")
		expect(panel.tiles[1].Text).toBe("+")
		expect(panel.cards.Forge.action.Text).toBe("BUILD  " .. BaseConfig.CostFor(BaseConfig.Get("Forge"), 1))
		expect(panel.cards.Springhouse.action.Text).toBe("HEARTH 2")
		expect(panel.hint.Text:find("Salvage Yard")).toBeTruthy()
	end)

	it("builds a picked building on the tapped empty tile, and moves a built one", function()
		local panel, calls = view()
		panel:SetState(baseState())
		panel:SelectBuilding("Forge")
		expect(panel.hint.Text:find("empty tile")).toBeTruthy()
		panel:TapTile(3)
		expect(calls.upgrade[1][1]).toBe("Forge")
		expect(calls.upgrade[1][2]).toBe(3)

		local built = baseState({ Layout = { Hearth = 6, Forge = 3 } })
		built.Levels.Forge = 1
		panel:SetState(built)
		panel:TapTile(3) -- picks the Forge standing there
		panel:TapTile(9)
		expect(calls.move[1][1]).toBe("Forge")
		expect(calls.move[1][2]).toBe(9)
	end)

	it("upgrades from the card, and does nothing for a locked or unaffordable level", function()
		local panel, calls = view()
		panel:SetState(baseState({ Balance = 10 }))
		panel.cards.Forge.action.Activated:Fire()
		expect(#calls.upgrade).toBe(0)
		panel:SetState(baseState())
		panel.cards.Springhouse.action.Activated:Fire()
		expect(#calls.upgrade).toBe(0)
		panel.cards.Bootworks.action.Activated:Fire()
		expect(calls.upgrade[1][1]).toBe("Bootworks")
		expect(calls.upgrade[1][2]).toBeNil() -- first free tile, chosen by the server
	end)

	it("shows the yard's fill and claims it", function()
		local panel, calls = view()
		panel:SetState(baseState({ Offline = { Coins = 30, Fill = 0.375, PerHour = 10, CapHours = 8 } }))
		expect(panel.claimButton.Text).toBe("CLAIM 30")
		expect(panel.yardFill.Size.X.Scale).toBeCloseTo(0.375)
		panel.claimButton.Activated:Fire()
		expect(calls.claim).toBe(1)
	end)

	it("lists the other players to visit and cheer, and visits your own plot", function()
		local panel, calls = view()
		panel:SetPlayers({ { UserId = 11, Name = "Ana" }, { UserId = 12, Name = "Bo" } })
		local row = find(panel.visits, "Visit11")
		expect(row).toBeTruthy()
		row:FindFirstChild("Cheer").Activated:Fire()
		find(panel.visits, "Visit12"):FindFirstChild("Visit").Activated:Fire()
		panel.myPlotButton.Activated:Fire()
		expect(calls.cheer[1]).toBe(11)
		expect(calls.visit[1]).toBe(12)
		expect(calls.visit[2]).toBe("own")
		-- A new list replaces the old one.
		panel:SetPlayers({})
		expect(find(panel.visits, "Visit11")).toBeNil()
	end)
end)

describe("CardPickerView 3.0", function()
	local function payload(extra)
		local base = {
			OfferId = 4,
			SecondsRemaining = 10,
			Cards = {
				{ Id = "Plating", Title = "Plating", Label = "+25 health", Icon = "🛡️", Description = "x", Category = "Survival", Rarity = "Common" },
				{ Id = "SplitShot", Title = "Split Shot", Label = "+1 projectile", Icon = "🔱", Description = "y", Category = "Projectile",
					Rarity = "Rare", Recommended = true },
				{ Id = "SharpEdge", Title = "Sharp Edge", Label = "+1 damage", Icon = "🗡️", Description = "z", Category = "Power", Rarity = "Common" },
			},
			FreeRerolls = 1,
			Rerolls = 0,
			CanRespec = true,
		}
		for key, value in extra or {} do
			base[key] = value
		end
		return base
	end

	it("leads each card with its icon and label, and tags the recommended one", function()
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end, { reroll = function() end })
		view:Show(payload())
		local cards = view.row:GetChildren()
		local tagged = 0
		for _, card in cards do
			if card:IsA("TextButton") then
				expect(card:FindFirstChild("Icon").Text).never().toBe("")
				expect(#card:FindFirstChild("Label").Text).toBeGreaterThan(0)
				if card:FindFirstChild("Recommended") then
					tagged += 1
					expect(card:FindFirstChild("Label").Text).toBe("+1 PROJECTILE")
				end
			end
		end
		expect(tagged).toBe(1)
	end)

	it("offers a free reroll, then counts tokens, and asks the server once per press", function()
		local rerolls = 0
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end, {
			reroll = function()
				rerolls += 1
			end,
		})
		view:Show(payload())
		expect(view.rerollButton.Visible).toBe(true)
		expect(view.rerollButton.Text).toBe("REROLL (FREE)")
		view.rerollButton.Activated:Fire()
		view.rerollButton.Activated:Fire()
		expect(rerolls).toBe(1)
		view:Show(payload({ FreeRerolls = 0, Rerolls = 3 }))
		expect(view.rerollButton.Text).toBe("REROLL (3 left)")
		view:Show(payload({ FreeRerolls = 0, Rerolls = 0 }))
		expect(view.rerollButton.Text).toBe("NO REROLLS")
		view.rerollButton.Activated:Fire()
		expect(rerolls).toBe(1)
	end)

	it("offers the free respec on the door stage after a pick, when the server allows it", function()
		local respecs = 0
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end, {
			respec = function()
				respecs += 1
			end,
		})
		view:Show(payload())
		view:SetDoors({ Doors = { { Id = 1, RoomName = "A", Zone = "Ruins", Kind = "Normal", RewardTitle = "T", RewardText = "t" } }, SecondsLeft = 9 })
		expect(view:ShowDoors()).toBe(true)
		expect(view.respecButton.Visible).toBe(true)
		view.respecButton.Activated:Fire()
		expect(respecs).toBe(1)
		view:Show(payload({ CanRespec = false }))
		view:ShowDoors()
		expect(view.respecButton.Visible).toBe(false)
	end)

	it("titles a fusion offer 'try it now' and shows no reroll for it", function()
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end, { reroll = function() end })
		view:Show(payload({ Fusion = true }))
		expect(view.title.Text:find("Try it now")).toBeTruthy()
		expect(view.rerollButton.Visible).toBe(false)
	end)

	it("marks the Bank loot door as the gold primary door, with the haul it keeps", function()
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end)
		view:SetHaul(214)
		view:SetDoors({ Doors = {
			{ Id = 1, RoomName = "Cold Smelter", Zone = "Foundry", Kind = "Normal", RewardTitle = "Heal", RewardText = "h" },
			{ Id = 2, RoomName = "The Surface", Zone = "Ruins", Kind = "Extract", RewardTitle = "Bank the loot", RewardText = "b" },
		}, SecondsLeft = 8 })
		view:ShowDoors()
		local bank = view.row:FindFirstChild("Door2")
		expect(bank:FindFirstChild("Kind").Text).toBe("BANK LOOT")
		expect(bank.BackgroundColor3).toBe(UiConfig.Colors.PrimaryButton)
		expect(bank:FindFirstChild("Body").Text:find("Your haul: 214 coins")).toBeTruthy()
		local other = view.row:FindFirstChild("Door1")
		expect(other.BackgroundColor3).never().toBe(UiConfig.Colors.PrimaryButton)
		expect(other:FindFirstChild("Body").Text).toBe("h")
	end)

	it("shows the fusion a card builds toward", function()
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end)
		local shown = payload()
		shown.Cards[2].FusionHint = { Fusion = "Fusillade", Have = 1, Need = 2 }
		view:Show(shown)
		local split = view.row:FindFirstChild("Card2")
		expect(split:FindFirstChild("FusionHint").Text).toBe("1 / 2  →  Fusillade")
		expect(view.row:FindFirstChild("Card1"):FindFirstChild("FusionHint")).toBeNil()
	end)

	it("keeps the cards and the reroll button inside a landscape phone screen", function()
		local view = CardPickerView.new(Instance.new("Folder"), function() end, function() end, { reroll = function() end })
		view:Show(payload())
		-- The button hangs from the bottom edge, inside it; the row ends above the button's top.
		local button = view.rerollButton
		expect(button.AnchorPoint.Y).toBe(1)
		expect(button.Position.Y.Scale).toBe(1)
		expect(button.Position.Y.Offset).toBeLessThan(0)
		local buttonTop = -button.Position.Y.Offset + button.Size.Y.Offset
		local rowBottom = -(view.row.Position.Y.Offset + view.row.Size.Y.Offset)
		expect(rowBottom).toBeGreaterThan(buttonTop)
		-- On a 300 px-tall screen the row still has room for a card's minimum height (150 px).
		expect(300 * view.row.Size.Y.Scale + view.row.Size.Y.Offset).toBeGreaterThanOrEqual(150)
		expect(view.respecButton.Position.Y.Offset).toBe(button.Position.Y.Offset)
		expect(view.respecButton.AnchorPoint.Y).toBe(1)
	end)
end)

describe("ResultsView 3.0", function()
	local function summary(extra)
		local base = {
			Outcome = "Defeated", RoomsCleared = 2, RoomCount = 9, EnemiesDefeated = 10, BestChain = 3, ShotsFired = 20,
			DamageTaken = 50, DurationSeconds = 90, CurrencyName = "Coins", Reward = 40, Upgrades = {},
			Haul = 60, HaulLost = 30, Banked = false,
		}
		for key, value in extra or {} do
			base[key] = value
		end
		return base
	end

	local function rowsText(view)
		local all = {}
		for _, row in view._rows do
			table.insert(all, row.Text)
		end
		return table.concat(all, "\n")
	end

	it("says how much of the haul was lost, or that it was banked", function()
		local view = ResultsView.new(Instance.new("Folder"), function() end)
		view:Show(summary())
		expect(rowsText(view):find("Haul lost in the depths: 30 of 60")).toBeTruthy()
		view:Show(summary({ Outcome = "Extracted", Banked = true, HaulLost = 0, DailyBonus = 60 }))
		local text = rowsText(view)
		expect(text:find("Loot banked!")).toBeTruthy()
		expect(text:find("Daily modifier bonus: %+60")).toBeTruthy()
	end)

	it("tells what the haul builds at home", function()
		local view = ResultsView.new(Instance.new("Folder"), function() end)
		view:SetNextBuild({ Title = "Forge", Level = 2, Cost = 260 }, 300)
		expect(view.buildLabel.Text).toBe("Your haul builds: Forge Lv2!")
		view:SetNextBuild({ Title = "Forge", Level = 2, Cost = 260 }, 200)
		expect(view.buildLabel.Text).toBe("60 more coins build Forge Lv2")
		view:SetNextBuild(nil)
		expect(view.buildLabel.Text).toBe("")
	end)

	it("offers DESCEND and BUILD AT BASE, each leaving the results first", function()
		local log = {}
		local view = ResultsView.new(Instance.new("Folder"), function()
			table.insert(log, "dismiss")
		end, {
			descend = function()
				table.insert(log, "descend")
			end,
			toBase = function()
				table.insert(log, "base")
			end,
		})
		view:Show(summary())
		expect(view.adButton.Visible).toBe(false) -- no ad handler, no ad button
		view.descendButton.Activated:Fire()
		view.baseButton.Activated:Fire()
		expect(log).toEqual({ "dismiss", "descend", "dismiss", "base" })
	end)
end)

describe("ShopView tabs by kind", function()
	it("lists each cosmetic kind on its own tab and marks how each is earned", function()
		local view = ShopView.new(Instance.new("Folder"), function() end, function() end)
		view:SetProfile({ Salvage = 1000, MetaUpgrades = {}, Progression = { Level = 1 }, Passes = {} })
		view:SetTab("Themes")
		local items = view.panel:FindFirstChild("Items")
		expect(items:FindFirstChild("Moss").Visible).toBe(true)
		expect(items:FindFirstChild("TrailEmber").Visible).toBe(false)
		expect(items:FindFirstChild("Moss"):FindFirstChild("Action").Text).toBe("Buy  " .. ShopConfig.CostFor(ShopConfig.Get("Moss"), 1))
		expect(items:FindFirstChild("Frost"):FindFirstChild("Action").Text).toBe("Level 8")
		expect(items:FindFirstChild("Gilded"):FindFirstChild("Action").Text).toBe("Pass")
		view:SetTab("Emotes")
		expect(items:FindFirstChild("Wave"):FindFirstChild("Action").Text).toBe("Play")
	end)

	it("equips by kind, plays owned emotes, and unlocks pass items with the pass", function()
		local equipped, played = {}, {}
		local view = ShopView.new(Instance.new("Folder"), function() end, function(itemId, kind)
			table.insert(equipped, { itemId, kind })
		end, nil, function(emoteId)
			table.insert(played, emoteId)
		end)
		view:SetProfile({
			Salvage = 0, MetaUpgrades = { Moss = 1 }, Progression = { Level = 1 }, Passes = { "SupporterPack" },
			Base = { Theme = "Moss", Sign = "" }, EquippedTrail = "",
		})
		local items = view.panel:FindFirstChild("Items")
		expect(items:FindFirstChild("Moss"):FindFirstChild("Action").Text).toBe("Unequip")
		items:FindFirstChild("Gilded"):FindFirstChild("Action").Activated:Fire()
		expect(equipped[1][1]).toBe("Gilded")
		expect(equipped[1][2]).toBe("Theme")
		items:FindFirstChild("Moss"):FindFirstChild("Action").Activated:Fire()
		expect(equipped[2][1]).toBe("") -- tapping the worn theme takes it off
		items:FindFirstChild("Cheer"):FindFirstChild("Action").Activated:Fire()
		expect(played[1]).toBe("Cheer")
	end)
end)

describe("HUD and menu 3.0", function()
	it("shows BASE in the lobby when there is a handler, and hides it in a run", function()
		local hud = HudView.new(Instance.new("Folder"))
		expect(hud.baseButton.Visible).toBe(false)
		local pressed = 0
		hud:SetBaseHandler(function()
			pressed += 1
		end)
		expect(hud.baseButton.Visible).toBe(true)
		hud.baseButton.Activated:Fire()
		expect(pressed).toBe(1)
		hud:UpdateRun({ State = RunConfig.States.Combat, RoomIndex = 1, RoomCount = 9, RoomName = "A", EnemiesRemaining = 3 })
		expect(hud.baseButton.Visible).toBe(false)
	end)

	it("shows today's modifier chip in the lobby and the run's own in a run", function()
		local hud = HudView.new(Instance.new("Folder"))
		hud:SetLobbyModifier({ Title = "Gold Rush", Text = "+25% coins from every run." })
		expect(hud.modifierChip.Visible).toBe(true)
		expect(hud.modifierLabel.Text:find("GOLD RUSH")).toBeTruthy()
		-- A first descent has no modifier: the chip goes.
		hud:UpdateRun({ State = RunConfig.States.Combat, RoomIndex = 1, RoomCount = 12, RoomName = "A", EnemiesRemaining = 6 })
		expect(hud.modifierChip.Visible).toBe(false)
		hud:UpdateRun({ State = RunConfig.States.Lobby, RoomIndex = 0, RoomCount = 0, RoomName = "", EnemiesRemaining = 0 })
		expect(hud.modifierChip.Visible).toBe(true)
	end)

	it("offers a revive while down and passes the token count to the handler", function()
		local hud = HudView.new(Instance.new("Folder"))
		local seen
		hud:OfferRevive(2, function(tokens)
			seen = tokens
		end)
		expect(hud.reviveButton.Visible).toBe(true)
		expect(hud.reviveButton.Text).toBe("USE REVIVE (2)")
		hud.reviveButton.Activated:Fire()
		expect(seen).toBe(2)
		expect(hud.reviveButton.Visible).toBe(false)
	end)

	it("puts BASE first on the menu rail", function()
		local opened = 0
		local dock = MenuDock.new(Instance.new("Folder"), {
			Base = function()
				opened += 1
			end,
		})
		expect(dock.buttons.Base).toBeTruthy()
		expect(dock.buttons.Base.LayoutOrder).toBe(1)
		dock.buttons.Base.Activated:Fire()
		expect(opened).toBe(1)
	end)
end)

describe("presets, preview and daily extras", function()
	it("saves and loads presets from the rig view, only in open slots", function()
		local calls = {}
		local view = RigView.new(Instance.new("Folder"), function() end, function(action, slot)
			table.insert(calls, action .. slot)
		end)
		view:SetProfile({ Progression = { Level = 1 }, SelectedRig = "Striker", PresetSlots = 2, Presets = { ["1"] = { Rig = "Striker" } } })
		expect(view.presetTiles[1].load.Visible).toBe(true)
		expect(view.presetTiles[2].load.Visible).toBe(false)
		expect(view.presetTiles[3].save.Visible).toBe(false)
		expect(view.presetTiles[3].label.Text).toBe("PASS SLOT")
		view.presetTiles[1].load.Activated:Fire()
		view.presetTiles[2].save.Activated:Fire()
		view.presetTiles[3].save.Activated:Fire()
		expect(calls).toEqual({ "Apply1", "Save2" })
		expect(#view.presetTiles).toBe(MetaConfig.Presets.MaxSlots)
	end)

	it("points the camera at the player's plot for three seconds, then hands it back", function()
		local player = Harness.addPlayer("Previewer")
		local camera = { CameraType = Enum.CameraType.Custom }
		expect(BasePreview.Play(player, camera)).toBe(false) -- no plot yet
		player:SetAttribute("PlotIndex", 2)
		expect(BasePreview.Play(player, camera)).toBe(true)
		expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
		expect(player:GetAttribute("Cinematic")).toBe(true)
		local centre = BaseConfig.PlotCentre(2, RunConfig.LobbyPosition)
		expect((camera.CFrame.Position - centre).Magnitude).toBeLessThan(90)
		Harness.advance(BasePreview.Seconds + 0.1)
		expect(player:GetAttribute("Cinematic")).toBeNil()
		expect(camera.CameraType).toBe(Enum.CameraType.Custom)
		Harness.removePlayer(player)
	end)

	it("shows the day 5 and day 7 extras on the daily tiles", function()
		local view = DailyView.new(Instance.new("Folder"), function() end)
		expect(view.tiles[5].frame:FindFirstChild("Detail").Text:find("Revive")).toBeTruthy()
		expect(view.tiles[7].frame:FindFirstChild("Detail").Text:find("Rerolls")).toBeTruthy()
		view:SetState({ CanClaim = true, Streak = 9, DayIndex = 3 }, 100)
		expect(view.streakLabel.Text:find("never lose your place")).toBeTruthy()
	end)
end)

describe("first descent aim hint", function()
	local AimIndicator = __require("AimIndicator")

	it("pulses a hint line ahead of the player, fading in and out", function()
		local world = Instance.new("Folder")
		local indicator = AimIndicator.new(Instance.new("Folder"), world, 0)
		indicator:Pulse(Vector3.new(0, 3, 0), Vector3.new(0, 0, -1), 1)
		local line = world:FindFirstChild("AimLine", true) or indicator._worldLine
		local bright = line.Transparency
		expect(bright).toBeLessThan(1)
		indicator:Pulse(Vector3.new(0, 3, 0), Vector3.new(0, 0, -1), 0)
		expect(line.Transparency).toBeGreaterThan(bright)
		indicator:Hide()
		expect(line.Transparency).toBe(1)
		expect(AimIndicator.PulseAlpha(0.25)).toBeCloseTo(1)
		expect(AimIndicator.PulseAlpha(0.75)).toBeCloseTo(0)
	end)
end)

describe("onboarding hints", function()
	local OnboardingView = __require("OnboardingView")

	it("shows the first-descent banner, and the new Bank loot and base hints even to veterans", function()
		local view = OnboardingView.new(Instance.new("Folder"))
		expect(view:Show("FirstDescent")).toBe(true)
		expect(view.label.Text).toBe("Bounce shots. Break everything.")
		expect(view:Show("FirstDescent")).toBe(false) -- once a session
		local veteran = OnboardingView.new(Instance.new("Folder"))
		veteran:MarkAllSeen()
		expect(veteran:Show("Aim")).toBe(false)
		expect(veteran:Show("BankLoot")).toBe(true)
		expect(veteran:Show("Base")).toBe(true)
	end)
end)
