-- Shot effects, and the one path every point of enemy damage after the first contact goes
-- through: chain arcs, kill explosions and burn ticks. Crits, chill and Hunter bonuses are
-- worked out here, and every kill is counted, paid and announced the same way whatever caused
-- it. Installed onto MatchService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local EnemyService = require(script.Parent.EnemyService)

local Effects = { methods = {} }

local UP = Vector3.new(0, 1, 0)
local NO_STATS = {}

-- What the target adds: Hunter against elites, champions and bosses, and the chill bonus
-- against a slowed enemy.
function Effects.TargetMultiplier(stats, enemy, now)
	local multiplier = 1
	local archetype = enemy.archetype
	if (stats.HunterBonus or 0) > 0 and (enemy.champion or archetype.IsElite or archetype.IsBoss) then
		multiplier *= 1 + stats.HunterBonus
	end
	if (stats.ChillDamageBonus or 0) > 0 and EnemyService.IsChilled(enemy, now) then
		multiplier *= 1 + stats.ChillDamageBonus
	end
	return multiplier
end

-- A direct hit's damage and whether it crit. A shot with enough contacts for Trick Shot always
-- crits; otherwise CritChance is rolled on `random` (only when there is a chance to roll).
function Effects.ShotDamage(stats, base, contacts, enemy, now, random)
	local crit = false
	local trick = stats.TrickShotContacts or 0
	if trick > 0 and contacts >= trick then
		crit = true
	elseif (stats.CritChance or 0) > 0 and random:NextNumber() < stats.CritChance then
		crit = true
	end
	local damage = base * Effects.TargetMultiplier(stats, enemy, now)
	if crit then
		damage *= stats.CritMultiplier or 2
	end
	return damage, crit
end

-- The shooter's current stats and run state. A shooter who has left still resolves, with no
-- effects, so a shot in flight when they go can still land.
function Effects.methods:_statsOf(shooter)
	local state = shooter and self._states[shooter]
	return state and state.stats or NO_STATS, state
end

function Effects.methods:_queueEffect(position, normal, kind, contacts, damage)
	if self._effects then
		self._effects:Queue(position, normal or UP, kind, contacts or 0, damage or 0)
	end
end

-- Everything that follows damage landing: burning and chill on a survivor (from shots and arcs
-- only), the kill if it died, and chain arcs from a direct hit. `damage` is what landed.
function Effects.methods:_afterHit(hit, stats, shooter, contacts, damage, source, now)
	local enemy = hit.enemy
	if not hit.killed and (source == "Shot" or source == "Arc") then
		self._enemies:ApplyStatus(enemy, stats.BurnDamage or 0, stats.ChillSeconds or 0, shooter, now)
	end
	if hit.killed then
		self:_onEnemyKilled(enemy, shooter, contacts, source, now)
	end
	-- Arcs only ever start from a direct hit, so an arc can never arc again.
	local arcs = math.floor(stats.ChainArcs or 0)
	if source == "Shot" and arcs >= 1 then
		local arcDamage = math.max(damage * (stats.ArcDamageFraction or 0.5), 1)
		for _, target in self._enemies:FindNear(enemy.position, CombatConfig.ArcRange, enemy, arcs) do
			self:_secondaryDamage(target, arcDamage, shooter, contacts, "Arc", now)
		end
	end
end

-- Damage that did not come from a projectile contact: "Arc", "Blast" or "Burn". Ignores
-- shields, which is what makes elemental builds the answer to a wall of Bulwarks.
function Effects.methods:_secondaryDamage(enemy, amount, shooter, contacts, source, now)
	if enemy.dead then
		return nil
	end
	local stats = self:_statsOf(shooter)
	local hit = self._enemies:ApplyHit(enemy.part, amount * Effects.TargetMultiplier(stats, enemy, now), nil, shooter)
	if not hit then
		return nil
	end
	self:_queueEffect(enemy.position, UP, hit.killed and "Kill" or source, contacts, hit.damage)
	if source == "Blast" and not hit.killed and (stats.ExplosionIgnites or 0) > 0 then
		self._enemies:ApplyStatus(enemy, math.max(stats.BurnDamage or 0, 1), 0, shooter, now)
	end
	self:_afterHit(hit, stats, shooter, contacts, hit.damage, source, now)
	return hit
end

-- A kill from any source: the shooter's tallies and Siphon, coins on the floor, the callout
-- event, and Volatile's explosion.
function Effects.methods:_onEnemyKilled(enemy, shooter, contacts, source, now)
	local stats, state = self:_statsOf(shooter)
	if state then
		state:RecordKill(enemy)
		if source == "Shot" then
			state.bestChain = math.max(state.bestChain, contacts)
		end
		if (stats.HealOnKill or 0) > 0 and state.alive and state:Heal(stats.HealOnKill) > 0 then
			self:_pushPlayerState(shooter)
		end
	end
	if self._coins then
		self._coins:Drop(enemy.position, enemy.coins or enemy.archetype.Coins or 0)
	end

	-- Who scored it and off how many contacts, for kill-streak and ricochet callouts.
	-- A real Player is userdata, not a table, so read the id defensively rather than by type.
	local hasId, shooterId = pcall(function()
		return shooter.UserId
	end)
	shooterId = hasId and shooterId or nil
	local chain = source == "Shot" and contacts or 0
	self:_fireAll("EnemyDefeated", enemy.position, enemy.archetypeId, shooterId, chain,
		enemy.champion and enemy.champion.Id or nil)
	self:_log("EnemyDefeated", {
		Archetype = enemy.archetypeId,
		Contacts = contacts,
		Source = source,
		Champion = enemy.champion and enemy.champion.Id or nil,
		RunId = self._runId,
	}, now)

	if (stats.ExplosionDamage or 0) > 0 then
		self:_queueEffect(enemy.position, UP, "Blast", contacts, 0)
		for _, target in self._enemies:FindNear(enemy.position, CombatConfig.ExplosionRadius, enemy) do
			self:_secondaryDamage(target, stats.ExplosionDamage, shooter, contacts, "Blast", now)
		end
	end
end

function Effects.Install(class)
	for name, method in Effects.methods do
		class[name] = method
	end
end

return Effects
