-- Per-archetype movement. Pure position maths on the travel plane: no pathfinding, no physics,
-- so behaviour stays readable and every decision is reproducible in tests.
local EnemyBehaviour = {}

local function flatten(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function towards(from, to, maxStep)
	local offset = flatten(to - from)
	local distance = offset.Magnitude
	if distance < 1e-4 then
		return from, 0
	end
	if distance <= maxStep then
		return Vector3.new(to.X, from.Y, to.Z), distance
	end
	return from + offset.Unit * maxStep, distance
end

-- Wanders inside a leash around its spawn point, picking a new anchor on an interval.
function EnemyBehaviour.Sentry(enemy, archetype, dt, _target, now, random)
	if now >= (enemy.wanderUntil or 0) then
		local angle = random() * math.pi * 2
		local radius = random() * archetype.WanderRadius
		enemy.wanderTarget = enemy.anchor + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		enemy.wanderUntil = now + archetype.WanderInterval
	end
	enemy.position = towards(enemy.position, enemy.wanderTarget or enemy.anchor, archetype.MoveSpeed * dt)
	return enemy.position
end

-- Closes to its standoff distance and holds there.
function EnemyBehaviour.Chaser(enemy, archetype, dt, target, _now, _random)
	if not target then
		return enemy.position
	end
	enemy.facing = flatten(target.position - enemy.position)
	local _, distance = towards(enemy.position, target.position, 0)
	if distance <= archetype.StandoffDistance then
		return enemy.position
	end
	enemy.position = towards(enemy.position, target.position, archetype.MoveSpeed * dt)
	return enemy.position
end

-- Approaches slowly, stops to telegraph, then commits to a short fast charge.
function EnemyBehaviour.Lunger(enemy, archetype, dt, target, now, _random)
	if not target then
		return enemy.position
	end
	enemy.facing = flatten(target.position - enemy.position)

	local lunge = archetype.Lunge
	enemy.lungeAt = enemy.lungeAt or (now + lunge.Interval)

	if enemy.phase == "Lunging" then
		if now >= enemy.phaseUntil then
			enemy.phase = "Approach"
			enemy.lungeAt = now + lunge.Interval
		else
			local speed = archetype.MoveSpeed * lunge.SpeedMultiplier
			enemy.position = towards(enemy.position, enemy.lungeTarget, speed * dt)
			return enemy.position
		end
	elseif enemy.phase == "Telegraph" then
		if now >= enemy.phaseUntil then
			enemy.phase = "Lunging"
			enemy.phaseUntil = now + lunge.Duration
			enemy.lungeTarget = target.position
		end
		return enemy.position -- rooted while telegraphing, which is what makes it readable
	elseif now >= enemy.lungeAt then
		enemy.phase = "Telegraph"
		enemy.phaseUntil = now + lunge.TelegraphTime
		return enemy.position
	end

	local _, distance = towards(enemy.position, target.position, 0)
	if distance > archetype.StandoffDistance then
		enemy.position = towards(enemy.position, target.position, archetype.MoveSpeed * dt)
	end
	return enemy.position
end

function EnemyBehaviour.Get(name)
	return EnemyBehaviour[name]
end

return EnemyBehaviour
