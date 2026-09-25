-- Authoritative per-player run state. The client is sent read-only snapshots of this and
-- never writes to it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArsenalConfig = require(ReplicatedStorage:WaitForChild("ArsenalConfig"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))

local PlayerState = {}
PlayerState.__index = PlayerState

function PlayerState.new(player)
	local self = setmetatable({}, PlayerState)
	self.player = player
	self.userId = player and player.UserId or 0
	self.name = player and player.Name or "Unknown"
	self.upgrades = {}
	self.upgradeOrder = {}
	-- Permanent bonuses: { stats = { [stat] = delta }, trail = def|nil, rig = id|nil } from the
	-- Armory, passes, the chosen rig and the run's Depth Pact. They outlive ResetRun and are
	-- refreshed from the profile when a run starts.
	self.meta = { stats = {}, trail = nil, rig = nil }
	self:ResetRun()
	return self
end

function PlayerState:SetMeta(meta)
	self.meta = {
		stats = type(meta) == "table" and type(meta.stats) == "table" and meta.stats or {},
		trail = type(meta) == "table" and meta.trail or nil,
		rig = type(meta) == "table" and type(meta.rig) == "string" and meta.rig or nil,
	}
	-- The player's account level, which gates cards with an UnlockLevel. nil: no gating.
	self.level = type(meta) == "table" and type(meta.level) == "number" and meta.level or nil
end

-- The stats a run starts from: the base values plus shop bonuses. Cards fold over these.
function PlayerState:_startingStats()
	local stats = table.clone(UpgradeConfig.BaseStats)
	for stat, delta in self.meta.stats do
		if stats[stat] ~= nil and type(delta) == "number" then
			stats[stat] += delta
		end
	end
	return stats
end

function PlayerState:ResetRun()
	table.clear(self.upgrades)
	table.clear(self.upgradeOrder)
	self.stats = self:_startingStats()
	self.maxHealth = RunConfig.BaseHealth + self.stats.MaxHealthBonus
	self.health = self.maxHealth
	self.alive = true
	self.kills = 0
	self.shotsFired = 0
	self.projectilesFired = 0
	self.bestChain = 0
	self.damageTaken = 0
	self.roomsCleared = 0
	-- Coins picked up this run; paid out at the end (or when the player leaves mid-run).
	self.coins = 0
	self.lastDamagedAt = -math.huge
	-- The room this player entered the run at. 1 for everyone who starts together; a late
	-- joiner's is set when they are admitted at a room boundary.
	self.joinedAtRoom = 1
	self.lastFireAt = -math.huge
	self.invulnerableUntil = 0
	-- Tallies for the results screen, the Codex and achievements.
	self.championKills = 0
	self.bossKills = 0
	self.crits = 0
	self.revivesGiven = 0
	self.killsByArchetype = {}
	-- Second Wind lives spent, and how far a teammate has got reviving this player.
	self.extraLivesUsed = 0
	self.reviveProgress = 0
	-- The arsenal: orbs in hand, the combo meter and the Surge meter, and the last dash.
	self.orbsHeld = self:OrbCapacity()
	self.combo = 0
	self.comboExpiresAt = 0
	self.bestCombo = 0
	self.comboXp = 0
	self.surge = 0
	self.surgeLevel = 1
	self.lastDashAt = -math.huge
	self.trickShots = 0
	-- Card-round allowances: rerolls taken free this run, and whether the respec is spent.
	self.freeRerollsUsed = 0
	self.respecUsed = false
	-- A Revive token spent this run (once a run).
	self.tokenReviveUsed = false
end

function PlayerState:OrbCapacity()
	return math.max(math.floor(self.stats.OrbCount or 1), 1)
end

-- Every orb back in hand, e.g. at the start of a room.
function PlayerState:RefillOrbs()
	self.orbsHeld = self:OrbCapacity()
end

function PlayerState:TakeOrb()
	if self.orbsHeld < 1 then
		return false
	end
	self.orbsHeld -= 1
	return true
end

function PlayerState:ReturnOrb()
	self.orbsHeld = math.min(self.orbsHeld + 1, self:OrbCapacity())
end

