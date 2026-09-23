-- Headless dry-run simulator.
--
-- Drives a scripted bot through the real MatchService, RoomService, EnemyService and
-- ProjectileService, with collision resolved against the actual room layouts, and reports how
-- long rooms and runs take.
--
-- THESE NUMBERS ARE LOWER-BOUND ESTIMATES, NOT MEASUREMENTS. The bot has exact enemy positions,
-- fires the instant its cooldown allows, never misjudges a bank shot, never hesitates over a
-- card and never panics. A human will be slower. Treat the output as "this run cannot be
-- shorter than roughly X", and nothing more. No balance value should be changed on the strength
-- of it; real playtest timings are the only thing that can confirm the 6-8 minute target.

local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomConfig = __require("RoomConfig")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local RunPlanner = __require("RunPlanner")
local UpgradeService = __require("UpgradeService")
local WorldAdapter = __require("WorldAdapter")

local PLANE_Y = 3
local DT = 1 / 30
local WALK_SPEED = 16
local KITE_DISTANCE = 22
-- How far off a straight line the bot sidesteps while working around cover.
local STRAFE_FRACTION = 0.6
local MAX_FRAMES = 30000 -- hard stop so a pathological run cannot hang the tool

-- None of these bots can plan a bank shot, which is the game's central skill. They fire
-- straight lines and only benefit from ricochets by accident. Read every number as a floor on
-- direct-fire clear speed, not as a prediction of how a player will do.
local SCENARIOS = {
	{
		name = "Direct fire, exact aim",
		note = "perfect straight-line aim, fires the moment the cooldown allows, never probes",
		jitterDegrees = 0,
		reactionSeconds = 0,
		missChance = 0,
		probeWhenBlocked = false,
		runs = 60,
	},
	{
		name = "Direct fire with aim error",
		note = "6 degrees of error, 0.25s to reacquire, 15% of shots thrown away",
		jitterDegrees = 6,
		reactionSeconds = 0.25,
		missChance = 0.15,
		probeWhenBlocked = false,
		runs = 40,
	},
	{
		name = "Probing bot",
		note = "aims straight when it can see a target, otherwise fires off-angle looking for a bank",
		jitterDegrees = 3,
		reactionSeconds = 0.15,
		missChance = 0,
		probeWhenBlocked = true,
		runs = 40,
	},
}

--// statistics ----------------------------------------------------------------

