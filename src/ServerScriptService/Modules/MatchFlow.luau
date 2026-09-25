-- Room-to-room progression: starting a room, clearing it, opening an upgrade round, finishing
-- a run and tearing it down. Installed onto MatchService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyModifierConfig = require(ReplicatedStorage:WaitForChild("DailyModifierConfig"))
local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local Payout = require(script.Parent.Payout)
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local RewardConfig = require(ReplicatedStorage:WaitForChild("RewardConfig"))
local RouteConfig = require(ReplicatedStorage:WaitForChild("RouteConfig"))
local RunSummary = require(script.Parent.RunSummary)
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local States = RunConfig.States

local Flow = { methods = {} }

function Flow.methods:_beginRoom(index, now)
	local definition = self._plan[index]
	if not definition then
		return self:_finish("Extracted", now)
	end

	-- Anyone who joined mid-run is admitted here, at a room boundary, never mid-fight.
	for _, player in self._pendingJoins do
		local joiner = self._states[player]
		if joiner and not table.find(self._participants, player) then
			self:_refreshMeta(player, joiner)
			joiner:ResetRun()
			-- No credit for rooms cleared before they arrived. roomsCleared only ever grows in
			-- _onRoomCleared, for participants present at the clear, so it counts rooms this
			-- player was actually in. Pre-crediting let a player wait out a run and join at the
			-- elite room to collect the whole team's room payout.
			joiner.joinedAtRoom = index
			table.insert(self._participants, player)
			self:_log("LateJoin", { RunId = self._runId, Room = index }, now)
		end
	end
	table.clear(self._pendingJoins)

	self._roomIndex = index

	local loaded, reason = self._rooms:Load(definition, now)
	if not loaded then
		-- Nothing was built, so there is nothing to clear: IsCleared stays false and the run
		-- would sit in Combat until the hard time limit. End it instead of hanging.
		if self._telemetry then
			self._telemetry:LogError("RoomLoadFailed", reason, now)
		end
		return self:_finish("Aborted", now)
	end

	-- Every orb back in hand, and whatever the door into this room promised.
	self:_resetOrbs()
	self:_enterRoom(index, definition, now)

	local spawnPoint = self._rooms:GetSpawnPoint()
	-- Everyone lands facing into the room, at the fight (the concept's "spawn facing the pit").
	local current = self._rooms:GetCurrent()
	local facing = current and current.bounds and current.bounds.center or nil
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			if not state.alive then
				state:Revive(now) -- downed players return at the start of the next room
			end
			state:GrantInvulnerability(now)
			if self._world then
				self._world.Teleport(player, spawnPoint, facing)
				if self._world.SetWalkSpeed then
					self._world.SetWalkSpeed(player, RunConfig.BaseWalkSpeed + state.stats.MoveSpeedBonus)
				end
			end
			self:_pushPlayerState(player)
		end
	end

	self:_setState(States.Combat, now)
	if index == 1 and self._runOptions and self._runOptions.firstDescent then
		self:_fireAll("Notify", { Kind = "Callout", Text = RunConfig.FirstDescent.Banner, Tone = "Gold" })
	end
	self:_log("RoomStart", { RunId = self._runId, Room = index, RoomId = definition.Id }, now)
	return nil
end

-- A participant whose character respawned mid-run (a reset, or a fall out of the world)
-- appears at the lobby's SpawnLocation; this puts them back in the current room. It also covers
-- a room start that could not teleport someone who was mid-respawn at the time.
function Flow.methods:HandleCharacterAdded(player)
	local state = self._states[player]
	if not state or not self:IsRunActive() or not table.find(self._participants, player) then
		return false
	end
	if not self._rooms:GetCurrent() or not self._world then
		return false -- no room yet: the room start teleports everyone
	end
	self._world.Teleport(player, self._rooms:GetSpawnPoint())
	if self._world.SetWalkSpeed then
		self._world.SetWalkSpeed(player, RunConfig.BaseWalkSpeed + state.stats.MoveSpeedBonus)
	end
	return true
end

-- Anyone who has dropped well below the room's floor (through a seam, or off an edge) is put
-- back on the spawn pad at once, rather than left to die and respawn in the lobby.
function Flow.methods:_rescueFallers(now)
	local current = self._rooms:GetCurrent()
	if not current or not self._world or not self._world.GetPosition then
		return
	end
	local lowest = current.bounds.center.Y - RunConfig.FallRescueDepth
	for _, player in self._participants do
		local position = self._world.GetPosition(player)
		if position and position.Y < lowest then
			self._world.Teleport(player, self._rooms:GetSpawnPoint())
			self:_log("FallRescued", { RunId = self._runId, Room = self._roomIndex }, now)
		end
	end
end

function Flow.methods:_onRoomCleared(now)
	local definition = self._plan[self._roomIndex]
	local current = self._rooms:GetCurrent()
	-- Under depth pressure, a normal room the clock had to clear forfeits its door's reward and
	-- any Trial: dragging a room out should never pay.
	if self._route.pressure and current and current.timedOut and definition and definition.Kind == "Normal" then
		self._activeReward = nil
		if self._failChallenge then
			self:_failChallenge("out of time")
		end
		self:_fireAll("Notify", { Kind = "Error", Text = "The depths drove you on. The door's reward is lost." })
	end
	-- Hunters leave with the room.
	if self._rooms.EndPressure then
		self._rooms:EndPressure()
	end
	-- The door's reward, challenge payouts and gallery scores land before the coins are swept.
	local armoury = self._activeReward == "Arsenal"
	self:_leaveRoom(definition, now)
	self:_sweepCoins()
	self:_resolveSurges(now, true)
	self:_resetOrbs()
	if definition and definition.Kind == "Elite" then
		self._eliteCleared = true
	end

	for _, player in self._participants do
		local state = self._states[player]
		if state then
			state.roomsCleared += 1
			if state.alive and state.stats.RoomClearHeal > 0 then
				state:Heal(state.stats.RoomClearHeal)
			end
			if state.alive and definition and definition.HealOnClear then
				state:Heal(state.maxHealth * definition.HealOnClear)
			end
			self:_pushPlayerState(player)
		end
	end
	self:_log("RoomClear", { RunId = self._runId, Room = self._roomIndex }, now)

	if self._roomIndex >= #self._plan then
		return self:_finish("Extracted", now)
	end

	self._projectiles:Clear()
	self:_openUpgradeChoice(now, armoury)
	return nil
end

-- armoury: the door into the room just cleared promised a bigger offer with a Rare in it.
function Flow.methods:_openUpgradeChoice(now, armoury)
	local offered = 0
	local count = self._pactEffects.OfferCount
	local options = nil
	if armoury then
		count = math.max(count or 0, RouteConfig.Rewards.Arsenal.Cards)
		options = { rare = true }
	end
	-- The first descent hands out the cards that teach a fusion.
	local forced = self._runOptions and self._runOptions.firstDescent and RunConfig.FirstDescent.ForceCards[self._roomIndex]
	if forced then
		options = options or {}
		options.force = forced
	end
	self._upgradeRound = (self._upgradeRound or 0) + 1
	self:_openDoors(now)
	if self._upgrades.ClearSettled then
		self._upgrades:ClearSettled()
	end
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			local offer = self._upgrades:BuildOffer(player, state, now, count, options)
			self:_fireClient("UpgradeOffer", player, self:_offerPayload(player, offer, now))
			offered += 1
			self:_log("CardOffered", { RunId = self._runId, Room = self._roomIndex }, now)
		end
	end

	-- Nobody to offer to: skip straight on rather than waiting for choices that cannot arrive.
	self:_setState(offered > 0 and States.UpgradeChoice or States.Transition, now)
end

-- An offer as the client sees it, with what this player may still do with it: reroll (free, or
-- how many tokens they hold) and respec.
function Flow.methods:_offerPayload(player, offer, now)
	local payload = self._upgrades.ToClientPayload(offer, now)
	local state = self._states[player]
	payload.FreeRerolls = state and math.max(RunConfig.Cards.FreeRerolls - state.freeRerollsUsed, 0) or 0
	payload.Rerolls = self._persistence and self._persistence.GetBalance and self._persistence:GetBalance(player, "Rerolls") or 0
	payload.CanRespec = state ~= nil and not state.respecUsed and (self._upgradeRound or 0) <= RunConfig.Cards.RespecRounds
	return payload
end

-- Redraws a player's pending offer. The first reroll of a run is free; after that each costs a
-- Reroll token, spent through the purchase path as the next level of a use counter.
function Flow.methods:RerollOffer(player, now)
	local state = self._states[player]
	if self._state ~= States.UpgradeChoice or not state or not self._upgrades.Reroll then
		return false, "not choosing upgrades"
	end
	local pending = self._upgrades:GetOffer(player)
	if not pending or pending.resolved then
		return false, "no pending offer"
	end
	if state.freeRerollsUsed < RunConfig.Cards.FreeRerolls then
		state.freeRerollsUsed += 1
	else
		local persistence = self._persistence
		if not persistence or not persistence.SpendOnUpgrade then
			return false, "no rerolls"
		end
		local useId = RunConfig.Cards.RerollUseId
		local used = persistence:GetMetaLevels(player)[useId] or 0
		local left, reason = persistence:SpendOnUpgrade(player, useId, used + 1, 1, "Rerolls")
		if not left then
			self:_fireClient("Notify", player, { Kind = "Error", Text = "No rerolls left. Find more in daily rewards." })
			return false, reason
		end
		persistence:SaveInBackground(player, now)
	end
	local offer = self._upgrades:Reroll(player, state, now)
	self:_fireClient("UpgradeOffer", player, self:_offerPayload(player, offer, now))
	self:_log("CardRerolled", { RunId = self._runId, Room = self._roomIndex }, now)
	return true
end

-- Respec: in the first RespecRounds rounds, once a run, undo the card just taken and choose again
-- from the same offer.
function Flow.methods:RespecCard(player, now)
	local state = self._states[player]
	if self._state ~= States.UpgradeChoice or not state or not self._upgrades.Reopen then
		return false, "not choosing upgrades"
	end
	if state.respecUsed or (self._upgradeRound or 0) > RunConfig.Cards.RespecRounds then
		return false, "respec spent"
	end
	local offer, reason = self._upgrades:Reopen(player, state, now)
	if not offer then
		return false, reason
	end
	state.respecUsed = true
	self:_pushPlayerState(player)
	self:_fireClient("UpgradeOffer", player, self:_offerPayload(player, offer, now))
	self:_log("CardRespec", { RunId = self._runId, Room = self._roomIndex }, now)
	return true
end

-- The day's modifier pays a bonus to the first run of the day that clears a room, once a day per
-- player: Limits.ModifierDay remembers the day for good (the run ledger only keeps recent keys),
-- and the ledger key makes two servers paying the same day pay once. Returns the coins paid.
function Flow.methods:_payDailyModifier(player)
	local persistence = self._persistence
	if not persistence or not persistence.Update then
		return 0
	end
	local day = MetaConfig.DayOf(self._wallClock())
	local fresh = false
	persistence:Update(player, function(profile)
		if profile.Limits.ModifierDay ~= day then
			profile.Limits.ModifierDay = day
			fresh = true
		end
	end)
	if not fresh then
		return 0
	end
	local bonus = DailyModifierConfig.Bonus
	return (Payout.Grant(persistence, player, "dailymod:" .. day, bonus.Coins, bonus.Xp))
end

-- Pays `coins` and `xp` to a player's profile under one ledger key (see Payout.Grant).
function Flow.methods:_payout(player, runKey, coins, xp)
	local granted, xpGranted, levelCoins, levelBefore, levelAfter = Payout.Grant(self._persistence, player, runKey, coins, xp)
	return granted, xpGranted, levelCoins, levelBefore, levelAfter
end

function Flow.methods:_finish(outcome, now)
	self._projectiles:Clear()
	self._doors = nil
	self._challenge = nil
	if self._orbDrops then
		self._orbDrops:Clear()
	end
	-- A perk waiting at the end of a run can change nothing; drop it rather than let it open
	-- another offer that would outlive the run.
	if self._surges then
		self._surges:ClearAll()
	end
	if self._coins then
		-- Nothing a player earned is left behind: coins still on the floor go to the nearest
		-- participant, downed or not, so a lost run still banks every drop.
		self:_creditCoins(self._coins:Sweep(self:_coinCollectors(true)))
	end
	self._rooms:Unload()
	self._upgrades:ClearAll()

	local context = {
		runId = self._runId,
		outcome = outcome,
		duration = now - self._runStartedAt,
		roomCount = #self._plan,
		eliteCleared = self._eliteCleared,
		heat = self._pactEffects.Heat,
		rewardMultiplier = self._pactEffects.RewardMultiplier,
		banked = self._banked == true,
	}
	if self._banked then
		-- Banked at an extract point: the deeper the zone, the bigger the bonus.
		local here = self._plan[self._roomIndex]
		context.extractionBonus = here and RewardConfig.BankBonusByZone[here.Zone] or nil
	end

	local runKey = string.format("%s-%d", self._runKeyPrefix, self._runId)
	for _, player in self._participants do
		local state = self._states[player]
		if state then
			local summary = RunSummary.ForPlayer(state, context)

			-- Two guards in series: the in-memory ledger stops a repeated completion event on
			-- this server, and the profile ledger stops a repeat across reconnects or servers.
			local reward, repeated = self._rewards:Grant(self._runId, player, summary.Reward)
			summary.Reward = reward
			if repeated then
				summary.XpEarned = 0
			end
			if self._persistence then
				local levelBefore, levelAfter
				summary.Reward, summary.XpEarned, summary.LevelReward, levelBefore, levelAfter =
					self:_payout(player, runKey, summary.Reward, summary.XpEarned)
				summary.LevelBefore = levelBefore
				summary.Progress = ProgressionConfig.Describe(Payout.XpOf(self._persistence, player))
				summary.Progress.LeveledUp = levelAfter > levelBefore
				if self._modifier and summary.RoomsCleared >= 1 then
					summary.DailyBonus = self:_payDailyModifier(player)
				end
				-- The first descent happens once, however it ends.
				if self._runOptions and self._runOptions.firstDescent and self._persistence.Update then
					self._persistence:Update(player, function(profile)
						profile.Flags.FirstDescentDone = true
					end)
				end
				-- Every finished run counts, paid or not: stats advance and onboarding retires.
				self._persistence:RecordRunEnd(player, summary)
				-- Quests, badges and leaderboards hear about every finished run.
				if self._onRunEnd then
					self._onRunEnd(player, summary)
				end
				-- Written now, not left for autosave or leave: a payout is the one change whose
				-- loss really hurts, and this single write carries it with the run's stats.
				self._persistence:SaveInBackground(player, now)
			end
			summary.RunKey = runKey
			self:_funnel(player, "FirstRunEnd")

			self:_fireClient("RunResults", player, summary)
		end
	end

	self:_log("RunEnd", {
		RunId = self._runId,
		Outcome = outcome,
		Rooms = self._roomIndex,
		Duration = math.floor(context.duration),
	}, now)
	self:_setState(States.Results, now)
end

function Flow.methods:_cleanup(now)
	self._projectiles:Clear()
	self._rooms:Unload()
	self._enemies:Clear()
	self._upgrades:ClearAll()

	for _, player in self._participants do
		local state = self._states[player]
		if state then
			state:ResetRun()
			if self._world then
				self._world.Teleport(player, RunConfig.LobbyReturnPosition)
				if self._world.SetWalkSpeed then
					self._world.SetWalkSpeed(player, RunConfig.BaseWalkSpeed)
				end
			end
			self:_pushPlayerState(player)
		end
	end

	table.clear(self._participants)
	table.clear(self._pendingJoins)
	self._roomIndex = 0
	self._modifier = nil
	self._partySize = 1
	self:_applyPact({})
	self:_setState(States.Lobby, now)
end

function Flow.Install(class)
	for name, method in Flow.methods do
		class[name] = method
	end
end

return Flow