-- A kill joins the combo. Returns the tier index before and after, so a tier-up can be shown.
function PlayerState:AddCombo(amount, now)
	local _, before = ArsenalConfig.ComboTier(self.combo)
	if now >= self.comboExpiresAt then
		self.combo = 0
	end
	self.combo += amount
	self.comboExpiresAt = now + ArsenalConfig.Combo.Window
	self.bestCombo = math.max(self.bestCombo, self.combo)
	local _, after = ArsenalConfig.ComboTier(self.combo)
	return before, after
end

-- Taking a hit keeps only part of the combo. Returns true if it changed.
function PlayerState:DamageCombo()
	if self.combo <= 0 then
		return false
	end
	self.combo = math.floor(self.combo * ArsenalConfig.Combo.HitKeeps)
	return true
end

-- Runs the combo out once its window passes. Returns true if it just ended.
function PlayerState:ExpireCombo(now)
	if self.combo > 0 and now >= self.comboExpiresAt then
		self.combo = 0
		return true
	end
	return false
end

function PlayerState:ComboMultiplier()
	return (ArsenalConfig.ComboTier(self.combo)).Multiplier
end

-- Adds Surge points. Returns true once the meter is full.
function PlayerState:AddSurge(points)
	self.surge += points * (self.stats.SurgeGain or 1)
	return self.surge >= ArsenalConfig.SurgeNeeded(self.surgeLevel)
end

-- Spends a full meter for one Surge level. Returns false if it was not full.
function PlayerState:SpendSurge()
	local needed = ArsenalConfig.SurgeNeeded(self.surgeLevel)
	if self.surge < needed then
		return false
	end
	self.surge -= needed
	self.surgeLevel += 1
	return true
end

-- Folds every held card over the base stats. Add effects scale linearly with stacks,
-- Multiply effects compound, so two 0.8x cards give 0.64x.
function PlayerState:RecomputeStats()
	local stats = self:_startingStats()
	for cardId, stacks in self.upgrades do
		local card = UpgradeConfig.Get(cardId)
		if card then
			for _, effect in card.Effects do
				local current = stats[effect.Stat]
				if current ~= nil then
					if effect.Op == "Add" then
						stats[effect.Stat] = current + effect.Value * stacks
					elseif effect.Op == "Multiply" then
						stats[effect.Stat] = current * effect.Value ^ stacks
					end
				end
			end
		end
	end
	self.stats = stats

	local previousMax = self.maxHealth
	self.maxHealth = RunConfig.BaseHealth + stats.MaxHealthBonus
	-- Extra maximum health arrives already filled, so the card is felt immediately.
	if self.maxHealth > previousMax then
		self.health = math.min(self.maxHealth, self.health + (self.maxHealth - previousMax))
	end
	self.health = math.min(self.health, self.maxHealth)
	return stats
end

function PlayerState:GetStacks(cardId)
	return self.upgrades[cardId] or 0
end

-- Returns false when the card is unknown or already at its stack cap.
function PlayerState:AddUpgrade(card)
	if type(card) ~= "table" or not card.Id then
		return false, "invalid card"
	end
	local stacks = self:GetStacks(card.Id)
	if stacks >= card.MaxStacks then
		return false, "stack cap reached"
	end

	self.upgrades[card.Id] = stacks + 1
	table.insert(self.upgradeOrder, card.Id)
	local capacity = self:OrbCapacity()
	self:RecomputeStats()
	-- A new orb arrives in hand.
	self.orbsHeld = math.min(self.orbsHeld + math.max(self:OrbCapacity() - capacity, 0), self:OrbCapacity())
	return true
end

-- Takes one stack of a card back off (a respec). Stats are refolded from the stacks, so nothing
-- the card did lingers. Returns false if the card is not held.
function PlayerState:RemoveUpgrade(cardId)
	local stacks = self:GetStacks(cardId)
	if stacks <= 0 then
		return false
	end
	self.upgrades[cardId] = stacks > 1 and stacks - 1 or nil
	for index = #self.upgradeOrder, 1, -1 do
		if self.upgradeOrder[index] == cardId then
			table.remove(self.upgradeOrder, index)
			break
		end
	end
	self:RecomputeStats()
	self.orbsHeld = math.min(self.orbsHeld, self:OrbCapacity())
	return true
