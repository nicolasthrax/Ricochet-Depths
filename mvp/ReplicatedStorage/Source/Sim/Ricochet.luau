--!strict
-- Deterministic 2D ricochet: circles swept through the lane, bouncing off the side and back
-- walls and off target boxes. The server simulation and the client aim preview both use this
-- module, so the path a player previews is the path the server simulates.
--
-- Plain numbers only (Luau doubles), no Vector2 and no Roblox physics: identical inputs give
-- identical paths on every machine. Game rules stay outside: when a shot touches a target, a
-- responder decides whether it bounces, pierces or stops. This module only moves circles.
--
-- A shot against a target is a ray against the target's box grown by the shot radius, with
-- rounded corners (the Minkowski sum), so a corner hit bounces off the true curved normal.

local GameConfig = require(script.Parent.Parent.GameConfig)

local Lane = GameConfig.Lane
local Tuning = GameConfig.Ricochet

local EPSILON = 1e-9

---------------------------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------------------------

-- A target's collision box in lane space (LaneGeometry.targetBox plus the target's id).
export type Obstacle = {
	id: number,
	minX: number,
	minY: number,
	maxX: number,
	maxY: number,
}

export type SurfaceKind = "Wall" | "Target" | "Exit"

export type EndReason =
	"Exit" -- left the lane past the rail
	| "Spent" -- touched something with no bounces left
	| "Slow" -- dropped below Ricochet.minSpeed
	| "Expired" -- outlived its lifetime
	| "Stopped" -- a responder stopped it on a target

export type Shot = {
	x: number,
	y: number,
	dirX: number, -- unit direction
	dirY: number,
	speed: number, -- studs per second
	radius: number,
	bouncesLeft: number,
	bouncesTaken: number,
	age: number, -- seconds
	lifetime: number,
	alive: boolean,
	endReason: EndReason?,
	-- The target this shot is piercing. It is ignored until the shot's next contact, so a
	-- pierced target is never hit twice on the way through.
	piercingId: number?,
}

export type Contact = {
	kind: SurfaceKind,
	targetId: number?,
	x: number, -- shot centre at the moment of contact
	y: number,
	normalX: number, -- surface normal, pointing back at the shot
	normalY: number,
	time: number, -- seconds into the step
	bouncesTaken: number, -- before this contact; per-bounce damage reads this
	-- Filled in once the contact is resolved:
	reflected: boolean, -- the shot bounced here (split-on-bounce triggers on this)
	outDirX: number, -- direction and speed leaving the contact
	outDirY: number,
	outSpeed: number,
}

export type ContactResponse = "Reflect" | "Pierce" | "Stop"

-- Decides what a target contact does. Walls always reflect and the rail edge always exits.
export type Responder = (contact: Contact) -> ContactResponse

export type PathPoint = {
	x: number,
	y: number,
	kind: SurfaceKind?, -- nil for the start and for the end of the traced distance
}

type Hit = {
	kind: SurfaceKind,
	distance: number,
	normalX: number,
	normalY: number,
	targetId: number?,
}

local Ricochet = {}

