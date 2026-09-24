-- Room objectives: rooms with a job other than "kill everything". A room definition names one in
-- its Objective field; RoomObjectives builds and runs it. Numbers only; no logic here.
local ObjectiveConfig = {}

-- Crystal Hunt: shatter every crystal. Only a shot that has already bounced can crack one; a
-- straight shot glances off. When the last crystal breaks, the room is won and anything left
-- flees.
ObjectiveConfig.Crystals = {
	Health = 2,
	Size = Vector3.new(3, 6, 3),
	Color = Color3.fromRGB(190, 120, 255),
	CrackedColor = Color3.fromRGB(120, 70, 180),
	Material = Enum.Material.Neon,
	CoinsEach = 6,
}

-- Hold the Beacon: stand in the ring. Its charge climbs while any live player is inside and
-- drains slowly when nobody is. Waves keep coming until it is full.
ObjectiveConfig.Beacon = {
	Radius = 10,
	Seconds = 22,
	DrainPerSecond = 0.25,
	Color = Color3.fromRGB(120, 255, 200),
	IdleColor = Color3.fromRGB(60, 110, 100),
}

-- Trick Shot Gallery: a calm bonus room. Targets pop up on stands; each is worth Points, doubled
-- for every bounce the shot made on the way. Score becomes coins when the clock runs out.
ObjectiveConfig.Gallery = {
	Duration = 30,
	LiveTargets = 4,
	RespawnDelay = 0.6,
	Points = 10,
	-- Points multiply by this for each bounce, up to MaxBounces of them.
	BounceMultiplier = 2,
	MaxBounces = 4,
	PointsPerCoin = 6,
	Size = Vector3.new(2.6, 4, 2.6),
	Color = Color3.fromRGB(255, 200, 80),
}

-- Treasure Runner events: the chance a normal room also holds a runner, by zone. They only run
-- when a match turns events on.
ObjectiveConfig.RunnerChance = {
	Ruins = 0.12,
	Foundry = 0.2,
	Abyss = 0.25,
}

return ObjectiveConfig