end

function PlayerState:IsInvulnerable(now)
	return now < self.invulnerableUntil
end

function PlayerState:GrantInvulnerability(now, duration)
	self.invulnerableUntil = now + (duration or RunConfig.SpawnInvulnerability)
end

-- Returns applied damage and whether this blow was fatal.
function PlayerState:ApplyDamage(amount, now)
	if not self.alive or self:IsInvulnerable(now) or amount <= 0 then
		return 0, false
	end
	local applied = math.min(amount, self.health)
	self.health -= applied
	self.damageTaken += applied
	self.lastDamagedAt = now
	if self.health <= 0 then
		-- Second Wind: a spare life turns the fatal blow into a narrow escape.
		if self.extraLivesUsed < math.floor(self.stats.ExtraLives or 0) then
			self.extraLivesUsed += 1
			self.health = math.max(math.floor(self.maxHealth * CombatConfig.ExtraLifeHealth), 1)
			self:GrantInvulnerability(now)
			return applied, false, true
		end
		self.health = 0
		self.alive = false
		self.reviveProgress = 0
		return applied, true
	end
	return applied, false
end

function PlayerState:Heal(amount)
	if not self.alive or amount <= 0 then
		return 0
	end
	local healed = math.min(amount, self.maxHealth - self.health)
	self.health += healed
	return healed
end

-- Back on their feet: at full health by default (a new room), or at `fraction` of it when a
-- teammate picked them up mid-fight.
function PlayerState:Revive(now, fraction, invulnerability)
	self.alive = true
	self.health = math.max(math.floor(self.maxHealth * (fraction or 1)), 1)
	self.reviveProgress = 0
	self:GrantInvulnerability(now, invulnerability)
end

-- A kill this player scored, for the run's tallies.
function PlayerState:RecordKill(enemy)
	self.kills += 1
	local archetypeId = enemy and enemy.archetypeId
	if archetypeId then
		self.killsByArchetype[archetypeId] = (self.killsByArchetype[archetypeId] or 0) + 1
	end
	-- Pressure hunters wear a champion's affix but earn none of a champion's credit.
	if enemy and enemy.champion and not enemy.hunter then
		self.championKills += 1
	end
	if enemy and enemy.archetype and enemy.archetype.IsBoss then
		self.bossKills += 1
	end
end

-- Read-only view for the HUD. Never send the state table itself.
function PlayerState:ToSnapshot()
	local upgrades = {}
	for cardId, stacks in self.upgrades do
		local card = UpgradeConfig.Get(cardId)
		if UpgradeConfig.IsMinor(card) then
			continue -- Surge perks show as the Surge level, not as a list
		end
		table.insert(upgrades, {
			Id = cardId,
			Title = card and card.Title or cardId,
			Category = card and card.Category or "Projectile",
			Stacks = stacks,
		})
	end
	table.sort(upgrades, function(a, b)
		return a.Id < b.Id
	end)

	return {
		Health = self.health,
		MaxHealth = self.maxHealth,
		Alive = self.alive,
		Kills = self.kills,
		RoomsCleared = self.roomsCleared,
		Coins = self.coins,
		BestChain = self.bestChain,
		-- Sent so the client can predict its own cooldown and give instant feedback on a
		-- shot that would be refused, without an extra remote for rejections.
		FireCooldown = ProjectileConfig.FireCooldown * self.stats.FireCooldownMultiplier,
		Upgrades = upgrades,
		Rig = self.meta.rig,
		ExtraLivesLeft = math.max(math.floor(self.stats.ExtraLives or 0) - self.extraLivesUsed, 0),
		ReviveProgress = self.reviveProgress,
		Orbs = self.orbsHeld,
		OrbsMax = self:OrbCapacity(),
		Combo = self.combo,
		ComboWindow = ArsenalConfig.Combo.Window,
		Surge = self.surge,
		SurgeNeeded = ArsenalConfig.SurgeNeeded(self.surgeLevel),
		SurgeLevel = self.surgeLevel,
		DashCooldown = ArsenalConfig.Dash.Cooldown * (self.stats.DashCooldownMultiplier or 1),
	}
end

return PlayerState
