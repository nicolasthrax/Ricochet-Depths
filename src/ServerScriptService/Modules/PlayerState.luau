-- Authoritative per-player run state. The client is sent read-only snapshots of this and
-- never writes to it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	-- Permanent salvage-shop bonuses: { stats = { [stat] = delta }, trail = def|nil }. They
	-- outlive ResetRun and are refreshed from the profile when a run starts.
	self.meta = { stats = {}, trail = nil }
	self:ResetRun()
	return self
end

function PlayerState:SetMeta(meta)
	self.meta = {
		stats = type(meta) == "table" and type(meta.stats) == "table" and meta.stats or {},
		trail = type(meta) == "table" and meta.trail or nil,
	}
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
	self:RecomputeStats()
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
		self.health = 0
		self.alive = false
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

function PlayerState:Revive(now)
	self.alive = true
	self.health = self.maxHealth
	self:GrantInvulnerability(now)
end

-- Read-only view for the HUD. Never send the state table itself.
function PlayerState:ToSnapshot()
	local upgrades = {}
	for cardId, stacks in self.upgrades do
		local card = UpgradeConfig.Get(cardId)
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
	}
end

return PlayerState