---------------------------------------------------------------------------------------------
-- Ray casts (the shot's centre as a ray; surfaces grown by the radius)
---------------------------------------------------------------------------------------------

-- Entry distance of a ray into a rectangle, with the entry face's normal. Nil when the ray misses,
-- enters beyond maxDistance, or starts inside (a shot inside a surface passes out of it freely).
local function rayRect(
	x: number,
	y: number,
	dx: number,
	dy: number,
	maxDistance: number,
	minX: number,
	minY: number,
	maxX: number,
	maxY: number
): (number?, number, number)
	local enter, exit = -math.huge, math.huge
	local normalX, normalY = 0, 0

	if math.abs(dx) < EPSILON then
		if x <= minX or x >= maxX then
			return nil, 0, 0
		end
	else
		local near, far, face = (minX - x) / dx, (maxX - x) / dx, -1
		if near > far then
			near, far, face = far, near, 1
		end
		if near > enter then
			enter, normalX, normalY = near, face, 0
		end
		exit = math.min(exit, far)
	end

	if math.abs(dy) < EPSILON then
		if y <= minY or y >= maxY then
			return nil, 0, 0
		end
	else
		local near, far, face = (minY - y) / dy, (maxY - y) / dy, -1
		if near > far then
			near, far, face = far, near, 1
		end
		if near > enter then
			enter, normalX, normalY = near, 0, face
		end
		exit = math.min(exit, far)
	end

	if enter < 0 or enter > exit or enter > maxDistance then
		return nil, 0, 0
	end
	return enter, normalX, normalY
end

-- Entry distance of a ray into a circle, with the normal at the entry point.
local function rayCircle(
	x: number,
	y: number,
	dx: number,
	dy: number,
	maxDistance: number,
	cx: number,
	cy: number,
	radius: number
): (number?, number, number)
	local fx, fy = x - cx, y - cy
	local c = fx * fx + fy * fy - radius * radius
	if c <= 0 then
		return nil, 0, 0 -- starts inside
	end
	local b = fx * dx + fy * dy
	if b >= 0 then
		return nil, 0, 0 -- moving away
	end
	local discriminant = b * b - c
	if discriminant < 0 then
		return nil, 0, 0
	end
	local distance = -b - math.sqrt(discriminant)
	if distance < 0 or distance > maxDistance then
		return nil, 0, 0
	end
	return distance, (fx + dx * distance) / radius, (fy + dy * distance) / radius
end

-- Entry into a box grown by `radius` with rounded corners: the union of two crossed rectangles
-- and four corner circles. The union's entry point is the earliest entry into any piece.
local function rayRoundedBox(
	x: number,
	y: number,
	dx: number,
	dy: number,
	maxDistance: number,
	box: Obstacle,
	radius: number
): (number?, number, number)
	local best: number? = nil
	local bestX, bestY = 0, 0

	local function consider(distance: number?, nx: number, ny: number)
		if distance ~= nil and (best == nil or distance < best :: number) then
			best, bestX, bestY = distance, nx, ny
		end
	end

	consider(rayRect(x, y, dx, dy, maxDistance, box.minX - radius, box.minY, box.maxX + radius, box.maxY))
	consider(rayRect(x, y, dx, dy, maxDistance, box.minX, box.minY - radius, box.maxX, box.maxY + radius))
	consider(rayCircle(x, y, dx, dy, maxDistance, box.minX, box.minY, radius))
	consider(rayCircle(x, y, dx, dy, maxDistance, box.maxX, box.minY, radius))
	consider(rayCircle(x, y, dx, dy, maxDistance, box.minX, box.maxY, radius))
	consider(rayCircle(x, y, dx, dy, maxDistance, box.maxX, box.maxY, radius))
	return best, bestX, bestY
end

-- The first wall (or the open rail edge) the ray reaches within maxDistance.
local function castWalls(x: number, y: number, dx: number, dy: number, maxDistance: number, radius: number): Hit?
	local hit: Hit? = nil
	local function consider(kind: SurfaceKind, distance: number, nx: number, ny: number)
		distance = math.max(distance, 0)
		if distance <= maxDistance and (hit == nil or distance < (hit :: Hit).distance) then
			hit = { kind = kind, distance = distance, normalX = nx, normalY = ny }
		end
	end

	if dx < -EPSILON then
		consider("Wall", (-Lane.halfWidth + radius - x) / dx, 1, 0)
	elseif dx > EPSILON then
		consider("Wall", (Lane.halfWidth - radius - x) / dx, -1, 0)
	end
	if dy > EPSILON then
		consider("Wall", (Lane.length - radius - y) / dy, 0, -1)
	elseif dy < -EPSILON then
		if Lane.openBottom then
			-- The whole shot has left the lane once its centre is a radius past the rail.
			consider("Exit", (-radius - y) / dy, 0, 1)
		else
			consider("Wall", (radius - y) / dy, 0, 1)
		end
	end
	return hit
end

-- The first surface the ray reaches: walls, the rail edge, or a target (skipping ignoreId).
local function cast(
	x: number,
	y: number,
	dx: number,
	dy: number,
	maxDistance: number,
	radius: number,
	obstacles: { Obstacle },
	ignoreId: number?
): Hit?
	local hit: Hit? = castWalls(x, y, dx, dy, maxDistance, radius)
	local limit = if hit then hit.distance else maxDistance

	-- Broad phase: the swept segment's bounds, grown by the radius.
	local endX, endY = x + dx * limit, y + dy * limit
	local sweepMinX, sweepMaxX = math.min(x, endX) - radius, math.max(x, endX) + radius
	local sweepMinY, sweepMaxY = math.min(y, endY) - radius, math.max(y, endY) + radius

	for _, obstacle in obstacles do
		if
			obstacle.id ~= ignoreId
			and obstacle.maxX >= sweepMinX
			and obstacle.minX <= sweepMaxX
			and obstacle.maxY >= sweepMinY
			and obstacle.minY <= sweepMaxY
		then
			local distance, nx, ny = rayRoundedBox(x, y, dx, dy, limit, obstacle, radius)
			-- Strictly earlier wins, so a tie between a wall and a target goes to the wall.
			if distance ~= nil and (hit == nil or distance < (hit :: Hit).distance) then
				local targetHit: Hit = {
					kind = "Target",
					distance = distance,
					normalX = nx,
					normalY = ny,
					targetId = obstacle.id,
				}
				hit = targetHit
				limit = distance
			end
		end
	end
	return hit
end

---------------------------------------------------------------------------------------------
-- Response
---------------------------------------------------------------------------------------------

-- Reflects a unit direction off a surface with unit normal n. Tangential friction shortens the
-- along-surface part before renormalising; at 0 (the default) the angle out equals the angle in.
function Ricochet.reflect(dx: number, dy: number, nx: number, ny: number): (number, number)
	local along = dx * nx + dy * ny
	local keep = 1 - Tuning.tangentialFriction
	local tx, ty = (dx - along * nx) * keep, (dy - along * ny) * keep
	local rx, ry = tx - along * nx, ty - along * ny
	local length = math.sqrt(rx * rx + ry * ry)
	if length < EPSILON then
		return nx, ny
	end
	return rx / length, ry / length
end

local function finish(shot: Shot, reason: EndReason)
	shot.alive = false
	shot.endReason = reason
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

export type ShotParams = {
	x: number,
	y: number,
	dirX: number,
	dirY: number,
	speed: number,
	radius: number,
	bounces: number,
	lifetime: number,
}

-- A new live shot. The direction is normalised; a zero direction, speed, radius or lifetime is an
-- error (step divides by speed).
function Ricochet.newShot(params: ShotParams): Shot
	local length = math.sqrt(params.dirX * params.dirX + params.dirY * params.dirY)
	assert(length > EPSILON, "shot direction must not be zero")
	assert(params.speed > 0 and params.radius > 0 and params.lifetime > 0, "shot speed, radius and lifetime must be positive")
	return {
		x = params.x,
		y = params.y,
		dirX = params.dirX / length,
		dirY = params.dirY / length,
		speed = params.speed,
		radius = params.radius,
		bouncesLeft = params.bounces,
		bouncesTaken = 0,
		age = 0,
		lifetime = params.lifetime,
		alive = true,
		endReason = nil,
		piercingId = nil,
	}
end

-- Advances a shot by dt seconds, resolving every contact on the way, and returns the contacts in
-- order. Mutates the shot. A target contact asks `respond` (Reflect when omitted):
--   Reflect: bounce, lose speed, spend a bounce (with none left the shot ends as Spent).
--   Pierce:  carry on straight; the target is ignored until the next contact.
--   Stop:    the shot ends here.
-- At most Ricochet.maxBouncesPerStep contacts resolve per step; the rest of that step's time is
-- dropped, so a shot trapped in a tight corner cannot stall the server.
function Ricochet.step(shot: Shot, dt: number, obstacles: { Obstacle }, respond: Responder?): { Contact }
	local contacts: { Contact } = {}
	if not shot.alive then
		return contacts
	end

	local timeLeft = math.min(dt, shot.lifetime - shot.age)
	local elapsed = 0

	while timeLeft > EPSILON and shot.alive do
		local hit = cast(shot.x, shot.y, shot.dirX, shot.dirY, shot.speed * timeLeft, shot.radius, obstacles, shot.piercingId)
		if hit == nil then
			shot.x += shot.dirX * shot.speed * timeLeft
			shot.y += shot.dirY * shot.speed * timeLeft
			elapsed += timeLeft
			break
		end

		local hitTime = hit.distance / shot.speed
		shot.x += shot.dirX * hit.distance
		shot.y += shot.dirY * hit.distance
		elapsed += hitTime
		timeLeft -= hitTime

		local contact: Contact = {
			kind = hit.kind,
			targetId = hit.targetId,
			x = shot.x,
			y = shot.y,
			normalX = hit.normalX,
			normalY = hit.normalY,
			time = elapsed,
			bouncesTaken = shot.bouncesTaken,
			reflected = false,
			outDirX = shot.dirX,
			outDirY = shot.dirY,
			outSpeed = shot.speed,
		}
		table.insert(contacts, contact)

		if hit.kind == "Exit" then
			finish(shot, "Exit")
			break
		end

		local response: ContactResponse = if hit.kind == "Target" and respond then respond(contact) else "Reflect"
		if response == "Stop" then
			finish(shot, "Stopped")
		elseif response == "Pierce" then
			shot.piercingId = hit.targetId
		elseif shot.bouncesLeft <= 0 then
			finish(shot, "Spent")
		else
			shot.piercingId = nil
			shot.bouncesLeft -= 1
			shot.bouncesTaken += 1
			shot.dirX, shot.dirY = Ricochet.reflect(shot.dirX, shot.dirY, hit.normalX, hit.normalY)
			shot.speed *= if hit.kind == "Wall" then Tuning.wallSpeedRetention else Tuning.targetSpeedRetention
			-- Step off the surface so the next cast does not start touching it.
			shot.x += hit.normalX * Tuning.surfaceSkin
			shot.y += hit.normalY * Tuning.surfaceSkin
			contact.reflected = true
			contact.outDirX, contact.outDirY, contact.outSpeed = shot.dirX, shot.dirY, shot.speed
			if shot.speed < Tuning.minSpeed then
				finish(shot, "Slow")
			end
		end

		if #contacts >= Tuning.maxBouncesPerStep then
			break
		end
	end

	shot.age += dt
	if shot.alive and shot.age >= shot.lifetime - EPSILON then
		finish(shot, "Expired")
	end
	return contacts
end

-- The path a shot would take, for the aim preview: the start, then every contact point up to
-- maxContacts, then the point where maxDistance runs out (unless the path exits first). Every
-- target reflects, since the preview cannot know what a hit will do.
function Ricochet.trace(
	x: number,
	y: number,
	dirX: number,
	dirY: number,
	radius: number,
	maxContacts: number,
	maxDistance: number,
	obstacles: { Obstacle }
): { PathPoint }
	local length = math.sqrt(dirX * dirX + dirY * dirY)
	assert(length > EPSILON, "trace direction must not be zero")
	local dx, dy = dirX / length, dirY / length
	local points: { PathPoint } = { { x = x, y = y } }
	local remaining = maxDistance

	for _ = 1, maxContacts do
		local hit = cast(x, y, dx, dy, remaining, radius, obstacles, nil)
		if hit == nil then
			break
		end
		x += dx * hit.distance
		y += dy * hit.distance
		remaining -= hit.distance
		table.insert(points, { x = x, y = y, kind = hit.kind })
		if hit.kind == "Exit" then
			return points
		end
		dx, dy = Ricochet.reflect(dx, dy, hit.normalX, hit.normalY)
		x += hit.normalX * Tuning.surfaceSkin
		y += hit.normalY * Tuning.surfaceSkin
	end

	if remaining > EPSILON then
		table.insert(points, { x = x + dx * remaining, y = y + dy * remaining })
	end
	return points
end

table.freeze(Ricochet)
return Ricochet