local function percentile(sorted, fraction)
	if #sorted == 0 then
		return 0
	end
	local index = math.clamp(math.ceil(fraction * #sorted), 1, #sorted)
	return sorted[index]
end

local function summarise(samples)
	if #samples == 0 then
		return { count = 0, mean = 0, median = 0, p10 = 0, p90 = 0, min = 0, max = 0 }
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	local total = 0
	for _, value in sorted do
		total += value
	end
	return {
		count = #sorted,
		mean = total / #sorted,
		median = percentile(sorted, 0.5),
		p10 = percentile(sorted, 0.1),
		p90 = percentile(sorted, 0.9),
		min = sorted[1],
		max = sorted[#sorted],
	}
end

--// one run -------------------------------------------------------------------

local function silentRemote()
	local remote = {}
	function remote:FireClient() end
	function remote:FireAllClients() end
	return remote
end

local function simulateRun(seed, scenario)
	local random = Random.new(seed)
	local world = __PhysicsWorld.new()

	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local geometry = Instance.new("Folder")
	geometry.Name = "SimGeometry"
	geometry.Parent = arena

	local enemies = EnemyService.new(arena, PLANE_Y, seed)
	local projectiles = ProjectileService.new(arena, arena, PLANE_Y)
	local rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(seed))
	local upgrades = UpgradeService.new(seed)

	local net = {}
	for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
		net[name] = silentRemote()
	end

	local player = Harness.addPlayer("DryRunBot" .. seed)
	Harness.giveCharacter(player, Vector3.new(0, PLANE_Y, 0))
	local root = player.Character:FindFirstChild("HumanoidRootPart")

	local match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = upgrades,
		projectiles = projectiles,
		rewards = RewardService.new(),
		net = net,
		world = WorldAdapter, -- the real adapter, driving the real character
		-- Seeded, so a given seed always plays the same rooms.
		planRun = function()
			return RunPlanner.Plan(Random.new(seed * 7919))
		end,
	})

	projectiles.OnImpact = function(result, entry)
		return match:HandleImpact(result, entry, Harness.now())
	end

	-- Who is doing the damage, per room: the audit question for any room that ends runs.
	local damageByRoom = {}
	local deliverContact = enemies.OnPlayerContact
	enemies.OnPlayerContact = function(target, damage, enemy, now)
		local state = match:GetPlayerState(target)
		local before = state and state.health or 0
		deliverContact(target, damage, enemy, now)
		local taken = before - (state and state.health or 0)
		if taken > 0 then
			local room = match:GetRunSnapshot().RoomIndex
			damageByRoom[room] = damageByRoom[room] or {}
			damageByRoom[room][enemy.archetypeId] = (damageByRoom[room][enemy.archetypeId] or 0) + taken
		end
	end

	local trackedEnemies = {}
	local builtLayout = nil
	local poolFolder = arena:FindFirstChild("ProjectilePool")

	-- Keeps the collision world in step with what the game actually has spawned.
	local function syncWorld()
		local current = rooms:GetCurrent()
		local layoutId = current and current.definition.Layout or nil
		if layoutId ~= builtLayout then
			world:Clear()
			geometry:ClearAllChildren()
			table.clear(trackedEnemies)
			if layoutId then
				world:AddRoomLayout(RoomConfig.GetLayout(layoutId), RoomConfig, geometry)
			end
			builtLayout = layoutId
		end

		local live = {}
		for _, enemy in enemies:GetEnemies() do
			live[enemy.part] = true
			if trackedEnemies[enemy.part] then
				world:MoveBox(enemy.part, enemy.position)
			else
				world:AddBox(enemy.part, enemy.position, enemy.archetype.Size)
				trackedEnemies[enemy.part] = true
			end
		end
		for part in trackedEnemies do
			if not live[part] then
				world:RemoveBox(part)
				trackedEnemies[part] = nil
			end
		end
	end

	world:Install()

	local clock = 0
	Harness.setClock(0)
	match:RegisterPlayer(player)
	match:RequestStart(player, clock)

	local runStartedAt = clock
	local roomTimings = {}
	local currentRoomIndex, currentRoomStart = nil, nil
	local aimTarget, nextAimAt = nil, 0
	local shots, frames = 0, 0
	local strafeSign = random:NextNumber() < 0.5 and -1 or 1

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { arena }
	local outcome = "Unfinished"

	net.RunResults.FireClient = function(_self, _target, summary)
		outcome = summary.Outcome
	end

	while frames < MAX_FRAMES do
		frames += 1
		clock += DT
		Harness.setClock(clock)

		enemies:Step(DT, clock)
		syncWorld()
		__integrateParts(poolFolder, DT)
		projectiles:Step(DT)

		local state = match:GetState()

		if state == RunConfig.States.Combat then
			local snapshot = match:GetRunSnapshot()
			if snapshot.RoomIndex ~= currentRoomIndex then
				-- Advancing means the previous room was genuinely cleared, so its time counts
				-- whatever happens later in the run.
				if currentRoomIndex and currentRoomStart then
					roomTimings[currentRoomIndex] = clock - currentRoomStart
				end
				currentRoomIndex = snapshot.RoomIndex
				currentRoomStart = clock
			end

			local botPosition = Vector3.new(root.Position.X, PLANE_Y, root.Position.Z)

			-- Prefer the nearest enemy the bot can actually shoot. A player works around cover
			-- rather than emptying the magazine into a pillar, so the bot must too.
			local bestVisible, bestVisibleDistance
			local nearest, nearestDistance
			for _, enemy in enemies:GetEnemies() do
				local enemyPosition = Vector3.new(enemy.position.X, PLANE_Y, enemy.position.Z)
				local distance = (enemyPosition - botPosition).Magnitude
				if not nearestDistance or distance < nearestDistance then
					nearest, nearestDistance = enemy, distance
				end
				if distance > 1e-3 then
					local hit = workspace:Raycast(botPosition, enemyPosition - botPosition, rayParams)
					if hit and hit.Instance == enemy.part then
						if not bestVisibleDistance or distance < bestVisibleDistance then
							bestVisible, bestVisibleDistance = enemy, distance
						end
					end
				end
			end

			if (bestVisible or nearest) and clock >= nextAimAt then
				aimTarget = bestVisible or nearest
				nextAimAt = clock + scenario.reactionSeconds
			end

			local bounds = rooms:GetCurrent() and rooms:GetCurrent().bounds
			local function moveTo(step)
				local moved = botPosition + step
				if bounds then
					moved = Vector3.new(
						math.clamp(moved.X, -bounds.half.X, bounds.half.X),
						PLANE_Y,
						math.clamp(moved.Z, -bounds.half.Y, bounds.half.Y)
					)
				end
				root.CFrame = CFrame.new(moved)
			end

			if nearest and nearestDistance and nearestDistance < KITE_DISTANCE then
				-- Circle away rather than reversing in a straight line. Backing straight up
				-- walks into a corner and dies there, which says more about the bot than the
				-- game, so the bot strafes the way a player would.
				local away = botPosition - Vector3.new(nearest.position.X, PLANE_Y, nearest.position.Z)
				if away.Magnitude > 1e-3 then
					local outward = away.Unit
					local tangent = Vector3.new(-outward.Z, 0, outward.X) * strafeSign
					moveTo((outward * 0.6 + tangent * 0.8).Unit * WALK_SPEED * DT)
				end
			elseif not bestVisible and nearest then
				-- Nothing in view: close on the nearest enemy, sidestepping so the bot works
				-- its way around whatever is blocking rather than pressing into it.
				local toward = Vector3.new(nearest.position.X, PLANE_Y, nearest.position.Z) - botPosition
				if toward.Magnitude > 1e-3 then
					local forward = toward.Unit
					local sideways = Vector3.new(-forward.Z, 0, forward.X) * strafeSign
					moveTo((forward + sideways * STRAFE_FRACTION).Unit * WALK_SPEED * DT)
				end
			end

			if aimTarget and not aimTarget.dead then
				local toTarget = Vector3.new(aimTarget.position.X - root.Position.X, 0, aimTarget.position.Z - root.Position.Z)
				if toTarget.Magnitude > 1e-3 then
					local angle = math.atan2(toTarget.Z, toTarget.X)
					if scenario.probeWhenBlocked and not bestVisible then
						-- Nothing on a straight line: throw the shot wide and let the walls do
						-- the work. A crude stand-in for a player hunting an angle.
						angle += math.rad((random:NextNumber() * 2 - 1) * 90)
					elseif scenario.jitterDegrees > 0 then
						angle += math.rad((random:NextNumber() * 2 - 1) * scenario.jitterDegrees)
					end
					if scenario.missChance > 0 and random:NextNumber() < scenario.missChance then
						angle += math.rad((random:NextNumber() * 2 - 1) * 45) -- a thrown-away shot
					end
					if match:HandleFire(player, Vector3.new(math.cos(angle), 0, math.sin(angle)), 1, clock) then
						shots += 1
					end
				end
			end
		elseif state == RunConfig.States.UpgradeChoice then
			local offer = upgrades:GetOffer(player)
			if offer then
				match:ChooseUpgrade(player, offer.id, offer.cards[1].Id, clock)
			end
		elseif state == RunConfig.States.Results then
			-- Only an extraction cleared the final room; a defeat leaves it unfinished, and a
			-- partial time is not a clear time.
			if outcome == "Extracted" and currentRoomIndex and currentRoomStart then
				roomTimings[currentRoomIndex] = clock - currentRoomStart
			end
			break
		end

		match:Step(DT, clock)
	end

	local state = match:GetPlayerState(player)
	local result = {
		outcome = outcome,
		duration = clock - runStartedAt,
		roomTimings = roomTimings,
		endedInRoom = currentRoomIndex or (state and state.roomsCleared or 0) + 1,
		roomsCleared = state and state.roomsCleared or 0,
		kills = state and state.kills or 0,
		shots = shots,
		frames = frames,
		damageByRoom = damageByRoom,
	}

	match:UnregisterPlayer(player, clock)
	Harness.removePlayer(player)
	__raycastHandler = nil
	return result
