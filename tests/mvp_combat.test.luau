-- Lane game, server services: UpgradeService (XP, offers, picks, fusion) and CombatService
-- (firing, the simulation, hits and on-hit modifiers), driven through their real remotes.
__freshMvp()
local GameConfig = __require("GameConfig")
local LaneGeometry = __require("LaneGeometry")
local Network = __require("Network")
local TargetField = __require("TargetField")
local UpgradeService = __require("UpgradeService")
local CombatService = __require("CombatService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

Network.mountServer()
UpgradeService.init()
CombatService.init()
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

-- Payloads a server -> client remote sent to `player` since the last clearFired().
local function sent(name, player)
	local list = {}
	for _, entry in remote(name)._fired do
		if entry.player == player then
			table.insert(list, entry.args[1])
		end
	end
	return list
end

local function allHits(player)
	local hits = {}
	for _, report in sent("DamageReport", player) do
		for _, hit in report.hits do
			table.insert(hits, hit)
		end
	end
	return hits
end

describe("UpgradeService", function()
	local player = Harness.addPlayer("Picker")
	local opened, closed = 0, 0
	UpgradeService.OfferOpened:Connect(function(who)
		if who == player then
			opened += 1
		end
	end)
	UpgradeService.OfferClosed:Connect(function(who)
		if who == player then
			closed += 1
		end
	end)

	-- The newest offer sent to the player, remembered across clearFired().
	local latest = nil
	local function lastOffer()
		local offers = sent("UpgradeOffered", player)
		latest = offers[#offers] or latest
		return latest
	end

	-- Picks like a player would: after the offer's input lock (and inside the remote's rate limit).
	local function pick(offer, modifierId)
		Harness.advance(GameConfig.Upgrades.inputLockSeconds + 0.1)
		remote("SelectUpgrade").OnServerEvent:Fire(player, { offerId = offer.offerId, modifierId = modifierId })
	end

	it("opens no offer until XP fills a level", function()
		clearFired()
		UpgradeService.beginRun(player, 5)
		UpgradeService.addXp(player, GameConfig.Xp.firstLevel / 2)
		expect(#sent("UpgradeOffered", player)).toBe(0)
		local xp = sent("XpChanged", player)
		expect(xp[#xp].fraction).toBeCloseTo(0.5, 1e-9)
		expect(UpgradeService.hasOpenOffer(player)).toBe(false)
	end)

	it("offers three distinct base cards with exactly one recommended", function()
		clearFired()
		UpgradeService.addXp(player, GameConfig.Xp.firstLevel)
		local offer = lastOffer()
		expect(offer).toBeTruthy()
		expect(#offer.choices).toBe(3)
		local seen, stars = {}, 0
		for _, choice in offer.choices do
			expect(seen[choice.modifierId]).toBeNil()
			seen[choice.modifierId] = true
			expect(__require("ModifierDefinitions").get(choice.modifierId).kind).toBe("Base")
			if choice.recommended then
				stars += 1
			end
		end
		expect(stars).toBe(1)
		expect(offer.inputLockSeconds).toBe(GameConfig.Upgrades.inputLockSeconds)
		expect(opened).toBe(1)
	end)

	it("ignores stale offers and cards that were not offered", function()
		local offer = lastOffer()
		clearFired()
		pick({ offerId = offer.offerId + 999 }, offer.choices[1].modifierId)
		for _, id in __require("ModifierDefinitions").baseIds do
			local offered = false
			for _, choice in offer.choices do
				offered = offered or choice.modifierId == id
			end
			if not offered then
				pick(offer, id)
				break
			end
		end
		expect(#sent("UpgradeResolved", player)).toBe(0)
		expect(UpgradeService.hasOpenOffer(player)).toBe(true)
	end)

	it("applies a pick, updates stats and closes the pick session", function()
		local offer = lastOffer()
		clearFired()
		local statsEvents = 0
		local connection = UpgradeService.StatsChanged:Connect(function()
			statsEvents += 1
		end)
		pick(offer, offer.choices[1].modifierId)
		connection:Disconnect()
		expect(#sent("UpgradeResolved", player)).toBe(1)
		expect(statsEvents).toBe(1)
		expect(closed).toBe(1)
		local loadout = sent("LoadoutChanged", player)
		expect(loadout[#loadout].modifiers[1].id).toBe(offer.choices[1].modifierId)
	end)

	it("queues several level-ups as one pick session", function()
		clearFired()
		opened, closed = 0, 0
		UpgradeService.addXp(player, 1000)
		local offers = sent("UpgradeOffered", player)
		expect(#offers).toBe(1)
		local picks = 0
		while UpgradeService.hasOpenOffer(player) and picks < 20 do
			local offer = lastOffer()
			pick(offer, offer.choices[1].modifierId)
			picks += 1
		end
		expect(picks).toBeGreaterThan(1)
		expect(opened).toBe(1)
		expect(closed).toBe(1)
	end)

	it("fuses a picked duplicate into its fused variant and recommends the fusing card", function()
		clearFired()
		UpgradeService.beginRun(player, 99)
		UpgradeService.grant(player, "Ember")
		local fusedBy = nil
		local picks = 0
		for _ = 1, 60 do
			UpgradeService.addXp(player, 10000)
			while UpgradeService.hasOpenOffer(player) and picks < 500 do
				picks += 1
				local offer = lastOffer()
				local choice = offer.choices[1]
				for _, candidate in offer.choices do
					if candidate.modifierId == "Ember" then
						expect(candidate.fusesInto).toBe("Inferno")
						expect(candidate.recommended).toBe(true)
						choice = candidate
					end
				end
				pick(offer, choice.modifierId)
				if choice.modifierId == "Ember" then
					fusedBy = offer.offerId
					break
				end
			end
			if fusedBy then
				break
			end
		end
		expect(fusedBy).toBeTruthy()
		local fusion = nil
		for _, change in sent("LoadoutChanged", player) do
			fusion = change.fusion or fusion
		end
		expect(fusion.result).toBe("Inferno")
		expect(UpgradeService.getShotStats(player).tint).toBe("Inferno")
		expect(UpgradeService.runSummary(player).fusions).toBe(1)
	end)

	it("fuses through grant and reports the fusion", function()
		UpgradeService.beginRun(player, 3)
		expect(UpgradeService.grant(player, "Echo")).toBeNil()
		local fusion = UpgradeService.grant(player, "Echo")
		expect(fusion.result).toBe("Resonance")
		expect(UpgradeService.getShotStats(player).bounces).toBe(GameConfig.Shot.baseBounces + 2)
	end)

	it("rerolls only with a token, into a fresh offer id", function()
		UpgradeService.beginRun(player, 8)
		clearFired()
		UpgradeService.addXp(player, GameConfig.Xp.firstLevel)
		local offer = lastOffer()
		expect(offer.rerollVisible).toBe(false)
		remote("RerollUpgrade").OnServerEvent:Fire(player, { offerId = offer.offerId })
		expect(#sent("UpgradeOffered", player)).toBe(1)
		UpgradeService.grantRerolls(player, 1)
		remote("RerollUpgrade").OnServerEvent:Fire(player, { offerId = offer.offerId })
		local rerolled = lastOffer()
		expect(rerolled.offerId).never().toBe(offer.offerId)
		expect(rerolled.rerollsLeft).toBe(0)
		UpgradeService.endRun(player)
		expect(UpgradeService.hasOpenOffer(player)).toBe(false)
	end)
end)

describe("CombatService", function()
	local player = Harness.addPlayer("Shooter")
	local sequence = 0

	-- A fresh run and lane holding the given blocks: { column, row, hp } each.
	local function lane(blocks, grants)
		UpgradeService.beginRun(player, 1)
		for _, id in grants or {} do
			UpgradeService.grant(player, id)
		end
		local field = TargetField.new()
		local ids = {}
		for _, block in blocks do
			local target = field:add("Block", block[1], block[2], 1, block[3])
			table.insert(ids, target.id)
		end
		CombatService.beginLane(player, field, CFrame.new(0, 0, 0))
		clearFired()
		return field, ids
	end

	local function fire(dx, dy, originX)
		sequence += 1
		remote("FireProjectile").OnServerEvent:Fire(player, {
			originX = originX or 0,
			direction = Vector2.new(dx, dy),
			sequence = sequence,
		})
	end

	it("fires a shot, reports its hit and the bounce, and ends it past the rail", function()
		local field, ids = lane({ { 5, 5, 100 } })
		Harness.advance(1)
		fire(0, 1)
		local spawned = sent("ShotsSpawned", player)
		expect(#spawned).toBe(1)
		local shot = spawned[1].shots[1]
		expect(shot.sequence).toBe(sequence)
		expect(shot.ownerUserId).toBe(player.UserId)
		expect(shot.y).toBeCloseTo(GameConfig.Shot.muzzleOffset, 1e-9)
		Harness.stepSeconds(2)
		local hits = allHits(player)
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(ids[1])
		expect(hits[1].source).toBe("Direct")
		expect(hits[1].amount).toBe(GameConfig.Shot.baseDamage)
		expect(field:get(ids[1]).hp).toBe(100 - GameConfig.Shot.baseDamage)
		expect(#sent("ShotsBounced", player)).toBeGreaterThan(0)
		expect(#sent("ShotsEnded", player)).toBe(1)
		expect(CombatService.activeShotCount(player)).toBe(0)
	end)

	it("enforces the cooldown and raises flat aims to the minimum angle", function()
		lane({})
		Harness.advance(1)
		fire(1, 0)
		fire(0, 1)
		local spawned = sent("ShotsSpawned", player)
		expect(#spawned).toBe(1)
		local shot = spawned[1].shots[1]
		expect(shot.dirY).toBeCloseTo(GameConfig.Shot.minAimY, 1e-9)
		expect(shot.dirX).toBeGreaterThan(0)
	end)

	it("fires from the client's origin only near the server's rail position", function()
		lane({})
		Harness.advance(1)
		fire(0, 1, 2)
		Harness.advance(1)
		fire(0, 1, 10)
		local spawned = sent("ShotsSpawned", player)
		expect(spawned[1].shots[1].x).toBe(2)
		expect(spawned[2].shots[1].x).toBe(0)
	end)

	it("limits how far each rail update can move the avatar", function()
		lane({})
		Harness.advance(0.1)
		remote("RailInput").OnServerEvent:Fire(player, { x = 12, sequence = 1 })
		local rail = GameConfig.Rail
		expect(CombatService.getRailX(player)).toBeCloseTo(rail.maxSpeed * rail.speedTolerance * 0.1, 1e-9)
		remote("RailInput").OnServerEvent:Fire(player, { x = -12, sequence = 1 }) -- stale sequence
		expect(CombatService.getRailX(player)).toBeGreaterThan(0)
	end)

	it("lets a shot carry on through a target it breaks", function()
		local field, ids = lane({ { 5, 6, 1 }, { 5, 4, 100 } })
		local broken = {}
		local connection = CombatService.TargetBroken:Connect(function(who, target, source, shotId)
			table.insert(broken, { id = target.id, source = source, shotId = shotId })
		end)
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(1)
		connection:Disconnect()
		local hits = allHits(player)
		expect(hits[1].targetId).toBe(ids[1])
		expect(hits[1].hpAfter).toBe(0)
		expect(hits[2].targetId).toBe(ids[2])
		expect(#broken).toBe(1)
		expect(broken[1].shotId).toBe(hits[1].shotId)
		expect(field:get(ids[1])).toBeNil()
	end)

	it("pierces with Drill and bounces off without it", function()
		local _, ids = lane({ { 5, 6, 100 }, { 5, 4, 100 } })
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(1)
		local plain = allHits(player)
		expect(#plain).toBe(1)
		expect(plain[1].targetId).toBe(ids[1])

		local _, drillIds = lane({ { 5, 6, 100 }, { 5, 4, 100 } }, { "Drill" })
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(1)
		local drilled = allHits(player)
		expect(drilled[1].targetId).toBe(drillIds[1])
		expect(drilled[2].targetId).toBe(drillIds[2])
		expect(drilled[1].amount).toBeCloseTo(GameConfig.Shot.baseDamage * 0.9, 1e-9)
	end)

	it("burns with Ember and blasts neighbours with Inferno", function()
		local _, ids = lane({ { 5, 5, 100 } }, { "Ember" })
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(3)
		local burned = 0
		for _, hit in allHits(player) do
			if hit.source == "Burn" then
				expect(hit.targetId).toBe(ids[1])
				burned += hit.amount
			end
		end
		expect(burned).toBeCloseTo(4, 1e-6)

		local _, infernoIds = lane({ { 5, 5, 100 }, { 6, 5, 100 } }, { "Ember", "Ember" })
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(0.5)
		local blasted = false
		for _, hit in allHits(player) do
			if hit.source == "Blast" and hit.targetId == infernoIds[2] then
				blasted = true
			end
		end
		expect(blasted).toBe(true)
	end)

	it("splits on bounce with Splitshot", function()
		lane({ { 5, 5, 100 } }, { "Splitshot" })
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(0.6)
		local shards = 0
		for _, batch in sent("ShotsSpawned", player) do
			for _, shot in batch.shots do
				if shot.parentShotId then
					shards += 1
				end
			end
		end
		expect(shards).toBe(2)
	end)

	it("arcs to a neighbour with Spark and chills with Frostbite", function()
		local _, ids = lane({ { 5, 5, 100 }, { 6, 5, 100 } }, { "Spark" })
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(0.6)
		local arced = false
		for _, hit in allHits(player) do
			arced = arced or (hit.source == "Arc" and hit.targetId == ids[2])
		end
		expect(arced).toBe(true)

		local field, chillIds = lane({ { 5, 5, 100 } }, { "Frostbite" })
		Harness.advance(1)
		fire(0, 1)
		Harness.stepSeconds(0.6)
		expect(field:get(chillIds[1]).skipSteps).toBe(1)
		field:advance()
		expect(field:get(chillIds[1]).row).toBe(5)
	end)

	it("freezes at time scale 0 and re-sends live shots when it resumes", function()
		lane({ { 5, 1, 100 } })
		Harness.advance(1)
		fire(0, 1)
		CombatService.setTimeScale(player, 0)
		Harness.stepSeconds(5)
		expect(#allHits(player)).toBe(0)
		clearFired()
		CombatService.setTimeScale(player, 1)
		local resync = sent("ShotsBounced", player)
		expect(#resync).toBe(1)
		expect(resync[1].bounces[1].y).toBeCloseTo(GameConfig.Shot.muzzleOffset, 1e-9)
		Harness.advance(1)
		fire(0, 1) -- frozen lanes refuse shots; this one is accepted again
		expect(CombatService.activeShotCount(player)).toBe(2)
		CombatService.clearShots(player)
		expect(CombatService.activeShotCount(player)).toBe(0)
		expect(#sent("ShotsEnded", player)[1].ends).toBe(2)
	end)

	it("refuses shots while frozen", function()
		lane({})
		CombatService.setTimeScale(player, 0)
		Harness.advance(1)
		fire(0, 1)
		expect(#sent("ShotsSpawned", player)).toBe(0)
		CombatService.setTimeScale(player, 1)
	end)

	it("aims with the shared rule on both sides", function()
		local x, y = LaneGeometry.clampAim(-1, -1)
		expect(x).toBeLessThan(0)
		expect(y).toBeCloseTo(GameConfig.Shot.minAimY, 1e-9)
		x, y = LaneGeometry.clampAim(0, 0)
		expect(x).toBe(0)
		expect(y).toBe(1)
	end)

	UpgradeService.stop()
	CombatService.stop()
end)
