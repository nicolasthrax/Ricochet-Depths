-- The route through a run and what happens inside a room beyond the fighting: the doors offered
-- after each room (and the group's vote on them), the reward a door promised, room challenges,
-- objective pieces, exploding barrels and loot crates. Installed onto MatchService.
--
-- Doors and challenges are switched on per match by deps.route ({ doors, challenges }); without
-- them a run follows its plan exactly as it always has.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArsenalConfig = require(ReplicatedStorage:WaitForChild("ArsenalConfig"))
local ObjectiveConfig = require(ReplicatedStorage:WaitForChild("ObjectiveConfig"))
local RouteConfig = require(ReplicatedStorage:WaitForChild("RouteConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local RunPlanner = require(ReplicatedStorage:WaitForChild("RunPlanner"))

local Route = { methods = {} }

local UP = Vector3.new(0, 1, 0)

local function zoneStep(definition)
	local zone = definition and RunConfig.Zones[definition.Zone]
	return zone and zone.Order or 1
end

--// doors ------------------------------------------------------------------------

-- Draws `count` distinct reward ids, weighted, never the one excluded.
function Route.methods:_drawRewards(count, exclude)
	local pool = {}
	for _, id in RouteConfig.RewardOrder do
		if id ~= exclude then
			table.insert(pool, RouteConfig.Rewards[id])
		end
	end
	local picked = {}
	while #picked < count and #pool > 0 do
		local total = 0
		for _, reward in pool do
			total += reward.Weight
		end
		local roll = self._random:NextNumber() * total
		for index, reward in pool do
			roll -= reward.Weight
			if roll <= 0 or index == #pool then
				table.insert(picked, table.remove(pool, index).Id)
				break
			end
		end
	end
	return picked
end

-- The doors to the next room: which room each leads to and what it promises. nil when doors
-- are off or this was the last room.
function Route.methods:_rollDoors()
	local nextIndex = self._roomIndex + 1
	local planned = self._plan[nextIndex]
	if not self._route.doors or not planned then
		return nil
	end
	local rooms = { planned }
	local slot = self._slots and self._slots[nextIndex]
	if slot and not slot.Room then
		local used = {}
		for _, room in self._plan do
			used[room.Id] = true
		end
		for _, candidate in RunPlanner.Candidates(slot, used, self._random) do
			if #rooms >= RouteConfig.Doors then
				break
			end
			table.insert(rooms, candidate)
		end
	end
	-- A lone room still gets a choice: the same room behind doors with different rewards.
	while #rooms < RouteConfig.Doors do
		table.insert(rooms, planned)
	end
	-- No bonus Gallery twice in a row, nor inside the scripted first descent.
	local noGallery = self._lastReward == "Gallery" or planned.Kind == "Tutorial"
	local rewards = self:_drawRewards(#rooms, noGallery and "Gallery" or nil)
	local doors = {}
	for index, room in rooms do
		local reward = RouteConfig.Rewards[rewards[index] or "Treasure"]
		table.insert(doors, {
			Id = index,
			RoomId = room.Id,
			RoomName = room.DisplayName,
			Zone = room.Zone,
			Kind = room.Kind,
			Reward = reward.Id,
			RewardTitle = reward.Title,
			RewardText = reward.Text,
			room = room,
		})
	end
	-- An extract point: the last door banks the haul and ends the run.
	local current = self._plan[self._roomIndex]
	if current and current.ExtractPoint then
		local bank = RouteConfig.BankLoot
		table.insert(doors, {
			Id = #doors + 1,
			RoomId = "Surface",
			RoomName = bank.RoomName,
			Zone = current.Zone,
			Kind = "Extract",
			Reward = bank.Id,
			RewardTitle = bank.Title,
			RewardText = bank.Text,
		})
	end
	return doors
end

function Route.methods:_openDoors(now)
	self._doors = self:_rollDoors()
	self._doorVotes = {}
	self._doorDeadline = now + RunConfig.DoorVoteSeconds
end

function Route.methods:ChooseDoor(player, doorId, _now)
	if self._state ~= RunConfig.States.UpgradeChoice or not self._doors then
		return false, "no doors"
	end
	if not table.find(self._participants, player) then
		return false, "not in the run"
	end
	if type(doorId) ~= "number" or not self._doors[doorId] then
		return false, "unknown door"
	end
	self._doorVotes[player] = doorId
	self:_broadcastRunState(self._now, true)
	return true
end

-- Whether the vote is over: nobody to vote, everyone voted, or time is up.
function Route.methods:_doorsSettled(now)
	if not self._doors then
		return true
	end
	if now >= self._doorDeadline then
		return true
	end
	for _, player in self._participants do
		if self._doorVotes[player] == nil then
			return false
		end
	end
	return true
end

-- The door with the most votes wins; a tie goes to the lower door; no votes takes door 1.
function Route.methods:_resolveDoors()
	local doors = self._doors
	self._doors = nil
	if not doors then
		return nil
	end
	local tally = {}
	for _, doorId in self._doorVotes do
		tally[doorId] = (tally[doorId] or 0) + 1
	end
	local winner = doors[1]
	for _, door in doors do
		if (tally[door.Id] or 0) > (tally[winner.Id] or 0) then
			winner = door
		end
	end
	if winner.Reward == RouteConfig.BankLoot.Id then
		-- Banked: the run ends here as an extraction (MatchService finishes it).
		self._banked = true
		self:_log("DoorChosen", { RunId = self._runId, Room = winner.RoomId, Reward = winner.Reward }, self._now)
		return winner
	end
	local nextIndex = self._roomIndex + 1
	self._plan[nextIndex] = winner.room
	self._lastReward = winner.Reward
	if winner.Reward == "Gallery" then
		-- The bonus room goes in first; the chosen room follows it.
		table.insert(self._plan, nextIndex, RouteConfig.GalleryRoom)
		if self._slots then
			table.insert(self._slots, nextIndex, false)
		end
	else
		self._roomRewards[nextIndex] = winner.Reward
	end
	self:_log("DoorChosen", { RunId = self._runId, Room = winner.RoomId, Reward = winner.Reward }, self._now)
	return winner
end

-- The doors and their votes, for the run snapshot.
function Route.methods:_doorsSnapshot(now)
	if not self._doors then
		return nil
	end
	local votes = {}
	for _, doorId in self._doorVotes do
		votes[doorId] = (votes[doorId] or 0) + 1
	end
	local list = {}
	for _, door in self._doors do
		table.insert(list, {
			Id = door.Id,
			RoomName = door.RoomName,
			Zone = door.Zone,
			Kind = door.Kind,
			Reward = door.Reward,
			RewardTitle = door.RewardTitle,
			RewardText = door.RewardText,
			Votes = votes[door.Id] or 0,
		})
	end
	return { Doors = list, SecondsLeft = math.max(math.ceil(self._doorDeadline - now), 0) }
end

--// rewards and challenges at the room boundaries --------------------------------------

-- A room is starting: the reward its door promised, and perhaps a challenge.
function Route.methods:_enterRoom(index, definition, now)
	local reward = self._roomRewards[index]
	self._roomRewards[index] = nil
	self._activeReward = reward
	if reward == "Heal" then
		for _, player in self._participants do
			local state = self._states[player]
			if state and state.alive then
				state:Heal(state.maxHealth * RouteConfig.Rewards.Heal.HealFraction)
			end
		end
	elseif reward == "Surge" then
		for _, player in self._participants do
			local state = self._states[player]
			if state then
				state.surge = math.max(state.surge, ArsenalConfig.SurgeNeeded(state.surgeLevel))
				self:_grantSurge(player, 0, now)
			end
		end
	end

	local current = self._rooms:GetCurrent()
	if current and current.runner then
		self:_fireAll("Notify", { Kind = "Callout", Text = "TREASURE RUNNER! CATCH IT!", Tone = "Gold" })
	end

	self._challenge = nil
	local challengeId = nil
	if self._route.challenges and definition.Kind == "Normal" and not definition.Objective then
		if reward == "Challenge" or self._random:NextNumber() < RouteConfig.ChallengeChance then
			challengeId = RouteConfig.ChallengeOrder[self._random:NextInteger(1, #RouteConfig.ChallengeOrder)]
		end
	elseif reward == "Challenge" then
		challengeId = "Untouchable"
	end
	if challengeId then
		self._challenge = { def = RouteConfig.Challenges[challengeId], state = "Active", startedAt = now }
		self:_fireAll("Notify", { Kind = "Callout", Text = "TRIAL: " .. RouteConfig.Challenges[challengeId].Text, Tone = "Warning" })
	end
end

function Route.methods:_failChallenge(reason)
	local challenge = self._challenge
	if challenge and challenge.state == "Active" then
		challenge.state = "Failed"
		self:_fireAll("Notify", { Kind = "Error", Text = "Trial failed: " .. reason })
	end
end

-- Every kill: Trick-shots-only fails on a straight shot kill.
function Route.methods:_onChallengeKill(_enemy, _shooter, source, bounces, _now)
	local challenge = self._challenge
	if challenge and challenge.def.Id == "BankOnly" and source == "Shot" and bounces == 0 then
		self:_failChallenge("a straight shot")
	end
end

-- A player took damage.
function Route.methods:_onPlayerHurt(_player, _now)
	local challenge = self._challenge
	if challenge and challenge.def.Id == "Untouchable" then
		self:_failChallenge("someone was hit")
	end
end

function Route.methods:_stepChallenge(now)
	local challenge = self._challenge
	if not challenge or challenge.state ~= "Active" then
		return
	end
	if challenge.def.Id == "Swift" and now - challenge.startedAt > challenge.def.Seconds then
		self:_failChallenge("out of time")
	elseif challenge.def.Id == "Combo" then
		for _, player in self._participants do
			local state = self._states[player]
			if state and state.combo >= challenge.def.Count then
				challenge.state = "Done"
				self:_fireAll("Notify", { Kind = "Callout", Text = "FRENZY REACHED!", Tone = "Gold" })
			end
		end
	end
end

-- A room was cleared: challenge payout, a treasure cache, and gallery scores.
function Route.methods:_leaveRoom(definition, now)
	local step = zoneStep(definition)
	local challenge = self._challenge
	self._challenge = nil
	if challenge then
		local won = challenge.state == "Done" or (challenge.state == "Active" and challenge.def.Id ~= "Combo")
		if won then
			for _, player in self._participants do
				local state = self._states[player]
				if state then
					state.coins += RouteConfig.ChallengeCoinsPerZone * step
					state.surge = math.max(state.surge, ArsenalConfig.SurgeNeeded(state.surgeLevel))
					self:_grantSurge(player, 0, now)
					self:_pushPlayerState(player)
				end
			end
			self:_fireAll("Notify", { Kind = "Reward", Text = string.format("Trial complete! +%d coins and a Surge perk",
				RouteConfig.ChallengeCoinsPerZone * step) })
		end
		self:_log("Challenge", { RunId = self._runId, Id = challenge.def.Id, Won = won }, now)
	end

	-- A room that bursts into coins when it is cleared (the first descent's Hoard Keeper).
	if definition and definition.CoinBurst and self._coins then
		local current = self._rooms:GetCurrent()
		local centre = current and current.bounds.center or Vector3.zero
		self._coins:Drop(centre + Vector3.new(0, 3, 0), definition.CoinBurst * math.max(#self._participants, 1))
	end

	if self._activeReward == "Treasure" and self._coins then
		local current = self._rooms:GetCurrent()
		local centre = current and current.bounds.center or Vector3.zero
		self._coins:Drop(centre + Vector3.new(0, 3, 0), RouteConfig.Rewards.Treasure.CoinsPerZone * step * math.max(#self._participants, 1))
	end
	self._activeReward = nil

	local objective = self._rooms.GetObjective and self._rooms:GetObjective()
	if objective and objective.kind == "Gallery" then
		for shooter, points in objective:Scores() do
			local state = self._states[shooter]
			if state then
				local coins = math.floor(points / ObjectiveConfig.Gallery.PointsPerCoin)
				state.coins += coins
				self:_fireClient("Notify", shooter, { Kind = "Reward", Text = string.format("Gallery score %d: +%d coins", points, coins) })
				self:_pushPlayerState(shooter)
			end
		end
	end
end

-- The room's challenge, for the run snapshot.
function Route.methods:_challengeSnapshot()
	local challenge = self._challenge
	return challenge and { Text = challenge.def.Text, State = challenge.state } or nil
end

--// things in the room -----------------------------------------------------------

-- A shot hit an objective piece (crystal or gallery target). Returns true if it was one.
function Route.methods:_objectiveImpact(result, entry, now)
	local objective = self._rooms.GetObjective and self._rooms:GetObjective()
	if not objective then
		return false
	end
	local what, points = objective:HandleImpact(result.Instance, entry)
	if not what then
		return false
	end
	if self._effects then
		local kind = (what == "Shattered" or what == "Target") and "Crit" or what == "Deflected" and "Block" or "Hit"
		self._effects:Queue(result.Position, result.Normal, kind, entry.contacts, points or 0)
	end
	if what == "Shattered" and self._coins then
		self._coins:Drop(result.Position, ObjectiveConfig.Crystals.CoinsEach)
	end
	if what == "Target" then
		self:_grantSurge(entry.shooter, 1, now)
	end
	return true
end

-- A barrel went off (and maybe set off others), or a crate broke open.
function Route.methods:_onMechanicBroken(kind, detail, shooter, now)
	if kind == "Broken" then
		if detail and detail.loot and detail.loot.Coins and self._coins then
			self._coins:Drop(detail.position, detail.loot.Coins)
		end
		self:_log("CoverBroken", { RunId = self._runId, Room = self._roomIndex }, now)
		return
	end
	local mechanics = self._rooms:GetMechanics()
	local queue = { detail }
	while #queue > 0 do
		local blast = table.remove(queue, 1)
		if self._effects then
			self._effects:Queue(blast.position, UP, "Blast", 0, 0)
		end
		for _, enemy in self._enemies:FindNear(blast.position, blast.radius) do
			self:_secondaryDamage(enemy, blast.damage, shooter, 0, "Blast", now)
		end
		for _, next in mechanics and mechanics:DetonateNear(blast.position, blast.radius) or {} do
			table.insert(queue, next)
		end
	end
	self:_log("BarrelExploded", { RunId = self._runId, Room = self._roomIndex }, now)
end

function Route.Install(class)
	for name, method in Route.methods do
		class[name] = method
	end
end

return Route
