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

-- Stands still, turns to the target, telegraphs, then asks the service to fire an orb at it.
function EnemyBehaviour.Turret(enemy, archetype, _dt, target, now, _random)
	local fire = archetype.Fire
	enemy.fireAt = enemy.fireAt or (now + fire.Interval)
	if target then
		enemy.facing = flatten(target.position - enemy.position)
	end
	if now >= enemy.fireAt then
		enemy.fireAt = now + fire.Interval
		enemy.phase = "Approach"
		if target and enemy.facing.Magnitude > 1e-4 then
			enemy.fireRequests = { { direction = enemy.facing.Unit, speed = fire.Speed, damage = fire.Damage } }
		end
	elseif now >= enemy.fireAt - fire.TelegraphTime then
		enemy.phase = "Telegraph"
	end
	return enemy.position
end

-- Chases; every Interval it telegraphs, blinks out (untouchable), and reappears near a player.
function EnemyBehaviour.Phaser(enemy, archetype, dt, target, now, random)
	local blink = archetype.Blink
	enemy.blinkAt = enemy.blinkAt or (now + blink.Interval)
	if enemy.phase == "Blinking" then
		if now >= enemy.phaseUntil then
			enemy.phase = "Approach"
			enemy.blinkAt = now + blink.Interval
			local centre = target and target.position or enemy.anchor
			local angle = random() * math.pi * 2
			local radius = blink.MinRadius + random() * (blink.MaxRadius - blink.MinRadius)
			enemy.position = Vector3.new(centre.X + math.cos(angle) * radius, enemy.position.Y, centre.Z + math.sin(angle) * radius)
		end
		return enemy.position
	elseif enemy.phase == "Telegraph" then
		if now >= enemy.phaseUntil then
			enemy.phase = "Blinking"
			enemy.phaseUntil = now + blink.Duration
		end
		return enemy.position
	elseif now >= enemy.blinkAt then
		enemy.phase = "Telegraph"
		enemy.phaseUntil = now + blink.TelegraphTime
		return enemy.position
	end
	return EnemyBehaviour.Chaser(enemy, archetype, dt, target, now, random)
end

-- The boss: phase from remaining health (see EnemyConfig.WardenPrime). Movement is a slow
-- chase; shield, orb rings and summons change by phase. Orbs and summons are requested from the
-- service, which owns pools and the active cap.
-- Which of the boss's phases its remaining health puts it in: the last whose Below it is under.
function EnemyBehaviour.BossPhase(enemy)
	local phases = enemy.archetype.Phases
	local fraction = enemy.health / enemy.maxHealth
	for candidate = #phases, 1, -1 do
		if fraction < phases[candidate].Below then
			return candidate
		end
	end
	return 1
end

function EnemyBehaviour.Boss(enemy, archetype, dt, target, now, _random)
	local index = EnemyBehaviour.BossPhase(enemy)
	local phase = archetype.Phases[index]
	if enemy.bossPhase ~= index then
		enemy.bossPhase = index
		enemy.ringAt = phase.RingInterval and now + phase.RingInterval or nil
		enemy.summonAt = phase.SummonInterval and now + phase.SummonInterval or nil
		enemy.shieldOff = phase.Shield == "None"
	end

	if phase.Shield == "Spin" then
		enemy.spin = (enemy.spin or 0) + math.rad(phase.SpinSpeed) * dt
		enemy.facing = Vector3.new(math.sin(enemy.spin), 0, math.cos(enemy.spin))
	elseif target then
		enemy.facing = flatten(target.position - enemy.position)
	end

	if enemy.ringAt and now >= enemy.ringAt then
		enemy.ringAt = now + phase.RingInterval
		enemy.ringTwist = (enemy.ringTwist or 0) + math.rad(phase.RingTwist or 0)
		local requests = {}
		for step = 1, phase.RingCount do
			local angle = enemy.ringTwist + (step - 1) * 2 * math.pi / phase.RingCount
			table.insert(requests, {
				direction = Vector3.new(math.cos(angle), 0, math.sin(angle)),
				speed = archetype.Orb.Speed,
				damage = archetype.Orb.Damage,
			})
		end
		enemy.fireRequests = requests
	end
	if enemy.summonAt and now >= enemy.summonAt then
		enemy.summonAt = now + phase.SummonInterval
		enemy.summonRequest = { archetype = phase.Summon, count = phase.SummonCount, max = phase.SummonMax }
	end

	if target then
		local _, distance = towards(enemy.position, target.position, 0)
		if distance > archetype.StandoffDistance then
			local speed = archetype.MoveSpeed * (phase.MoveSpeedMultiplier or 1)
			enemy.position = towards(enemy.position, target.position, speed * dt)
		end
	end
	return enemy.position
end

function EnemyBehaviour.Get(name)
	return EnemyBehaviour[name]
end

return EnemyBehaviour
