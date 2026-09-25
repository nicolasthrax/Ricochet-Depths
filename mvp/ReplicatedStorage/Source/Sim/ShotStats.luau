--!strict
-- Folds a modifier loadout into the numbers one shot uses. Pure: the server recomputes it when a
-- loadout changes, and the client uses the same function for the aim preview and shot visuals.
--
-- Stacking rules:
--   * ShotSize, FireRate and ExtraBounce stack: every copy and every fused card applies.
--   * The on-hit effects (split, burn, chill, arc, pierce) do not stack: one card of each kind
--     applies, and a fused variant always beats its base card. A second copy of such a card does
--     nothing until it is fused. That is what makes fusing worth it.
--   * Fire cooldown never drops below GameConfig.Shot.minCooldownSeconds.

local Types = require(script.Parent.Parent.Types)
local GameConfig = require(script.Parent.Parent.GameConfig)
local ModifierDefinitions = require(script.Parent.Parent.ModifierDefinitions)

local Shot = GameConfig.Shot

export type LoadoutEntry = {
	id: Types.ModifierId,
	stacks: number, -- whole number, at least 1
}

export type ShotStats = {
	damage: number, -- per direct hit before per-bounce growth
	radius: number,
	speed: number,
	bounces: number,
	lifetimeSeconds: number,
	cooldownSeconds: number,
	damagePerBounce: number, -- fraction added per bounce already taken
	tint: Types.ShotTint,
	split: Types.SplitOnBounceEffect?,
	burn: Types.BurnOnHitEffect?,
	chill: Types.ChillOnHitEffect?,
	arc: Types.ArcOnHitEffect?,
	pierce: Types.PierceEffect?,
}

local ShotStats = {}

function ShotStats.compute(loadout: { LoadoutEntry }): ShotStats
	local radiusScale, flatDamage, cooldownScale = 1, 0, 1
	local extraBounces, damagePerBounce = 0, 0
	local split: Types.SplitOnBounceEffect? = nil
	local burn: Types.BurnOnHitEffect? = nil
	local chill: Types.ChillOnHitEffect? = nil
	local arc: Types.ArcOnHitEffect? = nil
	local pierce: Types.PierceEffect? = nil

	for _, entry in loadout do
		local stacks = entry.stacks
		assert(stacks >= 1 and stacks % 1 == 0, `{entry.id}: stacks must be a whole number >= 1`)
		local definition = ModifierDefinitions.get(entry.id)
		-- A fused card replaces whatever base card of its kind was chosen before it.
		local overrides = definition.kind == "Fused"
		local effect = definition.effect

		if effect.kind == "ShotSize" then
			radiusScale *= effect.radiusScale ^ stacks
			flatDamage += effect.flatDamage * stacks
		elseif effect.kind == "FireRate" then
			cooldownScale *= effect.cooldownScale ^ stacks
		elseif effect.kind == "ExtraBounce" then
			extraBounces += effect.extraBounces * stacks
			damagePerBounce += effect.damagePerBounce * stacks
		elseif effect.kind == "SplitOnBounce" then
			if split == nil or overrides then
				split = effect
			end
		elseif effect.kind == "BurnOnHit" then
			if burn == nil or overrides then
				burn = effect
			end
		elseif effect.kind == "ChillOnHit" then
			if chill == nil or overrides then
				chill = effect
			end
		elseif effect.kind == "ArcOnHit" then
			if arc == nil or overrides then
				arc = effect
			end
		elseif effect.kind == "Pierce" then
			if pierce == nil or overrides then
				pierce = effect
			end
		end
	end

	local pierceScale = if pierce then pierce.damageScale else 1
	return {
		damage = (Shot.baseDamage + flatDamage) * pierceScale,
		radius = Shot.radius * radiusScale,
		speed = Shot.baseSpeed,
		bounces = Shot.baseBounces + extraBounces,
		lifetimeSeconds = Shot.lifetimeSeconds,
		cooldownSeconds = math.max(Shot.cooldownSeconds * cooldownScale, Shot.minCooldownSeconds),
		damagePerBounce = damagePerBounce,
		tint = if burn then burn.shotTint else "Default",
		split = split,
		burn = burn,
		chill = chill,
		arc = arc,
		pierce = pierce,
	}
end

-- Damage of a direct hit after `bouncesTaken` bounces (Resonance grows it per bounce).
function ShotStats.hitDamage(stats: ShotStats, bouncesTaken: number): number
	return stats.damage * (1 + stats.damagePerBounce * bouncesTaken)
end

table.freeze(ShotStats)
return ShotStats
