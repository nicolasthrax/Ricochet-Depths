-- Lane game, the run loop end to end: RunDirector with the real CombatService and UpgradeService.
__freshMvp()
local GameConfig = __require("GameConfig")
local Network = __require("Network")
local UpgradeService = __require("UpgradeService")
local CombatService = __require("CombatService")
local RunDirector = __require("RunDirector")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

Network.mountServer()
UpgradeService.init()
CombatService.init()
RunDirector.init()
local folder = ReplicatedStorage:FindFirstChild("NetworkRemotes")

local function remote(name)
	return folder:FindFirstChild(name)
end

local function clearFired()
	for _, child in folder:GetChildren() do
		local fired = rawget(child, "_fired")
		if fired then
			table.clear(fired)
		end
	end
end

local function sent(name, player)
	local list = {}
	for _, entry in remote(name)._fired do
		if entry.player == player then
			table.insert(list, entry.args[1])
		end
	end
	return list
end

local function lastState(player)
	local states = sent("RunStateChanged", player)
	return states[#states]
end

describe("RunDirector", function()
	local player = Harness.addPlayer("Runner")

	it("builds a lane and opens room 1 when a player joins", function()
		local run = RunDirector.getRun(player)
		expect(run).toBeTruthy()
		expect(run.phase).toBe("Combat")
		expect(run.depth).toBe(1)
		expect(run.room).toBe(1)
		expect(run.hp).toBe(GameConfig.Player.hpPips)
		expect(run.targets).toBeGreaterThan(0)
		local lane = workspace:FindFirstChild("Lanes"):FindFirstChild(`Lane_{player.UserId}`)
		expect(lane).toBeTruthy()
		expect(lane:FindFirstChild("Floor")).toBeTruthy()
		expect(lane:FindFirstChild("DangerLine")).toBeTruthy()
		local state = lastState(player)
		expect(state.phase).toBe("Combat")
		expect(state.roomCount).toBe(GameConfig.Run.roomsPerDepth)
		expect(state.laneOrigin).toBe(run.origin)
		expect(#sent("TargetsSpawned", player)).toBeGreaterThan(0)
	end)

	it("puts the avatar on the rail with walking switched off", function()
		local character = Harness.giveCharacter(player, Vector3.new(500, 500, 500))
		Harness.settle(1)
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChild("Humanoid")
		local origin = RunDirector.getRun(player).origin
		expect(humanoid.WalkSpeed).toBe(0)
		expect(humanoid.JumpPower).toBe(0)
		expect(root.Position.X).toBeCloseTo(origin.Position.X, 1e-6)
		expect(root.Position.Y).toBeCloseTo(origin.Position.Y + 2 + 0.5, 1e-6)
	end)

	it("advances the targets every pulse", function()
		clearFired()
		Harness.stepSeconds(GameConfig.Targets.pulseIntervalSeconds + 0.1)
		local pulses = sent("TargetsAdvanced", player)
		expect(#pulses).toBe(1)
		expect(pulses[1].pulse).toBe(1)
		expect(#pulses[1].moves).toBeGreaterThan(0)
	end)

	it("freezes the lane while a card pick is open", function()
		UpgradeService.addXp(player, GameConfig.Xp.firstLevel)
		local run = RunDirector.getRun(player)
		expect(run.phase).toBe("UpgradePick")
		expect(run.timeScale).toBe(0)
		expect(lastState(player).phase).toBe("UpgradePick")
		clearFired()
		Harness.stepSeconds(GameConfig.Targets.pulseIntervalSeconds * 3)
		expect(#sent("TargetsAdvanced", player)).toBe(0)
		local offers = sent("UpgradeOffered", player)
		expect(#offers).toBe(0) -- sent before clearFired; re-request through the snapshot below
		remote("FetchRunSnapshot").OnServerInvoke(player, nil)
		Harness.settle(1)
		local offer = sent("UpgradeOffered", player)[1]
		expect(offer).toBeTruthy()
		Harness.advance(1)
		remote("SelectUpgrade").OnServerEvent:Fire(player, { offerId = offer.offerId, modifierId = offer.choices[1].modifierId })
		run = RunDirector.getRun(player)
		expect(run.phase).toBe("Combat")
		expect(run.timeScale).toBe(1)
	end)

	it("pauses and resumes on request", function()
		Harness.advance(1)
		remote("SetPaused").OnServerEvent:Fire(player, { paused = true })
		expect(RunDirector.getRun(player).timeScale).toBe(0)
		expect(lastState(player).paused).toBe(true)
		Harness.advance(1)
		remote("SetPaused").OnServerEvent:Fire(player, { paused = false })
		expect(RunDirector.getRun(player).timeScale).toBe(1)
	end)

	it("answers a snapshot with everything needed to redraw the run", function()
		local snapshot = remote("FetchRunSnapshot").OnServerInvoke(player, nil)
		local run = RunDirector.getRun(player)
		expect(snapshot.state.runId).toBe(run.runId)
		expect(#snapshot.targets).toBe(run.targets)
		expect(snapshot.health.pips).toBe(run.hp)
		expect(snapshot.haul).toBe(run.haul)
		expect(snapshot.xp.level).toBeGreaterThanOrEqual(2)
		expect(#snapshot.loadout).toBe(1)
	end)

	it("rewards broken targets with gems and XP", function()
		local field = RunDirector.getField(player)
		local target = field:all()[1]
		clearFired()
		local before = RunDirector.getRun(player).haul
		CombatService.TargetBroken:Fire(player, target, "Direct", 12345)
		local haul = sent("HaulChanged", player)
		expect(#haul).toBe(1)
		local expected = math.ceil(target.maxHp * GameConfig.Gems.perBlockHp)
		expect(haul[1].delta).toBe(expected)
		expect(RunDirector.getRun(player).haul).toBe(before + expected)
		expect(#sent("XpChanged", player)).toBe(1)
		if UpgradeService.hasOpenOffer(player) then
			UpgradeService.endRun(player)
			UpgradeService.beginRun(player, 1)
		end
	end)

	it("clears the room when every target is gone and opens the next one", function()
		local field = RunDirector.getField(player)
		local cleared = false
		for _ = 1, 40 do
			for _, target in field:all() do
				field:remove(target.id)
			end
			Harness.step(1 / 60)
			if RunDirector.getRun(player).phase == "RoomClear" then
				cleared = true
				break
			end
			Harness.stepSeconds(GameConfig.Targets.pulseIntervalSeconds)
		end
		expect(cleared).toBe(true)
		expect(lastState(player).phase).toBe("RoomClear")
		clearFired()
		Harness.stepSeconds(GameConfig.Rooms.clearDelaySeconds + 0.1)
		local run = RunDirector.getRun(player)
		expect(run.phase).toBe("Combat")
		expect(run.room).toBe(2)
		expect(#sent("TargetsSpawned", player)).toBe(1)
	end)

	it("loses HP to breaches, ends the run at 0 HP and starts a new one", function()
		local runId = RunDirector.getRun(player).runId
		clearFired()
		local ended = false
		for _ = 1, 400 do
			Harness.stepSeconds(0.5)
			if #sent("RunEnded", player) > 0 then
				ended = true
				break
			end
		end
		expect(ended).toBe(true)
		local summary = sent("RunEnded", player)[1]
		expect(summary.outcome).toBe("Defeated")
		expect(summary.haulBanked).toBe(math.floor((summary.haulBanked + summary.haulLost) * GameConfig.Run.defeatedHaulKept))
		local health = sent("HealthChanged", player)
		expect(health[#health].pips).toBe(0)
		expect(RunDirector.getRun(player).phase).toBe("Ended")
		Harness.stepSeconds(GameConfig.Run.restartDelaySeconds + 0.1)
		local run = RunDirector.getRun(player)
		expect(run.runId).toBe(runId + 1)
		expect(run.phase).toBe("Combat")
		expect(run.hp).toBe(GameConfig.Player.hpPips)
		expect(run.room).toBe(1)
	end)

	it("gives each player their own lane slot and frees it on leave", function()
		local other = Harness.addPlayer("Second")
		local a, b = RunDirector.getRun(player), RunDirector.getRun(other)
		expect(b.origin.Position.X - a.origin.Position.X).toBe(GameConfig.World.laneSpacing)
		Harness.removePlayer(other)
		expect(RunDirector.getRun(other)).toBeNil()
		expect(workspace:FindFirstChild("Lanes"):FindFirstChild(`Lane_{other.UserId}`)).toBeNil()
		local third = Harness.addPlayer("Third")
		expect(RunDirector.getRun(third).origin.Position.X).toBe(b.origin.Position.X)
	end)

	RunDirector.stop()
	CombatService.stop()
	UpgradeService.stop()
end)
