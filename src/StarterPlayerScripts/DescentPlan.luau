-- What the descent cinematic plays, and where its camera is. Pure, so the headless suite covers
-- it; DescentCinematic does the drawing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local DescentPlan = {}

local States = RunConfig.States
-- Kept a little short of the server's own timer, so the screen is black before the room loads.
local LEAD = 0.2

local function zoneOfSlot(slot)
	if not slot then
		return nil
	end
	if slot.Zone then
		return slot.Zone
	end
	local room = slot.Room and RunConfig.GetRoomById(slot.Room)
	return room and room.Zone
end

local function zoneName(zoneId)
	local zone = RunConfig.Zones[zoneId or ""]
	return zone and zone.DisplayName or "The Depths"
end

-- The cinematic step for moving from `previous` to `snapshot.State`, or nil for none:
--   { Kind = "Plunge", Zone, Duration, Text }  fall down the shaft, ending on black
--   { Kind = "Arrive", Title, Subtitle }       fade in over the room with a title card
function DescentPlan.For(previous, snapshot)
	local state = snapshot.State
	if state == previous then
		return nil
	end
	if state == States.Starting then
		local zone = zoneOfSlot(RunConfig.RunShape[1]) or "Ruins"
		return {
			Kind = "Plunge",
			Zone = zone,
			Duration = RunConfig.StartCountdown - LEAD,
			Text = "DESCENDING  ·  " .. zoneName(zone):upper(),
		}
	elseif state == States.Transition then
		local zone = zoneOfSlot(RunConfig.RunShape[(snapshot.RoomIndex or 0) + 1]) or snapshot.Zone
		return {
			Kind = "Plunge",
			Zone = zone,
			Duration = RunConfig.TransitionDuration - LEAD,
			Text = "DEEPER  ·  " .. zoneName(zone):upper(),
		}
	elseif state == States.Combat and (previous == States.Starting or previous == States.Transition) then
		return {
			Kind = "Arrive",
			Title = string.format("Room %d  ·  %s", snapshot.RoomIndex, snapshot.RoomName),
			Subtitle = zoneName(snapshot.Zone),
		}
	end
	return nil
end

-- The camera `t` seconds into a plunge of `duration`, falling `depth` studs down a shaft whose
-- mouth is at `top`: { position, look, roll (radians), fade (0 clear .. 1 black) }.
function DescentPlan.CameraAt(t, duration, top, depth)
	local u = math.clamp(t / math.max(duration, 1e-3), 0, 1)
	local eased = u * u * (3 - 2 * u)
	local sway = math.sin(u * math.pi * 2)
	local position = top + Vector3.new(sway * 1.5, -depth * eased, math.cos(u * math.pi * 2) * 1.5 - 1.5)
	local look = Vector3.new(sway * 0.25, -1, 0.3).Unit
	local fade
	if u < 0.15 then
		fade = 1 - u / 0.15
	elseif u > 0.85 then
		fade = (u - 0.85) / 0.15
	else
		fade = 0
	end
	return {
		position = position,
		look = look,
		roll = math.sin(u * math.pi * 3) * 0.12,
		fade = math.clamp(fade, 0, 1),
	}
end

return DescentPlan