end

--// reporting -----------------------------------------------------------------

local function formatStats(label, stats)
	if stats.count == 0 then
		return string.format("  %-26s no samples", label)
	end
	return string.format(
		"  %-26s n=%-4d median %6.1fs   mean %6.1fs   p10 %6.1fs   p90 %6.1fs   range %.1f-%.1fs",
		label, stats.count, stats.median, stats.mean, stats.p10, stats.p90, stats.min, stats.max
	)
end

print("")
print("=========================================================================")
print(" Ricochet Depths - headless dry run")
print("")
print(" ESTIMATES, NOT MEASUREMENTS. These bots know exactly where every enemy is")
print(" and never hesitate, but none of them can plan a bank shot, which is the")
print(" game\'s central skill. They are a floor on direct-fire clear speed only.")
print(" A player who banks deliberately will clear cover-heavy rooms faster; a")
print(" player learning the controls will be far slower. Real playtest timings")
print(" are the only thing that can confirm the 6-8 minute target, and no balance")
print(" value should change on the strength of these numbers.")
print("=========================================================================")

for _, scenario in SCENARIOS do
	local durations, completed = {}, 0
	local outcomes = {}
	local perRoom = {}
	local endedIn = {}
	local totalKills, totalShots = 0, 0
	local damageByRoom = {}

	for run = 1, scenario.runs do
		local result = simulateRun(4000 + run, scenario)
		outcomes[result.outcome] = (outcomes[result.outcome] or 0) + 1
		endedIn[result.endedInRoom] = (endedIn[result.endedInRoom] or 0) + 1
		totalKills += result.kills
		totalShots += result.shots
		for room, byArchetype in result.damageByRoom do
			damageByRoom[room] = damageByRoom[room] or {}
			for archetype, amount in byArchetype do
				damageByRoom[room][archetype] = (damageByRoom[room][archetype] or 0) + amount
			end
		end

		-- Room times come from every room that was actually cleared, in any run. Full-run
		-- durations only make sense for a run that finished.
		for index, seconds in result.roomTimings do
			perRoom[index] = perRoom[index] or {}
			table.insert(perRoom[index], seconds)
		end
		if result.outcome == "Extracted" then
			completed += 1
			table.insert(durations, result.duration)
		end
	end

	print("")
	print(string.format("%s  (%d runs)", scenario.name, scenario.runs))
	print(string.format("  %s", scenario.note))
	print("")
	print(formatStats("full run, extracted", summarise(durations)))
	-- Rooms vary between runs, so timings are grouped by slot of the run shape.
	for index, slot in RunConfig.RunShape do
		local label = slot.Room or string.format("%s tier %d", slot.Zone, slot.Tier)
		print(formatStats(string.format("room %d %s", index, label), summarise(perRoom[index] or {})))
	end

	-- Full-run samples are scarce whenever the bots keep dying, so model the floor instead:
	-- the median clear for each room, plus the fixed pacing the run always spends.
	local modelled, missingRoom = 0, false
	local forceCleared = 0
	for index = 1, RunConfig.RoomCount() do
		local samples = perRoom[index]
		if samples and #samples > 0 then
			modelled += summarise(samples).median
			-- The last room is the boss's, which has its own, longer limit.
			local limit = index == RunConfig.RoomCount() and RunConfig.BossRoomTimeLimit or RunConfig.RoomTimeLimit
			for _, seconds in samples do
				if seconds >= limit then
					forceCleared += 1
				end
			end
		else
			missingRoom = true
		end
	end
	local fixedPacing = RunConfig.StartCountdown + RunConfig.TransitionDuration * (RunConfig.RoomCount() - 1)
	print("")
	if missingRoom then
		print("  modelled run floor: not enough room samples")
	else
		print(string.format(
			"  modelled run floor: %.0fs combat + %.0fs fixed pacing = %.0fs  (%.1f min)",
			modelled, fixedPacing, modelled + fixedPacing, (modelled + fixedPacing) / 60
		))
	end
	print(string.format("  rooms force-cleared by the %ds room time limit: %d", RunConfig.RoomTimeLimit, forceCleared))

	local outcomeParts = {}
	for name, count in outcomes do
		table.insert(outcomeParts, string.format("%s %d", name, count))
	end
	table.sort(outcomeParts)
	print("")
	print(string.format("  outcomes: %s", table.concat(outcomeParts, ", ")))
	print(string.format("  extraction rate: %.0f%%", completed / scenario.runs * 100))

	local endedParts = {}
	for index = 1, RunConfig.RoomCount() do
		if endedIn[index] then
			table.insert(endedParts, string.format("room %d: %d", index, endedIn[index]))
		end
	end
	print(string.format("  runs ended in:  %s", table.concat(endedParts, ",  ")))
	print(string.format("  average kills per run: %.1f", totalKills / scenario.runs))
	print(string.format("  average accepted shots per run: %.1f", totalShots / scenario.runs))
	if totalShots > 0 then
		print(string.format("  kills per shot: %.2f", totalKills / totalShots))
	end

	for index = 1, RunConfig.RoomCount() do
		local byArchetype = damageByRoom[index]
		if byArchetype then
			local total, parts = 0, {}
			for _, amount in byArchetype do
				total += amount
			end
			for archetype, amount in byArchetype do
				table.insert(parts, string.format("%s %.0f%%", archetype, amount / total * 100))
			end
			table.sort(parts)
			print(string.format(
				"  damage taken in room %d: %.0f per run  (%s)",
				index, total / scenario.runs, table.concat(parts, ", ")
			))
		end
	end

	__DRYRUN_RESULTS = __DRYRUN_RESULTS or {}
	__DRYRUN_RESULTS[scenario.name] = { durations = durations, completed = completed, runs = scenario.runs }
end

print("")
print("Target for comparison: RunConfig.TargetRunSeconds = " .. RunConfig.TargetRunSeconds .. "s")
print("")
